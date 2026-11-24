"""Wirehelm input and capture through the signed-in desktop's XDG portal."""
import ctypes
import json
import os
import signal
import sys
import uuid

import gi
from gi.repository import Gio, GLib, GLibUnix

PORTAL = "org.freedesktop.portal.Desktop"
ROOT = "/org/freedesktop/portal/desktop"
REMOTE = "org.freedesktop.portal.RemoteDesktop"
CAST = "org.freedesktop.portal.ScreenCast"
SESSION = "org.freedesktop.portal.Session"
REQUEST = "org.freedesktop.portal.Request"

MODIFIERS = {
    "ctrl": "Control_L", "alt": "Alt_L", "shift": "Shift_L", "super": "Super_L",
}
BUTTONS = {"left": 272, "right": 273, "middle": 274}


def options(**values):
    return {key: GLib.Variant(sig, value) for key, (sig, value) in values.items()}


class Desktop:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.session = None
        self.loop = GLib.MainLoop()
        self.pending = None
        self.running = True
        self.pipeline = None
        self.failure = None
        self.fd = None
        self.buffer = b""
        self.buttons = set()
        self.node = self.width = self.height = None
        self.keymap = ctypes.CDLL("libxkbcommon.so.0")
        self.keymap.xkb_keysym_from_name.argtypes = (ctypes.c_char_p, ctypes.c_int)
        self.keymap.xkb_keysym_from_name.restype = ctypes.c_uint32

    def call(self, interface, method, signature, args, path=ROOT):
        return self.bus.call_sync(
            PORTAL, path, interface, method, GLib.Variant(signature, args),
            None, Gio.DBusCallFlags.NONE, 4000, None,
        ).unpack()

    def request(self, interface, method, signature, args, opts):
        token = "wh" + uuid.uuid4().hex
        sender = self.bus.get_unique_name()[1:].replace(".", "_")
        expected = f"{ROOT}/request/{sender}/{token}"
        opts["handle_token"] = GLib.Variant("s", token)
        result = []
        waiting = GLib.MainLoop()

        def response(_bus, _sender, _path, _interface, _signal, parameters):
            result.extend(parameters.unpack())
            waiting.quit()

        def timeout():
            waiting.quit()
            return GLib.SOURCE_CONTINUE

        subscription = self.bus.signal_subscribe(
            PORTAL, REQUEST, "Response", expected, None,
            Gio.DBusSignalFlags.NONE, response,
        )
        timer = GLib.timeout_add_seconds(90, timeout)
        self.pending = waiting
        try:
            (actual,) = self.call(interface, method, signature, (*args, opts))
            if actual != expected:
                self.call(REQUEST, "Close", "()", (), actual)
                raise RuntimeError("Unexpected KDE permission request handle.")
            waiting.run()
            if not result:
                try:
                    self.call(REQUEST, "Close", "()", (), expected)
                except GLib.Error:
                    pass
                raise RuntimeError("Desktop permission request ended or timed out.")
            if result[0] != 0:
                raise RuntimeError("Desktop control was declined or unavailable on the PC.")
            return result[1]
        finally:
            self.pending = None
            GLib.source_remove(timer)
            self.bus.signal_unsubscribe(subscription)

    def start(self, video, remember, restore_token):
        result = self.request(
            REMOTE, "CreateSession", "(a{sv})", (),
            options(session_handle_token=("s", "wh" + uuid.uuid4().hex)),
        )
        self.session = result["session_handle"]
        self.bus.signal_subscribe(
            PORTAL, SESSION, "Closed", self.session, None,
            Gio.DBusSignalFlags.NONE, lambda *_: self.stop(),
        )
        devices = 3 if video else 1
        device_options = options(types=("u", devices))
        if remember:
            device_options["persist_mode"] = GLib.Variant("u", 2)
            if restore_token:
                device_options["restore_token"] = GLib.Variant("s", restore_token)
        self.request(
            REMOTE, "SelectDevices", "(oa{sv})", (self.session,), device_options,
        )
        if video:
            self.request(
                CAST, "SelectSources", "(oa{sv})", (self.session,),
                options(types=("u", 1), multiple=("b", False), cursor_mode=("u", 2)),
            )
        result = self.request(REMOTE, "Start", "(osa{sv})", (self.session, ""), {})
        if result.get("devices", 0) & devices != devices:
            raise RuntimeError("Allow the requested keyboard and mouse access on the PC.")
        return result

    def notify(self, method, signature, *args):
        self.call(REMOTE, method, "(oa{sv}" + signature + ")",
                  (self.session, {}, *args))

    def key(self, name, pressed):
        symbol = self.keymap.xkb_keysym_from_name(
            MODIFIERS.get(name, name).encode("ascii"), 0,
        )
        if not symbol:
            raise ValueError("Unsupported desktop key.")
        self.notify("NotifyKeyboardKeysym", "iu", symbol, int(pressed))

    def chord(self, chord):
        names = chord.split("+")
        held = []
        try:
            for name in names:
                self.key(name, True)
                held.append(name)
        finally:
            for name in reversed(held):
                try:
                    self.key(name, False)
                except GLib.Error:
                    if self.running:
                        self.stop()
                    raise

    def keyboard(self, event):
        if "text" in event:
            value = event["text"]
            if not isinstance(value, str) or not value or len(value.encode()) > 16384 or "\0" in value:
                raise ValueError("Enter up to 16 KB of text.")
            self.bus.call_sync(
                "org.kde.klipper", "/klipper", "org.kde.klipper.klipper",
                "setClipboardContents", GLib.Variant("(s)", (value,)), None,
                Gio.DBusCallFlags.NONE, 4000, None,
            )
            self.chord("ctrl+shift+v" if event.get("terminalPaste") else "ctrl+v")
        else:
            self.chord(event["key"])

    def pointer(self, event):
        action = event["action"]
        if action == "relative":
            dx = max(-1., min(1., float(event["deltaX"]))) * self.width
            dy = max(-1., min(1., float(event["deltaY"]))) * self.height
            self.notify("NotifyPointerMotion", "dd", dx, dy)
            return
        if action in {"move", "down", "click", "wheel"}:
            x = max(0., min(1., float(event["x"]))) * (self.width - 1)
            y = max(0., min(1., float(event["y"]))) * (self.height - 1)
            self.notify("NotifyPointerMotionAbsolute", "udd", self.node, x, y)
        if action == "wheel":
            self.notify("NotifyPointerAxisDiscrete", "ui", 0, 1 if event["delta"] > 0 else -1)
            return
        button = BUTTONS.get(event.get("button"), BUTTONS["left"])
        if action in {"down", "downAtCursor", "click", "clickAtCursor"} and button not in self.buttons:
            self.notify("NotifyPointerButton", "iu", button, 1)
            self.buttons.add(button)
        if action in {"up", "upAtCursor", "click", "clickAtCursor"} and button in self.buttons:
            self.notify("NotifyPointerButton", "iu", button, 0)
            self.buttons.discard(button)

    def video(self, result, width, fps, quality):
        gi.require_version("Gst", "1.0")
        from gi.repository import Gst

        streams = result.get("streams", [])
        if len(streams) != 1:
            raise RuntimeError("Select a single display in the desktop permission prompt.")
        self.node, properties = streams[0]
        size = properties.get("logical_size", properties.get("size"))
        if not size or min(size) < 2:
            raise RuntimeError("KDE did not report the shared display size.")
        self.width, self.height = size
        out_width = min(width, self.width) // 2 * 2
        out_height = max(2, round(out_width * self.height / self.width / 2) * 2)
        Gst.init(None)
        encoder = (
            f"jpegenc quality={quality}" if Gst.ElementFactory.find("jpegenc")
            else "avenc_mjpeg" if Gst.ElementFactory.find("avenc_mjpeg")
            else None
        )
        if not encoder:
            raise RuntimeError("Install gst-plugins-good or gst-libav for desktop streaming.")
        fd_result, fds = self.bus.call_with_unix_fd_list_sync(
            PORTAL, ROOT, CAST, "OpenPipeWireRemote",
            GLib.Variant("(oa{sv})", (self.session, {})), GLib.VariantType("(h)"),
            Gio.DBusCallFlags.NONE, 4000, None, None,
        )
        self.fd = fds.get(fd_result.unpack()[0])
        self.pipeline = Gst.parse_launch(
            f"pipewiresrc fd={self.fd} path={self.node} do-timestamp=true ! "
            "queue max-size-buffers=2 max-size-bytes=0 max-size-time=0 leaky=downstream ! "
            "videoconvert ! videoscale ! videorate drop-only=true ! "
            f"video/x-raw,format=I420,width={out_width},height={out_height},"
            f"framerate={fps}/1,pixel-aspect-ratio=1/1 ! {encoder} ! fdsink fd=1 sync=false"
        )
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()

        def failed(_bus, message):
            self.failure = f"Desktop video failed: {message.parse_error()[0].message}"
            self.stop()

        bus.connect("message::error", failed)
        bus.connect("message::eos", lambda *_: self.stop())
        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("Could not start the PipeWire desktop stream.")

    def read(self, fd, condition, video):
        if condition & (GLib.IO_HUP | GLib.IO_ERR) and not condition & GLib.IO_IN:
            self.stop()
            return GLib.SOURCE_REMOVE
        chunk = os.read(fd, 65536)
        if not chunk:
            self.stop()
            return GLib.SOURCE_REMOVE
        self.buffer += chunk
        if len(self.buffer) > 131072:
            self.failure = "Desktop command exceeded the input limit."
            self.stop()
            return GLib.SOURCE_REMOVE
        while b"\n" in self.buffer and self.running:
            line, self.buffer = self.buffer.split(b"\n", 1)
            request_id = None
            try:
                event = json.loads(line)
                if not isinstance(event, dict):
                    raise ValueError("Invalid desktop command.")
                request_id = event.get("id")
                if video and "action" in event:
                    try:
                        self.pointer(event)
                    except (GLib.Error, KeyError, ValueError, TypeError):
                        print("KDE could not send this pointer event.", file=sys.stderr, flush=True)
                    continue
                self.keyboard(event)
                ack = {"ok": True}
            except (GLib.Error, KeyError, ValueError, TypeError):
                # Do not report text or input payloads in diagnostics.
                ack = {"error": "KDE could not send this keyboard or mouse input."}
            if video:
                ack["id"] = request_id
            print(json.dumps(ack), file=sys.stderr if video else sys.stdout, flush=True)
        return GLib.SOURCE_CONTINUE

    def stop(self):
        self.running = False
        if self.pending:
            self.pending.quit()
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def close(self):
        if self.pipeline:
            from gi.repository import Gst
            self.pipeline.set_state(Gst.State.NULL)
        if self.session:
            try:
                self.call(SESSION, "Close", "()", (), self.session)
            except GLib.Error:
                pass
        # The connected PipeWire fd is owned by the capture process. It closes at exit.


def main():
    video = sys.argv[1] == "desktop"
    try:
        startup = json.loads(sys.stdin.buffer.readline(8193))
        remember = startup["remember"]
        restore_token = startup.get("restoreToken")
        if type(remember) is not bool or (restore_token is not None and (
            not remember or not isinstance(restore_token, str)
            or not 0 < len(restore_token) <= 512 or not restore_token.isascii()
            or not restore_token.isprintable()
        )):
            raise ValueError()
    except (AttributeError, KeyError, TypeError, ValueError):
        raise RuntimeError("Invalid desktop startup request.") from None

    desktop = Desktop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, desktop.stop)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, desktop.stop)

    def eof_before_start(_fd, _condition):
        desktop.stop()
        return GLib.SOURCE_REMOVE

    startup_watch = GLib.io_add_watch(
        0, GLib.PRIORITY_DEFAULT, GLib.IO_HUP | GLib.IO_ERR, eof_before_start,
    )
    try:
        result = desktop.start(video, remember, restore_token)
        if not desktop.running:
            return
        GLib.source_remove(startup_watch)
        if video:
            desktop.video(result, *map(int, sys.argv[2:5]))
        ready = {"portalReady" if video else "ready": True}
        if remember and "restore_token" in result:
            ready["restoreToken"] = result["restore_token"]
        print(json.dumps(ready), file=sys.stderr if video else sys.stdout, flush=True)
        GLib.io_add_watch(
            0, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
            desktop.read, video,
        )
        desktop.loop.run()
        if desktop.failure:
            raise RuntimeError(desktop.failure)
    finally:
        desktop.close()


if __name__ == "__main__":
    try:
        main()
    except (GLib.Error, ImportError, RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr, flush=True)
        sys.exit(1)

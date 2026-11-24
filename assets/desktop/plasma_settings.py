"""Wirehelm's Plasma settings over the existing authenticated SSH connection."""
import contextlib
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROTATIONS = {1: "none", 2: "left", 4: "inverted", 8: "right",
             16: "flipped", 32: "flipped90", 64: "flipped180", 128: "flipped270"}
FONT_DEFAULT = "Noto Sans,10,-1,5,400,0,0,0,0,0"
FONT_ROLES = (
    ("General", "font", FONT_DEFAULT),
    ("General", "menuFont", FONT_DEFAULT),
    ("General", "toolBarFont", FONT_DEFAULT),
    ("General", "taskbarFont", FONT_DEFAULT),
    ("WM", "activeFont", FONT_DEFAULT),
    ("General", "fixed", "Hack,10,-1,7,400,0,0,0,0,0"),
    ("General", "smallestReadableFont", "Noto Sans,8,-1,5,400,0,0,0,0,0"),
)
RESTORE_SECONDS = 15


def run(*command, seconds=6):
    result = subprocess.run(command, text=True, capture_output=True, timeout=seconds, check=False)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip()[:300] or f"{command[0]} failed.")
    return result.stdout


def displays():
    config = json.loads(run("kscreen-doctor", "-j"))
    outputs = [item for item in config["outputs"] if item["connected"]]
    if not outputs:
        raise RuntimeError("Plasma did not report any connected displays.")
    return outputs


def output_args(output, **changes):
    prefix = f"output.{int(output['id'])}."
    return [prefix + name + (f".{value}" if value is not None else "")
            for name, value in changes.items()]


def apply(args):
    result = run("kscreen-doctor", *args)
    # KScreen 6.8 can print a backend failure while exiting with status zero.
    if "applying config failed" in result.lower():
        raise RuntimeError(result.strip()[:300])


def configuration(outputs):
    fields = ("id", "enabled", "priority", "currentModeId", "scale", "rotation", "pos", "replicationSource")
    return {item["name"]: [item.get(key) for key in fields] for item in outputs}


def choose(outputs, name):
    for output in outputs:
        if output["name"] == name:
            return output
    raise ValueError("That display changed. Refresh and select it again.")


def edits(outputs, request):
    current = choose(outputs, request["name"])
    if current["id"] != request["id"]:
        raise ValueError("That display changed. Refresh and select it again.")
    enabled = request["enabled"]
    if type(enabled) is not bool:
        raise ValueError("Invalid display state.")
    if not enabled and current["enabled"] and not any(
        item["enabled"] for item in outputs if item is not current
    ):
        raise ValueError("Keep at least one display enabled.")
    if not enabled and any(
        item["enabled"] and item.get("replicationSource") == current["id"] for item in outputs
    ):
        raise ValueError("Change the mirrored display before disabling its source.")
    options = {}
    if enabled != current["enabled"]:
        options["enable" if enabled else "disable"] = None
    if enabled:
        mode = request["mode"]
        if not any(item["id"] == mode for item in current["modes"]):
            raise ValueError("Choose a resolution and refresh rate supported by this display.")
        scale = request["scale"]
        if type(scale) not in (int, float) or not math.isfinite(scale) or not 0.5 <= scale <= 4:
            raise ValueError("Scale must be between 50% and 400%.")
        rotation = request["rotation"]
        if type(rotation) is not int or rotation not in ROTATIONS:
            raise ValueError("Choose a supported rotation.")
        x, y = request["x"], request["y"]
        if any(type(value) is not int or abs(value) > 32768 for value in (x, y)):
            raise ValueError("Enter display positions from −32768 to 32768.")
        source = request.get("mirror")
        existing_source = current.get("replicationSource", 0) or 0
        if source is not None:
            target = choose(outputs, source)
            if (target is current or not target["enabled"]
                    or target.get("replicationSource", 0)
                    or any(item.get("replicationSource") == current["id"] for item in outputs)):
                raise ValueError("Choose an enabled display that is not already a mirror.")
            source_id = target["id"]
        else:
            source_id = 0
        if mode != current.get("currentModeId"):
            options["mode"] = mode
        if not math.isclose(scale, current["scale"]):
            options["scale"] = scale
        if rotation != current["rotation"]:
            options["rotation"] = ROTATIONS[rotation]
        if source_id != existing_source:
            options["mirror"] = source_id or "none"
        if not source_id and (x, y) != (current["pos"]["x"], current["pos"]["y"]):
            options["position"] = f"{x},{y}"
        if request.get("primary") and current["priority"] != 1:
            options["primary"] = None
    if not options:
        raise ValueError("No display settings changed.")
    return output_args(current, **options)


def restore(previous):
    current = displays()
    by_name = {item["name"]: item for item in current}
    old_names = {item["id"]: item["name"] for item in previous}
    args = []
    previous_by_name = {item["name"]: item for item in previous}
    can_restore_enabled = any(previous_by_name.get(item["name"], item)["enabled"]
                              for item in current)
    for old in previous:
        output = by_name.get(old["name"])
        if output is None:
            continue
        options = {}
        if old["enabled"] != output["enabled"] and (old["enabled"] or can_restore_enabled):
            options["enable" if old["enabled"] else "disable"] = None
        if old.get("currentModeId") and old["currentModeId"] != output.get("currentModeId"):
            # KWin's mode IDs may be rebuilt when an output is unplugged.
            old_mode = next((item for item in old["modes"] if item["id"] == old["currentModeId"]), None)
            if old_mode is not None:
                matching = next((item for item in output["modes"] if item["size"] == old_mode["size"]
                                 and abs(item["refreshRate"] - old_mode["refreshRate"]) < 0.01), None)
                if matching is not None:
                    options["mode"] = matching["id"]
        if old["pos"] != output["pos"]:
            options["position"] = f"{old['pos']['x']},{old['pos']['y']}"
        if not math.isclose(old["scale"], output["scale"]):
            options["scale"] = old["scale"]
        if old["rotation"] != output["rotation"]:
            options["rotation"] = ROTATIONS[old["rotation"]]
        previous_source = by_name.get(old_names.get(old.get("replicationSource")))
        previous_id = previous_source["id"] if previous_source else 0
        if previous_id != (output.get("replicationSource", 0) or 0):
            options["mirror"] = previous_id or "none"
        args.extend(output_args(output, **options))
    # Restore order in reverse so each newly promoted output takes its old slot.
    if any(item["name"] in by_name and item["enabled"]
           and by_name[item["name"]]["priority"] != item["priority"] for item in previous):
        for old in sorted(previous, key=lambda item: item["priority"], reverse=True):
            output = by_name.get(old["name"])
            if output is not None and old["enabled"] and old["priority"] > 0:
                args.extend(output_args(output, priority=old["priority"]))
    if args:
        apply(args)


@contextlib.contextmanager
def display_transaction():
    root = Path(os.environ["XDG_RUNTIME_DIR"]) / "wirehelm-display"
    root.mkdir(mode=0o700, exist_ok=True)
    with (root / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield root / "restore.json"


def read_restore(path, outputs):
    if not path.exists():
        return None
    saved = json.loads(path.read_text())
    if saved["expires"] <= time.monotonic() or saved["applied"] != configuration(outputs):
        path.unlink()
        return None
    return saved


def display_response(outputs, saved=None):
    response = {"outputs": outputs}
    if saved:
        response["restoreToken"] = saved["token"]
        response["restoreMs"] = max(0, int((saved["expires"] - time.monotonic()) * 1000))
    return response


def read_displays():
    with display_transaction() as path:
        outputs = displays()
        return display_response(outputs, read_restore(path, outputs))


def apply_display(request):
    with display_transaction() as path:
        # Clear an earlier app's preview so its timer cannot override this change.
        legacy = path.with_name("pending.json")
        if legacy.exists():
            restore(json.loads(legacy.read_text())["outputs"])
            legacy.unlink()
        previous = displays()
        options = edits(previous, request)
        try:
            apply(options)
            updated = displays()
            if configuration(previous) == configuration(updated):
                raise RuntimeError("Plasma did not apply the display change.")
            saved = {"token": uuid.uuid4().hex, "expires": time.monotonic() + RESTORE_SECONDS,
                     "outputs": previous, "applied": configuration(updated)}
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(saved))
            temporary.replace(path)
        except Exception:
            restore(previous)
            raise
        return display_response(updated, saved)


def restore_display(token):
    with display_transaction() as path:
        outputs = displays()
        saved = read_restore(path, outputs)
        if saved is None or saved["token"] != token:
            raise ValueError("That display change can no longer be restored.")
        restore(saved["outputs"])
        path.unlink()
        return display_response(displays())


def font_size_for_role(role, points):
    # Match Plasma's Adjust All Fonts behavior for the small-text role.
    return points - 2 if role == "smallestReadableFont" and points >= 9 else points


def text_size(request):
    fonts = []
    for group, role, default in FONT_ROLES:
        key = ("--file", "kdeglobals", "--group", group, "--key", role)
        saved = run("kreadconfig6", *key).rstrip("\n")
        parts = (saved or default).split(",")
        if len(parts) < 10 or not parts[0]:
            raise ValueError(f"Plasma could not read the {role} font.")
        points = float(parts[1])
        if not math.isfinite(points):
            raise ValueError(f"Plasma could not read the {role} font size.")
        fonts.append((key, role, saved, parts, points))

    _, _, _, general, points = fonts[0]
    if points <= 0 and "size" not in request:
        raise ValueError("Plasma’s general font uses a pixel size. Set a point size in System Settings first.")
    matched = all(size == font_size_for_role(role, points) for _, role, _, _, size in fonts)
    if "size" in request:
        size = request["size"]
        if type(size) not in (float, int) or not math.isfinite(size) or not 6 <= size <= 32:
            raise ValueError("Choose a size from 6 to 32 points.")
        changed = []
        refresh = ("busctl", "--user", "emit", "/KDEPlatformTheme",
                   "org.kde.KDEPlatformTheme", "refreshFonts")
        try:
            for key, role, saved, parts, old_size in fonts:
                target = font_size_for_role(role, size)
                if old_size == target:
                    continue
                parts[1:3] = [f"{target:g}", "-1"]
                value = ",".join(parts)
                changed.append((key, saved))
                run("kwriteconfig6", *key, "--notify", value)
                if run("kreadconfig6", *key).rstrip("\n") != value:
                    raise RuntimeError(f"KDE did not save the {role} font size.")
            if changed:
                run(*refresh)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            rollback_failed = False
            for key, saved in reversed(changed):
                try:
                    run("kwriteconfig6", *key, "--notify", saved or "--delete")
                except (OSError, RuntimeError, subprocess.TimeoutExpired):
                    rollback_failed = True
            try:
                run(*refresh)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                rollback_failed = True
            if rollback_failed:
                raise RuntimeError("Font changes could not be fully restored. Refresh to read the current settings.") from error
            raise
        points, matched = size, True
    return {"family": general[0], "size": points, "sizesMatch": matched}


def main():
    request = json.loads(sys.stdin.readline(16000))
    operation = request["action"]
    if operation == "displays":
        return read_displays()
    if operation == "apply":
        return apply_display(request)
    if operation == "restore":
        return restore_display(request["token"])
    if operation == "text":
        lock = Path(os.environ["XDG_RUNTIME_DIR"]) / "wirehelm-fonts.lock"
        with lock.open("a") as file:
            fcntl.flock(file, fcntl.LOCK_EX)
            return text_size(request)
    raise ValueError("Unsupported desktop setting.")


if __name__ == "__main__":
    try:
        reply = main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        reply = {"error": str(error)[:350]}
    print("__WIREHELM_SETTINGS__ " + json.dumps(reply), flush=True)

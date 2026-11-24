"""Run one request from Wirehelm against a standard Tuya RGB+CCT bulb."""

import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time


HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "wirehelm"
CONFIG = CONFIG_DIR / "smart-bulb.json"
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "wirehelm"
VENV = DATA_DIR / "smart-bulb" / "venv"
VERSIONS = (3.5, 3.4, 3.3, 3.2, 3.1)
MARKER = "__WIREHELM_BULB__ "


class BulbError(Exception):
    def __init__(self, message, code="operation_failed"):
        super().__init__(message)
        self.code = code


def typed_int(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise BulbError("One of the light controls is out of range.")
    return value


def normalized_config(data, existing=None):
    address = data.get("address")
    device_id = data.get("device_id")
    key = data.get("local_key")
    version = data.get("protocol_version")
    if not key and existing and device_id == existing["device_id"]:
        key = existing["local_key"]
        version = existing["protocol_version"]
    try:
        ip = ipaddress.IPv4Address(address)
    except (ipaddress.AddressValueError, TypeError):
        raise BulbError("Enter the bulb’s local IPv4 address.", "configuration") from None
    if not ip.is_private or ip.is_loopback or ip.is_unspecified or ip.is_reserved:
        raise BulbError("Enter the bulb’s private LAN IPv4 address.", "configuration")
    if not isinstance(device_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{6,80}", device_id):
        raise BulbError("Enter the bulb’s Smart Life Virtual ID.", "configuration")
    if not isinstance(key, str) or not key.isascii() or len(key) != 16 or not key.isprintable():
        raise BulbError("Enter a 16-character Tuya local key.", "configuration")
    if version is not None and version not in VERSIONS:
        raise BulbError("Choose a supported Tuya protocol version.", "configuration")
    return {"address": str(ip), "device_id": device_id, "local_key": key,
            "protocol_version": version}


def read_config():
    try:
        fd = os.open(CONFIG, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except FileNotFoundError:
        return None
    except OSError:
        raise BulbError("Could not open the bulb configuration on this host.", "configuration") from None
    with os.fdopen(fd, "r", encoding="utf-8") as saved:
        info = os.fstat(saved.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise BulbError("The bulb configuration must be private to the SSH user.", "configuration")
        try:
            data = json.loads(saved.read(4096))
        except (ValueError, UnicodeError):
            raise BulbError("The saved bulb configuration is invalid.", "configuration") from None
    if not isinstance(data, dict):
        raise BulbError("The saved bulb configuration is invalid.", "configuration")
    return normalized_config(data)


def save_config(config):
    temp = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=CONFIG_DIR, encoding="utf-8",
                                         prefix=".smart-bulb-", delete=False) as new_file:
            temp = Path(new_file.name)
            json.dump(config, new_file)
            new_file.write("\n")
        temp.replace(CONFIG)
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def install_dependency():
    # Use the host Python to create or repair an isolated environment.
    python = str(VENV / "bin" / "python")
    commands = [
        ["python3", "-m", "venv", str(VENV)],
        [python, "-m", "pip", "install", "--disable-pip-version-check",
         "--timeout", "10", "--retries", "1", "tinytuya==1.21.1"],
        [python, "-c", "import tinytuya"],
    ]
    for index, command in enumerate(commands):
        try:
            subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=True, timeout=25 if index != 1 else 100)
        except (OSError, subprocess.SubprocessError):
            message = ("Could not create a Python environment. Install Python 3 with venv "
                       "support on this host." if index == 0 else
                       "TinyTuya installation failed. Check this host’s access to PyPI and retry.")
            raise BulbError(message, "dependency") from None
    return {"installed": True}


def bulb_state(points, config):
    # Standard Tuya RGB+CCT data points (Type B).
    try:
        power, mode, brightness, temperature, hsv = (points[str(n)] for n in range(20, 25))
        if (type(power) is not bool or not isinstance(mode, str)
                or type(brightness) is not int or not 0 <= brightness <= 1000
                or type(temperature) is not int or not 0 <= temperature <= 1000
                or not isinstance(hsv, str) or not re.fullmatch(r"[0-9a-fA-F]{12}", hsv)):
            raise ValueError
        hue, saturation, color_brightness = (int(hsv[i:i + 4], 16) for i in (0, 4, 8))
        if hue > 360 or saturation > 1000 or color_brightness > 1000:
            raise ValueError
    except (KeyError, ValueError, TypeError):
        raise BulbError("This device does not report the expected RGB and tunable-white controls.",
                        "unsupported") from None
    return {
        "on": power,
        "mode": mode,
        "whiteBrightness": max(1, round(brightness / 10)),
        "temperature": round(temperature / 10),
        "hue": hue % 360,
        "saturation": round(saturation / 10),
        "colorBrightness": max(1, round(color_brightness / 10)),
        "address": config["address"],
        "deviceId": config["device_id"],
    }


def read_points(bulb):
    result = bulb.status()
    points = result.get("dps") if isinstance(result, dict) else None
    return points if isinstance(points, dict) and points else None


def open_bulb(config, tinytuya):
    preferred = config["protocol_version"]
    versions = (preferred,) if preferred else VERSIONS
    for version in versions:
        bulb = tinytuya.Device(config["device_id"], address=config["address"],
                              local_key=config["local_key"], version=version)
        bulb.set_socketTimeout(2)
        bulb.set_socketRetryLimit(1)
        bulb.set_socketPersistent(True)
        try:
            points = read_points(bulb)
        except (OSError, ValueError):
            points = None
        if points is not None:
            return bulb, points, version
        bulb.close()
    raise BulbError("Could not reach the bulb. Check its power, LAN address, and saved key.", "offline")


def values_for(action, request):
    if action == "power" and type(request.get("on")) is bool:
        return {"20": request["on"]}
    if action == "white":
        brightness = typed_int(request.get("brightness"), 1, 100)
        temperature = typed_int(request.get("temperature"), 0, 100)
        return {"21": "white", "22": brightness * 10, "23": temperature * 10}
    if action == "color":
        brightness = typed_int(request.get("brightness"), 1, 100)
        hue = typed_int(request.get("hue"), 0, 359)
        saturation = typed_int(request.get("saturation"), 0, 100)
        hsv = f"{hue:04x}{saturation * 10:04x}{brightness * 10:04x}"
        return {"21": "colour", "24": hsv}
    raise BulbError("Unsupported bulb request.")


def update_bulb(bulb, values):
    result = bulb.set_multiple_values(values)
    if isinstance(result, dict) and "Error" in result:
        raise BulbError("The bulb did not acknowledge the change. Refresh to check its state.")
    for delay in (0, 0.15, 0.25):
        time.sleep(delay)
        points = read_points(bulb)
        if points and all(points.get(dp) == value for dp, value in values.items()):
            return points
    raise BulbError("The requested change could not be confirmed. Refresh to check the bulb.")


def run(request):
    import logging
    logging.disable(logging.CRITICAL)
    action = request.get("action")
    if action == "install":
        return install_dependency()
    try:
        import tinytuya
    except ImportError:
        raise BulbError("Install TinyTuya on this host to connect to the bulb.", "dependency") from None

    configuring = action == "configure"
    try:
        prior = read_config()
    except BulbError:
        if not configuring:
            raise
        prior = None
    config = normalized_config(request, prior) if configuring else prior
    if config is None:
        raise BulbError("Set up the bulb on this host.", "configuration")
    values = None if action in ("status", "configure") else values_for(action, request)

    bulb, points, version = open_bulb(config, tinytuya)
    try:
        state = bulb_state(points, config)
        if values is not None:
            state = bulb_state(update_bulb(bulb, values), config)
        if configuring or config["protocol_version"] is None:
            config["protocol_version"] = version
            save_config(config)
        return state
    finally:
        bulb.close()


def main():
    try:
        with open(os.devnull, "w") as sink:
            # Keep third-party diagnostics, packet dumps and keys off the SSH response.
            import contextlib
            with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
                request = json.loads(sys.stdin.readline(4096))
                if not isinstance(request, dict):
                    raise ValueError
                CONFIG_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
                fd = os.open(CONFIG_DIR / ".smart-bulb.lock",
                             os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, "w") as lock:
                    # Serialize lamp actions across sessions from this host.
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    response = run(request)
    except BulbError as error:
        response = {"error": str(error), "code": error.code}
    except BlockingIOError:
        response = {"error": "This host is already processing a bulb request. Try again."}
    except (OSError, ValueError, RuntimeError):
        response = {"error": "The bulb request could not be completed. Refresh and try again."}
    print(MARKER + json.dumps(response), flush=True)


if __name__ == "__main__":
    main()

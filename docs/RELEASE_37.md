# Node Cockpit 1.2.0 (build 37)

- Added a Bluetooth devices screen on the device home page, with nearby and remembered device scanning, device type, address, pairing/connection state, signal strength where reported, and battery percentage when available.
- Added Pi controls for pairing, forgetting, connecting, disconnecting, and trusting/untrusting devices through BlueZ.
- Added Windows classic Bluetooth discovery, pairing and unpairing. Windows connection profiles are opened in Windows Bluetooth Settings because connection behavior is device/profile specific.
- Added a system audio output volume slider for Windows and Linux where the machine exposes a supported audio control.

Validated with Flutter analysis, Bluetooth/device-home/device-information tests, a Windows native Bluetooth helper test, and an Android ARM64 release build installed on the connected A36 (version 1.2.0, build 37).

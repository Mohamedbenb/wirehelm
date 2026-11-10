# Node Cockpit 1.2.1 (build 38)

- Added clear spacing between Bluetooth status, audio, device, and scan sections.
- Added a Windows Disconnect action that opens Windows Bluetooth settings and preserves the existing pairing.
- Treat Windows Bluetooth battery readings of zero or empty/unsupported values as unavailable instead of displaying a misleading 0%.

Validated with the Bluetooth devices test suite, Windows native Bluetooth helper test, and targeted Flutter analysis. Android ARM64 release build prepared for remote update.

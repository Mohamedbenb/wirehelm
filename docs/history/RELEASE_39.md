# Node Cockpit 1.2.2 (build 39)

- Windows volume control now uses the active default audio endpoint instead of the legacy wave device volume API.
- Windows pairing no longer asks for an arbitrary PIN in the phone app. It tries system pairing and opens Windows Bluetooth settings if Windows needs its pairing UI.
- Windows connection controls launch Bluetooth settings through Explorer so the system UI opens in the signed-in desktop session; Windows still manages profile-specific connect/disconnect behavior.
- Pi pairing now starts `bluetoothctl` with a no-input/no-output agent, suitable for headphones that pair without a PIN, and reports pairing failures without terminal color codes.
- Bluetooth scans run in short repeated passes and add discovered devices while scanning continues. Windows discovery passes skip the slower battery and adapter inventory.
- Bluetooth actions update the current device card immediately instead of waiting for another full remote inventory. Windows battery property checks are limited to discovered device addresses.

Validated with the Bluetooth test suite, Windows native helper compilation/snapshot test, and targeted Flutter analysis. Android ARM64 release build prepared for remote update.

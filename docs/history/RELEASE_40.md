# 1.2.3+40

- Windows pairing uses native authentication callbacks instead of an unseen PIN wizard. Just Works headphones pair without a PIN; other devices prompt for their actual code or confirmation on the phone.
- Windows disconnect requests the target Bluetooth link to close through the Bluetooth radio driver, without removing pairing. The app verifies the reported connection state and shows failures instead of claiming success.
- Remembered Windows devices count as paired. Pair appears only for unpaired disconnected devices; Disconnect appears only for connected devices.
- Pi discovery keeps one scan client alive while polling discovered devices, replacing repeated one-second scans. Discovery errors are surfaced and the owned scan channel closes when leaving the screen.
- Device actions refresh and verify remote state; the UI no longer fabricates successful pair/connect/disconnect state. Lightweight Windows state refresh runs every four seconds while the page is active.

Validation: Flutter analysis clean; five Bluetooth tests pass, including Windows native compilation, authentication ABI checks, snapshot parsing and action-state rules. Live Windows test paired the Mibro earbuds using legacy PIN 0000, then disconnected them with pairing preserved (paired=true, connected=false). The phone prompt offers a headphone PIN 0000 shortcut for legacy adapters. Live phone tests using the saved Pi connection found three devices, paired and connected the Mibro earbuds, and reported their battery as 100%. The Windows app scan showed the earbuds as paired with neither Pair nor Disconnect offered while disconnected; driver permissions or automatic reconnection may prevent Windows disconnect.

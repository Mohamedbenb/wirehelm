# Node Cockpit build 9

## Windows text size

Device tools (⋮) → Windows text size. Select 100–225% and tap Apply text size. The app uses Windows' Accessibility → Text size slider and Apply button through UI Automation in the signed-in desktop session, then confirms the active UISettings.TextScaleFactor. It does not use a registry-only setter. Windows Settings opens during the change; the desktop must be signed in and unlocked. Unsupported Windows Settings control IDs produce an explicit failure. Apps with their own font settings may not scale.

Validated on this PC by applying 140% → 145% → 140%, with active runtime confirmation and original setting restored.

## Performance diagnostics

- Device tools (⋮) → Performance, also accessible from the updater's Connection diagnostics button.
- Current host/route and last connection duration, including authentication and LAN fallback.
- Direct versus DERP relay information from the embedded tsnet peer status when available/recently active. Unconfirmed paths are labeled explicitly.
- Last 30 Windows helper requests, with queue, startup, remote execution, response and total milliseconds. Status batch names identify the commands in that batch. Timings are session-local; command text/output is not recorded. Response time includes transport, serialization and desktop helper polling.
- Settings → App updates → Test download speed now compares network-only SFTP reading against normal APK downloading/file writes. It downloads the APK twice, discards both copies and never requests installation. Network-only timing excludes SFTP setup; updater average includes setup and writes. Results suggest where to investigate; they do not isolate raw network from SSH encryption or prove a bottleneck.

This release adds measurement tools, not a claimed throughput increase. Terminal behavior is unchanged.

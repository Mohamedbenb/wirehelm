# Local customization milestone — 1.6.0+56

## Packaging and boundaries

The existing Flutter app remains the single manager APK. Android :customization packages generic libxposed API 102 hook entry points and the app-side libxposed service client. Flutter and SSH code are never loaded by the hook. The native bridge exposes only probe/apply/disable/rollback/install/framework/restartSystemUi operations; it does not accept arbitrary shell commands. KernelSU ZIP source is modules/node-cockpit-system and is reproducibly packaged with a bundled SHA-256 record by scripts/package_customization.py.

Minimum Android is now API 26 due to libxposed. Compile SDK is 37. The only initially accepted SystemUI build is google/frankel/frankel:17/CP3A.261005.005/16271449:user/release-keys. An OTA changes the fingerprint and fails closed until revalidated. system_server is not scoped or hooked. Zygisk/kernel capability IDs are reserved, without injection/kernel implementations.

Existing remote-control features, credentials and device records remain separate. The previous signing identity is retained so the installed app can update without losing state. Release builds currently use the project's existing debug signing configuration; move to protected release signing with an explicit data/signing migration before distribution or supporting other users. No signing key was replaced and no boot/AVB partition was modified.

## Configuration and health

A dedicated device-protected, private SharedPreferences repository is the authoritative local configuration (schema/revision, desired enable, update interval, text size, idle behavior, previous/last-good snapshots). Only the non-secret feature snapshot is published to framework-managed remote preferences. SSH/Tailscale secrets are never shared with hooks. Hooked code reads only the module configuration and keeps an in-memory view.

Health separates manager/package detection from actual Xposed binder/API/capabilities/scope, authorized root, module protocol/disable/pending-reboot state, watchdog heartbeat, and SystemUI hook heartbeat/applied revision. Generic capability requirements support ALL/ANY composition; net speed requires SystemUI hooking, remote preferences, the validated build and the recovery watchdog. A stale/missing observation is not reported as healthy. Root access is initially requested explicitly; after approval, hook-health traffic can refresh the backend check on a worker, never the SystemUI main thread. Loss of recovery backend disables customization. The package-installed probe is limited to known Vector/LSPosed/KSU manager IDs; it is not a universal detector for renamed/forked managers.

## Initial feature

The SystemUI-only hook targets PhoneStatusBarView.onFinishInflate. It verifies the clock TextView and its LinearLayout parent before adding a small text indicator beside it. Unsupported layouts are left untouched. It samples total device RX/TX counters at 0.5–5 seconds, displays K/M bytes per second, follows the clock color, supports 8–14 sp text and hides idle traffic when requested. These are aggregate traffic counters, not a link-speed test; VPN/virtual interfaces may affect accounting. The initial build is disabled by default. Feature exceptions hide the indicator and report a bounded error rather than escaping into SystemUI. Configuration and diagnostics callbacks run away from the render thread; only view updates run on main. Diagnostic work is bounded to one in-flight report.

## Recovery

KernelSU/Vector remain the emergency module suppression mechanism. Our installer refuses to overwrite or re-enable a present/disabled module; a pending installation is reported as requiring reboot. The root service starts only through the KernelSU module, has no independent init/service.d path, and respects disable/remove flags.

The watchdog observes SystemUI PIDs every 5 seconds. While our feature is enabled, three process restarts in a 120-second window quarantine our customization and signal disable to both the app and SystemUI. This is conservative process-restart detection, not definitive attribution of a crash to our code; intentional external restarts can count too. The watchdog never kills/restarts SystemUI. It stops monitoring on module disable/remove. Updates while disabled are not silently forced through.

RecoveryReceiver is protected by the platform DUMP permission and only disables. HealthProvider accepts bounded diagnostic reports only from SystemUI's UID (which may be shared with other platform components); it cannot enable features or execute root operations. Other provider operations reject access. Root state under /data/adb/node_cockpit_system is root-private. Backups and recovery evidence are retained on uninstall rather than silently deleted.

Manual rollback restores settings with enable=false. Last-good settings require at least 60 seconds of fresh active reports at the current revision. Publishing to root and Xposed is not a distributed transaction: on partial apply failure, the manager disables customization and reports the error. This is not a guarantee against all boot failures, and persistent vendor/database writes would require their own backup/restore adapter.

## Deliberately not implemented

No cfgdb/carrier modification was applied: the existing modification's source, target format, device checks and rollback data were not present in this repository. No generic arbitrary-file root editor, system_server hooks, Zygisk implementation, kernel modifications, automatic module re-enabling or automatic reboot was added.

## Validation

Flutter analyzer clean. Targeted Flutter tests: 11 passed (capability requirements, device home, transfer queue, keyboard layout). Native tests: 3 passed (device/OTA gating, bounds, elapsed-time rate calculation). An existing keyboard test was corrected to retain its controller before the ListView disposes the off-screen composer; production keyboard behavior was not changed. APK module metadata and ZIP checksum/contents were inspected. An ADB shell attempt to call HealthProvider was rejected with SecurityException. Live Pixel validation is recorded below.

## Live Pixel validation (build 56)

KernelSU v3.3.1 root access and installed protocol-1 watchdog were verified; heartbeat age 1 second, zero SystemUI restarts in the monitoring window. Vector 2.2 (3080), API 102, SystemUI-only scope and one running target were verified. The indicator displayed beside the clock and confirmed active configuration revision 8, with 1-second sampling, 10 sp text and hide-idle enabled. Manager, root helper and hook all reported revision 8. AVB remained green, bootloader locked and SELinux Enforcing. SystemUI PID 18898 stayed stable during feature/recovery tests and the crash buffer was empty.

The disable-only recovery broadcast was exercised without deliberately crashing SystemUI: the manager and hook switched to disabled revision 6. Last-good storage became available after the stable run; Restore previous settings applied revision 7 with enabled=false and restored the idle preference. Explicit re-enable produced active revision 8. An unprivileged ADB provider call was rejected. Actual crash-loop and Android safe-mode boots were not deliberately induced. LSPosed compatibility is an API-level design, not a live validation on this phone.

Release shrinking initially removed the metadata-loaded entry class. Consumer keep rules and a build-time DEX class-definition check now prevent publishing that failure. A controlled SystemUI restart loaded the corrected hook; repeated full reboots were not a useful activation test. A bounded (20-second) constructor-scheduled fallback initializes only after framework attachment and only in SystemUI, and can attach to an already-created status-bar view. Normal lifecycle callbacks remain the primary path. No upstream Vector defect is established by these observations.

Restart SystemUI is an explicit, confirmation-gated, fixed-target native operation requiring the validated build and a healthy root recovery backend. It disables customization first, sends TERM only to com.android.systemui, and may return the lock screen. The watchdog never invokes it automatically. Background health polls no longer disable UI controls or overwrite newer user-request results. Root checks, writes and publication are serialized; normal heartbeat confirmation has a 15-second grace period before suggesting an activation restart.

The installed initial watchdog is protocol-compatible with the final packaged ZIP; the newer ZIP adds explicit user/crash-loop reason labels. The installer intentionally does not overwrite an existing module or clear KernelSU disable flags.

After installing the final analyzer-clean APK, the live UI reported active requested/observed revision 9 and the same SystemUI PID 18898. No further reboot or SystemUI restart was used for the final app-side fixes.

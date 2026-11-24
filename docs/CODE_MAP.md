# Code map

Find the feature below, then read its entry point, owner, and relevant guide section. Use [the handoff](CODEX_HANDOFF.md) for build and device state.

## Phone features

| Feature | Entry point | Owner | Guide or focused check |
|---|---|---|---|
| Customization settings and health | [Dashboard](../lib/screens/local_customization_screen.dart) | `CustomizationBridge`, `LocalCustomization`, `IndicatorSettings`, `HealthProvider` | [Settings delivery](BEHAVIOR_GUIDE.md#2-settings-accepted-delivered-drawn-and-reported), [CP4A audit](compatibility/CP4A.md) |
| Network speed | [Settings and preview](../lib/screens/network_speed_screen.dart) | [NetworkSpeedModule](../android/customization/src/main/java/com/nodecockpit/customization/NetworkSpeedModule.java) renders the indicator in SystemUI. `StatusBarPlacement` resolves collisions. | [Page tests](../test/network_speed_screen_test.dart), [preview tests](../test/network_indicator_preview_test.dart), [placement](BEHAVIOR_GUIDE.md#4-dynamic-indicator-placement-and-visibility) |
| Edge panel, handle, and floating windows | [Settings](../lib/screens/edge_panel_screen.dart), [EdgePanelController](../android/customization/src/main/java/com/nodecockpit/customization/EdgePanelController.java) | `EdgeAppRules`, `EdgeBuiltinShortcuts`, `EdgeActionSettings`, `EdgeFloatingWindows`, `EdgeWindowLayout` | [Shortcuts/actions guide](EDGE_PANEL.md), `EdgeAppRulesTest`, [edge editing](BEHAVIOR_GUIDE.md#5-edge-edits-draft-state-versus-persistence) |
| Edge panel Wirehelm controls | Edge panel → Controls | `EdgeControlList`, `EdgePcControls`, `EdgeKeyboardControls`, `EdgePanelInk`, [native provider](../android/app/src/main/kotlin/com/example/remote_control/EdgeControlsProvider.kt), [SSH control worker](../lib/services/edge_controls.dart) | [Controls page](EDGE_PANEL.md#controls-page) |
| Saved setups | [Saved setup sheet](../lib/customization/saved_setup_sheet.dart) | `LocalCustomization`, `SavedSetupScope` | `saved_device_setups_test.dart` |
| SystemUI recovery | [RecoveryReceiver](../android/customization/src/main/java/com/nodecockpit/customization/RecoveryReceiver.java) | `BootRecoveryJobService`, `FeaturePolicy`, system root module | [Restarts and quarantine](BEHAVIOR_GUIDE.md#3-restarts-boot-recovery-quarantine-and-rollback) |
| Notification ring | [Ring settings](../lib/screens/camera_ring_screen.dart) | `CameraNotificationRing`, `CameraRingAmbientController` | [Ring guide](CAMERA_NOTIFICATION_RING.md), `CameraRingEligibilityTest` |
| Notification Undo | [Undo settings](../lib/screens/notification_undo_screen.dart) | `NotificationUndoController` in SystemUI | [Undo guide](NOTIFICATION_UNDO.md), `NotificationUndoSlotTest` |
| Screen-off buttons | [Button shortcuts](../lib/screens/button_shortcuts_screen.dart) | `ButtonShortcutService`, `ButtonShortcutActions` | [Button lifecycle](BEHAVIOR_GUIDE.md#screen-off-button-shortcuts), `ButtonHoldGestureTest`, `PowerTapGestureTest` |
| Carrier profile override | Carrier page in [Dashboard](../lib/screens/local_customization_screen.dart) | `LocalCustomization`, `CarrierDatabaseTool`, KernelSU carrier backend | [Firmware-local backend](CARRIER_OVERRIDE.md) |
| App network access | [App manager](../lib/screens/app_network_screen.dart) | `AppNetworkManager`, `NetworkFirewallWorker` | [Network access guide](APP_NETWORK.md), `app_network_screen_test.dart` |
| Root file explorer | [Explorer](../lib/screens/root_files_screen.dart) | `RootFilesBridge`, `RootFileWorker`, `RootFilePolicy` | [Explorer guide](ROOT_FILE_EXPLORER.md), `root_files_ui_test.dart` |
| Clipboard shelf | [Shelf](../lib/screens/clipboard_shelf_screen.dart) | SystemUI `ClipboardShelfObserver` / `ScreenshotShelfGate`, native `:clipboard` provider/store, `remote_clipboard.dart` | [Shelf guide](CLIPBOARD_SHELF.md), `ShelfPolicyTest`, `clipboard_shelf_screen_test.dart` |
| Battery usage | [Battery usage](../lib/screens/battery_usage_screen.dart) | `battery/BatteryUsageRecorder`, dedicated native observer and private provider | [Battery tracker guide](BATTERY_USAGE.md), battery native tests and `battery_usage_screen_test.dart` |
| Device snapshots | [What changed?](../lib/screens/device_snapshot_screen.dart) | `DeviceSnapshot` | `device_snapshot_screen_test.dart` |
| Google Photos Sources | [Sources settings](../lib/screens/photos_sources_screen.dart) | `PhotosSourcesProvider` serves Wirehelm settings. `PhotosCloudCameraModule` and `PhotosDownloadJob` run in Photos. | `PhotosSourceRulesTest` |
| Standalone Liquid Glass | [Glass Lab](../glass-lab/README.md) | [Engine](../android/liquid-glass-engine/README.md) and demo | [Preview coverage](../android/liquid-glass-engine/PREVIEW_COVERAGE.md) |

## Remote tools

| Feature | Entry point | Owner | Guide or focused check |
|---|---|---|---|
| Startup, settings, and platform bridges | [Flutter entry](../lib/main.dart) | `app_settings.dart`, `MainActivity.configureFlutterEngine` | [Build and deployment](BUILD_AND_DEPLOY.md) |
| Device connection and SSH terminal | [Connection service](../lib/devices/device_connection_service.dart) | `ssh_session_manager.dart`, `ssh_session.dart`, `persistent_terminal.dart`, `NativeTerminalBridge` | [Reconnect lifecycle](BEHAVIOR_GUIDE.md#6-ssh-backgrounding-reconnect-and-terminal-lifetime), `ssh_health_test.dart` |
| Saved commands and controls | [Controls screen](../lib/screens/controls_screen.dart) | `stateful_controls_controller.dart`, `stateful_command_executor.dart` | `stateful_controls_controller_test.dart` |
| Smart bulb | [Device controls](../lib/screens/controls_screen.dart), Edge panel Controls | [Smart bulb screen](../lib/screens/smart_bulb_screen.dart), `EdgeBulbControls`, `EdgeControlsProvider`, [SSH worker](../assets/automation/smart_bulb.py) | [Setup](CACHYOS_DESKTOP.md#smart-bulb), [Controls page](EDGE_PANEL.md#controls-page) |
| Pi wake and desktop resume | [Network & Pi health](../lib/screens/linux_health_screen.dart) | `pi_wake.dart`, `plasma_desktop_resume.dart`, `DesktopUnlockBridge` | [CachyOS desktop](CACHYOS_DESKTOP.md) |
| CachyOS power, fonts and displays | [Device controls](../lib/screens/controls_screen.dart) | `plasma_power.dart`, `plasma_settings.dart`, `assets/desktop/plasma_settings.py` | [CachyOS desktop](CACHYOS_DESKTOP.md#power-text-size-and-displays), `plasma_settings_worker_test.py` |
| Remote desktop and audio | [Desktop screen](../lib/screens/remote_desktop_screen.dart) | `remote_desktop.dart`, `wayland_access.dart`, `assets/desktop/wayland.py`, `RemoteAudioBridge` | [CachyOS desktop](CACHYOS_DESKTOP.md), [Cursor capture/recovery](REMOTE_DESKTOP.md), [Audio guide](AUDIO_RELAY.md), `remote_desktop_transport_test.dart`, `remote_desktop_cursor_test.py` |
| SFTP and transfers | [Files screen](../lib/screens/sftp_screen.dart) | `file_transfer_queue.dart`, download and upload stores | [Transfer cancellation](BEHAVIOR_GUIDE.md#7-file-transfers-cancellation-is-not-resume), `file_transfer_queue_test.dart` |
| Remote URL downloads | [Remote downloads](../lib/screens/remote_downloads_screen.dart) | `remote_downloads.dart`, `remote_download_worker.dart` | [Download guide](REMOTE_DOWNLOADS.md), `remote_download_worker_test.py`, `remote_downloads_test.dart` |
| Rooted OTA preparation | [Prepare rooted OTA](../lib/screens/ota_preparation_screen.dart) | `remote_ota_worker.dart`, `RemoteDownloads.ota`, `CustomizationBridge.otaDevice` | [Preparation guide](OTA_PREPARATION.md), `remote_ota_worker_test.py` |
| Embedded Tailscale | [Tsnet client](../lib/transport/tsnet_client.dart) | `TsnetBridge`, [Go bridge](../native/tsnet/README.md) | `integration_test/tsnet_smoke_test.dart` |
| App screen-off shutdown | [App lifecycle](../android/app/src/main/kotlin/com/example/remote_control/ScreenOffShutdown.kt) | `ScreenOffExitPolicy`, `SleepAwareMessenger`, `ProcessWork`, background work leases | [Sleep policy](APP_SLEEP.md), `ScreenOffExitPolicyTest`, `screen_off_work_test.dart` |
| Remote ADB | [Tailscale screen](../lib/screens/tailscale_screen.dart) | `AdbRelayService`, `AdbRelaySession`, `debug_relay.go` | [Remote ADB guide](REMOTE_ADB.md), `debug_relay_test.go` |
| App updates | [Update screen](../lib/screens/app_update_screen.dart) | `app_update.dart`, `AppUpdateBridge`, `scripts/build_update.ps1` | [Remote updates](REMOTE_UPDATES.md), `app_update_test.dart` |

For energy measurements and known polling/wake-lock costs, start with the [battery audit](BATTERY_AUDIT.md).

Use the [focused check commands](BUILD_AND_DEPLOY.md#narrow-checks-when-authorized) and the [symptom index](DEBUGGING.md#symptom-lookup) when verifying a change.

# Code map

Find the feature below, then read its entry point, owner, and relevant guide section. Use [the handoff](CODEX_HANDOFF.md) for build and device state.

## Phone features

| Feature | Entry point | Owner | Guide or focused check |
|---|---|---|---|
| Customization settings and health | [Dashboard](../lib/screens/local_customization_screen.dart) | `CustomizationBridge`, `LocalCustomization`, `IndicatorSettings`, `HealthProvider` | [Settings delivery](BEHAVIOR_GUIDE.md#2-settings-accepted-delivered-drawn-and-reported) |
| Network speed | [NetworkSpeedModule](../android/customization/src/main/java/com/nodecockpit/customization/NetworkSpeedModule.java) | `StatusBarPlacement` resolves collision geometry in SystemUI. `network_indicator_preview.dart` renders the app preview. | `network_indicator_preview_test.dart`, [placement](BEHAVIOR_GUIDE.md#4-dynamic-indicator-placement-and-visibility) |
| Edge panel, handle, and floating windows | [EdgePanelController](../android/customization/src/main/java/com/nodecockpit/customization/EdgePanelController.java) | `EdgeAppRules`, `EdgeFloatingWindows`, `EdgeWindowLayout` | `EdgeAppRulesTest`, [edge editing](BEHAVIOR_GUIDE.md#5-edge-edits-draft-state-versus-persistence) |
| Saved setups | [Saved setup sheet](../lib/customization/saved_setup_sheet.dart) | `LocalCustomization`, `SavedSetupScope` | `saved_device_setups_test.dart` |
| SystemUI recovery | [RecoveryReceiver](../android/customization/src/main/java/com/nodecockpit/customization/RecoveryReceiver.java) | `BootRecoveryJobService`, `FeaturePolicy`, system root module | [Restarts and quarantine](BEHAVIOR_GUIDE.md#3-restarts-boot-recovery-quarantine-and-rollback) |
| Notification ring | [Ring settings](../lib/screens/camera_ring_screen.dart) | `CameraNotificationRing`, `CameraRingAmbientController` | [Ring guide](CAMERA_NOTIFICATION_RING.md), `CameraRingEligibilityTest` |
| Notification Undo | [Undo settings](../lib/screens/notification_undo_screen.dart) | `NotificationUndoController` in SystemUI | [Undo guide](NOTIFICATION_UNDO.md), `NotificationUndoSlotTest` |
| Screen-off buttons | [Button shortcuts](../lib/screens/button_shortcuts_screen.dart) | `ButtonShortcutService`, `ButtonShortcutActions` | [Button lifecycle](BEHAVIOR_GUIDE.md#screen-off-button-shortcuts), `ButtonHoldGestureTest`, `PowerTapGestureTest` |
| App network access | [App manager](../lib/screens/app_network_screen.dart) | `AppNetworkManager`, `NetworkFirewallWorker` | [Network access guide](APP_NETWORK.md), `app_network_screen_test.dart` |
| Root file explorer | [Explorer](../lib/screens/root_files_screen.dart) | `RootFilesBridge`, `RootFileWorker`, `RootFilePolicy` | [Explorer guide](ROOT_FILE_EXPLORER.md), `root_files_ui_test.dart` |
| Device snapshots | [What changed?](../lib/screens/device_snapshot_screen.dart) | `DeviceSnapshot` | `device_snapshot_screen_test.dart` |
| Google Photos Sources | [Sources settings](../lib/screens/photos_sources_screen.dart) | `PhotosSourcesProvider` serves Wirehelm settings. `PhotosCloudCameraModule` and `PhotosDownloadJob` run in Photos. | `PhotosSourceRulesTest` |
| Standalone Liquid Glass | [Glass Lab](../glass-lab/README.md) | [Engine](../android/liquid-glass-engine/README.md) and demo | [Preview coverage](../android/liquid-glass-engine/PREVIEW_COVERAGE.md) |

## Remote tools

| Feature | Entry point | Owner | Guide or focused check |
|---|---|---|---|
| Startup, settings, and platform bridges | [Flutter entry](../lib/main.dart) | `app_settings.dart`, `MainActivity.configureFlutterEngine` | [Build and deployment](BUILD_AND_DEPLOY.md) |
| Device connection and SSH terminal | [Connection service](../lib/devices/device_connection_service.dart) | `ssh_session_manager.dart`, `ssh_session.dart`, `persistent_terminal.dart`, `NativeTerminalBridge` | [Reconnect lifecycle](BEHAVIOR_GUIDE.md#6-ssh-backgrounding-reconnect-and-terminal-lifetime), `ssh_health_test.dart` |
| Saved commands and controls | [Controls screen](../lib/screens/controls_screen.dart) | `stateful_controls_controller.dart`, `stateful_command_executor.dart` | `stateful_controls_controller_test.dart` |
| Remote desktop and audio | [Desktop screen](../lib/screens/remote_desktop_screen.dart) | `remote_desktop.dart`, `RemoteAudioBridge` | [Audio guide](AUDIO_RELAY.md), `remote_desktop_transport_test.dart` |
| SFTP and transfers | [Files screen](../lib/screens/sftp_screen.dart) | `file_transfer_queue.dart`, download and upload stores | [Transfer cancellation](BEHAVIOR_GUIDE.md#7-file-transfers-cancellation-is-not-resume), `file_transfer_queue_test.dart` |
| Embedded Tailscale | [Tsnet client](../lib/transport/tsnet_client.dart) | `TsnetBridge`, [Go bridge](../native/tsnet/README.md) | `integration_test/tsnet_smoke_test.dart` |
| Remote ADB | [Tailscale screen](../lib/screens/tailscale_screen.dart) | `AdbRelayService`, `AdbRelaySession`, `debug_relay.go` | [Remote ADB guide](REMOTE_ADB.md), `debug_relay_test.go` |
| App updates | [Update screen](../lib/screens/app_update_screen.dart) | `app_update.dart`, `AppUpdateBridge`, `scripts/build_update.ps1` | [Remote updates](REMOTE_UPDATES.md), `app_update_test.dart` |

Use the [focused check commands](BUILD_AND_DEPLOY.md#narrow-checks-when-authorized) and the [symptom index](DEBUGGING.md#symptom-lookup) when verifying a change.

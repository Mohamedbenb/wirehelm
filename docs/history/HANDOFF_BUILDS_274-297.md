# Wirehelm handoff

## Current source

The repository uses the Wirehelm name. Existing package and integration identifiers retain their original names for upgrade compatibility.

Build 274 adds **Features → What changed?** for comparing Android, launchable app versions, optional root module inventory, and recent SystemUI hook reports against a private baseline.

Build 275 adds **UI features → Edge panel → App-specific shortcuts**. The foreground signal selects the shortcut list before the panel window takes focus.

Build 276 adds direct **Edit** on the panel and **On this panel** in Wirehelm's app-specific picker. Contextual saves use the SystemUI-only provider and target the app whose panel was opened.

Build 277 distinguishes **Favorites** from **Shortcuts for [app]** and hides the foreground app in both lists, including inside Favorites folders. App-specific editing excludes the trigger app.

Build 278 includes Wirehelm in the edge-panel shortcut picker.

Build 279 adds opt-in **UI features → Screen-off buttons**. The root monitor observes physical volume holds and leaves the stock input path in place. It cancels a pending shortcut on playback or a power press.

Build 280 adds double tap, triple tap, and tap-then-hold per volume button, plus timed flashlight, Vibrate ↔ Ring, timed Do Not Disturb, and moment bookmarks.

Build 281 adds double and triple Power taps starting with the screen off, gated on Android's double-press shortcut being disabled. The monitor preserves the stock input path for Power, including long press and Emergency SOS.

Builds 282–283 add **Edge panel → Windows** on the supported Pixel build. Tap a shortcut in Windows to request Android freeform mode, or tap an existing task in the list to bring it forward. Use **Arrange** to preview and set its position and size, and **Minimize** to put it behind other tasks while keeping it available in Windows. The shelf is generated from Android’s running tasks on the primary display for the active user. Android controls which apps can run in freeform mode.

Build 284 adds **Pin** and **Unpin** to individual floating windows. Pinning uses Android’s per-task always-on-top flag so the window can stay visible when another app takes focus. Minimize clears the flag before sending the task behind other apps. The Windows list reads the flag from the live Android task.

Build 285 adds **Windows → Add** for searching and opening installed launcher apps without editing shortcuts. **Arrange** supports dragging the preview to move it, dragging its corner to resize, Small/Medium/Large presets, and separate position and size sliders. **Fullscreen** takes the same Android task out of floating mode.

Build 286 reworks the edge panel content layout. The footer uses two rows on narrow panels, contextual shortcuts show the app name as a separate caption, and the Windows list puts each task’s actions in its own menu. The panel and handle use the existing glass renderer and settings.

Build 293 adds **Google Photos → Collections → Sources** for Google Photos 7.99.0.1007655401 (52617560). Enable Google Photos in Wirehelm’s Vector scope, then restart Photos. Sources groups the selected account’s cached cloud-only media by recorded source, camera metadata, and known filename patterns. The Camera group splits by model, including aliases, and Videos receives clips without a model. Unsorted holds unassigned photos. The optional Development grouping is saved per Photos account on this device. Large groups open in pages and items use the native Photos viewer.

Build 295 adds **Download group** and **Camera → Download all Camera**. The picker shows existing device folders and their paths, with an option to create a new collection. The confirmation shows the item count and estimated size. The account-specific queue fetches original bytes sequentially, skips items Photos already indexed as local, and publishes a MediaStore row only after its length matches the Photos index. A paused queue can be resumed from Sources. The destination folder’s existing backup setting applies.

Build 296 adds **Run in background** for Sources downloads on Android 14 and later. An Android user-initiated transfer job in the Wirehelm Sources namespace runs the same Photos-owned queue and shows progress and Pause in a notification. Reopening Sources shows **Download progress** for a running or scheduled transfer and **Resume download** for a paused queue. The foreground queue remains available when the background binding is unsupported.

Build 297 adds **Wirehelm → Features → Photos Sources** for compatibility, last reported download status, filename rules, the Development group, and preferred device folders. Existing defaults and saved Photos queues are preserved. Reopen Photos after saving settings. Preferred paths rank existing folders in the Photos picker, where the user still confirms the destination. Photos keeps its viewer, transfer journal, and pause and resume controls.

The edge panel defaults to Card Glass, and the collapsed handle supports live Native Glass. Clear’s white veil and Regular’s adaptive tone each default to zero. The controls remain separate from tint strength. Android owns the rendering of notifications, Quick Settings, brightness, and volume.

## Last device verification

Build 297 passed four Photos source-rule tests and the APK signature, Xposed entry, provider manifest, and fresh Flutter frontend checks. The signer matches the verified build 296 updater APK. Use `build/artifacts/Wirehelm-1.37.91-build297.apk` and its SHA-256 sidecar. Android confirmed installation on the Pixel 10 over Remote ADB. The settings provider rejected the ADB shell caller. The Photos process still held the previous hook at verification time. Open Collections in a fresh Photos process to validate the settings and status exchange. The build 296 updater APK matches the archived checksum, while the separate build 296 archive copy failed signature and hash verification.

Wirehelm 1.37.90 (build 296) installed on the Pixel 10. The user resumed their saved Camera queue and confirmed background downloading. Android reported the namespaced user-initiated job active and its progress notification present, and verified photos continued publishing while Wirehelm was foregrounded. Three focused source-rule tests passed. The signed artifact is `build/artifacts/Wirehelm-1.37.90-build296.apk` with its SHA-256 sidecar.

Wirehelm 1.37.89 (build 295) installed on the Pixel 10 through local ADB. The full Camera confirmation selected the existing `DCIM/Camera/` destination and counted all 674 then-eligible Camera items. The test saved one photo and one video into separate new device collections. Both matched the cloud dedup fingerprint and byte size and were indexed with the original capture timestamp. The test video queue resumed after a Photos restart and app update. The full Camera queue was not started during verification. The signed artifact is `build/artifacts/Wirehelm-1.37.89-build295.apk` with its SHA-256 sidecar.

Build 293 showed 2,211 photos and 129 videos on the Pixel. The Camera model counts, both supplied camera samples, and the native photo and video viewers were verified. Enabling Development gave 23 items in Development and 29 in Unsorted. Three source-rule tests passed.

Wirehelm 1.37.85 (build 291) installed on the Pixel 10 through local ADB. In Google Photos 7.99.0.1007655401, the Cloud Camera entry opened a 658-photo grid, a thumbnail rendered, and tapping it opened the native viewer with Share and Edit. The read-only index check included the supplied Samsung sample and verified seven pages with a smaller test page size. The signed APK passed the Xposed entry and signing certificate checks. The artifact and SHA-256 sidecar are in `build/artifacts/` as `Wirehelm-1.37.85-build291.apk` and `Wirehelm-1.37.85-build291.apk.sha256`.

Wirehelm 1.37.80 (build 286) installed on the Pixel 10 through Remote ADB, and hook 190 reported active after one SystemUI reload. At the saved 140 dp width, on-device checks verified the two-row footer, the window actions menu, resize and add entry points, and edit/cancel. The saved panel and handle material settings had the same checksum before and after. Build 285 verified picker, preview move/resize and fullscreen on Clock. Build 284 verified Pin across app focus and Minimize on Calculator. Power gesture behavior still needs on-device validation.

The signed APK and SHA-256 sidecar are in `build/artifacts/` as `Wirehelm-1.37.80-build286.apk` and `Wirehelm-1.37.80-build286.apk.sha256`. Release lint, the Xposed release entry check, the signature and transfer checks, and fourteen focused edge panel tests passed.

## Development references

- [Build and deployment](../BUILD_AND_DEPLOY.md)
- [Feature ownership](../CODE_MAP.md)
- [Edge materials and standalone lab](../GLASS_FEATURE_STATUS.md)
- [Root file explorer](../ROOT_FILE_EXPLORER.md), [notification ring](../CAMERA_NOTIFICATION_RING.md), and [Notification Undo](../NOTIFICATION_UNDO.md)

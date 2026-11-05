# Debugging guide


Start with [code ownership](CODE_MAP.md), read the relevant [behavior sequence](BEHAVIOR_GUIDE.md), then inspect its source. Historical release notes describe what was tested at that time, not guarantees about the current build.

## Symptom lookup

| Symptom | Inspect first | Distinguish / preserve |
|---|---|---|
| Indicator overlaps newly appearing icons | NetworkSpeedModule.placeMeter / positionFloatingMeter; status-bar native layout | Anchored meter participates in a native row; the free-position overlay must explicitly avoid native bounds. Inspect StatusBarPlacement, native system-icon container bounds, cached leaf visibility/alpha, insets and cutouts. Preferred and effective positions differ while blocked. |
| Missing indicator/handle after a long screen-off period | Behavior guide section1; scheduleWakeRecovery; lease and watchdog freshness | Hooks can remain loaded while output is suspended. Earlier wake passes can report immediately;900ms is the forced retry. Rendering precedes asynchronous verification. Long-sleep reproduction remains unverified. |
| Slider preview moves but phone does not | _liveNetworkSetting; CustomizationBridge; applyVisual; requestConfiguration; acceptSettings | Check persisted revision, effective configuration and hook revision independently. Do not restart SystemUI for every edit. |
| Intermittent multi-second edits | LocalCustomization background root collection; channel worker queues | Background shell commands must not monopolize the visual settings lock. ADB/screenshot timings include transport overhead. |
| Value and unit collide | drawColumn; protectLineSpacing; TightUnitSpan; preview spacing | Negative gap is constrained by actual glyph clearance; test bold, unit scale, height and both layouts. |
| Enabled but missing after boot/unlock | health metrics; attachExistingWindows; scheduleWakeRecovery; boot jobs | Compare waitingForStatusBar, idle, screenOff, statusBarHidden, quarantine and overdue lease; do not equate enabled with visible. |
| Remote ADB connection refused | AdbRelaySession diagnostics; debug_relay.go | Tailnet reachability does not prove adbd is listening. Check actual LISTEN socket, app loopback connection, both guards, selected peer and normal authorization. |
| APK rejected as older | app_update.dart / AppUpdateBridge and actual published APK | Verify the downloader alias, package version and signing certificate; a newly built named APK does not update a stale alias automatically. |
| Reconnect differs from explicit disconnect | Behavior guide section6; lastDeviceId; terminal ownership | Unexpected loss can retain history/reconnect target; explicit disconnect clears them. Reconnect does not establish command replay or shell continuity. |
| Transfer retry fails or leaves a partial file | Behavior guide section7; runner and queue ownership | Cooperative cancel is not immediate rollback; retrying a callback is not byte-resume. Inspect the specific runner. |
| SSH disconnected / changed LAN address | DeviceConnectionService; SshSession; known_host_storage | Separate address discovery, transport reachability, SSH host identity and authentication. Do not silently accept a changed host key. |
| Terminal sizing/input wrong | native_terminal.dart; NativeTerminalBridge; docs/TERMINAL_RESIZE_48.md | Preserve PTY lifecycle, native terminal sizing and session ownership. |

## Phone diagnostics

Use the currently connected serial, not a historical LAN port:

```powershell
adb devices -l
adb mdns services
adb -s <serial> shell dumpsys package com.example.remote_control
adb -s <serial> shell dumpsys window
adb -s <serial> logcat -d -t 300 NodeCockpit:V AndroidRuntime:E '*:S'
```

The app's Customization health screen is the normal entry point. For authorized root debugging, read only the relevant fields from:

`/data/user_de/0/com.example.remote_control/shared_prefs/local_customization_v1.xml`

Useful fields: revision, hookRevision, hookVersion, hookState, hookError, hookMetrics. Metrics include visibilityReason, textClipped, attachments/detachments, deliveryFailures and edgeFailures. Free placement exposes placementRequestedLeft, placementActualLeft, placementBlocks and placementAdjustments (pixels/counters). statusBarCrowded means no safe horizontal slot currently fits. The nested edge counters distinguish appearance changes from window creates/removes/rebuilds. Health reports are throttled, so an observation can lag the current draw.

Do not log credentials, private keys, tokens or unrelated notifications. Saved preference XML can be atomically replaced while being read; retry a brief empty/missing read rather than declaring corruption.

## Reproduction checklist

1. Record build code and loaded hook version, selected layout/design and relevant settings.
2. Record expected vs actual pixels. Capture before, during and after the triggering change.
3. Test the real trigger: newly appearing status icon, ongoing drag, video frame change, wake or process restart. A final screenshot alone does not prove continuous response.
4. Record hook/edge failures and clipping before/after. Restore only values changed by the test; do not overwrite newer manual user changes with an old backup.
5. Keep evidence in build/ with a descriptive name; summarize results and limits in the handoff.

For UI automation, a failed `uiautomator dump` must not reuse an old XML file. Remove or uniquely name dump files and fail on unavailable hierarchy. If the screen is changing continuously, inspect a screenshot instead. Secure lock screens require normal user authentication; never bypass it to finish a test.

## Validation scope

Run tests only when requested/authorized. Narrow checks live in test/ and android/customization/src/test/. Preview widget tests establish layout/callback behavior, not SystemUI correctness. Native settings tests establish parsing/policy behavior, not real Android view layout or graphics. Phone visual checks are still required for native adapter changes.

Known platform limits: Android/SystemUI class shapes and resource IDs are build dependent; full-screen apps may hide native status bars. Verify compatibility gates before modifying an unknown ROM.

## Verified collision regression (build116/hook49)

A temporary DND icon reproduced the original overlay bug and verified the correction on Pixel10. The preferred fraction stayed762; effective left moved654 ->599 when the icon appeared, then back654 after removal. See the handoff for screenshots and test record. Preserve the system-icon container adapter: walking drawable leaf views alone missed the icon and failed the first phone test. Restore the original DND mode after reproducing; do not leave a test mode enabled.

## Read-only investigation boundaries

To investigate sleep without changing state, read power/keyguard/device-idle dumps, current SystemUI PID, stored hook fields and watchdog timestamps. Do not open the app, call the health provider or run control.sh status as a supposedly passive check: these can initialize/refresh state (control.sh also ensures its state directory exists). Do not force sleep/idle, wake/unlock, toggle controls or restart processes without scope for those actions. An awake snapshot cannot certify prolonged-sleep recovery.

Compare like clocks: hookElapsed/rootSuccessElapsed are elapsed-realtime values; hookAt/watchdog_at are wall-clock timestamps (milliseconds for hookAt, seconds for watchdog_at). Compute report age before interpreting stored metrics. Redact unrelated fields. Distinguish missing hooks, expired safety, a stale report and intentional AOD/native fallback before proposing recovery.

## Sleep recovery and saved choices (117)

Compare desired flags with emergency state and effective hook settings. Check recoveryReason, feature choice events, root lease age, watchdog freshness and the loaded hook version. On wake, an off-main-thread verification request precedes restoring the edge windows and indicator, with bounded retries before ordinary health recovery.

Save setup stores all local customization choices, not backend installations or remote-device credentials. Restore creates a Before restore checkpoint and uses normal enablement validation. The UI no longer invokes legacy rollback. Check the persisted savedSetups list, requested snapshot ID and resulting config revision if a restore appears incomplete; ensure pending visual edits were flushed before saving. Twelve newest snapshots are retained.

## Native runtime reflection and release shrinking

Check reflection against the target SystemUI build and the optimized APK. A successful lookup and a loaded hook do not establish that a feature attached or rendered.

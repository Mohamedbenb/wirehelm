# Behavior and lifecycle guide


Read the relevant section, then follow its owner in the [code map](CODE_MAP.md).

## Evidence labels and state distinctions

- **Source-checked:** the implementation contains this behavior. Scheduling, OS policy and failure conditions can still affect what happens on a phone.
- **Device-observed:** a specific reproduction was captured on a named build. See CODEX_HANDOFF.md for evidence and limits.
- **Unverified consequence:** a plausible interaction derived from code, requiring a targeted runtime reproduction before calling it the cause of a symptom.

Keep these states separate: desired user configuration; effective safety-gated configuration sent to the hook; hook process and loaded version; view attachment/visibility; latest reported health. An enabled switch or matching revision alone does not prove visible pixels, completed persistence or ongoing transport availability.

## 1. Lock, sleep and wake

**Owners:** [NetworkSpeedModule](../android/customization/src/main/java/com/nodecockpit/customization/NetworkSpeedModule.java) (`scheduleWakeRecovery`, `render`, `report`), [LocalCustomization](../android/customization/src/main/java/com/nodecockpit/customization/LocalCustomization.java) (`refreshSafetyNowIfNeeded`, `acceptRootHealth`), [FeaturePolicy](../android/customization/src/main/java/com/nodecockpit/customization/FeaturePolicy.java), [root watchdog](../modules/node-cockpit-system/service.sh).

### Source-checked sequence

1. Locking alone does not unload hooks or automatically disable desired settings. Interactive keyguard, screen off, AOD and CPU deep sleep are different states. The edge controller has no blanket keyguard-disable check; Android window visibility still applies.
2. The safety lease lasts90seconds from a verified root result and is tied to the Android boot count. Its `elapsedRealtime` clock includes deep sleep. Handler work is dispatched on an uptime clock and can be delayed by deep sleep; it does not wake the device just because a callback was scheduled. See [Android Handler timing](https://developer.android.com/reference/android/os/Handler#postDelayed(java.lang.Runnable,%20long)). The watchdog's ordinary shell loop also has no explicit wake lock.
3. Consequently, a sufficiently long gap without verification can expire the lease. That is not equivalent to "every90seconds of screen lock disables features": checks can continue if the CPU stays awake.
4. New edge controllers receive the current settings immediately even if preferences arrived before context/window creation. The tick also checks actual interactive power state, covering a screen-off event missed while SystemUI was starting. Screen-off explicitly cancels the traffic tick and suspends edge windows through the existing safety gate. It does not write feature flags. No wake lock or screen-off heartbeat polling is added.
5. Screen-on starts one generation-checked recovery. User-present/unlocked broadcasts coalesce while verification is pending; a new off/on cycle supersedes old replies. A UID-restricted `wakeConfiguration` request performs a fast root/backend check off the SystemUI main thread before enabling visual output. Delayed/stale heartbeat results retry at500ms, at most12 retries, then return to ordinary health recovery with output still safety-gated. OS/root scheduling can delay these targets; this is not an instantaneous-wake guarantee.
6. Successful verification reapplies current configuration, restores edge windows and resets the traffic baseline before restarting one tick. Late preference/health replies cannot resume visuals while screen-off or wake verification is pending. Actual quarantine/emergency conditions stay fail-closed until an explicit safe apply.
7. Routine15second root maintenance and wake/expired-lease checks omit carrier database hashes/telephony diagnostics; explicit full root probes retain those diagnostics. A fast probe preserves the cached carrier result. Expired leases are never renewed from stale watchdog evidence.

### Failure path and confidence

Automatic emergency suspension preserves desired choices and gates effective output. The explicit Disable action clears desired feature choices.

Build117 runtime evidence and remaining limits belong in the latest handoff entry. A short screen-off test beyond the lease duration is not equivalent to overnight deep-sleep certification.

## 2. Settings accepted, delivered, drawn and reported

**Owners:** `_liveNetworkSetting` / `_apply` in [local_customization_screen.dart](../lib/screens/local_customization_screen.dart); `applyVisual`, `publish`, `hookConfiguration` in LocalCustomization; `requestConfiguration`, `acceptSettings` and `report` in NetworkSpeedModule; [HealthProvider](../android/customization/src/main/java/com/nodecockpit/customization/HealthProvider.java).

**Source-checked:** local controls update optimistically. Network writes have one in-flight operation and one latest pending value; obsolete responses cannot rewind a newer preview. Native save validates and increments the persisted revision, then publication/provider delivery lets SystemUI apply it on its main thread. Enablement uses the safety apply path; a visual call must not change feature enable flags or bypass emergency state.

These are separate checkpoints: local preview -> persisted app revision -> effective hook configuration -> applied view -> health acknowledgement. `applyVisual` can persist before a later publication step fails; the UI error is not evidence that nothing was saved. Conversely, an optimistic preview is not proof that the hook changed. Inspect both revisions and the actual surface before retrying. Background root collection runs outside the visual lock, but explicit safety checks and channel work can still take time.

A new cosmetic revision does not require a SystemUI restart. Traffic interval controls counter sampling, not the collision/pre-draw update rate. "Applying settings" can reflect a stale dashboard/health snapshot; do not time rendering using that label alone. Numeric `sampleAgeMs` describes the age at report creation; combine it with report age before judging current freshness.

`lastGood` is saved after an active hook reports the current revision stably for more than60seconds. It is not a screenshot-backed visual certificate. Explicit failure reports for the current revision can trigger emergency disable; stale failures for a superseded revision must not disable a newer configuration.

## 3. Restarts, boot recovery, quarantine and rollback

**Owners:** [BootRecoveryJobService](../android/customization/src/main/java/com/nodecockpit/customization/BootRecoveryJobService.java), `recoverMissingBootHook` / `emergency` / `rollback` in LocalCustomization, [RecoveryReceiver](../android/customization/src/main/java/com/nodecockpit/customization/RecoveryReceiver.java), root `service.sh` / [control.sh](../modules/node-cockpit-system/control.sh).

| Event | Source-checked behavior |
|---|---|
| App process restarts | Hooks in a surviving SystemUI process are not unloaded. A valid same-boot root observation can be restored from preferences; an expired observation cannot extend itself. App-owned SSH/relay state has a different lifetime. |
| SystemUI restarts | Old injected objects/windows disappear; the new process must load the installed module and attach again. An installed APK version does not prove that the process loaded its hook version. |
| Boot | A job is configured with45second minimum latency /75second override deadline. These are JobScheduler parameters, not an availability SLA. A desired feature and missing/freshness checks gate one recorded recovery attempt per boot; compatibility and healthy root backend are required before a targeted SystemUI restart. The attempt marker is saved before root health validation, so a skipped unhealthy attempt does not imply another automatic retry later that boot. It is not a repeating wake-recovery job. |
| Safety lease expires | Effective output is suspended; desired flags remain saved. This is recoverable by successful verification. |
| Automatic emergency suspension | Desired enable flags are retained, emergency state/reason are saved, revision advances and publication is attempted. Effective output remains off. Only explicit Disable clears desired enable flags. |
| Watchdog quarantine | Three observed SystemUI PID changes within its120second counting window can trigger protection. These are observed restarts, not proven crashes; manual reloads can contribute. The watchdog polls every5seconds and does not restart SystemUI itself. An explicit safe apply can clear its own quarantine; code must not clear KernelSU/framework disable flags. |
| Rollback | Current implementation selects lastGood, otherwise previous. It forces the network indicator off before applying and retains the saved edge panel choice. Do not describe it as "turn every feature off" or as merely undoing the last slider. |

**Confidence:** these sequences were source-checked. See historical/current handoff entries for the particular boot/restart cases tested. Long-duration sleep, arbitrary crash loops and every recovery branch have not been certified by this audit.

### Saved device setups (117)

Save setup persists a named snapshot of the local customization configuration, including the indicator, panel, handle, apps and folders. Flutter flushes pending live edits first. Up to12 most recent snapshots are stored privately on the device; live tuning does not replace them. Snapshots exclude revisions, emergency state, leases, root authorization, credentials, remote devices and carrier/root installation actions.

From118, each customization feature has a visible Save action. The adaptive save sheet offers Update existing or Create new. Updating keeps the selected setup's ID/name and merges only the settings for the network indicator or edge panel. Other stored features are untouched even when their current live values differ. This updates the saved snapshot only; it does not reapply settings or advance the live configuration revision. Updated setups move to the front of retention order and show their latest update time. Creating new always starts with a complete current snapshot. Unknown feature scopes are rejected; runtime safety fields are never copied by a partial update. See `SavedSetupScope` for ownership.

From119, Restore on a feature page uses the same ownership boundaries in the opposite direction: start with current live settings and copy only that feature's keys from the selected snapshot. Other current features are retained even if the snapshot differs. The full current setup is checkpointed before the normal validated apply; dashboard Restore still restores the whole setup. The saved source snapshot is unchanged. Old callers without a scope default to all; unknown scopes are rejected before checkpoint creation.

Restore selects a snapshot by ID, first creates a **Before restore** checkpoint, then uses the normal validated safety apply path. It does not bypass a disabled framework or missing backend. A failed restore can leave a checkpoint and a reported safety suspension; it is not an atomic rollback of external root operations. The legacy `rollback` endpoint remains for compatibility, but the UI now opens saved setups for user-selected restoration.

## 4. Dynamic indicator placement and visibility

**Owners:** `placeMeter`, `observeCollisionLayout`, `positionFloatingMeter`, [StatusBarPlacement](../android/customization/src/main/java/com/nodecockpit/customization/StatusBarPlacement.java).

Anchored mode participates in the native icon row. Dragged mode saves a preferred fraction, then resolves an effective coordinate against visible native bounds and the camera cutout before drawing. Native icon containers matter: some drawing is virtual/Compose and is absent from a leaf-only view scan. Cached hierarchy refresh and current bounds/alpha checks have different jobs. Do not turn collision handling into a slow preference poll.

An obstacle can move the indicator without modifying its saved preferred fraction. It moves back when room returns. No safe slot means temporary `statusBarCrowded` hiding; idle hiding, fullscreen/native status-bar visibility and safety suspension are separate causes.

**Device-observed on116/hook49:** preferred762 remained unchanged; a temporary DND icon moved effective left654 ->599, and removal returned654. Screenshot/evidence links are recorded in the handoff. No-space fallback has unit coverage; deliberate full-crowding, landscape and other-ROM cases were not phone-certified.

## 5. Edge edits: draft state versus persistence

**Owner:** `enterEditMode`, `exitEditMode`, `persistApps`, `persistPlacement`, folder text watcher in [EdgePanelController](../android/customization/src/main/java/com/nodecockpit/customization/EdgePanelController.java).

**Source-checked:** editing copies app/folder state into drafts. Reordering, removals and folder changes in edit mode affect that draft; Save sends app/folder state through the UID-restricted provider, whereas Cancel exits without that save. Persistence is asynchronous and failures are reported through the edge failure handler. Closing the edit UI alone is not proof of a successful saved revision.

Folder naming outside edit mode takes a different path: the text watcher calls persistence as the name changes. It is not covered by a later edit-mode Cancel. Handle placement also has its own persistence path when the drag ends. Closing/destroying a modal window discards transient editing objects; applying safety suspension is not the same action as committing an edit.

## 6. SSH backgrounding, reconnect and terminal lifetime

**Owners:** [DeviceLifecycleController](../lib/devices/device_lifecycle_controller.dart), [SshSession](../lib/ssh/ssh_session.dart), DeviceConnectionService and session manager.

**Source-checked:** inactive/paused/hidden state marks sessions inactive; it is not an explicit disconnect command. The20second health timer checks only while active. A ping has a10second timeout; a closed client or three active missed checks can mark the session disconnected. These are application checks, not a guarantee that Android/network/NAT preserves the transport in the background.

On resume, existing transports are checked first. Eligible unexpectedly disconnected sessions retain lastDeviceId and can be reconnected sequentially, unless reconnect is blocked. Explicit disconnect clears that target and destroys its terminal; unexpected loss preserves the reconnect target and terminal history but invalidates the remote shell. Reconnect does not imply that a lost shell/remote process resumed or that an interrupted command was replayed. SSH host-key/authentication checks still apply. Verify current implementation before changing retry semantics for commands with side effects.

## 7. File transfers: cancellation is not resume

**Owners:** [FileTransferQueue](../lib/services/file_transfer_queue.dart), [SFTP screen](../lib/screens/sftp_screen.dart) and the individual upload/download runner.

**Source-checked:** this queue runs one task at a time. Cancel sets a cooperative flag; the runner must observe it. Retry resets cancellation/error/progress and reruns the callback; the queue itself does not negotiate byte-offset resume or undo partial remote files. Determine partial-file cleanup/overwrite behavior in the specific runner.

The SFTP route guards leaving while work is queued/running with "Cancel pending transfers?". Its disposal cancels the queue and closes SFTP. Queue state is in-memory. Do not transfer these guarantees to the updater or Android download/upload stores: those have separate owners and lifecycles.

## 8. Temporary ADB: tailnet access versus root cleanup

**Owners:** [AdbRelaySession](../android/app/src/main/kotlin/com/example/remote_control/AdbRelaySession.kt), [Go relay](../native/tsnet/bridge/debug_relay.go), [ADB guide](REMOTE_ADB.md).

**Source-checked:** Start creates an explicit temporary session; there is no automatic restart after reboot/process death. Active duration changes reset the deadline from now without replacing listener/sockets. Native relay expiry and Android root-state cleanup are separate operations. Deadline callbacks require the app runtime to execute; do not promise precise cleanup timing during process suspension/deep sleep.

Stop closes the relay first. Root mode then restores only session-owned properties and confirms the temporary listener is gone before removing its tagged IPv4/IPv6 guards. Cleanup failure retains guards/ownership and reports an error so Stop/restore can retry. A dead app can therefore lose tailnet access while root listener/guard state remains until reconciliation/reboot. Status reconciliation can retry cleanup; it is not a passive read-only diagnostic.

**Device-observed:** authenticated ADB connectivity with protected wildcard legacy listener worked on108. Active duration changes, complete expiry restoration and unattended deep-sleep availability do not have equivalent end-to-end phone certification in this guide. App engine cleanup unregisters bridge callbacks; do not equate merely leaving a Flutter route with stopping the native node. Explicit stop and process death are distinct.

## 9. Update and deployment success boundaries

**Owners:** [AppUpdateBridge](../android/app/src/main/kotlin/com/example/remote_control/AppUpdateBridge.kt), [app_update.dart](../lib/services/app_update.dart), [build guide](BUILD_AND_DEPLOY.md).

Candidate package, signing certificate and version are checked before opening the installer. A completed byte transfer does not mean installation succeeded. Opening Android's installer is another intermediate state. An availability sidecar, published alias, downloaded APK, installed package and loaded hook can each be different versions if publication or reload is incomplete.

Updating the app can terminate its own temporary ADB relay; regular wireless ADB is independent of that app process. Verify the installed package after installation and the loaded hook after a required native reload. For screenshots/renderer behavior, also verify actual pixels and health. Reopening the app is not proof that injected code reloaded. Preserve the installed identity/signing key and app data.

## Maintenance checklist

When changing a feature, check for changes to: trigger and operation order; clocks/timers and throttles; process/route/window ownership; desired versus effective state; asynchronous acknowledgement; cancellation/retry/partial failure; restoration and fallback. Update the relevant section and debugging entry if any changes.

Label code-derived behavior separately from device evidence, retain failed attempts as failed, and link exact source owners. Record build-specific measurements in the handoff, not as timeless guarantees. Areas not behavior-reviewed here (for example full remote desktop/audio/backpressure semantics) remain entry-point indexed in the code map; read their sources before making behavioral claims.

## Verified boot display (120)

The health screen shows the Android property followed by the bootconfig value in parentheses, for example `green (yellow)`. `verifiedBoot` reads `ro.boot.verifiedbootstate`; `verifiedBootRaw` reads `androidboot.verifiedbootstate` from `/proc/bootconfig` during the existing root health probe. Missing or unrecognized bootconfig state displays `unknown`. These are OS-visible observations, not hardware-backed attestation. Tricky Store was observed overriding the property to green while bootconfig reported yellow on this phone.

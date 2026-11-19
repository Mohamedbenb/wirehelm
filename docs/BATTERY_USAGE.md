# Battery usage utility

Open **Features → Battery usage** and enable **Track battery sessions**. The native tracker waits while external power is connected, starts a session when unplugged, and closes that session when power is connected again. A plugged-in phone at its charge limit is treated as externally powered, not as a discharge test. Enabling monitoring while already unplugged starts a clearly marked partial session.

## What is recorded

Each session includes battery percentage and charge-counter loss, elapsed duration, screen-on/off durations and drain rates, battery-level checkpoints, reported customization activity, configuration/context and optional Android UID energy estimates. The copy-report action copies the selected session's summary as JSON. History retains the latest 60 sessions, up to 2048 plot samples and 32 configuration checkpoints per session, plus the latest configuration and total change count.

Charge counter values come from [BatteryManager](https://developer.android.com/reference/android/os/BatteryManager). Missing counters produce unavailable mAh values rather than fabricated numbers. Counter increases are flagged as gauge adjustments and suppress unreliable screen-specific rates. Hourly rates are withheld for intervals shorter than one minute. Times use elapsed realtime, so changing the wall clock does not create extra usage. Sessions separated by a process restart/reboot are marked interrupted/partial; an unobserved gap is not silently credited as a complete discharge.

Reported activity includes network-indicator visibility, edge-panel activity, edge-handle enabled screen-on time, ring visibility and shake listening. Connection/service context includes Remote ADB, SSH keep-alive and button monitoring. Settings snapshots also include ring appearance/AOD mode, panel material/blur, saved button bindings, saved firewall rule count and the last checked carrier override state. These are observations of existing diagnostics/settings, not new hooks, notification/message-content collection or independent per-feature energy meters. Activity states follow the most recently observed SystemUI report until the next update; stale/missing reporting can limit attribution. Configuration history is bounded rather than an unlimited slider-event log.

## Android estimates

The optional root reader captures Android's estimated **whole Wirehelm UID** and **SystemUI UID** totals at the start/end of a session and approximately every 15 minutes when the CPU is already running. It uses bounded read-only `dumpsys batterystats` requests; it does not reset Android battery statistics or save unrelated UID reports. The accounting-window identity must match, and a negative difference is rejected. Enabling estimates halfway through a session does not manufacture a start baseline. Read failures preserve battery-loss tracking and are displayed separately.

Wirehelm's estimate includes the tracker, remote connections, transfers and other app work. SystemUI's estimate includes stock Android as well as injected customizations. Display, GPU, kernel/root helpers and native radio effects can appear elsewhere. Individual customizations show reported activity time, never invented per-feature mAh. See [Android power attribution](https://source.android.com/docs/core/power). A controlled comparison of similar sessions is still required to establish incremental feature drain.

## Background lifetime and privacy

The opt-in observer runs as `com.example.remote_control:battery` with a quiet foreground notification. It does not initialize Flutter, Tailscale, Xposed management or the main root-safety worker. The main app can still follow the [30-second shutdown policy](APP_SLEEP.md); its self-exit does not terminate the battery observer. No persistent wake lock, repeated wakeup alarm or root daemon is added.

Power/screen broadcasts and private preference file events drive collection. Writes are normally limited to one checkpoint per minute unless power, screen, configuration or activity state changes; a handler-only 15-minute checkpoint does not wake a suspended CPU. The tracker waits on external power without accumulating a discharge session or periodically requesting root estimates. Foreground service lifetime keeps observation available while allowing CPU suspend. Android may stop the tracker; interrupted sessions are retained honestly, and enabled monitoring is resumed after supported boot/update events or from **Resume tracker**.

The service/provider/boot receiver are private and live in the dedicated process. Session storage and configuration have one writer. Only whitelisted feature settings and parsed requested UID values are retained; credentials, private keys and message text are not collected. Disabling tracking stops the service and keeps history. The tracker itself has a cost, included in Wirehelm's UID estimates; no claim of zero overhead or overnight battery savings has been measured.

## Ownership and verification

- `android/app/.../battery/BatteryUsageService.kt`: foreground observer, broadcasts and file-event subscriptions.
- `BatteryUsageRecorder.kt` / `BatteryUsageStore.kt`: serialized session/SQLite persistence, bounded checkpoints and root reads.
- `BatterySession.kt`: elapsed-time, charge and screen accounting; unplug boundaries.
- `BatteryCustomization.kt`: fresh, whitelisted feature snapshots and own-service context, avoiding cross-process SharedPreferences caches.
- `BatteryPowerReport.kt`: selected UID/window parsing and comparable estimate differences.
- `BatteryUsageProvider.kt`: private same-UID IPC; `CustomizationBridge` exposes UI operations.
- `lib/screens/battery_usage_screen.dart`: tracking controls, session history, chart, activity and report copy.

Seventeen native tests cover accounting, unavailable gauges, screen-specific drain, reboot/time regressions, plug boundaries, report resets and stale-boot feature state. Three Flutter tests cover controls, session presentation and read failures. Device verification must separately establish service startup, actual plug/unplug boundaries, process separation, history survival and absence of a tracker wake lock. Unit tests alone do not establish sustained low-power behavior.


## Build 311 device evidence

The final signed build installed successfully with its transferred hash verified. Tracking and Android estimates are enabled. The observer created an honest partial unplugged session and accumulated real charge-counter loss; Android UID reads succeeded. Replacement of the candidate restarted the observer automatically, preserved history and marked the earlier session interrupted. A transient incomplete XML write initially produced false configuration changes; the final reader now keeps the last complete snapshot. No false configuration changes were observed in the final capture.

The observer ran as PID 31706 in `:battery`, without Flutter/Tailscale libraries. No persistent tracker wake lock was present in the held-lock snapshot. SystemUI remained PID 22843 with hook 193 active, synchronized revisions 5880/5880 and no reported error. Android denied a normal external shell UID access to the private provider. Evidence is in ignored `build/battery-311-verification.json`. These checks establish startup, persistence and process separation, not measured overnight overhead or exact per-feature energy cost.

Actual charger-boundary testing was deferred at the user's request; only the boundary model has focused unit coverage. UI presentation confirmation and a sustained normal-use discharge remain pending. The initial validation session in history includes the pre-correction configuration-read artifact; new sessions use the corrected reader. Remote ADB/active transfers can materially distort a measurement and should be stopped when collecting an ordinary-use baseline.

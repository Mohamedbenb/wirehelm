# Customization battery audit — 2026-11-12

For ongoing, opt-in unplugged-session measurements, see the [battery usage utility](BATTERY_USAGE.md). The audit below is a historical snapshot; it is not a measurement of the new tracker.

Scope: Pixel 10 CP4A.261105.040.A1, Wirehelm 309 / hook 193. Read-only source and device audit; no battery-stat reset, feature/settings change, forced idle, reboot or installation. Evidence: ignored `build/battery-audit-2026-11-12/`. This is a baseline audit, not a controlled measurement of incremental feature cost.

## Observed accounting window

Android reported about 3h44m on battery, with about 1h53m screen-on and 1h51m screen-off. BatteryStats uptime was 99.8% of on-battery realtime (only about 22 seconds outside uptime). The current boot's suspend counters were success=0, fail=3. These observations establish poor suspend residency in this diagnostic window, not its complete causal breakdown. Statistics persist across reboots and include older builds plus heavy debugging/download traffic; they are not a clean build-309 sample. Snapshot battery level was 51%, unplugged, charge counter 2,607,500 µAh; reported full capacity was 4,975,000 µAh.

The current held partial wake locks were `node_cockpit:remote_adb` and `remote_control:ssh_keep_alive`. These explicitly keep the CPU awake while held. No customization wake alarm matched the selected names/package in the captured alarm dump. This is a point-in-time finding, not proof no alarm ever fired.

Android's estimated UID energy in one captured usage report:

| Attribution | Estimate | Approximate share of reported full capacity | Interpretation |
|---|---:|---:|---|
| Wirehelm UID 10415 | 223 mAh | 4.48 percentage points | Whole app: remote connections, relay/transfer work, Flutter, services and customization management |
| Wirehelm cellular radio component | 201 mAh | 4.04 points | About 90% of that UID estimate; does not isolate Remote ADB, SSH or VPN traffic individually |
| Wirehelm CPU component | 5.60 mAh | 0.11 points | Modeled component attribution, not a direct incremental customization measurement |
| Wirehelm wakelock component | 6.85 mAh | 0.14 points | Does not include every indirect consequence of keeping the device awake |
| SystemUI UID 10279 | 9.57 mAh | 0.19 points | Stock SystemUI plus injected code; cannot separate Wirehelm's share |
| Global ambient display | 5.95 mAh | 0.12 points | Entire device's ambient display activity; cannot assign it to the ring |

These are estimates over the existing accounting window, not rates per hour and not the customizations' added drain. They do not form a complete additive decomposition of hardware drain. GPU, display/compositor, kernel/root helper and native radio consequences can appear outside these UIDs. Thus 9.57 mAh is not an upper bound for all customization cost. [Android power attribution](https://source.android.com/docs/core/power) describes timing/power-model accounting and shared-resource allocation.

## Feature and infrastructure audit

| Component | What it does | Battery assessment / limitation |
|---|---|---|
| Remote ADB | [AdbRelayService](../android/app/src/main/kotlin/com/example/remote_control/AdbRelayService.kt) holds a partial wake lock through the session deadline, plus tunnel traffic | Confirmed current sleep blocker. Keep off during an idle comparison; disconnecting the desktop alone does not stop the service lock |
| SSH background keep-alive | [KeepAliveService](../android/app/src/main/kotlin/com/example/remote_control/KeepAliveService.kt) takes an untimed lock until service destruction. [Session manager](../lib/ssh/ssh_session_manager.dart) keeps it running for connected sessions or a retained reconnect target | Confirmed current sleep blocker; an unexpected disconnect can retain the service. Strong optimization candidate: separate active I/O/reconnect-attempt protection from idle reconnect waiting |
| Notification ring | Handler-driven redraw at a nominal 100ms cadence with fade-boundary alignment (~10/s with the saved 1000ms fade); no animation wake lock or recurring wake alarm. On-demand mode can keep native ambient display active while an eligible notification exists | Highest-priority customization to measure during screen-off use. Costs include display/doze/compositor work outside the app UID. Animation callbacks pause during CPU suspend; faster draws while ADB prevents suspend are not normal idle behavior |
| Ring state at capture | Awake; windowOwned=false, windowCreates=5/windowRemoves=5, cleanupError empty | No retained ring window in this snapshot. Does not yet establish absence of future leaks or overnight cost |
| Network indicator | [NetworkSpeedModule](../android/customization/src/main/java/com/nodecockpit/customization/NetworkSpeedModule.java) samples at saved 1000ms while interactive; explicit screen-off path removes tick and hides UI | ~3600 sample callbacks/hour of screen-on time. Smaller CPU/layout overhead; no direct wake lock. Predraw collision callbacks also run with the status bar drawing |
| Edge handle/panel | Appearance fallback every350ms (~10,286 callbacks/hour while enabled), native region sampling; open panel shader/blur affects composition | Candidate for replacing/reducing fallback polling while preserving contrast adaptation. Source stops watcher/sampling/windows when screen-off safety disables edge visuals. Current liveHandle=false, panel Card material configured. Closed-panel cost differs from open-panel GPU cost |
| Notification Undo shake | Registers accelerometer at SENSOR_DELAY_GAME only while a five-second Undo slot is pending; unregisters afterward | Currently shakeListening=false and pending=false. No evidence of continuous idle shake sampling. Burst cost only unless a registration leak occurs |
| Screen-off buttons | Root getevent readers block waiting for input. A partial lock is bounded to tap recognition delay+250ms | Event-driven idle path; brief gesture-related cost. Persistent service/process presence is not equivalent to continuous CPU work |
| Recovery watchdog | [service.sh](../modules/node-cockpit-system/service.sh) polls every5 seconds and rewrites heartbeat, invoking several child utilities each iteration | ~720 checks/hour while CPU runs; not 720 hardware wakeups/hour. No wake lock/wakeup alarm, so shell sleeps do not inherently wake suspended CPU. Optimize process churn/heartbeat writes while preserving crash-loop response |
| Health and safety | Reports normally every5 seconds while active, root refresh about every15 seconds of report activity; background probes exclude carrier database inspection | Up to ~720 ordinary reports and ~240 root probes/hour of sustained awake activity, plus forced event reports. IPC, preferences and helper process overhead; candidate for batching/caching while retaining immediate wake verification and safety leases |
| Carrier override | [post-mount.sh](../modules/node-cockpit-carrier/post-mount.sh) derives and mounts database at boot | No resident periodic carrier patcher. Explicit status/configuration checks have finite cost. Any cellular energy change from the selected radio profile needs its own comparison |
| App firewall | Android enforces UID rules; boot/package/configuration events reconcile them. Timed allow exception uses one exact wakeup alarm for expiry | No app-side perpetual packet-forwarding VPN loop. Kernel rule cost and radio behavior are not established by this audit |
| Photos Sources | User-initiated JobScheduler download in Google Photos | Network/storage/CPU cost during actual downloads, attributed largely to Photos. Current queue/job activity was not quantified here |
| Root explorer / snapshots / saved setups | Work on explicit use or requested reconciliation | No continuous background drain identified from those interaction paths |
| Standalone glass lab | Preview animation/light observation gated by visibility/resume; stopped/released on hide/detach | Rendering while open can be costly; installing the engine does not imply an always-running preview |

Timer callback counts above are derived from source intervals. They are not measured CPU wakeups, energy or causal drain estimates. Holding a wake lock has indirect energy consequences beyond its modeled `wakelock` line; see [Android wake lock guidance](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock).

## Priority and next measurement

1. Establish an idle baseline with Remote ADB stopped and all SSH sessions explicitly disconnected (including reconnect targets). Keep ordinary networking settings the same. Do not disable the recovery watchdog or weaken safety protections to improve a benchmark.
2. Measure ring/AOD on-demand enabled versus ring disabled, with stock AOD setting held constant, the same eligible notification, same orientation/proximity/ambient lighting, similar charge level/temperature and comparable network signal. Prefer 2–4-hour quiet windows and repeat in alternating order; overnight is better for small differences.
3. Separately compare edge/network indicator during a repeatable screen-on workload, with brightness/refresh rate/content and panel visibility held constant. Assess open glass panel separately from the collapsed handle.
4. Optimize SSH lock lifetime, watchdog process churn and health IPC/write cadence; then repeat the same workload. Treat 350ms appearance polling as a smaller candidate and retain its adaptation behavior.

For each interval take charge-counter, BatteryStats and suspend snapshots before/after, disconnect debugging during the interval, and do not reset accumulated stats. Charge-counter delta (µAh)/1000/elapsed hours yields mAh/hour; subtract the comparable disabled-feature baseline to estimate incremental drain. Use full-capacity normalization only as percentage points/hour. Account for the short reconnect/unlock observation overhead in both runs. A short standalone `current_now` reading is not a sustained drain rate.

No controlled on/off experiment was performed in this audit, and no honest per-feature percentage can yet be assigned. A UID estimate cannot separate code injected into SystemUI from stock code, and stock display/GPU totals cannot be assigned to one overlay without a comparison. Google now favors [system tracing / power profiling](https://developer.android.com/topic/performance/power/battery-historian) over relying solely on the unmaintained Battery Historian viewer.

## Follow-up in build 310

The subsequent [app-only screen-off policy](APP_SLEEP.md) removes disconnected reconnect targets as an SSH keep-alive reason, stops empty sticky SSH restarts, and releases obsolete runtime ownership. Active SSH and Remote ADB remain deliberate exceptions and can still hold their session wake locks. Build 310 installation does not establish a measured battery improvement; no controlled follow-up energy comparison has been run.

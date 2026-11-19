# Wirehelm screen-off shutdown

Build 310 adds a default 30-second screen-off rule for the Wirehelm app runtime. Waking the screen cancels the deadline. If required work is still running, the process stays alive; after that work finishes, the expired deadline is rechecked without another 30-second delay.

## Scope and exceptions

The exit operation targets only the current Wirehelm PID. It does not force-stop the package/UID, stop Android jobs or receivers, restart SystemUI, kill Google Photos, or disable injected customizations. Existing settings, credentials and Tailscale identity remain on disk. An on-demand native health/provider process may subsequently start to service SystemUI; it does not launch Flutter and is not placed in a repeated kill/restart loop.

The connection and shortcut foreground services share the main app process. Any required service in that process protects it as a whole. Build 311's opt-in [battery observer](BATTERY_USAGE.md) runs separately in `:battery`: it survives the main PID's self-exit and does not prevent that exit.

- Connected SSH sessions and active connection/authentication attempts.
- Remote ADB while its service is active.
- Screen-off button shortcut service while running.
- File-transfer queues and app-update downloads, including network stalls.
- In-flight native calls, root-file work, native support/provider requests and background safety/recovery work.

A saved SSH reconnect target alone no longer holds the keep-alive service. The SSH service is non-sticky and rejects an empty restart: it cannot recover a transport belonging to a dead Dart runtime. Unexpected disconnect can still preserve the target/history in memory while the app survives, but process shutdown loses in-memory terminal history. Saved devices and credentials remain available for a new connection. Flutter runtime teardown releases its Dart work ownership and SSH service; independently owned native services are preserved.

The [clipboard shelf](CLIPBOARD_SHELF.md) also uses an on-demand native `:clipboard` provider. Capture events originate from the SystemUI listener; neither component keeps the main app PID alive.

## Timing and observability

`ScreenOffShutdown` runs in the existing UI process; no permanent shutdown service or wake lock is added. It uses elapsed time, a handler deadline and one listener-based exact wakeup alarm per screen-off session. Listener alarms do not relaunch an already-dead app. Android can defer/cancel alarms or freeze cached components, so 30 seconds is the target rather than a hard real-time guarantee. See [Android alarm scheduling](https://developer.android.com/develop/background-work/services/alarms) and [AlarmManager listener lifecycle](https://developer.android.com/reference/android/app/AlarmManager).

Actual required services are checked again at the deadline. Failed service-state inspection conservatively keeps the process alive. Completion callbacks coalesce a recheck by about 300ms. An active task does not receive a new deadline every time it makes progress. No scheduled callback terminates an interactive phone session.

Native diagnostics are in device-protected preferences `screen_off_shutdown.xml`: last state, protection reasons, PID and elapsed timestamp. An `idle process exit` record is committed before terminating the PID. Another native component can legitimately restart the package process later; compare the recorded PID, not merely whether any package process exists.

## Ownership and checks

- `ScreenOffExitPolicy.java`: Android-free deadline/wake/work decision.
- `ScreenOffShutdown.kt`: screen events, deadline, own-service inspection and self-exit.
- `SleepAwareMessenger.kt`: keeps asynchronous native requests protected until their reply/error.
- `ProcessWork.java`: bounds native provider/safety/recovery work without a wake lock.
- `background_keep_alive.dart`: explicit Dart work leases, used for connection setup, transfer queues and update staging.
- `SshSessionManager`: only connected sessions retain SSH keep-alive.

Focused checks cover six deadline/wake/exception cases, three messenger cases, three native-support ownership cases, plus twelve Dart work/SSH/transfer/update cases. These do not prove real Android background delivery timing.

Device validation requires opening Wirehelm once to attach the UI-runtime policy, then testing screen-off for at least 35 seconds: first with active required work (must survive), then without required work (exit record/PID termination). Use independent local ADB for the idle test; active Remote ADB is deliberately an exception. Confirm SystemUI PID and hook remain unchanged. No on-device exit/timing success should be claimed solely from unit tests or APK installation.

## Observed idle test on build 310

After the user disconnected SSH and performed the requested screen-off interval, diagnostics recorded `idle process exit` at elapsed 52238471 for PID 31956. That PID no longer existed at capture. SystemUI retained PID 22843 with hook 193 active, no error and revisions 5880/5880 synchronized. The later Wirehelm PID 1179 hosted the native health provider, had neither libflutter.so nor libapp.so loaded and had no running app service records. This is the intended on-demand native support restart, not a surviving Flutter runtime. Evidence is saved under ignored `build/sleep-310-idle-verification.json`.

The observed idle-exit path passed. The capture did not independently time alarm latency; required-work exception behavior remains covered by focused tests rather than a separate completed device trial.

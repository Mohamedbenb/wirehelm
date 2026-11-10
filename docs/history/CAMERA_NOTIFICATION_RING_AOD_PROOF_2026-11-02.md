# Camera notification ring: AOD proof

User requested a slowly blinking camera ring for selected-app notifications while the screen is off. This first milestone tests the camera geometry, AOD drawing and scheduling only. Notification filtering/settings are not implemented yet. Glass work remains paused and its sources are untouched.

## Device and current limits

Pixel fingerprint google/frankel/frankel:17/CP3A.261005.005/16271449:user/release-keys. Matching cached SystemUI APK contains FaceScanningOverlay, ScreenDecorations and DozeScreenState. The native face animation uses DisplayCutoutBaseView camera protection geometry. This trial uses a separate small window with the exact native DisplayCutout path; no face-authentication fields or behavior are modified.

Always-on Display was initially disabled. User temporarily enabled it for this experiment; setting doze_always_on read1. The trial does not change this setting. Fully OFF display is not eligible. AOD/DOZE_SUSPEND are distinct from interactive keyguard and full OFF.

## Failed standalone route

experiments/camera-notification-ring/CameraRingProbe.java compiled against SDK android-37.0 and was run once in root app_process. WindowManager rejected openSession: Unknown pid16024 uid0. It exited with0 draws/0 toggles and no added window. This is not AOD rendering evidence; do not retry the unregistered-process route.

## Registered-process trial

CameraRingAodProbe is a dedicated opt-in class in the existing SystemUI module, initialized only through shared NetworkSpeedModule start. It registers a receiver requiring android.permission.DUMP. Default state creates no window/timer/display listener. Explicit broadcast com.nodecockpit.customization.CAMERA_RING_PROBE with boolean starttrue starts the trial; startfalse stops. No ordinary app feature setting exists for this probe.

On start, exact-firmware/build and quarantine gates apply. A small top-camera native path is enlarged slightly and stroked dim white in an untouchable/unfocusable type2024 ScreenDecorations window. It is hidden while interactive or display OFF, shows only during noninteractive DOZE/DOZE_SUSPEND, and stops on unsupported rotation, quarantine or180seconds elapsed deadline. Deadline is checked on CPU resume; it does not wake the CPU to enforce timeout. Repeated display changes do not reset the blink interval. Cleanup removes callbacks/listener/window and contains exceptions locally.

Blink uses ordinary uptime Handler scheduling, alternating lit/dark every2.5seconds. No wake lock, alarm, forced power/display state, brightness override, refresh override, screenshot capture, face-unlock invocation or glass dependency. If CPU suspend stalls blink, record that as a limitation. Do not silently compensate with wake locks. Eight pure policy tests cover interactive/off/doze gating, expiry, resume after long sleep, quarantine, rotation and backwards time; actual view/window/display behavior requires phone evidence.

## Test sequence and evidence boundaries

Install verified Node249/hook165 using the staged one-shot updater. Verify package/hook/health before starting. User locks/wakes normally; no automated gestures. First take a short AOD baseline, then explicitly start bounded trial, inspect NodeCameraRing log, display/power state and process CPU-time deltas. Stop with explicit broadcast and verify no probe window remains. User confirms physical ring appearance and blinking. Canvas counters or a screenshot do not prove what a suspended panel displayed.

Live ADB, other services and short measurement windows affect power behavior. This experiment cannot certify overnight battery consumption or burn-in safety. Production app selection, notification collection ownership, proximity/face-down rules and user-facing settings remain subsequent milestones only after proof.

Build/deployment/runtime status is tracked in CODEX_HANDOFF. No visual or battery acceptance yet.


## Installed249 result: visible ring, appearance needs tuning

Verified Node1.37.43/build249/hook165, revision5774 matched, SystemUI PID31111, no hookError/emergency. One-shot installer reports Success, exactly one activation restart24568->31111, healthy/nonquarantined. APK67975449B SHA256fc961eaa0b4d5c33f2c733ef1e65eb1f50889dc0bd5229fdd2ed7cf4412c6fd4.240 adapter tests including8 new policy tests passed; no glass engine changes or engine retesting for this task.

DUMP-protected receiver registration verified. Invisible initialization READY while interactive, with no surface shown; stopped cleanly. User then locked the phone manually. Baseline had no probe window, Power Dozing, committed display DOZE. Active test produced a113x112 window at483,30 using exact cutout contour; top safe-cutout rect485,0-595,173 is NOT the actual contour bounds. Logs alternate phase every approximately2500ms; final captured active trace reached38 toggles/39draws at158seconds. User confirmed seeing it in AOD and reported it very dim and thin. That is visibility proof, not acceptance of final styling or persistent battery behavior.

Probe explicitly stopped; after-stop.json confirms no probe window. Same SystemUI PID31111, hook165 active, no hookError/emergency. No automated phone inputs, display-state or brightness overrides. AOD remains enabled by the user's manual choice; do not silently change it back.

Test appearance was1.5dp stroke (5 physical pixels at this density), white alpha150/255, every2.5s phase transition (5s full cycle). Next real feature should expose thickness/intensity/color and timing instead of requiring a new build for tuning. App filtering, persistent enable state and user-facing controls remain UNIMPLEMENTED. Current build is only explicit synthetic test mode, disabled after cleanup.

Power evidence limits: baseline and active both reported DOZE and wake-lock summary0x41; no DOZE_SUSPEND or material CPU suspend gap was observed (pulse elapsed-vs-uptime deltas approximately0). Other existing wake locks and live ADB mean deep-sleep/overnight behavior is not established. Nominal renderFrameRate120 is mode metadata, NOT measured AOD panel refresh. CPU interval between first/last active snapshots included a user wake/relock, so it is not a controlled A/B performance result. Do not claim negligible battery drain or high-refresh rendering from these measurements. Evidence JSON files in build/camera-notification-ring: health249,awake-before-test,aod-baseline-start/end,aod-ring-start/end,after-stop. First baseline files cpu_ns denotes main-thread schedstat, not whole process; later snapshots correctly distinguish process_cpu_ticks/main_thread_cpu_ns.

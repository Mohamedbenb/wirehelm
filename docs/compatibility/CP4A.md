# Pixel 10 CP4A compatibility

Target: SDK 37, `google/frankel/frankel:17/CP4A.261105.040.A1/16581829:user/release-keys`.

## Binary audit

Read the installed SystemUI APK and matching framework.jar through ADB. SystemUI SHA-256: `f3e03499ad9ccd0318f3f3112a2da2786b8f9f424987458cd66024a9c069bfb0`.

The APK uses a DEX 041 container with three logical DEX files. Inspect all three, using physical-file offsets as specified by the [Android DEX format](https://source.android.com/docs/core/runtime/dex-format#container-format). Reading only the first logical file falsely reports missing classes.

The audit found 46 of 47 checked SystemUI contracts. The absent `SystemBarAttributesListener.onSystemBarAttributesChanged` is an optional first choice: the existing `CommandQueue.onSystemBarAttributesChanged` fallback has the required String argument. No required audited contract was missing.

| Feature | Verified binary contract |
|---|---|
| Network indicator | PhoneStatusBarView inflation and keyguard collision hooks |
| Edge panel and handle | Foreground fallback; framework shader registration, setPostProcess, view-root transaction synchronization, native blur drawable and BLAST queue APIs |
| Notification ring | Final shade render boundary, notification dismissal/removal observers, DozeService/DozeMachine/DozeTriggers hooks |
| Notification Undo | Original row dismissal/reset methods, notification collection/group operations, keyguard filter, entry and stack fields |

Local machine-readable inspection artifacts are under ignored `build/compat-CP4A/`. The existing source owners remain listed in [the code map](../CODE_MAP.md).

## Activation and validation

Build 304 / hook 191 adds this exact fingerprint alongside the existing CP3A fingerprint. SDK mismatch, unknown fingerprints and another incremental build remain rejected. Saved choices, safety leases, watchdog quarantine and per-feature hook checks are retained. No material code or carrier backend is changed.

Binary inspection is complete. Build/install, loaded-hook health and user-visible behavior are separate validation steps; see the [current handoff](../CODEX_HANDOFF.md) for their latest status. Do not interpret this binary audit as validation of notification content, dismissal behavior, ring appearance or touch interaction.

The obsolete Tunisia carrier profile remains disabled. Its database is not part of this compatibility update.

## Runtime evidence on build 304

Local ADB verified installation and hook 191 active in SystemUI PID 18892. The indicator reports one attachment, no detachments, visible sampling and no clipping. Settings delivery and edge failures are zero. The notification ring observer selects an eligible winner with no observer/controller error; Notification Undo is enabled and connected to the native collection. The recovery watchdog remains healthy and unquarantined, with only the one controlled activation reload. Saved feature settings match the pre-activation backup.

A read-only screenshot showed the collapsed edge handle. The user subsequently reported successful verification of the requested expanded panel/handle appearance, locked ring, and shake-to-Undo checks on build 304. These user checks complement the binary and runtime evidence; they are not certification of every lifecycle or future notification case. The optional task-stack callback reports unavailable; the existing system-bar-event/one-shot foreground fallback is selected.

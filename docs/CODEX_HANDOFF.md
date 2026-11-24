# Wirehelm handoff

## Installed build

Wirehelm **1.38.31 (337)** was installed in place over local wireless ADB on the Pixel 10. Android reported version 1.38.31 and version code 337. The installed base APK matched `build/artifacts/Wirehelm-1.38.31-build337.apk` with SHA-256 `0326448546e682ca69637bf83c716709b838aae09477514df48e04f77a809663`.

Build 337 gives network speed, Edge panel and carrier settings their own Flutter screens. The ARM64 release passed signing and Xposed entry checks. Static analysis was clean, 199 Flutter tests passed with 13 skipped, and all 187 Android customization tests passed. [Feature owners](CODE_MAP.md)

## Hands-on checks

The last runtime hook check was on build 336. SystemUI reported hook 204, settings revisions matched at 5961, and the Edge panel reported zero errors. The network indicator was off in saved settings. [Settings delivery](BEHAVIOR_GUIDE.md#2-settings-accepted-delivered-drawn-and-reported)

On build 336, the user confirmed that the Edge remote keyboard shows one readable placeholder and PC power → Unlock PC displays the phone authentication prompt. [Edge controls](EDGE_PANEL.md#controls-page)

The status-bar network-speed readout and SSH session reuse across Edge controls still await on-device confirmation.

## Device and release constraints

- Pixel 10 `frankel` runs Android 17, SDK 37, build `CP4A.261105.040.A1`. Preserve KernelSU, ReSuSFS, signing keys and recovery points. Custota work is on hold. [OTA preparation](OTA_PREPARATION.md) · [Custota notes](CUSTOTA.md)
- Preserve the package `com.example.remote_control`, signing identity and stored settings. The Edge panel uses Card Glass, the handle uses Native Glass and the standalone engine is active. Android owns notification, Quick Settings, brightness and volume styling.
- Direct deployment and updater publication are separate. The last recorded updater alias was build 296. Photos work is on hold after the user verified background downloads. The Pixel controls which notifications can be dismissed on its lock screen.

See the [code map](CODE_MAP.md) for feature owners and the [deployment guide](BUILD_AND_DEPLOY.md) for release checks. Earlier device results and open checks are in the archived handoffs for [builds 308–335](history/HANDOFF_BUILDS_308-335.md) and [builds 274–297](history/HANDOFF_BUILDS_274-297.md).

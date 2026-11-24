# Wirehelm handoff

## Installed build

Wirehelm **1.38.30 (336)** was installed in place on the Pixel 10 over Remote ADB. The relay reconnected. The signed ARM64 APK and Xposed entries were verified, and the installed APK matched `build/artifacts/Wirehelm-1.38.30-build336.apk`. Its SHA-256 is `1bbacd067456fcdd47cafbcb022d20b04ef5b033fc360f92f159d492d24bb272`.

Build 336 accepts a fresh SystemUI report as evidence of the hook. The network speed switch shows its first blocker and waits for the safety check before changing state. At installation, SystemUI was running hook 204 on PID 20609, settings revisions matched at 5961, and the Edge panel reported zero errors. The network indicator was off in saved settings. Eighteen focused Flutter tests and 187 Android customization tests passed for that release. [Settings delivery](BEHAVIOR_GUIDE.md#2-settings-accepted-delivered-drawn-and-reported)

## Hands-on checks

On build 336, the user confirmed that the Edge remote keyboard shows one readable placeholder and PC power → Unlock PC displays the phone authentication prompt. [Edge controls](EDGE_PANEL.md#controls-page)

The status-bar network-speed readout and SSH session reuse across Edge controls still await on-device confirmation.

## Device and release constraints

- Pixel 10 `frankel` runs Android 17, SDK 37, build `CP4A.261105.040.A1`. Preserve KernelSU, ReSuSFS, signing keys and recovery points. Custota work is on hold. [OTA preparation](OTA_PREPARATION.md) · [Custota notes](CUSTOTA.md)
- Preserve the package `com.example.remote_control`, signing identity and stored settings. The Edge panel uses Card Glass, the handle uses Native Glass and the standalone engine is active. Android owns notification, Quick Settings, brightness and volume styling.
- Direct deployment and updater publication are separate. The last recorded updater alias was build 296. Photos work is on hold after the user verified background downloads. The Pixel controls which notifications can be dismissed on its lock screen.

See the [code map](CODE_MAP.md) for feature owners and the [deployment guide](BUILD_AND_DEPLOY.md) for release checks. Earlier device results and open checks are in the archived handoffs for [builds 308–335](history/HANDOFF_BUILDS_308-335.md) and [builds 274–297](history/HANDOFF_BUILDS_274-297.md).

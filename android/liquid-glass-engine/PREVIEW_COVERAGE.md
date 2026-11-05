# Engine preview and test coverage — 1.2.1

Glass Engine Lab 1.2 (APK version code 3, Android 13+) exposes the engine's rendering families, parameters, interactions and lifecycle scenarios. It renders from an app-owned backdrop. It never changes actual phone brightness or SystemUI settings.

## What can be exercised

| Capability | Preview / test path |
| --- | --- |
| Local lens | Original GlassLensRenderer / RenderEffect chain, normal and outward refraction, Clear/Regular, rounded/circular/asymmetric shapes and two-shape union |
| Compositor card source | Exact 240-byte CardLiquidShader through a local RenderEffect input; app-local preblur |
| Two-shape compositor source | Exact 272-byte CardLiquidMergeShader and production packer, independent secondary shape dimensions, merge distance and separation |
| Notification material | Exact 848-byte union source/packer, 1–13 regions, alternate alpha, up to 10 control masks and pill blur |
| QS/brightness material | Exact 1392-byte source/packer, up to 16 regions, per-corner geometry/clip/alpha and independent RTL progress/indicator blur masks |
| Classic material | Exact NativeLiquidMaterial source, all four presets, dark ink, contrast, tint, edge, refraction and diffusion |
| Optical controls | Material blur, bevel, refraction direction/amount, falloff, dispersion, specular, softness, saturation, dimming, veil/regular tone and manual material tint |
| Lighting | Manual light angle and optional live gravity sensor; listener removed while hidden, paused, detached or motion/power policy blocks it |
| Interaction | Touch down/move/up/cancel, native click semantics, press/release displacement, touch reaction and four-pulse ripples with strength/speed/damping |
| Foreground | Canvas text/sun path with editable ink, outline/shadow widths/opacity/colors/offsets and auto contrast colors; separate native TextView/drawable protection sample exercises its older fixed policy |
| Contrast/policy | Known-luminance swatch; actual SmoothInkTone duration/damped transitions, safety repair/limited state, crop/tint/border/tone calculations, tunable MaterialTuning values and validation. This model does not pretend to sample another window |
| Geometry/motion | Position, resize, visibility/alpha, host clip, per-region clip, scale/rotation, progress sweep, moving backdrop, profile/page cycle and combined stress cycle |
| Lifecycle | Activity pause/resume, hide/show host, detach/recreate, rotation with saved settings, sensor/HUD teardown, reduced-motion and power/thermal fallback simulations |
| Failure paths | Forced fallback, deterministic local shader failure, per-profile failure circuit, renderer recreation and diagnostics retaining the failure cause |
| Instrumentation | UI draw/record CPU counts, optional actual engine host-window HUD, shader-build/error counts, profile submission outcomes and copied settings/report |
| CPU contracts | On-device smoke runner plus host unit tests for uniform bounds/layouts, invalid geometry, lease lifetime, hidden readiness grace/timeout, ripple expiry, foreground policy, contrast, transitions and fence metric validation |

The existing class/ABI sources are used. The lab does not copy a different simplified optical model for compositor variants. It changes their **input transport** to an app-owned recorded View, which makes shader behavior inspectable without privileged cross-window access. App-local preblur cannot certify the native compositor blur transport.

## Parameters that are profile-specific

The UI disables controls that do not apply. Separate brightness masks require `QS / brightness` + `Slider`; notification pill blur requires `Notification union`. Per-region clips and separate corners require a supporting profile. The older local/card shader's native Regular adaptation does not expose the newer regular-tone-strength multiplier; that knob is enabled only for profiles which consume it. Classic uses its own parameter group. The native widget sample has its own fixed protection policy; configurable protection is demonstrated in the canvas sample.

Geometry-guide outlines are a diagnostic overlay, separate from the optical rim. Transform scenarios intentionally help reveal backdrop/coordinate alignment errors; successful draw submission does not establish visually correct sampling under every transform.

Policy controls for filtering/publication timing resolve through MaterialTuning, but their scheduling belongs to host integration and is not simulated as production behavior. Invalid policy combinations retain the last valid policy and show `valid=false` in diagnostics. Auto ink uses known demo luminance, not a final-surface pixel readback.

## Suggested exercise sequence

1. Open `QS / brightness` with `Slider`. Set material blur to zero, then vary progress blur and indicator blur separately. Drag the preview, then enable RTL and repeat at progress 0 and 1.
2. Cycle all six shaders. Copy the report and inspect each profile's submission outcome. A submission is not a GPU/pixel correctness pass.
3. Select notification union and region grid; test counts 1 and 13, alternate alpha and pill blur. Select QS and test count 16, per-region clipping and asymmetric corners.
4. Select a merged pair. Move separation and merge distance through overlap; test Clear/Regular, dark/light/checkerboard backdrops and extreme optical values.
5. Enable touch effects. Tap/hold/release/cancel and drag. Change ripple lifetime controls, then disable effects and confirm they stop.
6. Adjust ink/outline/shadow colors, alpha, geometry and text. Compare the canvas sample to native widgets. Enable the known-input policy probe and sweep known luminance/transition duration.
7. Run translate/resize/fade/scale/profile/stress scenarios. Hide/show, pause/resume, rotate and recreate the renderer. A stopped/hidden preview should not keep its own animation or sensor subscription running.
8. Force fallback, then inject a shader failure. The selected local profile should retain fallback and its error without repeated recompilation. Recreate the renderer to retry.
9. Run CPU contract checks and copy the report. Inspect actual device performance using the optional HUD; no isolated glass GPU timing is claimed.

## Native tests that an ordinary APK cannot execute

The coverage panel reports permissions and native method availability, explicitly marked **not executed**. It does not silently replace these tests with a green result:

* Register/unregister the platform compositor shader and verify cleanup.
* Allocate, resize, submit and release actual compositor buffers/layers, including startup readiness and first-buffer failures.
* Supply the real cross-window SAMPLE_BEHIND input and validate blur/refraction across windows.
* Verify applyTransactionOnDraw ordering, presentation/fence behavior and teardown against a real host window.
* Exercise actual screen-off, power-save, thermal/circuit and resource cleanup paths in the privileged backend.

Those need a compatible privileged host. Their algorithmic contracts are unit tested where separable; capability detection is not runtime validation. SystemUI's native component discovery, input/actions, Compose scenes and frame synchronization are adapter integration tests outside this library.

## Validation status

Build and host tests run in the workspace. No emulator is available and the APK has not been installed or visually exercised on the phone in this task. On-device smoke checks, sensor motion, shader GPU/pixel behavior and privileged transport are **not reported as passed**.

## Enforced source inventory

`coverage/inventory.json` maps every engine Java/Kotlin source to a preview/test/privileged requirement. `tools/verify_coverage.py` runs before compilation and rejects unclassified source files. This prevents silent omissions; it is not branch coverage or proof of rendered pixels.

### optical_profiles

Local lens, Compositor card, Two-shape merge, Notification union, QS / brightness, Classic material

Checks: Material uniform, mask, blur and contrast host tests; shader submissions require device execution

Sources: `CardLiquidMergeShader.java`, `CardLiquidParameters.java`, `CardLiquidShader.java`, `CardNotificationShader.java`, `NativeLiquidMaterial.java`, `NativeQsShader.java`, `CardCompositorMaterial.kt`, `GlassBlur.kt`, `GlassLensRenderer.kt`, `GlassReaction.kt`, `GlassTouchRipples.kt`

### uniform_contracts

Exact production uniform packers drive each profile; masks have independent controls

Checks: CardMergeUniformsTest CardNotificationUniformsTest NativeQsUniformsTest NativeLiquidMaterialTest; on-device CPU checks

Sources: `CardMergeUniforms.java`, `CardNotificationUniforms.java`, `NativeQsUniforms.java`

### touch_and_lighting

Touch down/up, press, reaction, four ripples and manual/live sensor lighting

Checks: CardRippleTimelineTest TouchRippleStateTest; live touch and sensor require device

Sources: `CardRippleTimeline.java`, `LightSourceController.kt`, `TouchRippleState.kt`

### foreground_and_policy

Configurable canvas text/sun, native TextView/drawable sample and known-input policy probe

Checks: ForegroundInkStyleTest ForegroundInkPolicyTest GlassContrastTest SmoothInkToneTest DampedShadeTest MaterialTuningTest GlassTransitionMathTest

Sources: `DampedShade.java`, `ForegroundInkStyle.java`, `GlassContrast.java`, `GlassTransitionMath.java`, `MaterialTuning.java`, `SmoothInkTone.java`, `TimedShade.java`, `DrawerForegroundProtection.kt`, `ForegroundInkPolicy.kt`

### resources_and_metrics

Own-window engine HUD, CPU/draw metrics, hide/recreate lifecycle and runtime lease/readiness checks

Checks: GlassShaderLeaseTest GlassFrameStatsTest NativeSurfaceReadinessTest; actual driver/fence behavior requires device

Sources: `GlassFrameObserver.java`, `GlassFrameStats.java`, `GlassPerformanceHud.java`, `GlassResourceMonitor.java`, `GlassShaderLease.java`, `NativeSurfaceReadiness.java`

### privileged_transport

Read-only capability report only; native execution explicitly NOT RUN

Checks: Privileged host required: register/unregister shader, layers, buffers, cross-window backdrop, transactions, real thermal/screen-off policy and teardown

Sources: `CardCompositorBuffer.java`, `CardCompositorSampler.java`, `CardLiquidSurface.java`, `NativeLiquidSurface.java`, `NativeUniformBuffer.java`, `CardCompositorBroker.kt`

### configuration_and_host_contract

Configuration validation, native-session API, source-bounded merge interface and read-only capabilities

Checks: Foreground validation and core policy tests; native attachment/session tests require privileged host

Sources: `EdgeMaterialSurface.java`, `GlassMergeGeometry.java`, `GlassTestConfig.java`, `LiquidGlassEngine.java`, `NativeLiquidConfig.java`

### lab_harness

Scenario controls, background motion, profile cycle, fallback/failure/recreate, policy model and saved state

Checks: GlassLabStateTest; on-device CPU checks; shader failure injection is an interactive device test

Sources: `GlassLabChecks.java`, `GlassLabRenderer.java`, `GlassLabGeometry.kt`, `GlassLabState.kt`, `GlassPreviewView.kt`


## Build verification for this delivery

Final independent build and integrated host checks pass: 110 engine tests, 192 adapter tests and 5 app tests (307 total, zero failures/errors). The final APK/AAR use one shared motion-phase snapshot for visible and captured backdrop drawing; geometry tests cover that clock and ensure merge blur flags cannot overwrite the second shape's width. Both source-boundary and 49-source/8-group coverage inventories pass. Artifact inspection verifies the demo has no requested permissions, SystemUI/Xposed integration or packaged framework stub.

No on-device/GPU run was performed and the in-app CPU smoke runner has not been executed here. The production app/SystemUI was not installed or restarted. This delivery is the independent demo and library, not a new activated SystemUI build.

## Interactive additions in 1.2

Use **Load playground** for immediate tests without finding individual settings:

* **Drag cards together to merge:** two host-owned draggable cards feed their current geometry directly to the unchanged two-shape merge shader. Move them together/apart or hold each with a different finger. Geometry controls still adjust merge distance and shape.
* **Multi-touch ripple card:** an enlarged card with press, reaction and ripple effects enabled. Tap/release with multiple fingers to exercise the engine's four-pulse history; adjust strength/speed/damping under Touch.
* **Movable glass cards:** independently drag several QS-profile cards. Pointer capture follows stable card indices and normalized positions survive resizing. The selected card's foreground is drawn last.
* **Functional glass buttons:** tap to toggle and count clicks. The default last button is disabled and ignores input. QS button corner geometry also changes with toggle state. Dragging beyond touch slop or cancellation does not click. Options controls host dragging and last-button disable state.
* **Brightness slider** and **Maximum region grid:** existing masks and region budgets remain directly accessible.

Gesture hit testing uses the displayed host transform and clip; removed cards release their pointers. Host input/actions are demonstrations, not new engine physics, SystemUI controls or device actions. The engine controls optics, merging and touch effects. Reset positions/state separately, or recreate the renderer for a full reset. Temporary card positions and toggle states do not persist through activity recreation.

The independent gesture model has unit tests for multi-pointer movement, duplicate/nonfinite input, tap versus drag, cancelled/disabled touches, resize normalization, removal and reset. Interactive geometry tests include tiny preview bounds and profile region limits. No screenshot/GPU validation of these additions is claimed until exercised on device.

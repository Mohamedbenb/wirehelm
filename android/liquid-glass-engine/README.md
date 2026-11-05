# Liquid Glass Engine

Reusable Android library, engine 1.5.2-dev / API 1. It has no dependency on Flutter, the Node Cockpit application, libxposed or SystemUI classes. The main app remains the settings/controller; the SystemUI adapter remains responsible for discovering components, geometry/visibility, native paint ownership, transitions, authentication gates and recovery.

## What moved

Material shader sources and generation; material parameter validation and uniform packing; card/union/QS material profiles; blur/refraction, reaction/ripple calculations; foreground contrast/outline/shadow policy; generic Android rendering and compositor buffer transport; shader leases, resource/performance instrumentation and surface readiness. Existing Android view hosts, settings storage, services and all native component hooks remain in their host projects.

Java and Kotlin package/class names are retained to preserve binary/reflection compatibility during extraction. Legacy names containing `Qs`, `Notification` or `Edge` describe existing material profiles/contracts; they do not authorize the engine to find or hook those components. Most Java implementation types remain package-private. SystemUI currently consumes that compatibility surface in the same package. This is a source-module boundary, not a security sandbox or process boundary.

## Native-frame shader prototype (248 / hook164)

`GlassNativeFrameMaterial` binds the existing SurfaceFlinger QS shader/token and card optics to an empty RenderNode inside native drawing. It creates one effect surface per container, carries no captured backdrop pixels, and merges position/crop/scale/opacity/material transactions with the owning window's native frame number. UI appearances are frozen per window-frame callback; RenderThread callbacks never read Compose state. A bounded generation-aware join rejects old windows and frames. An unchanged pose/material does not repost its buffer. The transparent buffer and shader lease are shared per native root and released on root detach or explicit host disable. Ordinary draw-owner replacement retires its effect surface with the next native frame; bounded pending retirements are drained on root teardown.

The current adapter trial uses this **only for the brightness container**. Native progress and indicator drawing remain the accepted baseline. This is not full brightness migration, and QS migration is paused. Native geometry callbacks do not include alpha: the adapter supplies effective ancestor RenderNode opacity, observes tracked native alpha setters and isolates firmware-specific Compose reflection from the baseline API. Background paint alpha is not component opacity.

Warmup establishes a committed hidden transaction and available resources, not proof of GPU presentation. It uses no new capture, per-frame shader compilation or Android preblur for the shader container. Static material options are reused; touch ripples, sensor lighting and progress masks are not part of this trial. Axis-aligned equal-radius containers only; rotation, swapped bounds, stretch, unfamiliar layers, filters/compositing and foreign-thread opacity are outside this proof. Unsupported integration retains the baseline; geometry is never inferred from an old invisible window. Window hiding tears down child surfaces even when no final positionLost arrives.

Host contract: construct on the UI thread, provide valid card-options JSON and effective-opacity supplier, call `record` in the actual primitive Canvas and suppress that primitive only on true. Call `appearanceChanged` after tracked UI-thread native alpha setters, `configure` on optics edits, and `close` on draw-owner detach. `releaseWindowResources` is for host disable; ordinary replacement reuses the root lease. The engine has no SystemUI class dependency and installs no hooks. Privileged platform methods remain required, so this bridge cannot run in the ordinary lab app.

CPU frame-policy tests and coverage mapping exist; actual framework callback, compositing order, cancellation, ancestor clips, replacement and presented motion still require device validation. The established native brightness preview remains available separately.

## Public entry points

* `GlassBrightnessGeometry.track`: validated component-local primitive bounds and asymmetric corners. It takes ordinary scalar values; Compose packed-value decoding stays in the adapter.
* `GlassBrightnessMaterial`: component-local Android backdrop blur/tint/border used in the lab’s native brightness preview. Android31+, hardware Canvas and native drawable access required; calls belong on the UI thread. Construct per native draw owner with progress/indicator blur radii, call `draw` inside native drawing with an ordinal slot0..3 and CONTAINER/TRACK/INDICATOR role, and suppress stock only when it returns true. Host retains input, transforms, clipping and draw order. Call `setVisible` for visibility and `close` on detach or configuration replacement. Acquisition failure is cached per slot; recreate to retry. There is no shader substitution. The unchanged TRACK policy applies progress blur at local x<=1 and zero blur on the trailing track; hosts must supply native start-relative geometry, not screen coordinates.

* `com.nodecockpit.customization.LiquidGlassEngine`: VERSION / API_VERSION and optional native compositor sessions (`attach`, `configure`, `active`, `diagnostics`, idempotent `close`). All session calls belong on the UI thread. Native configuration must validate and select `backend: native`; close/recreate to switch renderer families. Host owns placement, foreground and stock fallback. A session does not install hooks or grant platform permissions.
* `com.nodecockpit.customization.GlassPreviewView`: Android 13+ app-local material demonstration using the extracted `GlassLensRenderer`, `GlassBlur` and shared foreground policy. It only records the caller-owned backdrop view. The bounded GlassLabState/GlassLabCatalog expose profile, scene, material, masks, geometry, foreground, interaction, policy and failure/lifecycle controls. The original scalar properties remain as compatibility helpers. It does not sample other apps or modify screen brightness.

The compositor backend still requires matching platform support and privileges. Loading the AAR into an ordinary app does not provide those capabilities. The preview backend uses public RenderNode/RenderEffect/RuntimeShader APIs and needs no root. It demonstrates optics/lifecycle in one window, not cross-window synchronization or SystemUI transition correctness.

## Build without the current app

From the repository/source-bundle root, set JAVA_HOME to JDK 17+ compatible with the Android build tools and ANDROID_HOME to an installed Android SDK (platform 37). Python 3 must be available as `python`.

```powershell
android/gradlew.bat -p glass-lab :liquid-glass-engine:testDebugUnitTest :liquid-glass-engine:assembleRelease :liquid-glass-demo:assembleDebug
```

The independent settings file does not load Flutter or include the SystemUI adapter. Initial dependency downloads need network access. Gradle's `--offline` option works after dependencies are cached.

Outputs: `android/liquid-glass-engine/build/outputs/aar/liquid-glass-engine-release.aar` and `android/liquid-glass-demo/build/outputs/apk/debug/liquid-glass-demo-debug.apk`. Add the source module as a Gradle project dependency to retain Kotlin/annotation dependency metadata; a manually copied AAR alone does not convey all dependency metadata.

`tools/verify_boundary.py` runs before compilation and rejects known SystemUI, hook-framework and host-project dependencies. The tiny `libs/card-platform-compile-only.jar` is a compile-only stub for the optional compositor sampler, not a runtime implementation, and must not ship in the AAR's classes.

## Control and failure ownership

The existing app continues saving settings and reading hook/material diagnostics. The SystemUI adapter reports `engine=1.2.1/api1` through its existing telemetry. No new service, foreground notification, process or settings app is introduced for production. An app update still updates the bundled engine; independent engine installation/hot swapping is intentionally not implemented.

The host must keep native fallback visible until material readiness, invalidate on relevant state changes and close sessions on final disposal. Renderer exceptions or unavailable privileges must retain fallback; invalid facade arguments are rejected before attachment. Code running inside SystemUI shares SystemUI's process and can still crash it. Moving code into a library does not eliminate stale host geometry or synchronize a backdrop automatically.

## Glass Engine Lab 1.2

The standalone APK (`com.nodecockpit.glassdemo`, version code 3, Android 13+) now has all six rendering profiles, grouped optical/shape/mask/foreground/policy controls, touch/ripple/sensor input, motion and lifecycle scenarios, failure injection/recovery, CPU contract checks and live/copyable diagnostics. Settings survive activity recreation. It requires no root or requested permissions and does not change device settings.

See [PREVIEW_COVERAGE.md](PREVIEW_COVERAGE.md) for exact capabilities, profile-specific controls, test recipes, privileged-only paths and actual validation status. The coverage inventory is enforced before compilation. Every source must declare how it is previewed or tested; a capability probe is never counted as native execution.

Existing MIT optical implementation attribution is retained in `src/main/assets/licenses/liquid-glass-views.txt` and source headers.

### Direct interaction playgrounds

The Load playground menu now provides direct card merging, multi-touch ripples, movable cards, functional toggle/disabled glass buttons, brightness and maximum-region samples. Dragging and button callbacks are explicitly lab-owned host behavior; material merging, deformation, ripples and foreground rendering use the engine. The gesture model supports independent pointer IDs, drag-versus-click thresholds, cancellation, disabled regions and normalized positions across resizing. Reset positions/button states separately from material settings. Button states and dragged positions are temporary sample-host state and reset on renderer/activity recreation.

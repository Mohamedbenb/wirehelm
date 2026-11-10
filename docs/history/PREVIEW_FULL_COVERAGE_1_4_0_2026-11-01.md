# Standalone engine preview 1.4.0

## Scope and installation

The standalone preview uses the extracted engine with app-owned Android foreground widgets. This change does not deploy Node Cockpit or modify SystemUI adapters. The APK is `build/artifacts/Liquid-Glass-Preview-1.4.0.apk`, version code 8. ADB reported `Success` for installation. The app was not launched, and no device gestures, screenshots, UI inspection or SystemUI restart were performed.

## Preview coverage

The preview separates SystemUI-like samples (notifications, paged QS, brightness and volume), material studies (local lens, card and classic) and engine building blocks (buttons, merging cards, ripples, movable cards, geometry, masks, native icons and policy). These are app-owned samples, not imported private SystemUI components.

Tune groups are Glass, Shape, Motion, Touch, Ink and Checks. Controls are scoped to supported profiles rather than presented as universally effective. Added controls include optical falloff, bevel, dispersion, specular response, softness, veil, dimming, lighting, ripple/reaction tuning, per-corner shapes, independently sized secondary shapes and clipped/alpha regions. Native mask content follows the selected region count. The local-lens study also supports a merged pair. Classic has its own material controls and backdrop selector.

The shared motion chooser exposes supported movement, resize, fade, scale, backdrop and stress scenarios. Slider samples additionally expose progress sweep. The canvas policy study exposes profile cycling and luminance/tone inputs; those simulated inputs are clearly distinguished from hardware measurements. Browser controls scroll independently below the fixed preview.

## Foreground ink

Native text and drawable icons consume the same `ForegroundInkStyle` policy, including text/icon color, outline width and opacity, shadow radius and opacity, offsets and automatic/manual edge colors. `GlassInkDrawable` caches glyph alpha, outline and shadow masks; it does not capture the backdrop or apply a shader to the app chrome. Source, geometry and mask-affecting style changes invalidate the cache, while paint-only changes reuse it. Published bitmap masks are released by reference rather than explicitly recycled while RenderThread may still use them. The native-icon study contains platform drawable, bitmap and path examples. Button backgrounds and input/ripple behavior remain native.

## Blur and composition

Profiles 2–4 expose shader versus local Android RenderEffect blur. The card profile uses Android preblur directly and explains that choice instead of offering an ineffective backend selector. Local lens and classic retain their own rendering paths. Brightness/volume retain their component-specific progress masks and glass indicators.

Standalone View variants of compositor shaders output transparent pixels outside the material and premultiplied coverage at its edge. Their original compositor sources and uniform ABI remain unchanged. Removing the extra hard union clip lets the shader draw the actual smooth merge bridge. Slider input masks still restrict rendering to their card geometry. This adaptation prevents a preblurred rectangular backdrop from appearing outside the glass.

## Checks and lifecycle

Checks provides CPU contract checks, next-submission failure injection where supported, forced fallback, local power/thermal simulations, HUD, pause, hide/show, recovery, renderer recreation and activity recreation. Simulations do not change device power or thermal settings. Pausing freezes motion while preserving the rendered material. Recovery clears local simulation state and recreates the renderer to reset its failure circuit.

The HUD uses public Window FrameMetrics callbacks instead of private renderer reflection. It labels results as host frame reports, not presentation FPS. These reports describe the hosting window and cannot prove that native foreground and glass were presented together. Actual preview/native-buffer attachment declares API 33 requirements; pure library utilities retain their lower API applicability. No privileged cross-window sampling or compositor transport is claimed by this app.

## Verification and remaining limits

- Debug APK assembled successfully.
- Engine unit tests: 126 passed, zero failures or errors.
- Demo lint: zero errors, five warnings. Engine lint: zero errors, 21 warnings. No lint baseline was added to hide errors.
- New CPU tests cover independent secondary geometry/radius limits, local shader output coverage/ABI preservation and truthful host-frame reporting.
- APK installed successfully through ADB; SHA-256 accompanies the artifact.

CPU checks and successful compilation establish contracts and build validity. They do not establish GPU output, actual rendering cost, visual authenticity or synchronized presentation. The new studies and diagnostics make those behaviors accessible for manual validation, which remains pending. Saved-instance restoration is not a promise of permanent preferences after force-stop. Privileged SystemUI lifecycle/transport tests remain a separate integration phase.

# Current engine preview coverage audit

## Version 1.4.0 completion update

The gaps below describe the earlier 1.3.0 audit. Version 1.4.0 implements the material-family samples, scoped tuning controls, drawable-icon ink, geometry/mask studies, shared motion chooser and explicit failure/fallback exercises. See [the implementation and validation report](PREVIEW_FULL_COVERAGE_1_4_0_2026-11-01.md) for current coverage and limits. Local checks pass: 126 unit tests, zero failures, and zero lint errors. Installation succeeded; these new additions have not been visually or GPU validated on the phone because device interaction was excluded by the user.

Scope: current standalone demo source and extracted engine. This audit supersedes statements about visible controls in the historical 1.1 lab coverage document. Engine source inventory classification and passing unit tests do not establish current UI access or GPU correctness.

## Currently exposed

| Area | Current preview |
|---|---|
| Components | Individual/grouped notifications, horizontal brightness, paged/stateful QS tiles, vertical volume with local mute and streams |
| Building blocks | Glass buttons, merging cards, touch ripples, movable cards |
| Rendering profiles | Profile 1 card, 2 merge, 3 notification union and 4 QS/slider; shader blur and local Android RenderEffect |
| Optics/tint | Blur strength, refraction amount, tint strength, saturation, Clear/Regular, backdrop cycling |
| Geometry/motion | Radius, merge distance, width/height; Still, Move, Resize, Fade, Scale, Backdrop; component-specific expansion and page offsets |
| Touch/light | Ripple on/off, press response on/off, live light on/off; functional component controls |
| Native ink | Text color toggle, size, outline width/opacity, shadow size/opacity; applies to the preview foreground |
| Diagnostics | Error/build counters, reports, capability probe, renderer recreation |

The initial audit found 15 distinct numeric keys explicitly exposed through slider builders. Version 1.3.0 adds the two shadow-offset controls and manual outline/shadow color entry. Component gestures and selectors expose additional behavior; a control count is not overall feature coverage.

## Gaps and required follow-up

| Area | Evidence / gap | Follow-up |
|---|---|---|
| Local and classic profiles | Engine retains profiles 0 and 5, but no current sample selects them | Add dedicated material building-block samples with profile-specific controls |
| Material tuning | Bevel, falloff, dispersion, specular, softness, dimming, veil/Regular tone and manual lighting angle remain in the engine without visible controls | Add named optical/tint/light groups under Tune, scoped to supported materials |
| Touch tuning | Ripple strength/speed/damping, reaction intensity and drag threshold are retained but unexposed | Put these controls beneath the matching ripple/drag building blocks |
| Shapes and masks | Per-corner radii, alternate alpha, region clipping, region count, union separation and notification control-mask blur are not currently selectable | Add standalone geometry/mask exercises; do not alter component item counts without native content to match |
| Native foreground | Version 1.3.0 uses the engine ForegroundInkStyle policy for native text and text-based glyphs, including offsets/manual colors/auto colors and opacity. Bitmap/vector ImageButton decoration remains a separate path | Validate drawable-icon outline/shadow separately; do not claim text styling covers every drawable |
| Button state ownership | Fixed in 1.3.0: one app-owned state feeds both material shape and native appearance; native button input does not also toggle engine interaction state | Initial, toggled, disabled, renderer-recreated and activity-recreated states checked on the phone |
| Failure/fallback/policy | injectFailure, runContractChecks, forced fallback, power/thermal simulations, policy probe and HUD exist in engine code but have no current UI entry | Add explicit diagnostics exercises with clear CPU-only versus GPU/device status |
| Lifecycle/configuration | Version 1.3.0 saves/restores selected sample, material settings, notification state, QS state/page, volume streams/mute restoration, button state and normalized dragged-card positions. Info exposes activity recreation separately from renderer recreation | On-device recreation checks passed; this is saved-instance restoration, not permanent storage after force-stop or an exhaustive process-death test |
| Motion reachability | Resize exists in the footer cycle, but the Tune Motion list omits it. Progress sweep and stress/profile cycles are absent from the current chooser | Use a shared list for supported scenarios; isolate profile cycling from native component samples |

## Order of work

1. Button state, native text ink and activity restoration were completed in 1.3.0. Drawable-icon ink remains to be covered separately.
2. Restore material-family samples and scoped optical, shape, touch and lighting controls.
3. Add explicit failure/fallback/policy/metrics exercises and update the source inventory's UI references.
4. Repeat focused functional and GPU/presentation checks for those additions before declaring preview coverage complete.

Privileged compositor transport, cross-window sampling and SystemUI adapters remain outside this standalone-preview task. Their presence in the engine inventory is not evidence that the app can exercise them.

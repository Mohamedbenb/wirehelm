# Preview 1.3.0: state ownership and native ink

Installed standalone app version 1.3.0 / code 7 and engine 1.3.0. Public API level remains 1; ForegroundInkStyle is now exposed as an immutable style configuration for caller-owned native text.

## Changes

- Glass buttons have one app-owned toggle map. The material receives that map through region activity; native labels, alpha and disabled semantics commit during native geometry placement. Native samples no longer also toggle engine interaction state.
- The button sample supports disabling its last button and retains its state through renderer/activity recreation.
- Native text and text-based glyphs consume the engine outline/shadow policy. Outline drawing uses the native text Layout before the native fill pass. Opacity, automatic/manual colors and shadow offsets use the same bounded engine configuration. Relative label/icon text sizes are retained when changing font scale. Native bitmap/vector ImageButtons are not claimed to have this text decoration path.
- Tune exposes shadow offsets, automatic color choices and validated #RRGGBB manual colors.
- Activity saved state covers sample/material settings, notification grouping and expansion, QS page/toggles, volume stream levels and pre-mute values, button state, and normalized movable-card positions. Transient animations settle before snapshots. Pressed pointers are not restored.
- Info now distinguishes Recreate renderer and Recreate activity. Renderer recreation also preserves dragged-card positions.

## Validation

Build succeeded; 122 engine tests passed with zero failures/errors. New position tests cover restoration without pressed pointers and rejection of malformed/nonfinite/out-of-range snapshots without replacing existing state.

Phone checks:

- Airplane button began Off, toggled On, and Home exposed enabled=false after Disable last button was selected.
- Button state and disabled state survived both activity and renderer recreation.
- An outline setting changed to 50% survived full activity recreation.
- A grouped, expanded notification remained grouped and expanded after activity recreation.
- QS page 2 and Torch On were restored; returning to page 1 retained Wi-Fi On.
- Muted Ring stream restored as Ring/0% after recreation; Unmute recovered the pre-mute 45% value.
- A dragged card moved from `[84,390][662,653]` to `[234,500][812,763]`; both activity and renderer recreation retained the latter bounds exactly in the accessibility hierarchy.
- Process-scoped error-log inspection returned no entries.
- Static screenshot inspected: `build/preview-1.3.0-buttons.png`, showing distinct active/inactive/disabled states and native text outlines.

These checks do not establish every-frame GPU synchronization, every drawable-icon style path, permanent preferences, or exhaustive OS process-death restoration. Manual ink-color appearance remains available for user review. Remaining engine/UI gaps are tracked in ENGINE_PREVIEW_COVERAGE_AUDIT_2026-11-01.md.

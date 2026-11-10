# Notification preview lifecycle checks

Scope: standalone Liquid Glass preview on Pixel 10. User confirmed notification visuals before the following checks. No new installation or SystemUI deployment was needed during this validation run.

## Behavior checked

- Shader mode: three single-card expand/collapse cycles. Details and Reply appeared expanded and details disappeared collapsed.
- Shader mode: two shared-container expand/collapse cycles. The third notification appeared expanded (message bounds `[141,1030][939,1104]`) and disappeared collapsed.
- Android RenderEffect mode explicitly selected and verified through the displayed selector.
- Android mode: expanded container content retained after Home/resume and renderer recreation through Info. The native third row remained present after each transition.
- Android mode: Move, Resize, Fade, Scale and Backdrop modes exercised for approximately three seconds each, then returned to Still. Subsequent collapse hid the additional group rows.
- Android mode: individual-card details and Reply appeared expanded and details disappeared collapsed.
- Main renderer diagnostics reported `error=none`, `failures=0`, and zero remaining pointers after the lifecycle sequence.

## Short frame measurements

| Run | Frames | Janky frames | Frame p95 | GPU p95 |
|---|---:|---:|---:|---:|
| Shader, individual-card cycles | 614 | 2 (0.33%) | 11 ms | 3 ms |
| Shader, shared-container cycles | 407 | 1 (0.25%) | 11 ms | 3 ms |
| Android, shared-container motion sequence | 1938 | 3 (0.15%) | 14 ms | 5 ms |

Measurements come from Android dumpsys gfxinfo. These short runs include UI input and hierarchy-inspection work and are not controlled comparisons, sustained thermal benchmarks, or proof of frame-perfect GPU synchronization. User visual confirmation and hierarchy checks serve different purposes.

The existing engine unit tests passed during the preceding implementation build. Preview left in Android mode with a collapsed single notification and Still motion.

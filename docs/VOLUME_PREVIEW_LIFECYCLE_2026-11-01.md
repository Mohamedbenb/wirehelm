# Volume preview lifecycle checks

Standalone engine preview on Pixel 10. No app code changes or installation were required in this validation turn. ADB disconnected during setup; the user re-enabled local wireless debugging and the measured runs below were performed after it was restored. Initial setup attempts were excluded.

## Behavior

- Six vertical drags in Android blur mode; subsequent mute reached zero and unmute restored the pre-mute value (26%).
- Home/resume retained the value. Info renderer recreation retained the value and speaker control.
- Move, Resize, Fade, Scale and Backdrop modes ran for approximately three seconds each, then returned to Still. Renderer reported error=none, zero failures and zero pointers. Process-scoped error-log inspection returned no entries.
- After lifecycle checks, Ring retained 45%, Alarm 72%, and Media 26% while switching streams.
- Shader mode was explicitly selected and verified, then six vertical drags were measured. A later attempt to restore Android mode was not confirmed after the active UI surface changed; final backend selection is not asserted.

| Short run | Frames | Janky frames | Frame p95 | GPU p95 |
|---|---:|---:|---:|---:|
| Android blur, drags | 405 | 1 (0.25%) | 12 ms | 3 ms |
| Android blur, motion cycle | 1892 | 3 (0.16%) | 12 ms | 3 ms |
| Shader blur, drags | 450 | 0 (0.00%) | 12 ms | 3 ms |

Android dumpsys gfxinfo measurements include app/UI/input work. These short sequential runs are not sustained thermal benchmarks or controlled blur-backend comparisons. They do not establish pixel correctness or exact synchronization on every GPU frame.

MainActivity saved-instance restoration remains absent, as documented in the current engine coverage audit. The tests here cover renderer recreation and pause/resume, not full activity/process state restoration.

# Brightness preview lifecycle and short performance checks

Scope: standalone `com.nodecockpit.glassdemo` on the connected Pixel 10. Visual appearance was validated by the user before these checks.

## Corrections installed

- Reset the cached Android blur radius when releasing its RenderNode effect so a resumed preview reinstalls the effect.
- Preserve the stage child index when recreating the renderer so native foreground views remain above the material.
- Expose Resize in the motion cycle and Recreate renderer in Info for repeatable manual checks.

## Checks

Gradle assembleDebug succeeded. The existing engine unit test suite passed: 115 tests, zero failures and zero errors.

The on-device sequence covered six horizontal brightness drags, renderer recreation through Info, Home/background and resume, then approximately three seconds each of Move, Resize, Fade, Scale and Backdrop modes. Native brightness text remained present in the hierarchy after recreation/resume. Main renderer diagnostics reported no errors, zero masked-blur failures and zero remaining pointers. The inspected AndroidRuntime log excerpt contained no matching crash output.

| Short run | Rendered frames | Janky frames | Frame p95 | GPU p95 |
|---|---:|---:|---:|---:|
| Android blur, six drags | 536 | 2 (0.37%) | 15 ms | 9 ms |
| Android blur, motion cycle | 1884 | 1 (0.05%) | 14 ms | 6 ms |
| Shader blur, six drags | 492 | 1 (0.20%) | 14 ms | 5 ms |

Values are Android dumpsys gfxinfo observations from short sequential runs, including input/UI work. They are not controlled benchmarks, sustained thermal measurements, proof of exact frame synchronization, or a validation of all GPU pixels. A separate attempted shader switch remained in Android mode; its measurements were excluded from the table. Shader selection was explicitly confirmed before the final shader measurement.

The updated APK was installed successfully. No SystemUI hook deployment was performed.

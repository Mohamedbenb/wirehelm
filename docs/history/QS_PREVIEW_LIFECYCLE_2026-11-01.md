# QS preview device checks

Standalone engine preview, Pixel 10. No source changes or installation were required during this validation run.

## Behavior

- Wi-Fi and Bluetooth toggled from Off to On in the accessibility hierarchy.
- Next opened page 2. Torch toggled On. Returning to page 1 retained Wi-Fi and Bluetooth; swiping forward retained Torch. Reverse swipe returned with page 1 states still intact, without toggling the tile used to initiate the swipe.
- A captured settled frame showed an active rounded rectangular tile alongside inactive pill shapes. Image: `build/qs-preview-device.png`. This is a static visual inspection, not a frame-by-frame transition proof.
- Page 2 and Torch state survived renderer recreation and Home/resume.
- Android RenderEffect selection was explicitly confirmed before timing its interaction sequence.
- Six local toggles and six page changes completed, followed by approximately three seconds each of Move, Resize, Fade, Scale and Backdrop motion, returning to Still.
- Main renderer reported no errors, zero failures, and zero remaining pointers. Process-scoped error-log inspection returned no entries.
- A page change immediately followed by Home resumed on the destination page with its expected tile present. Exact pause timing relative to the animation midpoint was not traced.

## Short measurements

| Android blur run | Frames | Janky frames | Frame p95 | GPU p95 |
|---|---:|---:|---:|---:|
| Tile toggles and page changes | 640 | 4 (0.62%) | 13 ms | 5 ms |
| Motion cycle | 1909 | 2 (0.10%) | 14 ms | 6 ms |

Android dumpsys gfxinfo observations from short runs, including UI/input work. These are not sustained thermal measurements, controlled shader-vs-Android comparisons, or proof of exact native/material synchronization on every frame.

The app was left on QS page 2 with Android blur and Still motion for user visual review. Existing engine tests passed during the implementation build preceding this run.

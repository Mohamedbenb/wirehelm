# Vertical volume preview

Implemented and installed in the standalone engine app. Volume uses profile 4 / slider scene with a vertical orientation, sharing the brightness fill/indicator pipeline. The rotated SDK SeekBar was removed.

Touch, Android blur fill bounds and glass indicator geometry use shared functions in GlassLabGeometry. Shader mode uses the same vertical orientation with a bottom-anchored fill and straight cutoff. The Android blur input is recorded around the full control bounds plus filter padding, keeping that render region stable as volume changes.

Native foreground includes a speaker mute/restore button, stream name, value and stream selector. Media/Ring/Alarm levels are local preview state. Fill and indicator blur can be adjusted separately.

## Verification

- Build succeeded and APK installation reported Success.
- 120 engine unit tests passed, including five new geometry tests covering direction, fill endpoints, touch mapping, indicator bounds and invalid progress.
- Phone: upward drag produced 58%; downward drag produced 26%. Mute produced 0%, unmute restored 26%.
- Stream selection showed independent Ring 45% and Alarm 72%; returning to Media restored 26%.
- Android blur selection explicitly confirmed. Dragging continued to work; renderer reported error=none, zero failures and zero remaining pointers. Process-scoped error-log read returned no entries.
- Static captures inspected: `build/volume-preview-device.png` (shader) and `build/volume-preview-android.png` (Android). These show a vertical glass control, bottom-up fill and horizontal glass indicator.

Follow-up lifecycle and short frame measurements are recorded in [VOLUME_PREVIEW_LIFECYCLE_2026-11-01.md](VOLUME_PREVIEW_LIFECYCLE_2026-11-01.md). These do not establish frame-perfect synchronization or sustained performance.

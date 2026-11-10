# Node Cockpit 1.1.14 (build 36)

- Replaced the oversized synthetic pointer marker with the native Windows cursor composited into each captured desktop frame. The cursor keeps its Windows shape, size, and hotspot and scales with the image, including in fullscreen.
- Changed trackpad-relative movement to set precise cursor positions, avoiding Windows mouse acceleration and reducing unpredictable jumps near screen edges.
- Kept direct-touch clicks and the trackpad double-tap-and-hold drag gesture.

Validated with Flutter analysis, desktop interaction tests, the signed-in Windows worker smoke test, an Android ARM64 release build, and installation on the connected A36 (version 1.1.14, build 36).

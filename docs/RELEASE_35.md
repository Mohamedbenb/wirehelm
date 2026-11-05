# Node Cockpit 1.1.13 (build 35)

- Trackpad taps now click at the current desktop pointer instead of teleporting it to the finger location. Swipes move the pointer relatively; double-tap-and-hold remains available for dragging.
- Increased default trackpad sensitivity and added Low, Medium, and High settings.
- Added a compact cursor marker that follows the actual Windows cursor position in the stream, since Windows screen capture does not include the cursor.
- Added the same stream, input, and sensitivity options to the fullscreen landscape view in a scrollable dialog that fits both orientations.

Validated with desktop interaction tests, Flutter analysis, and the signed-in Windows worker smoke test. The Android ARM64 release APK was built and installed on the connected A36; live streaming and the fullscreen options were verified on-device.

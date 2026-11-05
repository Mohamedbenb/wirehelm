# Release 1.1.0 (build 22)

## Live desktop

- Added an opt-in live desktop viewer to the device's main remote tools.
- Tap the image to move/click, choose left/right click from the app bar, and use the wheel gesture to scroll. The text action opens an explicit send dialog.
- Windows capture runs in the signed-in interactive desktop session and does not require FFmpeg. The session uses a private temporary directory, a random per-session control token over the existing SSH tunnel, a heartbeat, and a ten-minute maximum duration. It stops when the app leaves the foreground or the viewer closes.
- Linux capture/control currently requires an active X11 desktop, FFmpeg, xrandr, and xdotool. Wayland is not supported in this release.

## Validation

- Full Flutter test suite and static analysis pass.
- Windows scheduled-task capture smoke test passed locally without rendering or saving the captured frame outside its temporary session folder.

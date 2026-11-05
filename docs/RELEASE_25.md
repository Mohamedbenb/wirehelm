# 1.1.3 (build 25)

- Fixed Windows live desktop access to its per-session frame files when the SSH launcher and interactive desktop worker use different Windows logon tokens. Queued pointer and click actions are now applied before the next screen capture.
- Mouse pointer mode now moves on tap or drag and never clicks when a finger lifts. Use the visible Left click and Right click controls to click. Touch mode retains tap-to-left-click and drag-to-move.
- Reworked the stream choices around actual responsiveness: Fast response (960 px, 20 fps), Balanced (1280 px, 8 fps), and Data saver (640 px, 4 fps).
- Restored Enter in the Shortcuts pad and migrated existing per-device keyboard layouts once so the key reappears. Added an obvious button for choosing visible keys and shortcuts, creating named shortcuts, and deleting custom shortcuts.

Flutter static analysis and the Android ARM64 release build completed successfully.

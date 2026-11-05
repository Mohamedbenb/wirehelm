# Node Cockpit 1.1.8 (build 30)

- Added the familiar trackpad double-tap-and-hold drag gesture. The second tap holds the left button at the current cursor position; moving then drags or selects text, and lifting releases it.
- Kept single-tap-to-click, swipe-to-move, single long-press drag, direct-touch mode, and the explicit right-click control.

Flutter analysis and the focused trackpad gesture tests passed. I installed the Android ARM64 update on the A36 and exercised double-tap-and-drag over the live Windows stream: the cursor moved, the left button released, and stopping the stream did not move the cursor.

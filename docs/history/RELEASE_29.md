# Node Cockpit 1.1.7 (build 29)

- Changed trackpad mode to relative pointer movement. Swipes move the Windows or Linux cursor from its current position; taps click at that position without relocating it.
- Holding for 450 ms and then moving starts a deliberate drag. Direct touch mode still uses absolute screen positions for tapping and dragging.
- Kept the separate left- and right-click controls.

Flutter analysis and the focused gesture tests passed. On the A36 over LAN, a swipe moved the Windows cursor and a tap left its cursor coordinates unchanged; stopping the stream also left the cursor position unchanged. The update APK was installed and launched successfully.

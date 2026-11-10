# 1.1.4 (build 26)

- Removed the synthetic crosshair overlay from live desktop.
- Restored tap-to-left-click in both input modes. A drag in Mouse pointer mode moves without holding a mouse button; drag in Touch mode holds left for drag-and-drop. Right-click remains available as an explicit action.
- The Windows stream uses the user's normal private `%TEMP%` permissions for its per-session files. A later intermittent `frame.seq` read failure required an additional retry fix in build 27.
- Fast response now targets up to 30 fps at 960 px; the bootstrap checks for new frames every 10 ms. Balanced and Data saver presets remain available.

Flutter static analysis and the Android ARM64 release build completed successfully. Sixty fps is not promised by this JPEG-over-SSH capture path; consistent 60 fps would need a native screen encoder and video transport such as WebRTC/H.264.

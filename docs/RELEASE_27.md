# Node Cockpit 1.1.5 (build 27)

- Prevented intermittent Windows live desktop stream shutdowns when the SSH reader polls `frame.seq` during the capture worker's atomic file replacement. Brief sharing or access collisions now skip a poll and retry.
- Stopping the stream or leaving the screen only releases mouse buttons that were actually held. This avoids unmatched button-up events being interpreted as clicks; explicit left- and right-click controls remain available.
- Kept the 30 fps Fast response target and the other stream presets.

Flutter static analysis and the Android ARM64 release build completed successfully.

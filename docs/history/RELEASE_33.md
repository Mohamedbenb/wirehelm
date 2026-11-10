# Node Cockpit 1.1.11 (build 33)

- Removed the large pointer overlay from the live desktop stream.
- A trackpad tap still moves to the tapped position and clicks. A follow-up tap within 450 ms stays at the first tap's cursor position, allowing double-clicks without a location jump. This uses elapsed time rather than distance between taps.
- Double-tap-and-hold still supports dragging from the current cursor position.

Flutter analysis and desktop surface interaction tests passed. The Android ARM64 release build was installed on the connected A36 for live verification.

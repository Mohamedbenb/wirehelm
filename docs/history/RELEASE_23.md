# 1.1.1 (build 23)

- Live desktop taps are mapped directly within the displayed image. Black bars cannot send clicks. Taps send a single click and drags release correctly outside the image.
- Windows capture and cursor movement explicitly use physical pixels under the same per-monitor DPI context.
- Fixed PowerShell selecting an integer clamping overload for fractional pointer coordinates, which could send a click to an edge of the screen.
- Temporary contention or replacement of a Windows frame file no longer aborts the desktop stream. Input files are published only after fully written.
- Stream shutdown allows the Windows helper to remove its task and files; the worker releases held mouse buttons. Late startup/frame callbacks cannot revive a stopped viewer.
- The viewer has a clear title, a Details action for errors, and no overlapping Start button.
- Update notices appear on the device's main page as well as the device list. A known newer update remains visible across navigation or an offline update source, and clears after installation.

Validation includes portrait/landscape touch regression tests, cached-update widget tests, Windows capture, real stream contention/recovery and cleanup, and physical cursor mapping without clicks.

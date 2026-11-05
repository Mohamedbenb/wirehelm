# Native terminal — 1.4.0+47

Android terminal display/emulation/input/selection now use pinned Termux v0.118.3 components inside a native platform view. Dart owns SSH authentication, transport and session lifecycle. No local phone shell or Termux app installation is required. Existing command composer, modifiers, extra keys, multiline-paste review, clear, font controls, history and reopen controls remain.

The native emulator lives independently of the view so navigation preserves scrollback and parses protocol responses while hidden. Resize dimensions originate from Termux's actual font cell measurement; SSH uses the existing coalesced Windows resize path. The SSH subclass does not create or resize a local PTY. Protocol replies bypass typed-key modifiers and startup gating. Native copy/paste callbacks route through app clipboard/review controls.

The previous Dart renderer remains a fallback for non-Android targets and host-side transport tests; it does not parse or render Android stream output. This release is a module replacement, not a guarantee that remote ConPTY or SSH issues cannot occur.

Upstream source and modification details: android/termux-terminal/UPSTREAM.md.

Live verification on the Samsung phone: native PowerShell prompt and echo command rendered and executed; Samsung IME opened and terminal resized; portrait/landscape preserved output; Pi shell executed stty size (23 rows, 53 columns with keyboard open); leaving and reopening the Pi terminal retained transcript and session. Corrected native renderer initialization order and focusability during these tests. Flutter analysis and eight host-side transport/UI tests passed. Native selection and complex full-screen terminal programs still need broader usage testing.

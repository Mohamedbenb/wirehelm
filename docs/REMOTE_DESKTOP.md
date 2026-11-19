# Remote desktop cursor investigation

## Missing Windows pointer (2026-11-16)

The user reports the desktop keeps updating and pointer movement/clicks still work while the pointer image disappears, without a clear trigger.

The Windows worker in `lib/services/remote_desktop.dart` captures the screen with `CopyFromScreen`, composites the pointer with `NcDesktopInput.DrawCursor`, then scales/encodes the complete bitmap. `lib/widgets/desktop_surface.dart` displays that complete JPEG; there is no separate client-side pointer renderer.

`DrawCursor` silently returns when GetCursorInfo fails, CURSOR_SHOWING is absent, or hCursor is null. Thus a live stream can omit the pointer while control still works. Microsoft's [CURSORINFO documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-cursorinfo) defines flags 2 as CURSOR_SUPPRESSED, distinct from flags 0 (hidden).

A read-only Windows PowerShell probe ran in process session 1, matching active console session 1. All 12 recorded samples returned GetCursorInfo success, flags 2, null cursor image and a valid GetCursorPos result. Calling the unchanged production DrawCursor against an off-screen magenta bitmap changed zero pixels in every sample. Hide-pointer-while-typing was queried successfully and is disabled. This reproduces the cursor omission path on the PC; it does not establish what caused Windows to enter suppression or prove every prior episode had the same cause.

Evidence is in ignored `build/desktop-cursor-probe.ps1` and `build/desktop-cursor-probe.json`. The probe compiles the embedded production C# unchanged, reads cursor metadata and draws only onto a blank image. No desktop screenshot, pointer move, click, clipboard access or settings change was performed. It does not exercise the full SSH-to-phone stream.

## Actual Windows cursor recovery (build 316)

The user explicitly requested restoring the real Windows pointer. No synthetic/stream-only cursor fallback is implemented.

The Windows worker now recovers CURSOR_SUPPRESSED at explicit stream startup and immediately before a queued mouse action. It sends two bounded absolute mouse-input events through SendInput: an adjacent physical pixel, then the original pixel. Zero-delta mouse input was accepted on this PC but left suppression unchanged; a real one-pixel movement and return changed flags 2 → 1, supplied a valid native cursor handle and left the original position unchanged in six follow-up samples. Ordinary application-hidden state (flags 0) is left alone.

Requested absolute and trackpad-relative movement also uses SendInput, mapped to pixel centers over the physical virtual desktop. This avoids SetCursorPos-only movement and preserves the app's chosen sensitivity without applying Windows relative-input acceleration a second time. Coordinates include negative monitor origins and clipping. SendInput failures are checked; partial two-event recovery makes one bounded restoration attempt and reports failure. Button-release controls bypass recovery; absolute releases attempt movement inside try/finally so a movement failure still releases the button. A startup recovery error is recorded without terminating capture. ShowCursor display counters, cursor schemes, registry policy and persistent Windows settings are unchanged. Recovery never runs in the frame-capture loop or an idle timer.

The existing DrawCursor path continues compositing the actual native cursor shape and hotspot into the captured bitmap. It never substitutes an arrow. The phone displays the complete received JPEG as before.

The compiled production helper passed a host check after native visibility was restored: all 12 samples had showing state, a real cursor handle and unchanged position; the native cursor drew 282 pixels onto a blank test bitmap. This does not by itself prove startup recovery on every suppressed host or a full phone session. Earlier raw zero-delta and movement probes are retained under ignored `build/desktop-cursor-native-wake.json` and `build/desktop-cursor-native-nudge.json`; final production-helper evidence is `build/desktop-cursor-production-check.json`.

Sixteen deterministic tests in `test/remote_desktop_cursor_test.py` cover ABI layout, pixel-center mapping, recovery conditions, edges/tiny bounds, errors, partial restoration and DPI cleanup. Fifteen C# cases execute under both installed x64/x86 PowerShell runtimes with all native input and capture calls replaced by fail-closed stubs. Run `python test/remote_desktop_cursor_test.py`. Ten focused Flutter checks pass, one opt-in live transport check is skipped; analysis is clean. These checks do not establish long-session behavior on the phone.

The earlier diagnostic limitations remain separate: cursor-query failure is not distinguished from hidden state in DrawCursor, and transient __NC_ERROR__ messages are retained privately until a later stream failure. No wider capture/error UI redesign is included.

The worker is sent from the app at session startup. Start a new Remote desktop session after installing an update; existing sessions do not hot-reload it. Build, installed version and actual phone validation are recorded separately in the handoff.

## Deployment evidence

Build 316 installed through Remote ADB; installed APK SHA-256 matches `8d20feec612668b5cc04a418e90863fda1c64b16d62e5273097df70520d6370a`. SystemUI stayed PID 26678 with hook 197 (screenOff, no error, revisions 5941/5941); panel preferences matched the pre-update snapshot. No hook reload or root/carrier module change. The user was asked to start a fresh desktop session and verify the real cursor, clicks and dragging; this manual validation is pending. Evidence `build/desktop-316-verification.json`.

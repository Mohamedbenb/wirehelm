# Terminal compatibility — 1.4.1+48

A raw recording from standalone Termux confirmed the ConPTY height expansion mismatch: Windows repainted the old viewport from row one (75–100 in a numbered test) while the emulator had pulled rows 52–74 into that viewport. Repainting overwrote those history rows.

Windows sessions now enable a native buffer policy that appends blank rows on height expansion and keeps history in scrollback. The policy is off for Linux and does not alter alternate-screen resizing. It addresses same-column height expansion, including keyboard dismissal; column-changing reflow remains upstream behavior and needs separate verification.

The overflow menu groups input, copying/navigation and session actions. Terminal options contains font sizing, extra keys, clear, restart and licenses. Clear is no longer mislabeled as Ctrl+C. Existing restart confirmation and paste review are retained.

Regression tests cover preserving history during expansion plus a destructive viewport repaint and preserving upstream Linux expansion behavior.

Verification: Flutter analysis clean; eight existing tests and two native regression tests passed. Installed ARM64 APK48 on Samsung phone; Windows 1..100 output retained consecutive lines across keyboard dismissal (including 56–99 visible after scrolling), and overflow/options entries fit without clipping. Width-changing reflow and full-screen programs require broader testing.

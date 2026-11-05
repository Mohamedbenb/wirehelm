# Termux terminal components

Source: https://github.com/termux/termux-app/tree/v0.118.3
Pinned release: v0.118.3 (downloaded from GitHub codeload).
Includes terminal-emulator Java sources and terminal-view Java sources/resources, with original copyright headers retained.

Local upstream change: TerminalSession.java changes `public final class TerminalSession` to `public class TerminalSession`, permitting the application's SSH-backed subclass. TerminalBuffer and TerminalEmulator add an opt-in ConPTY height-expansion policy: keep history in scrollback and append blank screen rows rather than pulling history into a repaintable viewport. Linux and alternate-screen behavior remains upstream. NativeTerminalBridge.RemoteSession overrides all process/PTY entry points used by the view; no local shell, Termux bootstrap, package manager or JNI library is installed. Android library build configuration is local.

Upstream LICENSE.md documents GPLv3-only licensing with Apache-2.0 exceptions for Android Terminal Emulator code. Retain notices and make corresponding source available with distributions as applicable. The source and adapter are included in this workspace.

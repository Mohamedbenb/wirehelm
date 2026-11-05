# Updating Wirehelm away from home

For current build/publication commands use [BUILD_AND_DEPLOY.md](BUILD_AND_DEPLOY.md). For download/install/hook-activation distinctions see [behavior guide section9](BEHAVIOR_GUIDE.md#9-update-and-deployment-success-boundaries). Older numbered examples below describe their historical release; always choose a build code above the installed app.

Install the version containing **Update Node Cockpit** once using ADB. Later
updates can be downloaded through the PC's existing SSH/Tailscale connection;
the phone and PC do not need the same Wi-Fi network.

1. Build the APK on the PC, keeping the same package name and signing key:

   ```powershell
   .\scripts\build_update.ps1 -BuildNumber <next-build-code>
   ```

   Increase the build number for subsequent updates. The script builds a smaller
   ARM64 release APK using this PC's existing signing key, then publishes it to
   both the new update path and the old `app-debug.apk` path for older installed
   versions. Switching signing keys will make the updater reject the APK.

2. Keep the PC awake, online, and reachable over SSH/Tailscale.
3. On the phone, open **Settings → App updates**, select **Desktop** as the
   source, then continue. The selection is remembered and the app connects when
   needed. Older versions still open the updater from the device's tools menu;
   use that once to install the version with the Settings entry.
4. The default remote path is:

   ```text
   <checkout>/build/app/outputs/flutter-apk/node-cockpit-update.apk
   ```

   Change it if the project was moved. It is saved separately for each device.
5. Tap **Download update**. The APK streams into the app's private cache. The
   package, signing certificate, version code, and complete byte count are
   checked before enabling installation. Cancelled/failed downloads are removed.
6. Tap **Install update**. The first time, Android may ask you to allow
   installations from Node Cockpit. Enable that permission, return to the app,
   and tap **Install update** again.
7. Confirm the update in Android's installer, then reopen the app.

Saved devices, credentials, and settings remain in place. Wireless debugging,
router port forwarding, public download hosting, and FFmpeg are not required.
Downloading is initiated from the update page, not a background polling job.
The Devices page shows an update banner when the saved source is connected and
its APK has a newer build. It checks on app resume and once a minute without
downloading the APK or reconnecting a disconnected device. The build script
publishes a small `.apk.json` version file beside both APK paths; keep it with
the APK if you move the files to another device. Select an update source in
Settings once to enable these checks. **Later** hides that build for this session.
Android installation still requires its normal confirmation. Phone restrictions
such as Samsung Auto Blocker or device-management policies can also prevent
sideloading; the Android installer controls that decision.

# Terminal improvements

The terminal keeps its shell and scrollback when you leave its screen. A lost
SSH connection closes the old shell; reconnection starts a new one and retains
scrollback. A command that was interrupted by network loss is not replayed.

Windows opens PowerShell directly with a PTY, UTF-8 encoding, a working-directory
prompt, and PSReadLine Emacs bindings (Ctrl+A/E/U, arrows/history, menu-style Tab
completion). Prediction is disabled when the installed PSReadLine supports it.
Startup waits for the ready marker and reports failure instead of hiding output
forever. This does not change your saved PowerShell profile.

- Two compact, fixed rows provide Ctrl/Alt, arrows, Tab, Escape, Home/End,
  page keys, slash and hyphen. Tap the terminal to type; **⋮** can show/hide the
  keyboard and extra keys. The toolbar remains above Android's keyboard.
- **⋮ → Command composer** allows editing a command before sending it.
  **Insert** sends a single line without Enter; **Run** sends it with Enter.
  Windows multiline scripts are encoded and executed as one script block.
- Composer history is limited to 20 entries in the live terminal session. It is
  not persisted to disk by the app. Remote shell history follows that shell's
  own settings.
- **⋮** provides paste, copy selection/scrollback, latest output, persistent
  font size, interrupt, Enter, clear screen, and shell restart.
- Windows startup preserves cursor-control sequences and answers terminal
  queries independently of Ctrl/Alt keys. Windows owns line reflow; keyboard
  animation resizes are consolidated before notifying the remote PTY.
- Multiline clipboard pastes require confirmation because newlines can execute
  commands. Clear screen sends interrupt/clear input on Windows before clearing
  ConPTY's remote screen to prevent stale content returning after resize.
- Restart closes the shell and its running commands; it preserves scrollback.

This is an SSH command-line terminal. Desktop keyboard input and screenshot
tools remain separate from it.

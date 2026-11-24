# Wirehelm on CachyOS and KDE Plasma

In Wirehelm, add a new device and choose **CachyOS · KDE Plasma** under **Command environment**. Enter the PC's LAN or tailnet address and use the SSH account already signed into Plasma. A fresh OS installation usually has a different SSH host key. Verify the new key on the PC if Wirehelm prompts you.

Enable OpenSSH on the PC if it is inactive. Use **Install identity** in Wirehelm while connected with a password to authorize your phone’s SSH public key. The Linux installer works with fish and other login shells that can launch `sh`.

```sh
sudo systemctl enable --now sshd
```

## Remote keyboard

Open **Remote keyboard** and tap a key or send a draft. On KDE Wayland, approve the desktop input prompt on the PC. The open keyboard page reuses its current session. Keys, modifiers and saved shortcuts go to the focused window.

**Send text** sets the PC clipboard through Klipper and presses Ctrl+V. **Paste in terminal** uses Ctrl+Shift+V. Both retain the text in the PC clipboard, and Klipper may retain it in clipboard history. The phone clears the draft once the worker confirms it sent the shortcut. A receiving app can still decline paste.

Requires a running Plasma session, Python with GObject bindings, and the KDE XDG Desktop Portal. Typical CachyOS packages are `python-gobject` and `xdg-desktop-portal-kde`. On X11, Wirehelm uses `xdotool`.

## Remember KDE approval

Open the shield in **Remote keyboard** or **Live desktop** and choose **Turn on**. Start that feature and check **Allow the application to do this without asking next time** in KDE’s prompt on the PC before approving. The phone saves the token in secure storage for the verified SSH host and account. Keyboard-only and live desktop approval are independent. KDE can ask again if the saved approval is no longer valid.

**Turn off and forget** in the same dialog clears the token from this phone. You can end current sharing from Plasma. Remote control requires the desktop user to have a running Plasma session.

## Wake and open the desktop through the Pi

In the Raspberry Pi’s **Network & Pi health** screen, choose the saved CachyOS PC and use **Wake setup** to save the PC Ethernet MAC if needed. **Wake & open desktop** sends the existing Wake-on-LAN packet through the Pi and waits for SSH. An already reachable PC shows **Open desktop**.

Wirehelm connects to the PC with its saved SSH account. If that account’s existing Plasma Wayland session is locked, Android asks for a fingerprint or the phone’s screen-lock credential. The app unlocks that specific session, wakes the display through KDE, and opens **Live desktop**. Enable saved Live desktop approval before relying on this while away from the PC. After a fresh boot, sign in to Plasma on the PC first.

Open **Unlock PC** from the CachyOS device’s **Controls → Power controls** to unlock and wake its display without opening a stream.

## Power, text size and displays

**Controls → Power controls** includes Lock, Unlock PC, Sleep, Lock & sleep, Restart and Shut down. Live desktop also offers **Lock & sleep** under its options. Lock & sleep waits for Plasma to report the lock before requesting suspend.

Under **Controls → Display**, **Plasma text size** updates the General, menu, toolbar, taskbar, window title, fixed-width and small font roles while preserving their families and styles. Plasma’s GTK integration can sync the General font to GTK apps. Apps with their own fonts may need to be reopened or configured separately. Use **Display configuration** for resolution and refresh rate, scaling, orientation, primary display, mirroring and logical positions. Changes apply immediately. **Restore previous settings** is available for 15 seconds.

## Other desktop tools

| Tool | CachyOS backend |
|---|---|
| Live desktop | Approve screen and input sharing in Plasma. Wirehelm uses PipeWire for the selected view, the portal for mouse and keyboard, and GStreamer to send JPEG over SSH. Requires `gst-plugin-pipewire` and either `gst-plugins-good` or `gst-libav`. |
| Screenshot | KDE Spectacle captures a full desktop screenshot. FFmpeg or ImageMagick can resize the preview. |
| Clipboard shelf | Text can use Klipper. Install `wl-clipboard` for image transfers. |
| Camera and audio | FFmpeg and V4L2 for cameras. PipeWire's PulseAudio service supplies microphone sources and desktop output monitors. ALSA remains available when the PulseAudio service is absent. |
| Saved controls | Lock the desktop, check displays, turn displays on and off, and check or mute PipeWire output. Linux power and system templates are available in the device editor. |
| Terminal, SFTP, remote downloads | The existing Linux paths apply. Remote downloads use Python 3. |
| Rooted OTA preparation | Use the Linux avbroot and KernelSU tools in the selected host folder with the existing signing keys. |

The port targets the signed-in KDE Wayland session. Windows display presets, adapter switching and text size controls have no CachyOS controls in this pass.

## Verification

The CachyOS PC granted a keyboard-only portal session and the worker closed it on disconnect. A second approved session produced a PipeWire JPEG in memory and delivered Enter to a focused temporary window. With persistent approval, new keyboard and live desktop workers restored their sessions on the same PC without another prompt. The restored desktop produced a fresh JPEG. The tests discarded the captured pixels and did not exercise the Android app connection.

## Smart bulb

Open the Linux device in Wirehelm and select **Controls → Accessories → Smart bulb**. The SSH host talks to the bulb over its LAN. Use an always-on host such as a Raspberry Pi when you need control while the desktop sleeps.

On a new host, tap **Install TinyTuya** and **Set up bulb**. Enter the bulb's LAN IPv4 address, Smart Life Virtual ID, and Tuya local key. The host verifies the connection before saving the configuration in its private Wirehelm settings. The current screen supports standard Tuya RGB and tunable-white bulbs with data points 20–24. Power and mode changes apply immediately. Moving a slider sends live updates, and releasing it sends the final setting.

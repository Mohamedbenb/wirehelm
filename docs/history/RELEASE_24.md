# 1.1.2 (build 24)

- Live desktop input no longer uses a long press to generate a right click. Touch mode taps and drags with the left button; Mouse pointer mode moves without holding a button. Left and right click controls are explicit and available in either mode.
- Added Responsive, Balanced, and Data saver stream presets for different image detail, refresh rate, CPU use, and bandwidth.
- Screenshot capture now transfers a scaled preview first. The original PNG remains in a private, uniquely named temporary folder on the remote device until Download is tapped; it is deleted after a successful save or when the screenshot screen closes. Old capture folders are swept after 24 hours.
- The remote keyboard lets users choose visible navigation/function keys and shortcuts, and create up to 24 named shortcuts from modifier-key chords. Layout choices are saved per device.
- Pi network health distinguishes a direct LAN route to the saved PC from a routed or VPN path. Wake-on-LAN can save the PC's Ethernet MAC, derive the subnet broadcast from the Pi's route, send the wake packet, and wait for the PC's SSH port before offering Connect.

Validation: Flutter static analysis completed with no issues. The update APK is built for Android ARM64.

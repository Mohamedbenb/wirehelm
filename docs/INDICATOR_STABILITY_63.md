# Indicator stability — 1.6.1+65

The existing APK remains the manager and libxposed module. No boot, AVB, kernel or system_server changes were made. The KernelSU recovery module remains unchanged.

## Fixes and customization

Preference refreshes now render the cached sample without hiding the indicator or resetting counters. Attach/detach recovery follows replacement status-bar views; only the main SystemUI process renders the meter. Sampling, diagnostics and configuration work remain bounded.

The compact two-line layout separates the rate and equally sized unit; a one-line layout is optional. Upload and direction arrows can be hidden independently. Arrow spacing, download/upload spacing, system-icon spacing, rate width, indicator height and vertical offset are adjustable. Arrows now use their natural glyph width plus the selected gap rather than a fixed-width cell. The rate allocation is independent of requested text size, so changing font size scales the glyphs without moving a right-anchored meter left. Left/right placement is configurable; right placement prepends the readout to the actual Pixel end-side content group, before its dynamic icons. Bytes/bits, decimal places, interval, text size and idle behavior are configurable with an example preview. Native text fitting respects available clock-row space and reserves the natural widths of right-side system icons. Wide layouts can reduce text below the selected maximum size to fit; values and units always share the resulting size. The adjustable height remains capped by the containing SystemUI row. Width and height clipping are reported. Android can still hide its status bar in fullscreen applications.

A separate Customization health screen explains feature state, configuration revisions, hook protocol/PID, view attachment and clipping, sample age, safety lease, backend versions, recovery status and recent events. Raw diagnostics remain available behind an expansion.

## Safety policy

A verified root result grants a 90-second monotonic lease tied to the current boot. Transient checks cannot renew it without verification; expiry suspends effective output while retaining the user's desired setting. Confirmed disabled/removed/incompatible recovery backend, denied access and quarantine still disable immediately. The hook checks the lease independently. The manager persists only the last verified same-boot observation to avoid an artificial disable when its process restarts. It never clears framework or KernelSU disable flags.

## Validation

Native policy tests cover lease expiry/boot boundaries, formatting and configuration snapshots. Flutter tests cover health classification, dependency requirements and existing home/keyboard behavior; analysis passed. Release APK metadata and Xposed entry-class verification passed.

Live Pixel testing confirmed upload visibility, preserved idle-off settings, configuration refreshes and manager process restart without restarting SystemUI. No attributable app/SystemUI crash was found in the filtered crash log. Hook updates used targeted SystemUI restarts, not full device reboots.

Crash loops, root revocation, safe mode and long-duration doze were not deliberately induced. Short live testing cannot guarantee that every intermittent lifecycle case has been eliminated.

## Final build 65 device result

Protocol 9 was active in SystemUI PID 4290. Final manager/hook configuration revision 93 matched. The text-size control was exercised at 8sp and 14sp with an unchanged 38dp rate allocation, confirming that it no longer shifts the meter. Original-resolution captures exercised upload plus arrows with a natural-width arrow, 6dp inter-direction gap and 6dp system-icon gap. Signal, Wi-Fi and battery remained visible.

Final checks passed: one attachment, zero detachments, zero counter resets, zero diagnostic delivery failures, fresh root lease and no clipping. Restored configuration: enabled, right, stacked, bytes, one decimal, 1-second interval, 14sp maximum, 17dp height, 38dp rate width, zero arrow gap, 6dp direction and system-icon gaps, zero vertical offset, upload off, arrows off and idle hiding off. The actual two-line text remains bounded by automatic fitting. These are short functional tests, not a long-term stability guarantee.

# Notification ring

The notification ring shows a slowly fading light around the front camera while a supported Pixel is in portrait ambient display. Open **Notification ring** in Wirehelm, choose apps, then set each app’s color and priority. Save to apply the choices.

The highest-priority eligible notification wins. For equal priorities, the newest notification wins. Dismissing it lets the next eligible notification take over. Ongoing notifications require opt-in. Android’s lock-screen visibility rules apply, so a notification hidden on the lock screen may never become a ring candidate.

The **Fade duration** applies to each half of the pulse. The ring rises to the configured intensity, then fades to zero over the same duration. Intensity changes ring opacity independently of display brightness.

## With Always-on Display off

Enable **Use ring with Always-on Display off** to let eligible notifications request a native ambient session. Android’s proximity, power and authentication gates still apply. The feature releases its session when the last eligible notification clears, the phone wakes, or the feature is disabled. The Android Always-on Display setting stays at its chosen value.

The ring also has a short appearance test. That test uses the saved appearance and ends automatically. It does not post a sample notification.

## Implementation

CameraRingSettings validates app rules and appearance settings. CameraRingSelection picks the winner. CameraRingNotifications and CameraRingEligibility observe the filtered SystemUI notification list and reconcile removals. CameraNotificationRing owns the ring window and fade. CameraRingAmbientController coordinates the optional native ambient session.

The renderer uses notification metadata for eligibility and does not read or store message text. Ordinary animation can pause during CPU suspend. Overnight battery cost has not been measured.

## Stuck window investigation (build 308)

A passive capture on CP4A / hook 192 found the phone awake while ring diagnostics reported `state=screen awake`, with draws=256 and pulseUpdates=231 unchanged across captures. WindowManager still reported one `NodeCockpit.NotificationRing` window with a shown surface and `isVisible=true`. SystemUI PID remained 3314. Evidence is saved locally under ignored `build/ring-stuck-2026-11-12.json`; no lock, wake, settings change or SystemUI restart was performed during capture.

The old cleanup gated removal on `View.isAttachedToWindow()` and discarded the view reference unconditionally. A WindowManager registration can exist before the view's first attachment, making this an unsafe ownership check and a likely explanation for the orphan. AOSP's [WindowManagerGlobal](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/view/WindowManagerGlobal.java) tracks registration in its own view/root lists. Build 309 / hook 193 removes that gate: a dedicated owner keeps the exact view and remover until removal succeeds or WindowManager confirms absence. Cleanup hides the view first and makes at most three delayed retries after a transient failure, retaining ownership if cleanup continues to fail. Diagnostics report owned/attached state, window creates/removes and cleanup failures. No recurring wake alarm or wake lock was added.

Three ownership regression tests plus four AOD policy and eight pulse tests pass. Build/deployment status is in the handoff. The user authorized installation: build 309 is installed and hook 193 reports active with synchronized settings and no error after one controlled SystemUI reload. The old window is absent; the post-install snapshot was Dozing with proximity near/unknown, windowOwned=false and zero WindowManager ring windows. A normal wake/unlock reproduction and visual validation remain pending. The exact triggering transition was not instrumented before the incident.

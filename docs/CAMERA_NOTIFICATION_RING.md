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

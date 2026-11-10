# Superseded feasibility notes: implementation is now in NOTIFICATION_UNDO.md

User subsequently approved implementation.255/hook171 prototype installed and user reports working (live5 holds/5 undos/no error).256 source improves permission flow and records exact exclusions after Messenger/music skip report. Music is intentionally excluded; Messenger needs the new diagnostic reason before classification. See docs/NOTIFICATION_UNDO.md and CODEX_HANDOFF for current state. No shake sensor yet; original tap/reply/delete callback proof still pending because sample permission was denied. Earlier statements below that no code was authorized/performed describe only the initial research date/stage, not current work.

## Historical feasibility investigation

# Notification dismissal undo: feasibility only

2026-11-03 user asked to examine shake-to-undo dismissal suggestion. No implementation/build/install/settings change/phone operation authorized or performed by this investigation. Ring254/hook170 remains the accepted complete baseline; glass remains paused.

## Proposed contract

A short configurable grace window (initially5s) after an ordinary individual swipe. Visually hide promptly, defer irreversible server cancellation, permit explicit Undo (first prototype) and then a deliberate shake while awake within the same window. Timeout commits the original cancellation once. Shake detection runs only while a pending undo exists, with sensitivity/haptic feedback, no continuous screen-off sensor loop. This is bounded deferred dismissal, not arbitrary recovery of already-cancelled historical notifications.

## Verified boundaries

Cached exact CP3A.261005.005 SystemUIGoogle-inspect.apk remains after cleanup. NotifCollection.dismissNotifications builds a background NotifCollection$$ExternalSyntheticLambda5, executes it via mBgExecutor, then calls locallyDismissNotifications and dispatchEventsAndRebuildList. The lambda invokes IStatusBarService.onNotificationClear with entry/package/user/key/dismissal stats. Its NotificationEntry.mSbn is read when run, so holding a mutable Runnable without generation checks could cancel a later updated notification. Native local dismissal state and server cancellation are separate but current build does not offer a general public undo hook.

updateDismissInterceptors is specialized by R8 to BubbleCoordinator$2 (concrete checkcast), so do not promise registering an arbitrary proxy/interceptor through a generic interface. Need a targeted prototype of deferred server cancellation plus native local-entry restoration. Verify all state changes use native pipeline invalidation/drawing rather than an external renderer. Evidence build/camera-notification-ring/notif-collection.smali.txt and dismiss-cancel-dispatch.smali.txt; only tiny disassembly generated, no APK archive duplication.

Official docs: Notification.Builder.setDeleteIntent sends the app-supplied PendingIntent on explicit user clearing (https://developer.android.com/reference/android/app/Notification.Builder#setDeleteIntent(android.app.PendingIntent)). NotificationListenerService cancellation really removes the notification; snooze is a distinct remove-and-later-post lifecycle (https://developer.android.com/reference/android/service/notification/NotificationListenerService). A reposted look-alike cannot be assumed to undo an app's already-run dismissal effects or preserve live actions.

## Required policy and proof before a feature build

- Keep original Android entry/identity/action tokens in memory only during grace; never synthesize a duplicate notification. App-origin removal/cancellation wins and invalidates undo. Key reuse/repost/update must invalidate or safely transfer pending work by generation; do not cancel a new update at old deadline.
- Initially ordinary single swipe only. Clear all, summary/children batches, bubbles, ongoing services, calls, media and active remote input have separate semantics and should pass through unchanged until specifically supported. Native auto-dismiss child/summary and interception state cannot be restored by blindly setting one mDismissState.
- Undo must restore the original native entry and working original tap/reply/actions without a second alert, duplicate entry or content logging. Expiry commits once. A small Undo-button prototype should prove this before sensor work.
- Ring eligibility must remain absent while dismissal is pending and only be re-admitted through authoritative native render on explicit undo. Preserve accepted251/254 non-resurrection/privacy/dismissal guarantees. No ring backend changes merely for this examination.
- User lock/deactivation should resolve pending grace predictably (initial proposal: commit) and stop the sensor. Avoid replaying stale callbacks across process/native instance generations.
- Process death before deferred cancellation can cause the still-server-active notification to reappear after native reload. This conservative failure mode must be accepted/documented; no reliable promise of transactional undo across abrupt SystemUI death from an in-memory client queue.

Research result: plausible short-window feature on exact firmware, NOT yet proven. First acceptance must test held cancellation, action-preserving restore, genuine app removal/update races and timeout. No need for additional runtime renderer or glass engine. Do not start implementation from these notes without user go-ahead.

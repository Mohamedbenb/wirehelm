# Notification ring priority audit —2026-11-04

## Scope and outcome

User initially reported the wrong app color, then could not reproduce it and requested a general audit of code/update handling. This audit changed no production source, settings, notifications or phone UI, built/installed no APK and restarted no service. Current installed263/hook179 stays in place. Evidence is under build/camera-notification-ring/priority-audit/. No physical wrong-color observation was captured, so none of the findings is established as the cause of that reported event.

The numeric comparator is correct for the documented contract:5 highest; higher priority outranks recency; equal priority uses newest SBN post time then stable key. Current saved rules are ChatGPT3/white, WhatsApp2/green, Messenger1/cyan. The awake snapshot reported ChatGPT3 with no ring error, consistent with that order (not proof of physical color).

## Update path checked

Native completed filtered list -> CameraRingNotifications.snapshot -> CameraRingEligibility.rendered replaces metadata -> CameraNotificationRing.notifications -> render reselects -> existing view.style updates Paint color -> invalidate. New higher-priority keys therefore take over on a completed render; lower-priority arrivals do not steal the ring. Priority setting edits trigger the same selection without needing a new notification. Removal/cancellation hooks queue reconciliation and drop absent/dismissed/canceled keys; the next remaining eligible app wins. Nonempty fallback retains the owned ambient session. Last eligible removal releases it. Android keyguard visibility and ongoing opt-in remain eligibility gates.

Exact cached firmware DEX call tracing found ShadeListBuilder$$ExternalSyntheticLambda7.run publishes the final list before calling RenderStageManager.dispatchOnAfterRenderEntries with mReadOnlyNotifList. Both frame and timeout paths run the same listener set. The final callback is present as an actual invoke, not optimized away in DEX. No alternative dropped-arrival path was found in this audit. Native stability/visibility can still delay or suppress a completed list; the ring intentionally waits for authoritative eligibility rather than reading raw retained notifications.

## F1 —stale metadata during reconciliation (P2, conditional)

CameraRingEligibility.reconcile retains keys but never refreshes the Notice objects. Updating an existing key keeps its old posted timestamp, ongoing/summary flags and therefore potentially its old selection effect until the next authoritative rendered call.

The standalone audit compiles the unchanged production CameraRingSelection/Eligibility/Settings classes and runs12 scenarios. Ten controls pass, including a new high key, lower-key arrival, settings priority edit, deletion fallback and non-resurrection. Two counterexamples reproduce stale metadata: equal-priority A updates newer than B but B remains chosen after reconcile; a high-priority normal entry becomes an excluded ongoing entry with the same key but remains chosen over a low normal entry. Authoritative rendered refresh corrects both.

This establishes a stale-cache interval, not a permanently missed callback or phone-visible wrong color. Reconciliation is deliberately conservative about additions, so the repair must preserve the accepted non-resurrection/privacy guarantee. Prefer generation-aware invalidation and authoritative refresh; do not blindly re-add raw collection records or promote an unconfirmed new generation to solve this.

Sources: CameraRingEligibility.java:15, CameraRingSelection.java:15. Reproduction: RingPriorityAudit.java/results.json in the audit directory. That harness is outside production/test source; no failing tests were left in CI.

## F2 —expired preview can keep its old paint (P2, source-confirmed path)

Test deadline uses elapsedRealtime; its Handler expiry uses uptime. Handler delays are deferred by deep sleep: https://developer.android.com/reference/android/os/Handler#postDelayed(java.lang.Runnable,%20long).

CameraNotificationRing.step notices elapsed expiry and clears testUntil but does not call render/restyle. With the feature enabled it continues invalidating the old view. onDraw changes alpha only. Thus if CPU sleep separates the clocks and a pulse executes before the delayed expiry/render callback, the previous test color can persist after logical test expiry, or continue showing with no actual eligible notice. A later render fixes it. This is especially visible when the preview's highest configured app differs from the actual pending winner. It was not reproduced visually on the phone.

Repair: when step detects expiry, clear test state and immediately re-run render, then return. This can restyle/remove promptly on that callback without adding a wake lock or a recurring alarm. It cannot force a sleeping CPU/panel to update before any callback runs.

Sources: CameraNotificationRing.java:35,75,95. Do not confuse intentional active test override with an ordinary priority error.

## F3 —backend default versus settings UI (P3, accepted-input compatibility)

Backend accepts app rules without priority and assigns3; it also defaults omitted color to white. The returned config is raw JSON, not a normalized rule. The Flutter ring page casts priority as int and color as String without defaults. A valid imported/partial rule can therefore fail to display/edit. Native acceptance and missing transport field are reproduced in schema-edge.json; the widget failure follows from those required Dart casts and was not driven on-device. This does not affect the currently fully populated rules and does not itself explain the observed wrong color.

Repair: normalize rule defaults before exposing config or consistently apply native-equivalent defaults in the UI. Source: CameraRingSettings.java app parsing; camera_ring_screen.dart preview and priority dropdown.

## Follow-up boundaries

No code fixes or deployment were requested/performed by this general audit. Recommended order: preview-expiry restyle, generation-aware stale candidate handling preserving non-resurrection, then settings normalization. Validate with real arrivals/updates/dismissal and AOD behavior after implementation; current tests and callback traces are not visual certification. Keep notification-ring privacy filtering, accepted automatic ambient ownership and gradual pulse behavior intact. Undo's locked-test follow-up is separate; this request did not validate or fix it.

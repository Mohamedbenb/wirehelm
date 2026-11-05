# 1.3.1+44

- Fix Pi playback target resolution and forbid unintended output fallback/reconnection.
- Relay-only software volume; changes no longer modify Bluetooth output state, reinstall the receiver, or block monitoring.
- Configurable 5–200 ms application buffer, with a separate 10 ms PipeWire request.
- Smaller playback chunks and bounded capture/backlog queues to reduce avoidable delay.
- Immediate PC ↔ Pi SSH round-trip probes in monitoring, separate from delivery telemetry and acoustic latency.
- Error details collapse behind an explanation.

Validation and limits are recorded in AUDIO_RELAY.md.

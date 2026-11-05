# Node Cockpit build 11

- Prefer AES-256-CTR, then AES-128-CTR, with existing SSH MAC authentication and GCM/ChaCha fallbacks. Password and key connections retain host-key verification. Reconnect to renegotiate.
- Show the negotiated incoming cipher in diagnostics. The local pure-Dart packet benchmark measured GCM 1.03 MiB/s versus AES-256-CTR plus SHA-256 MAC 24.67 MiB/s. This is a synthetic PC comparison, not mobile throughput. Source: scripts/benchmark_ssh_crypto.dart.
- Allow saved scripts with one literal C# source assignment to use the persistent Windows helper; reassigned/dynamic definitions keep the fresh-process path. Stored command text is unchanged.
- Record helper failures/startup timeouts and desktop/standard fallback requests. Missing PC timings display as a dash.
- Retry unavailable helper startup after 30 seconds instead of disabling it for the whole connection. Submitted requests are not replayed.
- Allow 45 seconds for the outer status check to cover cold startup plus the existing 20-second execution deadline.
- Improve diagnostics with a route/cipher card, compact timings, failure indicators and a collapsed explanation.

Reconnect after updating to activate cipher preference. On-phone LAN throughput and Tailscale status verification remain necessary. Windows text size is unchanged.

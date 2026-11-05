# Node Cockpit build 10

- Fix a possible UI-isolate starvation path in SSH packet processing: yield to the event queue after a 4 ms slice, between complete packets with sequence/rekey bookkeeping finished. Completed-future microtask loops no longer drain an entire buffered burst before timers/input can run.
- Use a workspace-local dartssh2 4.1.0 patch, preserving the original license and documenting the change. Shared package cache is unchanged.
- Reduce updater, network benchmark and SFTP download read-ahead from 64 to 16 requests (1 MiB at 64 KiB/request).
- Explicitly yield during network-only benchmark progress so cancellation gets event-loop turns.
- Windows text-size control is unchanged.

Includes a buffered SSH regression test requiring a timer to fire before all 10,000 queued packets are drained, while checking every packet is processed. Android LAN ANR still needs on-phone verification; ADB had no attached device during development. No mobile throughput improvement is claimed.

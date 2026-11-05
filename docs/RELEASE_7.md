# Node Cockpit build 7

- Windows actions and status checks reuse PowerShell workers. Display/screen
  requests reuse one hidden worker in the signed-in user's desktop; standard
  PowerShell actions and status batches use a separate worker in the SSH session.
  Standard batch refresh no longer starts PowerShell for each refresh.
- A random authenticated loopback connection is forwarded through the existing
  SSH connection. No public port, router configuration or Windows service is
  installed. SSH forwarding must be permitted to use this fast path.
- If worker startup fails before submission, execution falls back to the old
  path for that SSH connection. Submitted/timed-out actions are never replayed.
- Idle workers stop after a minute; explicit disconnect and transport loss close
  them. Desktop tasks and temporary files are cleaned up on normal exit.
- C# types compiled by plain `Add-Type -TypeDefinition` commands are reused.
  Changed definitions restart the helper after returning an error, allowing the
  next request to compile the new definition. Namespace-qualified/custom Add-Type
  forms retain their original behavior.
- Device controls show LAN/Tailscale/Direct as the actual connection route.
- Stateful cards show the time of their last completed check, including failed
  checks; a failed check is still shown as unavailable/stale.
- App updates adds **Test download speed**. This downloads the APK through the
  same transfer/write/validation path, reports average MB/s and discards it.
  It does not request installation, so the same build can be tested repeatedly.
- Terminal behavior is unchanged.

Local Windows tests executed repeated real display/screen probes in one process:
warm combined probes were approximately 40–44 ms, versus an initial request
around one second in isolation. Cold startup was slower under concurrent tests.
These are local execution timings, not end-to-end phone/mobile measurements.

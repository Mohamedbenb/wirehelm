# Release 1.0.1 (build 21)

This release hardens the Windows remote-command path and makes saved custom
commands safer to use.

- Windows helper requests run in a fresh local script scope. PowerShell global
  variables and process-wide changes can still persist until that helper exits.
- Desktop helper processes rotate after 100 requests or 30 minutes, and continue
  to close after the existing idle period.
- Windows command workers and scheduled tasks have a 10-minute execution cap.
- Temporary artifacts use per-request or per-worker folders with restricted
  access. This covers the Windows helper environment (worker/launcher scripts,
  request/response staging files, captured output and completion markers).
  Request output files are deleted after they are read.
- A cautious, age-bounded cleanup removes only stale files and folders matching
  Node Cockpit's own temporary naming patterns, including abandoned helper
  environments and their scheduled tasks; running tasks and recent files are
  preserved.
- A timed-out command is reported as possibly completed. The app does not
  automatically replay it.
- Saved user-authored commands and stateful controls require confirmation.
  Windows custom controls also show a warning when the SSH account has
  administrator privileges (or the privilege check cannot be completed).

The terminal remains a full remote shell. These safeguards reduce accidental
state leakage and exposure of app-created temporary files; they do not sandbox
commands submitted by the user.

# Cleanup

This pass was intentionally narrow to avoid changing the behavior of separately
deployable scripts or the existing in-progress fixes.

- `Remove-DATStaleBIOSMarkers.ps1` now derives the OEM name once per OEM registry
  key rather than once for every model, and uses the surrounding camel-case
  naming convention for its root and log paths. Its best-effort logger also
  explicitly returns when logging fails instead of using an empty catch block.
- Removed an inactive post-restore debug `Write-Host` from both the current UI
  and the bundled 10.1.5 UI.
- Refreshed `FileHashes.md` for the working-copy changes, including pre-existing
  edits, so its recorded hashes and sizes match the shipped core files.

These cleanup-only edits do not change runtime behavior. Other pending work was
preserved; deployment scripts and public module surfaces were not rewritten.

## Integration with current main

The reviewed changes were replayed onto the maintained fork's current 10.3.2
branch rather than merging its divergent historical baseline. The original
checkout history and full working snapshot remain on a local preservation branch.
Current upstream archive validation, BIOS flag helpers, vendor update scripts,
and the 20-file integrity manifest remain intact.

Cancellation now retains incomplete status for unreadable descendants and
enumeration failures even after stopping a verified wrapper. Custom capture
rejects incomplete cancellation and never reports an abort as successful
packaging. The driver deployment script retains pre-install WIM dismounting,
uses a finally block for error cleanup, and uses a literal installer-log path.
The maintained and bundled hotfix driver-install templates now include the
duplicate checkout's reviewed fix: empty INF packages and generic pnputil code
1 are failures, while the existing accepted codes 0, 259, and 3010 are preserved.

Offline regressions cover these contracts. This does not claim validation on
real hardware, ConfigMgr, Intune, firmware, or a live servicing workload.

## Final lifecycle audit

The post-publication audit identified additional defects that were not covered
by the earlier passing tests. The maintained 10.3.2 code now:

- Creates DISM wrappers and logs in a per-operation directory beneath
  `Program Files\DriverAutomationTool-Runtime`, with SYSTEM/Administrators-only
  permissions applied at creation. Existing runtime paths and their ancestry
  must have trusted owners, no reparse points, and no untrusted replacement
  rights. Batch creation uses `CreateNew` and fails before launch if writing or
  trust verification fails. A shared or permissive temporary path is no longer
  used for executable wrappers.
- Confirms process exit with a bounded five-second wait after termination,
  rather than treating an asynchronous `Kill()` request as completed.
- Leaves regular and custom DISM cancellation to the worker holding the process
  handle. Custom cancellation no longer queries/stops a tree on the UI thread,
  races the worker, or disposes it on a partial-root success.
- Checks custom-capture completion and stalls inside the polling loop. Ten
  minutes without stdout or WIM growth is a failure, not an unbounded wait.
  Incomplete cancellation retains process identity and blocks another custom
  build until the operation is recovered.
- Shares WIM-release logic between GUI and headless cleanup. Failed dismounts
  or unverified mount state preserve records and temporary content; they never
  become permission to delete an active mount.

Failed operations retain protected runtime files for diagnosis. Recovery must
verify the logged process identity and active WIM state; do not clear tracking
values or terminate unrelated servicing processes to bypass the safeguards.
These changes apply to the maintained code, not the historical 10.1.5 snapshot.
The additional lifecycle tests use extracted functions, synthetic process
objects, and mocked registry/DISM calls. Live elevated WPF/DISM validation is
still required before production rollout.

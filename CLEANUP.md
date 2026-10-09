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

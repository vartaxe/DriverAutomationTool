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

## Headless-build reliability audit

The maintained application now preserves `DisableRestart` when importing an
exported build configuration, including the default `false` for older files.
Configuration import/export treats filenames literally, so square brackets do
not become wildcard expressions.

Headless builds check the processing outcome before retention or success
reporting. Failed, aborted, unfinished, missing, or unreadable outcomes fail the
run instead of triggering package retention. Successful `CompletedNoMatch` BIOS
runs remain successful. Completion is published after offline export and
XML-refresh progress logging, so those operations cannot leave a successful
build in `Running` state.

Error reporting in the final build catch no longer terminates the catch under
`ErrorActionPreference = Stop`; failure logging, upgrade-state cleanup, and the
documented scheduler exit codes remain reachable: `0` for completion, `1` for
failure, and `2` for the API upgrade-required condition. Temporary-storage and
run-marker cleanup still execute in `finally`.

`Tests/HeadlessBuild.Tests.ps1` extracts the real configuration functions and
build lifecycle, using mocked registry, scheduling, telemetry, retention, and
processing operations. It does not launch the GUI or perform live servicing.
These fixes apply to the maintained application, not `HotFix/10.1.5`.

## Localized ownership and generated firmware results

The maintained core and custom-capture UI no longer hardcode `takeown /D Y`.
They share `Invoke-DATTakeown`, which reads the installed Windows executable's
localized help and accepts only one bounded `/D` section containing `/R` and
exactly two distinct quoted ASCII-letter choices, in Windows' ownership/skip
order. Unknown, ambiguous, or changed formats fail before ownership; the code
does not guess a response from the user's culture or a language mapping.

The executable is resolved from Windows' system-directory API, never `PATH`.
Its file and directory ancestry must have trusted owners, no reparse points,
and no nonadministrative replacement rights. ACL checks request SIDs directly
instead of resolving account names through a possibly unavailable domain.
Content paths must be existing absolute local directories with no reparse
ancestry, and cannot be protected roots or Windows descendants. Recursive
ownership uses `/A /SKIPSL`, closes stdin, drains both output streams, and has a
10-second help timeout and a configurable 900-second ownership timeout
(maximum 1800 seconds), with bounded drain/termination waits. Only the launched
process handle can be terminated. Internal callers disable confirmation
prompts; the public helper also supports `WhatIf` and `Confirm`.

The redundant second ownership traversal before regular wimlib capture was
removed. Access-denied retry and custom capture use the same helper without
leaking output temporary files. Failed discovery or ownership stops capture
instead of silently continuing. Existing `icacls` and capture-process behavior
outside these ownership changes is not claimed to have new timeout coverage.

The generated Dell BIOS installer now rejects exit code `1` as failure and
does not misdiagnose unspecified error `10` as an AC-power-only retry. Existing
accepted codes `0`, `2`, and `6` remain; this is not an expansion to every
possible Dell package result. Lenovo code `1` remains unchanged because its
existing utility-specific success handling is distinct from Dell's.

`Tests/OwnershipSafety.Tests.ps1` uses extracted production ASTs, synthetic
processes, localized help fixtures, and mocked ACLs/callers. The installed
English Windows tool was additionally tested with read-only `/?` only.
No ownership/ACL changes, firmware operations, or live servicing were run.
Historical `HotFix/10.1.5` ownership entry points remain unsupported snapshots,
not silently updated or newly certified.

References: [Microsoft takeown documentation](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/takeown)
and [Dell client BIOS DUP options and exit codes](https://www.dell.com/support/kbdoc/en-us/000148745/dup-bios-updates).

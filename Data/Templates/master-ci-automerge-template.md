# Master CI and Auto-Merge Template

Reusable starting point for `{{ REPO_NAME }}`. This document describes a workflow
to place at `.github/workflows/auto-merge-ci.yml`. Review repository branch
protection, test conventions, and the analyzer baseline before enabling automatic
merging. The workflow below is deliberately limited to same-repository,
non-draft pull requests and grants write access only to its final merge job.

> **Security boundary:** CI executes pull-request code. The test job receives a
> read-only token, no repository secrets, and no merge permission. The separate
> landing job does not check out or execute pull-request content. Do not combine
> verification and write permissions in one job.

## 1. GitHub settings and administrative setup

### Workflow permissions

1. Open the repository on GitHub and select **Settings**.
2. In the left navigation, select **Actions**, then **General**.
3. Find **Workflow permissions**.
4. Set the default `GITHUB_TOKEN` permission to **Read repository contents and packages permissions** (read-only).
5. The **Allow GitHub Actions to create and approve pull requests** checkbox is **not required** by this template. This workflow neither creates nor approves a pull request; it merges an existing one. Leave this option unchecked unless a separately reviewed workflow genuinely needs to create or approve PRs.
6. If an administrator enables that option for another workflow, return to this section and ensure the repository's workflow token default remains read-only. Organization policy may disable or override repository settings.

Enabling the create-and-approve option increases what workflows can do with
`GITHUB_TOKEN`; do not enable it merely to make `gh pr merge` work. Merging uses
the job-scoped `contents: write` and `pull-requests: write` permissions shown
below. No personal access token or long-lived secret is needed.

### Merge policy and branch cleanup

1. In **Settings > General > Pull Requests**, enable **Allow auto-merge**.
2. In the same section, enable **Automatically delete head branches** if the organization permits it.
3. Configure branch protection or a ruleset for the default branch. Require the `verify` job and any reviews, signed-commit, deployment, or other checks your policy requires. Auto-merge must not be used to bypass required reviews or checks.
4. Ensure the repository permits **squash merging**. Keep the intended merge-message format compatible with the changelog generator.
5. Confirm that Actions are enabled for the repository and that organization Actions policies allow the pinned actions and PowerShell Gallery modules used by CI.

`gh pr merge --auto` queues the squash merge until all repository rules and
required checks pass. `--delete-branch` requests deletion after the merge; the
repository's automatic head-branch deletion setting is the durable fallback
when auto-merge is queued.

## 2. One-time repository preparation

Replace these example-specific assumptions before deploying the workflow:

| Placeholder or convention | Set it to |
|---|---|
| `{{ REPO_NAME }}` | Repository name used in this document and PR audit messages |
| `main` / `master` | Actual default branch or branches; keep only those that are valid base branches |
| `Tests/**/*.Tests.ps1` | This repository's Pester test discovery paths |
| `Tests/Test-*.ps1` | Optional standalone PowerShell harness convention; remove the harness step if not used |
| `.github/analyzer-error-baseline.json` | Reviewed, protected baseline described below |
| `.github/copilot-instructions.md` | Required tracked policy file whose Git blob must not change in a PR |

The workflow intentionally fails if it cannot find a Pester test file or the
instructions file. Repositories that do not yet have those files are not ready
to enable this template; add and review the required content first rather than
changing the workflow to silently pass.

### Error baseline

Commit `.github/analyzer-error-baseline.json` on the protected default branch
before enabling the workflow:

```json
{
  "schemaVersion": 1,
  "entries": []
}
```

Populate `entries` only with exact, reviewed pre-existing error findings. The
workflow computes a fingerprint from the rule name, repository-relative path,
and trimmed source line. Each allowed entry must include:

```json
{
  "fingerprint": "<SHA256 fingerprint emitted by the CI step>",
  "rule": "PSAvoidUsingConvertToSecureStringWithPlainText",
  "path": "relative/path/to/file.ps1",
  "justification": "Reviewed in-memory credential conversion; no persistence here.",
  "expiresOn": "2026-12-31"
}
```

The examples above describe the schema, not a recommended permanent exception.
Inventory findings on the protected base branch; review their call sites and
data flow; add each accepted fingerprint with an owner-visible justification
and near-term expiry. Never auto-update the baseline from a pull request. CI
loads the baseline from the event's **base commit**, not from the proposed PR,
so a change cannot hide a new finding by editing the baseline in the same PR.
Unknown findings fail the gate. Remove stale entries and renew expiries only
after review.

`PSAvoidUsingConvertToSecureStringWithPlainText` is a static-analysis finding,
not proof that plaintext was persisted. In-memory `PSCredential` construction
can require this conversion. For persisted values, verify producer and consumer
identities, registry/file ACLs, and DPAPI scope before changing encryption.
Use `ConvertFrom-SecureString`/DPAPI only where the design requires persistence;
do not blindly convert service credentials to machine scope when they must be
decrypted by a different account.

### Instructions file immutability

Ensure `.github/copilot-instructions.md` is tracked on the base branch. This
workflow compares its Git blob in the PR base and head commits; missing or
changed content fails verification. Changes to those instructions must be
reviewed and landed separately under the repository's normal policy.

## 3. Reusable workflow: `.github/workflows/auto-merge-ci.yml`

This example accepts pull requests targeting either `main` or `master`, whether
they were opened manually or by a same-repository automation such as a
performance loop. It tests the exact PR head SHA. The merge job is gated on the
successful verification job and pins the merge request to that same SHA to
prevent merging a newer, untested head.

```yaml
name: CI and squash auto-merge

on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review]
    branches: [main, master]

# All jobs start with no write access. Jobs opt in only to what they need.
permissions:
  contents: read

concurrency:
  group: ci-pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  verify:
    name: Verify PR head
    if: github.event.pull_request.draft == false
    runs-on: windows-latest
    permissions:
      contents: read
    steps:
      - name: Check out the exact PR head
        # actions/checkout v7.0.1; retain a reviewed full-length action SHA.
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0
          persist-credentials: false

      - name: Verify protected Copilot instructions are present and unchanged
        shell: powershell
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          $ErrorActionPreference = 'Stop'
          $path = '.github/copilot-instructions.md'
          $baseBlob = git rev-parse "$($env:BASE_SHA):$path"
          if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($baseBlob)) {
            throw "$path is missing from the PR base commit."
          }
          $headBlob = git rev-parse "$($env:HEAD_SHA):$path"
          if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headBlob)) {
            throw "$path is missing from the PR head commit."
          }
          if ($baseBlob -cne $headBlob) {
            throw "$path changed in this PR; land policy changes separately."
          }
          if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "$path is not present in the checked-out PR."
          }

      - name: Install pinned validation modules
        shell: powershell
        run: |
          $ErrorActionPreference = 'Stop'
          Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -ErrorAction Stop
          Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force -ErrorAction Stop
          Import-Module Pester -RequiredVersion 6.2.0 -ErrorAction Stop
          Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop

      - name: Parse all tracked PowerShell files
        shell: powershell
        run: |
          $ErrorActionPreference = 'Stop'
          $files = @(git ls-files --cached | Where-Object { $_ -match '\.(ps1|psm1|psd1)$' })
          if ($files.Count -eq 0) { throw 'No tracked PowerShell files were found.' }
          $parseFailures = [System.Collections.Generic.List[string]]::new()
          foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
              (Join-Path $env:GITHUB_WORKSPACE $file),
              [ref]$tokens,
              [ref]$parseErrors
            ) | Out-Null
            foreach ($parseError in $parseErrors) {
              $parseFailures.Add("$file`:$($parseError.Extent.StartLineNumber): $($parseError.Message)")
            }
          }
          if ($parseFailures.Count -gt 0) {
            $parseFailures | ForEach-Object { Write-Error $_ }
            throw 'PowerShell parsing failed.'
          }

      - name: Block new analyzer errors and unmapped SecureString findings
        shell: powershell
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          $ErrorActionPreference = 'Stop'
          $baselinePath = '.github/analyzer-error-baseline.json'
          $baselineJson = git show "$($env:BASE_SHA):$baselinePath"
          if ($LASTEXITCODE -ne 0) {
            throw "Reviewed analyzer baseline is missing from the PR base: $baselinePath"
          }
          $baseline = ($baselineJson -join "`n") | ConvertFrom-Json -ErrorAction Stop
          if ($baseline.schemaVersion -ne 1 -or $null -eq $baseline.entries) {
            throw 'Analyzer baseline schema is invalid.'
          }
          $today = [DateTime]::UtcNow.Date
          $allow = @{}
          foreach ($entry in @($baseline.entries)) {
            foreach ($field in @('fingerprint', 'rule', 'path', 'justification', 'expiresOn')) {
              if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
                throw "Analyzer baseline entry is missing '$field'."
              }
            }
            $expiry = [DateTime]::MinValue
            if (-not [DateTime]::TryParse(
              [string]$entry.expiresOn,
              [Globalization.CultureInfo]::InvariantCulture,
              [Globalization.DateTimeStyles]::AssumeUniversal,
              [ref]$expiry
            ) -or $expiry.Date -lt $today) {
              throw "Expired or invalid analyzer baseline entry: $($entry.path) $($entry.rule)"
            }
            if ($allow.ContainsKey([string]$entry.fingerprint)) {
              throw "Duplicate analyzer fingerprint: $($entry.fingerprint)"
            }
            $allow[[string]$entry.fingerprint] = $entry
          }

          $root = $env:GITHUB_WORKSPACE.TrimEnd('\') + '\'
          $files = @(git ls-files --cached | Where-Object { $_ -match '\.(ps1|psm1|psd1)$' })
          $newFindings = [System.Collections.Generic.List[string]]::new()
          $matched = @{}
          foreach ($file in $files) {
            $fullPath = Join-Path $env:GITHUB_WORKSPACE $file
            $sourceLines = [IO.File]::ReadAllLines($fullPath)
            foreach ($finding in @(Invoke-ScriptAnalyzer -Path $fullPath -Severity Error)) {
              $lineIndex = [int]$finding.Line - 1
              $sourceLine = if ($lineIndex -ge 0 -and $lineIndex -lt $sourceLines.Length) {
                $sourceLines[$lineIndex].Trim()
              } else {
                ''
              }
              $relativePath = $fullPath.Substring($root.Length).Replace('\', '/')
              $material = '{0}|{1}|{2}' -f $finding.RuleName, $relativePath, $sourceLine
              $sha = [Security.Cryptography.SHA256]::Create()
              try {
                $digest = [BitConverter]::ToString(
                  $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($material))
                ).Replace('-', '')
              } finally {
                $sha.Dispose()
              }
              if (-not $allow.ContainsKey($digest)) {
                $newFindings.Add("$digest|$($finding.RuleName)|$relativePath`:$($finding.Line) $($finding.RuleName): $($finding.Message)")
              } else {
                $matched[$digest] = $true
              }
            }
          }
          if ($newFindings.Count -gt 0) {
            $newFindings | ForEach-Object { Write-Error $_ }
            throw 'New or unmapped analyzer errors were found. Review the code; do not suppress or update the baseline in this PR.'
          }
          $stale = @($allow.Keys | Where-Object { -not $matched.ContainsKey($_) })
          if ($stale.Count -gt 0) {
            Write-Warning "$($stale.Count) baseline entries are no longer present; remove them in a separately reviewed cleanup."
          }

      - name: Run every repository Pester test
        shell: powershell
        run: |
          $ErrorActionPreference = 'Stop'
          Import-Module Pester -RequiredVersion 6.2.0 -ErrorAction Stop
          $testFiles = @(Get-ChildItem -Path (Join-Path $env:GITHUB_WORKSPACE 'Tests') `
            -Filter '*.Tests.ps1' -File -Recurse -ErrorAction Stop | Sort-Object FullName)
          if ($testFiles.Count -eq 0) {
            throw 'No Pester tests found. Configure the repository test path before enabling auto-merge.'
          }
          $result = Invoke-Pester -Path $testFiles.FullName -Output Detailed -PassThru
          if ($null -eq $result -or $result.Result -ne 'Passed' -or
              $result.TotalCount -eq 0 -or $result.FailedCount -gt 0 -or
              $result.FailedContainersCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or
              $result.SkippedCount -gt 0 -or $result.NotRunCount -gt 0) {
            throw 'Pester did not complete with 100% passing tests.'
          }

      - name: Run optional standalone PowerShell harnesses
        shell: powershell
        run: |
          $ErrorActionPreference = 'Stop'
          $testRoot = Join-Path $env:GITHUB_WORKSPACE 'Tests'
          $harnesses = @(Get-ChildItem -Path $testRoot -Filter 'Test-*.ps1' -File -Recurse |
            Where-Object { $_.Name -notlike '*.Tests.ps1' } | Sort-Object FullName)
          foreach ($harness in $harnesses) {
            Write-Host "Running $($harness.FullName)"
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $harness.FullName
            if ($LASTEXITCODE -ne 0) {
              throw "$($harness.Name) failed with exit code $LASTEXITCODE."
            }
          }

  squash-auto-merge:
    name: Squash merge after verification
    needs: verify
    if: >-
      needs.verify.result == 'success' &&
      github.event.pull_request.draft == false &&
      github.event.pull_request.head.repo.full_name == github.repository
    runs-on: windows-latest
    # These are the only write permissions in the workflow.
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Enable squash auto-merge for the tested head
        shell: powershell
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPOSITORY: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          $ErrorActionPreference = 'Stop'
          gh pr merge $env:PR_NUMBER `
            --repo $env:REPOSITORY `
            --squash `
            --auto `
            --match-head-commit $env:PR_HEAD_SHA `
            --delete-branch
          if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI could not queue or complete the squash merge for PR #$env:PR_NUMBER."
          }
```

## 4. DAT and disk-layout coverage

The Pester step discovers and runs every `Tests/**/*.Tests.ps1` file; it does not
hard-code an expected test count that could accidentally omit newly added tests.
On the current DAT baseline this discovery covers the five suites and 59 test
cases, including lifecycle and driver-install safety. On the disk-layout branch
it covers the branding and disk-layout suites (71 cases). The optional
`Tests/Test-*.ps1` step also executes DAT standalone regression harnesses. Keep
required checks and this discovery convention aligned when suites are added,
renamed, or moved.

## 5. Deploy and operate safely

1. Validate the YAML and PowerShell blocks in a disposable test repository.
2. Pin every third-party action to a reviewed full commit SHA; update pins only
   in a separate dependency-review change. The checkout SHA shown above is the
   SHA used by the current DAT workflow; verify it before copying to a different
   repository.
3. Populate and review the base-branch analyzer baseline. Do not bless findings
   just to obtain a green check.
4. Confirm test discovery finds all expected suites and no test is skipped or
   marked not-run.
5. Add `verify` as a required status check in branch protection before enabling
   auto-merge.
6. Open a same-repository test PR and verify the PR head SHA, baseline check,
   instructions-file guard, Pester count, branch-protection behavior, merge
   message, and head-branch deletion.
7. Monitor the first runs and audit the squash merge actor and workflow run.

Fork PRs intentionally receive verification but not auto-merge. GitHub can
downgrade `GITHUB_TOKEN` permissions for fork or Dependabot PRs; do not work
around that restriction by exposing a PAT or repository secret to untrusted PR
code. Draft PRs do not merge. A failed, pending, stale-head, review-blocked, or
policy-blocked PR is not merged by this workflow.

The template does not create PRs, approve PRs, skip reviews, bypass required
checks, run deployment steps, or certify live ConfigMgr/Intune/firmware behavior.
Treat merge permissions as a production write capability and retain normal
branch protection.

## References

- [GitHub Actions: automatic token authentication](https://docs.github.com/en/actions/security-guides/automatic-token-authentication)
- [GitHub Actions: controlling permissions for `GITHUB_TOKEN`](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#modifying-the-permissions-for-the-github_token)
- [GitHub Actions: approving pull request workflows from forks](https://docs.github.com/en/actions/managing-workflow-runs/approving-workflow-runs-from-forks)
- [GitHub pull request auto-merge](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-auto-merge-for-pull-requests-in-your-repository)
- [`gh pr merge` manual](https://cli.github.com/manual/gh_pr_merge)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
- [Pester 6](https://pester.dev/)

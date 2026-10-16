# Repository Copilot customizations

Installed from [github/awesome-copilot](https://github.com/github/awesome-copilot)
at commit `82701c24b99488536ca399ff4789a458b7a05db7`.
The upstream MIT license is retained in [AWESOME-COPILOT-LICENSE](AWESOME-COPILOT-LICENSE).

| Customization | Location | Purpose |
|---|---|---|
| Terminal helper | [Agent profile](agents/terminal-helper.agent.md) | PowerShell and Bash command assistance |
| Microsoft Learn contributor | [Agent profile](agents/microsoft_learn_contributor.agent.md) | Documentation structure, accessibility, and Microsoft writing style |
| PowerShell guidance | [Instructions](instructions/powershell.instructions.md) | Applies to `*.ps1` and `*.psm1` |
| Pester 6 guidance | [Instructions](instructions/powershell-pester-6.instructions.md) | Applies to `*.Tests.ps1` |
| Copilot PR autopilot | [Skill](skills/copilot-pr-autopilot/SKILL.md) | Explicitly requested PR review and feedback loops |

Select agent profiles in a compatible Copilot client. Tool identifiers and the
terminal helper's model setting are upstream defaults; availability depends on
the client. Installing these files does not start either agent or a PR loop.
Instruction files guide future edits; they do not retroactively rewrite code.
Preserve Windows PowerShell 5.1 compatibility and existing public parameter
contracts when applying general suggestions.

The PR skill includes its reference documents, scripts, and reply templates.
Running it requires an explicitly selected pull request, authenticated GitHub CLI,
and the permissions described in its documentation. It can commit, push, post
replies, and resolve threads when invoked; installation performs none of those
operations.

All 28 downloaded customization files were verified against upstream Git blob
hashes. The seven PowerShell scripts additionally received a UTF-8 byte-order
mark, without text changes: Windows PowerShell 5.1 otherwise misdecodes some
upstream non-ASCII characters and fails to parse a script. All seven then passed
on-disk parser checks. No PR scripts were executed.

Two whitespace-only example lines in the PowerShell instructions were trimmed
after verification so the repository's `git diff --check` CI gate passes.

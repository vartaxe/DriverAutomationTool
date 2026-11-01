# Maintained-fork provenance

The `v1.0.0` maintained-fork baseline identifies this repository's consolidated
snapshot, not a new version of the upstream Driver Automation Tool. The embedded
application/module version is **10.3.6.0**. Existing script version histories,
copyright notices, original authorship, and third-party licenses remain intact.
Rebaselining Git history does not transfer ownership or change license terms.

## Recorded sources before history rebaselining

Recorded on 2026-10-16; commit identifiers refer to the pre-rebaseline histories.

| Source | Upstream URL | Recorded upstream default-branch SHA | Recorded fork SHA |
| --- | --- | --- | --- |
| Driver Automation Tool | https://github.com/maurice-daly/DriverAutomationTool | `6b78e8dfd198beae603d0c6b12f4b6665e99c252` | `0462306fe2238c5d05f34501fe0199afb4bb11d7` |
| Modern Driver Management | https://github.com/MSEndpointMgr/ModernDriverManagement | `f18a59aa8c0cc59688232edfba91e860b1a5c4d6` | `0f345564971b26151042461a66a286603e866f40` |
| Modern BIOS Management | https://github.com/MSEndpointMgr/ModernBIOSManagement | `43372b1ba6a44c0ea3ccda7865d0fd622443892b` | `13f993b1d5e7b9143a6fcca7aef8c179a3783666` |

The respective fork repositories are `vartaxe/DriverAutomationTool`,
`vartaxe/ModernDriverManagement`, and `vartaxe/ModernBIOSManagement`. At the
recorded heads they were ahead of their upstream default branches by 1, 3, and
4 commits respectively, with no upstream commits missing. Subsequent local
maintenance is part of the baseline snapshot, not those recorded fork SHAs.
The earlier bundled-script import baselines are retained separately in
[`Data/BundledScriptParity.md`](Data/BundledScriptParity.md).

## Current Driver Automation Tool upstream alignment

On 2026-11-01, Vartaxe `main` was compared with
`maurice-daly/DriverAutomationTool` `master` at
`cda3d6275f81e003b900965b5f32587af2d53b6e`. Vartaxe PR #26 carries the adapted
10.3.3–10.3.6 releases. At that comparison, every upstream path was present in
Vartaxe: 114 of 136 paths were byte-identical, 22 same-path files differed, and
Vartaxe had 71 additional paths. No upstream path was missing.

The repositories had no shared commit ancestry because the maintained-fork
baseline was re-established independently. The upstream history is now recorded
as a second parent of Vartaxe `main`, preserving Vartaxe's first-parent history
and application code without a force-push. This records the reviewed content
relationship; future upstream changes still require content review and
adaptation before being treated as synchronized.

## Ownership and maintenance boundary

- Maurice Daly is the original Driver Automation Tool author. Its existing
  [CC BY-NC 4.0 license](LICENSE) still applies; this is not a relicensing.
- The imported MSEndpointMgr driver/BIOS scripts retain their named authors
  (including Maurice Daly, Nickolaj Andersen, and Lauri Kurvinen) and the
  [MSEndpointMgr MIT notice](LICENSES/MSEndpointMgr-MIT.txt).
- Bundled wimlib and related components retain the license notices under
  `Driver Automation Tool/Tools/Wimlib`. Microsoft tooling retains its original
  distribution terms; inclusion is not a claim of ownership.
- Active fork maintenance is consolidated in this repository. The standalone
  ModernDriverManagement and ModernBIOSManagement forks remain archived
  compatibility/provenance sources. Their `v1.0.0` archive baselines do not
  represent newly validated driver/firmware products.

Offline parser and regression checks do not certify the complete legacy source,
vendor payloads, WPF interaction, firmware flashing, Windows servicing, or live
ConfigMgr/Intune infrastructure. The historical `HotFix/10.1.5` directory is not
the active application or a recommended downgrade.

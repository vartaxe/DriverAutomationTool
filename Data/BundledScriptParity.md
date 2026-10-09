# Consolidated ConfigMgr deployment scripts

This repository is now the canonical maintained home for the ConfigMgr driver and
BIOS package selectors and the four vendor BIOS apply scripts. The consolidation
preserves the maintained standalone forks at these reviewed heads:

| DAT artifact set | Source project | Pinned maintenance baseline |
|---|---|---|
| `Invoke-CMApplyDriverPackage.ps1` | `vartaxe/ModernDriverManagement` | `ffd45de80ae58ece1dd83e9c10fa2406fa320e70` |
| `Invoke-CMDownloadBIOSPackage.ps1` and four vendor apply scripts | `vartaxe/ModernBIOSManagement` | `3859244657c7a05b62203cb174576f2c3720d060` |

The package selectors include the standalone maintenance fixes plus DAT's
certificate-pinning compatibility and ConfigMgr hierarchy scoping. `-SiteCode`
or the `MDMSiteCode` task-sequence variable limits AdminService results using
the ConfigMgr `SMS_Package.SourceSite` property. Omitting it preserves the
previous all-sites behavior.

`Tests/Test-BundledScriptParity.ps1` protects the shared XML/AdminService
surface, scoped certificate-pinning boundary, hierarchy filter, vendor-script
presence, and Getac manufacturer normalization for administrator-created or
imported matching driver packages.
Getac recognition does not represent automated catalog acquisition or BIOS
firmware support. Any future port must update this contract and preserve those
DAT-specific controls.

The imported MSEndpointMgr scripts remain under the MIT license recorded in
`LICENSES/MSEndpointMgr-MIT.txt`; the rest of DAT remains under its existing
license.

# Bundled ConfigMgr script parity

The ConfigMgr scripts shipped in this repository are maintained as DAT-integrated
artifacts, not as byte-for-byte copies of the standalone projects:

| Bundled artifact | Comparison baseline | Pinned baseline |
|---|---|---|
| `Driver Automation Tool/Scripts/Invoke-CMApplyDriverPackage.ps1` | Modern Driver Management | `87c57414428856159cbc599b4f2e9d1d1b62ede7` |
| `Driver Automation Tool/Scripts/Invoke-CMDownloadBIOSPackage.ps1` | Modern BIOS Management | `4c8629dadfa94729f3269b8db7f8293db7da4f2a` |

The pinned versions were reviewed during the 2026 parity audit. The bundled
files are materially divergent (2967 vs. 2954 lines for the driver script and
1897 vs. 1894 lines for the BIOS script). Blind replacement is unsafe: the
bundled files contain DAT-specific certificate pinning and authentication
behavior, while the standalone files contain later VM/platform/XML/AdminService,
cleanup, CIM, TLS, and BitLocker changes.

Until each upstream change has a reviewed DAT integration, parity is defined by
the structural regression test in `Tests/Test-BundledScriptParity.ps1`, not by
line count or an exact hash. That test protects the shared XML/AdminService
surface and the DAT certificate-pinning boundary. Any future port must update
this contract and preserve those DAT-specific controls.

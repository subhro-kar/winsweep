# WinSweep

A Windows system cleanup utility with a tabbed WinForms GUI. Scans for orphaned registry keys, leftover folders, stale startup entries, broken shortcuts, and deep-cleans browser/dev caches — all with 3-layer recovery protection.

## Features

- **Tabbed categories** — Recommended (safe defaults), System, Applications, Registry
- **Risk badges** — `[Safe]`, `[Review]`, `[Advanced]` on every category
- **22 scan categories** including app presets (VS Code, Discord, npm, pip, NuGet)
- **3-layer recovery** — System Restore Point, `.reg` backup, Recycle Bin move
- **Undo dialog** — re-import registry backups, open Recycle Bin
- **Admin detection** — elevation prompt at startup, limited-mode banner

### Scan categories

| Recommended | System | Applications | Registry |
|---|---|---|---|
| Temp Files | Windows Update Cache | Orphaned Folders | Uninstall Keys |
| Thumbnail Cache | Delivery Optimization | Startup Entries | COM/ActiveX |
| Browser Caches | DirectX Shader Cache | Scheduled Tasks | Services |
| Log Files | Microsoft Store Cache | Broken Shortcuts | File Associations |
| WER/Crash Dumps | Defender History/Logs | VS Code Cache | Shell Extensions |
| Recycle Bin | Old WU Backups | Discord Cache | App Paths |
| Stale Downloads | Prefetch | npm/pip/NuGet Cache | Fonts |

## Requirements

- Windows 10 or later
- PowerShell 5.1

## Usage

```powershell
.\winsweep.ps1
```

Or double-click **`Run WinSweep.cmd`**.

Optional switches:

| Switch | Description |
|---|---|
| `-RequireAdmin` | Require admin privileges, prompt to relaunch |
| `-NoElevationPrompt` | Skip the elevation prompt |

### Safety

- Registry deletions are backed up to `.reg` files before removal
- Files and folders are moved to the Recycle Bin when possible
- A System Restore Point can be created before cleanup
- Categories with `[Advanced]` or `[Review]` badges are unchecked by default

## Releases

Push a `v*` tag to trigger the release workflow:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The workflow auto-generates `CHANGELOG.md` from conventional commits, runs a parse check, and publishes a GitHub Release with `winsweep.ps1` attached.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
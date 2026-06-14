# Win-Clean

A Windows cleanup utility with a WinForms GUI that scans for orphaned registry keys, leftover filesystem folders, startup entries, scheduled tasks, and deep-cleans caches.

## Features

- **Tabbed category groups** — Recommended, System, Applications, Registry
- **Risk badges** — Safe, Review, Advanced labels on each category
- **Safer defaults** — Recommended categories pre-checked; registry and system categories unchecked
- **Scan categories**:
  - Recommended: Temp Files, Thumbnail Cache, Browser Caches, Log Files, WER/Crash Dumps, Recycle Bin, Stale Downloads
  - System: Windows Update Cache, Delivery Optimization, DirectX Shader Cache, Microsoft Store Cache, Defender History/Logs, Old WU Backups, Prefetch
  - Applications: Orphaned Folders, Startup Entries, Scheduled Tasks, Broken Shortcuts, VS Code Cache, Discord Cache, npm Cache, pip Cache, NuGet Cache
  - Registry: Uninstall Keys, COM/ActiveX, Services, File Associations, Shell Extensions, App Paths, Fonts
- **3-layer recovery**: System Restore Point, registry `.reg` backup, Recycle Bin move
- **Undo dialog** to re-import registry backups and open Recycle Bin
- **Admin/limited mode** detection with elevation prompt

## Requirements

- Windows 10 or later
- PowerShell 5.1

## Usage

### GUI (recommended)

```powershell
.\win-clean-gui.ps1
```

Optional switches:

| Switch | Description |
|---|---|
| `-RequireAdmin` | Require admin privileges, prompt to relaunch |
| `-NoElevationPrompt` | Skip the elevation prompt |
| `-Elevated` | Internal flag used during admin relaunch |

### Safety notes

- Registry deletions are backed up to `.reg` files before removal.
- Files and folders are moved to the Recycle Bin when possible.
- A System Restore Point can be created before cleanup.
- Categories with `[Advanced]` or `[Review]` badges are unchecked by default.

## Screenshots

_Screenshots coming soon._

## Building a release

Push a `v*` tag to trigger the release workflow:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The workflow will:
1. Parse `CHANGELOG.md` for release notes
2. Run a PowerShell parse check on `win-clean-gui.ps1`
3. Create a GitHub Release with `win-clean-gui.ps1` attached

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

See [LICENSE](LICENSE).
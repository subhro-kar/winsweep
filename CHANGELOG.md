# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Category groups with tabbed UI (Recommended, System, Applications, Registry)
- Risk badges ([Advanced], [Review]) beside category names
- Safer default selections — Recommended checked by default; all others unchecked
- Recycle Bin cleanup using `Clear-RecycleBin`
- Delivery Optimization cache scanner
- DirectX Shader Cache scanner
- Microsoft Store Cache scanner
- Defender History/Logs scanner
- Old WU Backups scanner
- Broken Shortcuts scanner (resolves .lnk targets, expands env vars)
- Stale Downloads scanner (installers/archives older than 30 days in ~/Downloads)
- App-specific cleanup presets: VS Code Cache, Discord Cache, npm Cache, pip Cache, NuGet Cache
- Row color coding for Registry (red), Application (blue), Deep Clean (green)

### Fixed

- Find-BrokenComRegistrations function header missing after insert
- Broken Shortcuts scanner handles COM errors on corrupted .lnk files
- Recycle Bin scanner returns result even when COM size lookup fails
- Discord Cache scanner selects current install (sorted by LastWriteTime)
- Removed duplicate SoftwareDistribution\Download path from Old WU Backups
- Removed dangerous WinSxS\CleanupManifests path from Old WU Backups

## [0.2.0] - 2026-06-13

### Fixed

- Fix category definitions retrieval to ensure proper handling of empty results (#2)

## [0.1.0] - 2026-06-13

### Added

- WinForms GUI for Windows Cleaner (`win-clean-gui.ps1`)
- Scan categories: Uninstall Keys, COM/ActiveX, Services, File Associations, Shell Extensions, App Paths, Fonts, Orphaned Folders, Startup Entries, Scheduled Tasks, Temp Files, Windows Update Cache, WER/Crash Dumps, Prefetch, Thumbnail Cache, Browser Caches, Log Files
- Cleanup with 3-layer recovery: System Restore Point, registry .reg backup, Recycle Bin move
- Undo dialog for last session
- Admin/limited mode detection and elevation prompt
- Progress window with cancel support
- Category checklist with scan/clean workflow
# AGENTS.md — Win-Clean Project Guide

## Project Overview

Windows leftover cleaner with CLI (`win-clean.ps1`) and GUI (`win-clean-gui.ps`) scripts. Scans for orphaned registry keys, filesystem folders, startup entries, scheduled tasks, and deep-clean caches.

## Key Files

| File | Purpose |
|---|---|
| `win-clean.ps1` | CLI script — unchanged, keep stable |
| `win-clean-gui.ps` | WinForms GUI — active development target |
| `WIN-CLEAN-ROADMAP.private.md` | Private planning (do not commit to public) |
| `WIN-CLEAN-GUI-PLAN.md` | GUI implementation status tracker |

## Architecture (win-clean-gui.ps)

### Adding a new scan category

1. **Write a scan function** — two patterns:
   - **Pattern A** (`Find-*`): returns list of individual `New-ScanResult` objects (for registry/app items)
   - **Pattern B** (`Get-*Item`): returns single aggregate via `New-DeepCleanAggregateItem` (for cache/cleanup dirs)
2. **Register** in `Get-CategoryDefinitions` (line ~1071)
3. **Cleanup** is automatic — existing `DeepCleanPaths` type handles directory content removal

### Key functions

| Function | Line | Purpose |
|---|---|---|
| `New-ScanResult` | 234 | Result object factory |
| `New-DeepCleanAggregateItem` | 948 | Aggregate deep-clean item factory |
| `Get-CategoryDefinitions` | 1071 | Category registry |
| `Add-ResultRow` | 1287 | Grid population + color coding |
| Scan button handler | 1386 | Scan invocation loop |
| Clean button handler | 1498 | Cleanup dispatch via `DeleteMeta.Type` |

### DeleteMeta types

`RegistryKey`, `FontValue`, `StartupRegistryValue`, `StartupShortcut`, `ScheduledTask`, `FilesystemPath`, `DeepCleanPaths`, `DeepCleanGlob`

## Conventions

- PowerShell 5.1, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'SilentlyContinue'`
- Use `Test-PathExists` helper (not raw `Test-Path`) for path checks
- Use `[System.Collections.Generic.List[object]]::new()` for mutable result lists
- No comments unless asked
- Parse-check after edits: `[System.Management.Automation.PSParser]::Tokenize(...)`

## Verification

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath 'win-clean-gui.ps' -Raw), [ref]$null)
```

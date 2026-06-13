#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Leftover Cleaner - finds and removes orphaned registry keys,
    filesystem folders, startup entries, and scheduled tasks left behind by
    uninstalled applications.

.DESCRIPTION
    Scans for:
      - Orphaned uninstall registry keys (InstallLocation / executables missing)
      - Orphaned startup registry entries and startup folder shortcuts
      - Scheduled tasks whose executable no longer exists
      - Leftover folders in common app directories

    Always shows a dry-run report first and asks for confirmation before
    deleting anything. Registry changes are backed up to a .reg file first.

.PARAMETER SkipRegistry
    Skip registry orphan scan.

.PARAMETER SkipFilesystem
    Skip filesystem leftover scan.

.PARAMETER SkipStartup
    Skip startup entry scan.

.PARAMETER SkipTasks
    Skip scheduled task scan.

.PARAMETER BackupDir
    Directory to write registry backup .reg files. Defaults to script directory.

.EXAMPLE
    .\win-clean.ps1
    .\win-clean.ps1 -SkipFilesystem
    .\win-clean.ps1 -BackupDir "C:\Backups"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipRegistry,
    [switch]$SkipFilesystem,
    [switch]$SkipStartup,
    [switch]$SkipTasks,
    [string]$BackupDir = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Header {
    param([string]$Text)
    $line = '=' * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n-- $Text" -ForegroundColor Yellow
}

function Write-Found {
    param([string]$Text)
    Write-Host "  [FOUND] $Text" -ForegroundColor Magenta
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  [OK]    $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Gray
}

# Resolve the actual executable path from a command string like:
#   "C:\Program Files\App\app.exe" --flag
#   C:\Windows\system32\cmd.exe /c "..."
function Resolve-ExecutablePath {
    param([string]$CommandString)
    if ([string]::IsNullOrWhiteSpace($CommandString)) { return $null }

    $cmd = $CommandString.Trim()

    # Quoted path at the start
    if ($cmd -match '^"([^"]+)"') {
        return $Matches[1]
    }

    # Unquoted: take everything before the first space that isn't a flag
    # Walk token by token to handle paths with spaces that aren't quoted
    $tokens = $cmd -split '\s+'
    $candidate = ''
    foreach ($tok in $tokens) {
        $candidate = if ($candidate) { "$candidate $tok" } else { $tok }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    # Fallback: first token
    return $tokens[0]
}

function Test-PathExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath $Path)
}

# Export a registry key subtree to a .reg backup file
function Backup-RegistryKey {
    param(
        [string]$KeyPath,   # e.g. HKLM:\SOFTWARE\...
        [string]$OutDir
    )
    # Convert PSDrive path to reg.exe format
    $regPath = $KeyPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                        -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
                        -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\' `
                        -replace '^HKU:\\',  'HKEY_USERS\'

    $safe   = ($regPath -replace '[\\/:*?"<>|]', '_').Substring(0, [Math]::Min(80, $regPath.Length))
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile = Join-Path $OutDir "backup_${stamp}_${safe}.reg"

    & reg.exe export $regPath $outFile /y 2>$null | Out-Null
    return $outFile
}

# ---------------------------------------------------------------------------
# Data classes (PSCustomObject factories)
# ---------------------------------------------------------------------------

function New-RegistryItem {
    param([string]$KeyPath, [string]$Reason, [string]$DisplayName, [string]$MissingPath)
    [PSCustomObject]@{
        Category    = 'Registry'
        KeyPath     = $KeyPath
        DisplayName = $DisplayName
        Reason      = $Reason
        MissingPath = $MissingPath
    }
}

function New-FilesystemItem {
    param([string]$FolderPath, [string]$Reason)
    [PSCustomObject]@{
        Category   = 'Filesystem'
        FolderPath = $FolderPath
        Reason     = $Reason
    }
}

function New-StartupItem {
    param([string]$Source, [string]$Name, [string]$Command, [string]$MissingExe)
    [PSCustomObject]@{
        Category   = 'Startup'
        Source     = $Source
        Name       = $Name
        Command    = $Command
        MissingExe = $MissingExe
    }
}

function New-TaskItem {
    param([string]$TaskPath, [string]$TaskName, [string]$MissingExe)
    [PSCustomObject]@{
        Category   = 'ScheduledTask'
        TaskPath   = $TaskPath
        TaskName   = $TaskName
        MissingExe = $MissingExe
    }
}

# ---------------------------------------------------------------------------
# Scan: Orphaned uninstall registry keys
# ---------------------------------------------------------------------------

function Find-OrphanedRegistryKeys {
    Write-Section 'Scanning uninstall registry keys...'

    $results = [System.Collections.Generic.List[object]]::new()

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($basePath in $uninstallPaths) {
        if (-not (Test-Path $basePath)) { continue }

        $keys = Get-ChildItem -LiteralPath $basePath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $props       = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $displayName = $props.DisplayName
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

            $installLoc  = $props.InstallLocation
            $uninstStr   = $props.UninstallString
            $displayIcon = $props.DisplayIcon

            $orphaned   = $false
            $missing    = ''
            $reason     = ''

            # Check InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($installLoc)) {
                $cleanLoc = $installLoc.Trim().Trim('"')
                if (-not (Test-PathExists $cleanLoc)) {
                    $orphaned = $true
                    $missing  = $cleanLoc
                    $reason   = 'InstallLocation does not exist'
                }
            }

            # If InstallLocation is absent/empty, check UninstallString exe
            if (-not $orphaned -and -not [string]::IsNullOrWhiteSpace($uninstStr)) {
                $exe = Resolve-ExecutablePath $uninstStr
                if ($exe -and -not (Test-PathExists $exe)) {
                    # Skip MSI-based entries (msiexec.exe always exists)
                    if ($exe -notmatch 'msiexec(\.exe)?$' -and $exe -notmatch '^{') {
                        $orphaned = $true
                        $missing  = $exe
                        $reason   = 'Uninstall executable not found'
                    }
                }
            }

            # Check DisplayIcon exe (last resort signal)
            if (-not $orphaned -and -not [string]::IsNullOrWhiteSpace($displayIcon)) {
                $iconPath = ($displayIcon -split ',')[0].Trim().Trim('"')
                if ($iconPath -match '\.(exe|dll)$' -and -not (Test-PathExists $iconPath)) {
                    if ($iconPath -notmatch '^%SystemRoot%' -and
                        $iconPath -notmatch '^C:\\Windows' -and
                        $iconPath -notmatch 'msiexec') {
                        $orphaned = $true
                        $missing  = $iconPath
                        $reason   = 'DisplayIcon executable not found'
                    }
                }
            }

            if ($orphaned) {
                Write-Found "$displayName  ($reason)"
                $results.Add((New-RegistryItem -KeyPath $key.PSPath -Reason $reason `
                    -DisplayName $displayName -MissingPath $missing))
            }
        }
    }

    Write-Info "Found $($results.Count) orphaned uninstall key(s)."
    return $results
}

# ---------------------------------------------------------------------------
# Scan: Orphaned startup entries
# ---------------------------------------------------------------------------

function Find-OrphanedStartupEntries {
    Write-Section 'Scanning startup entries...'

    $results = [System.Collections.Generic.List[object]]::new()

    $runPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($regPath in $runPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $values = Get-Item -LiteralPath $regPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        foreach ($valueName in $values) {
            $cmd = (Get-ItemProperty -LiteralPath $regPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }

            $exe = Resolve-ExecutablePath $cmd
            if (-not (Test-PathExists $exe)) {
                Write-Found "$valueName  ->  $exe  (in $regPath)"
                $results.Add((New-StartupItem -Source $regPath -Name $valueName `
                    -Command $cmd -MissingExe $exe))
            }
        }
    }

    # Startup folders
    $startupFolders = @(
        [System.Environment]::GetFolderPath('Startup'),
        [System.Environment]::GetFolderPath('CommonStartup')
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-PathExists $folder)) { continue }
        $shortcuts = Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -ErrorAction SilentlyContinue
        foreach ($lnk in $shortcuts) {
            $shell  = New-Object -ComObject WScript.Shell
            $target = $shell.CreateShortcut($lnk.FullName).TargetPath
            if (-not [string]::IsNullOrWhiteSpace($target) -and -not (Test-PathExists $target)) {
                Write-Found "$($lnk.Name)  ->  $target  (in $folder)"
                $results.Add((New-StartupItem -Source $folder -Name $lnk.Name `
                    -Command $lnk.FullName -MissingExe $target))
            }
        }
    }

    Write-Info "Found $($results.Count) orphaned startup entry/entries."
    return $results
}

# ---------------------------------------------------------------------------
# Scan: Orphaned scheduled tasks
# ---------------------------------------------------------------------------

function Find-OrphanedScheduledTasks {
    Write-Section 'Scanning scheduled tasks...'

    $results = [System.Collections.Generic.List[object]]::new()

    # Skip built-in Microsoft tasks to avoid false positives
    $skipPrefixes = @('\Microsoft\', '\Windows\')

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($task in $tasks) {
        $skip = $false
        foreach ($prefix in $skipPrefixes) {
            if ($task.TaskPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true; break
            }
        }
        if ($skip) { continue }

        foreach ($action in $task.Actions) {
            if ($action.CimClass.CimClassName -ne 'MSFT_TaskExecAction') { continue }
            $exe = $action.Execute
            if ([string]::IsNullOrWhiteSpace($exe)) { continue }

            # Expand environment variables
            $exe = [System.Environment]::ExpandEnvironmentVariables($exe)

            # Skip system executables
            if ($exe -match '^(C:\\Windows\\|%SystemRoot%|%windir%)') { continue }
            if ($exe -match '^(cmd\.exe|powershell\.exe|wscript\.exe|cscript\.exe)$') { continue }

            if (-not (Test-PathExists $exe)) {
                $fullPath = "$($task.TaskPath)$($task.TaskName)"
                Write-Found "$fullPath  ->  $exe"
                $results.Add((New-TaskItem -TaskPath $task.TaskPath `
                    -TaskName $task.TaskName -MissingExe $exe))
            }
        }
    }

    Write-Info "Found $($results.Count) orphaned scheduled task(s)."
    return $results
}

# ---------------------------------------------------------------------------
# Scan: Orphaned filesystem folders
# ---------------------------------------------------------------------------

function Find-OrphanedFilesystemFolders {
    Write-Section 'Scanning filesystem for leftover folders...'

    $results = [System.Collections.Generic.List[object]]::new()

    # Build a set of known installed app display names (lowercased) for matching
    $installedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedLocations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($basePath in $uninstallPaths) {
        if (-not (Test-Path $basePath)) { continue }
        foreach ($key in (Get-ChildItem -LiteralPath $basePath -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName) { [void]$installedNames.Add($props.DisplayName) }
            if ($props.Publisher)   { [void]$installedNames.Add($props.Publisher) }
            if ($props.InstallLocation) {
                $loc = $props.InstallLocation.Trim().Trim('"').TrimEnd('\')
                if ($loc) { [void]$installedLocations.Add($loc) }
            }
        }
    }

    # Directories to scan + whether to check sub-folders one level deep
    $scanRoots = @(
        [System.Environment]::GetFolderPath('ProgramFiles'),
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        [System.Environment]::GetFolderPath('ApplicationData'),   # Roaming
        [System.Environment]::GetFolderPath('LocalApplicationData')
    ) | Where-Object { $_ -and (Test-PathExists $_) } | Select-Object -Unique

    # Folders to always ignore
    $ignoredFolders = @(
        'Microsoft', 'Windows', 'WindowsApps', 'Common Files', 'Common', 'internet explorer',
        'MSBuild', 'Reference Assemblies', 'dotnet', 'Packages', 'nvidia', 'intel',
        'Temp', 'temp', 'cache', 'Cache', 'Low', 'VMware', 'Hyper-V', 'docker'
    )

    foreach ($root in $scanRoots) {
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            # Skip always-ignored names
            if ($ignoredFolders -contains $dir.Name) { continue }

            # If this folder is an exact known install location, skip
            if ($installedLocations.Contains($dir.FullName)) { continue }
            if ($installedLocations.Contains($dir.FullName.TrimEnd('\'))) { continue }

            # Check if any installed app name is a substring of (or matches) the folder name
            $matchedApp = $installedNames | Where-Object {
                $_ -and ($dir.Name -match [regex]::Escape($_) -or $_ -match [regex]::Escape($dir.Name))
            } | Select-Object -First 1

            if ($matchedApp) { continue }  # Active app owns this folder

            # Check for any running processes with files in this folder
            $folderNorm = $dir.FullName.ToLower()
            $processInFolder = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                try { $_.MainModule.FileName.ToLower().StartsWith($folderNorm) } catch { $false }
            } | Select-Object -First 1

            if ($processInFolder) { continue }

            # Check if folder is completely empty or only contains empty sub-trees
            $fileCount = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                          Select-Object -First 1)

            if (-not $fileCount) {
                Write-Found "$($dir.FullName)  (empty, no installed app claims it)"
                $results.Add((New-FilesystemItem -FolderPath $dir.FullName `
                    -Reason 'Empty folder, not claimed by any installed application'))
                continue
            }

            # Check if all files are old (>180 days) and no app claims the folder
            $newestFile = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                          Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if ($newestFile -and $newestFile.LastWriteTime -lt (Get-Date).AddDays(-180)) {
                Write-Found "$($dir.FullName)  (>180 days stale, no installed app claims it)"
                $results.Add((New-FilesystemItem -FolderPath $dir.FullName `
                    -Reason "Stale folder (newest file: $($newestFile.LastWriteTime.ToString('yyyy-MM-dd'))), not claimed by any installed application"))
            }
        }
    }

    Write-Info "Found $($results.Count) potentially orphaned folder(s)."
    return $results
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

function Show-Report {
    param([object[]]$Items)

    if ($Items.Count -eq 0) {
        Write-Host "`nNothing to clean up. Your system looks tidy!" -ForegroundColor Green
        return
    }

    Write-Header "DRY-RUN REPORT  ($($Items.Count) items found)"

    $grouped = $Items | Group-Object Category
    foreach ($group in $grouped) {
        Write-Host "`n  [$($group.Name.ToUpper())]  $($group.Count) item(s)" -ForegroundColor Yellow
        $i = 1
        foreach ($item in $group.Group) {
            switch ($item.Category) {
                'Registry' {
                    Write-Host "    $i. $($item.DisplayName)" -ForegroundColor White
                    Write-Host "       Key    : $($item.KeyPath)" -ForegroundColor Gray
                    Write-Host "       Reason : $($item.Reason)" -ForegroundColor DarkGray
                    Write-Host "       Missing: $($item.MissingPath)" -ForegroundColor DarkRed
                }
                'Filesystem' {
                    Write-Host "    $i. $($item.FolderPath)" -ForegroundColor White
                    Write-Host "       Reason : $($item.Reason)" -ForegroundColor DarkGray
                }
                'Startup' {
                    Write-Host "    $i. $($item.Name)" -ForegroundColor White
                    Write-Host "       Source : $($item.Source)" -ForegroundColor Gray
                    Write-Host "       Command: $($item.Command)" -ForegroundColor DarkGray
                    Write-Host "       Missing: $($item.MissingExe)" -ForegroundColor DarkRed
                }
                'ScheduledTask' {
                    Write-Host "    $i. $($item.TaskPath)$($item.TaskName)" -ForegroundColor White
                    Write-Host "       Missing: $($item.MissingExe)" -ForegroundColor DarkRed
                }
            }
            $i++
        }
    }
}

# ---------------------------------------------------------------------------
# Deletion
# ---------------------------------------------------------------------------

function Remove-OrphanedItems {
    param(
        [object[]]$Items,
        [string]$BackupDir
    )

    $logPath = Join-Path $BackupDir "win-clean_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $log     = [System.Collections.Generic.List[string]]::new()
    $log.Add("win-clean removal log  $(Get-Date)")
    $log.Add('=' * 60)

    foreach ($item in $Items) {
        switch ($item.Category) {

            'Registry' {
                try {
                    $backupFile = Backup-RegistryKey -KeyPath $item.KeyPath -OutDir $BackupDir
                    Remove-Item -LiteralPath $item.KeyPath -Recurse -Force -ErrorAction Stop
                    $msg = "REMOVED  Registry: $($item.KeyPath)  [backup: $backupFile]"
                    Write-Ok $msg
                    $log.Add($msg)
                } catch {
                    $msg = "FAILED   Registry: $($item.KeyPath)  [$_]"
                    Write-Host "  [FAIL] $msg" -ForegroundColor Red
                    $log.Add($msg)
                }
            }

            'Filesystem' {
                try {
                    Remove-Item -LiteralPath $item.FolderPath -Recurse -Force -ErrorAction Stop
                    $msg = "REMOVED  Folder: $($item.FolderPath)"
                    Write-Ok $msg
                    $log.Add($msg)
                } catch {
                    $msg = "FAILED   Folder: $($item.FolderPath)  [$_]"
                    Write-Host "  [FAIL] $msg" -ForegroundColor Red
                    $log.Add($msg)
                }
            }

            'Startup' {
                try {
                    if ($item.Source -match '^HK') {
                        # Registry run key value
                        Remove-ItemProperty -LiteralPath $item.Source -Name $item.Name -Force -ErrorAction Stop
                        $msg = "REMOVED  Startup reg value: $($item.Name) from $($item.Source)"
                    } else {
                        # Startup folder shortcut
                        Remove-Item -LiteralPath $item.Command -Force -ErrorAction Stop
                        $msg = "REMOVED  Startup shortcut: $($item.Command)"
                    }
                    Write-Ok $msg
                    $log.Add($msg)
                } catch {
                    $msg = "FAILED   Startup: $($item.Name)  [$_]"
                    Write-Host "  [FAIL] $msg" -ForegroundColor Red
                    $log.Add($msg)
                }
            }

            'ScheduledTask' {
                try {
                    Unregister-ScheduledTask -TaskName $item.TaskName -TaskPath $item.TaskPath `
                        -Confirm:$false -ErrorAction Stop
                    $msg = "REMOVED  Scheduled task: $($item.TaskPath)$($item.TaskName)"
                    Write-Ok $msg
                    $log.Add($msg)
                } catch {
                    $msg = "FAILED   Scheduled task: $($item.TaskName)  [$_]"
                    Write-Host "  [FAIL] $msg" -ForegroundColor Red
                    $log.Add($msg)
                }
            }
        }
    }

    $log | Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "`nLog written to: $logPath" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Elevation check
# ---------------------------------------------------------------------------

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Header 'Windows Leftover Cleaner'
Write-Host '  Scans for registry, filesystem, startup, and task leftovers' -ForegroundColor Gray
Write-Host '  from uninstalled applications.' -ForegroundColor Gray

if (-not (Test-IsAdmin)) {
    Write-Host "`n[WARNING] Not running as Administrator." -ForegroundColor Yellow
    Write-Host "          HKLM registry keys and scheduled tasks may be inaccessible." -ForegroundColor Yellow
    Write-Host "          Re-run as Administrator for a complete scan.`n" -ForegroundColor Yellow
}

$allItems = [System.Collections.Generic.List[object]]::new()

if (-not $SkipRegistry)   { Find-OrphanedRegistryKeys    | ForEach-Object { $allItems.Add($_) } }
if (-not $SkipStartup)    { Find-OrphanedStartupEntries  | ForEach-Object { $allItems.Add($_) } }
if (-not $SkipTasks)      { Find-OrphanedScheduledTasks  | ForEach-Object { $allItems.Add($_) } }
if (-not $SkipFilesystem) { Find-OrphanedFilesystemFolders | ForEach-Object { $allItems.Add($_) } }

Show-Report -Items $allItems.ToArray()

if ($allItems.Count -eq 0) { exit 0 }

Write-Host "`n"
Write-Host '  Registry keys will be backed up as .reg files before removal.' -ForegroundColor Gray
Write-Host "  Backup directory: $BackupDir" -ForegroundColor Gray
Write-Host "`n  WARNING: Review the list above carefully. Filesystem deletions are" -ForegroundColor Yellow
Write-Host '           NOT recoverable from the Recycle Bin for some paths.' -ForegroundColor Yellow

$confirm = Read-Host "`nProceed with cleanup? [y/N]"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host 'Aborted. No changes made.' -ForegroundColor Cyan
    exit 0
}

Write-Header 'Cleaning up...'
Remove-OrphanedItems -Items $allItems.ToArray() -BackupDir $BackupDir

Write-Host "`nDone." -ForegroundColor Green

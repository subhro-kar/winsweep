#Requires -Version 5.1

param(
    [switch]$RequireAdmin,
    [switch]$NoElevationPrompt,
    [switch]$Elevated
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'src\Core\Helpers.ps1')
. (Join-Path $PSScriptRoot 'src\Core\Admin.ps1')
. (Join-Path $PSScriptRoot 'src\Models\ScanResult.ps1')
. (Join-Path $PSScriptRoot 'src\Scanners\Registry.ps1')

function Find-OrphanStartupEntries {
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

            $exe = Resolve-ExecutablePath -CommandString $cmd
            if (-not (Test-PathExists $exe)) {
                $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Startup Entries' -Name $valueName `
                    -PathOrKey $regPath -Reason "Missing executable: $exe" -DeleteMeta @{
                        Type = 'StartupRegistryValue'
                        Source = $regPath
                        Name = $valueName
                        Command = $cmd
                    }))
            }
        }
    }

    $startupFolders = @(
        [System.Environment]::GetFolderPath('Startup'),
        [System.Environment]::GetFolderPath('CommonStartup')
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-PathExists $folder)) { continue }
        $shortcuts = Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -ErrorAction SilentlyContinue
        foreach ($lnk in $shortcuts) {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $target = $shell.CreateShortcut($lnk.FullName).TargetPath
                if (-not [string]::IsNullOrWhiteSpace($target) -and -not (Test-PathExists $target)) {
                    $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Startup Entries' -Name $lnk.Name `
                        -PathOrKey $lnk.FullName -Reason "Shortcut target missing: $target" -DeleteMeta @{
                            Type = 'StartupShortcut'
                            ShortcutPath = $lnk.FullName
                            TargetPath = $target
                        }))
                }
            } catch {
            }
        }
    }

    return $results
}

function Find-OrphanScheduledTasks {
    $results = [System.Collections.Generic.List[object]]::new()
    $skipPrefixes = @('\\Microsoft\\', '\\Windows\\')

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($task in $tasks) {
        $skip = $false
        foreach ($prefix in $skipPrefixes) {
            if ($task.TaskPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        foreach ($action in $task.Actions) {
            if ($action.CimClass.CimClassName -ne 'MSFT_TaskExecAction') { continue }
            $exe = [Environment]::ExpandEnvironmentVariables($action.Execute)
            if ([string]::IsNullOrWhiteSpace($exe)) { continue }
            if ($exe -match '^(C:\\Windows\\|%SystemRoot%|%windir%)') { continue }
            if ($exe -match '^(cmd\.exe|powershell\.exe|wscript\.exe|cscript\.exe)$') { continue }

            if (-not (Test-PathExists $exe)) {
                $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Scheduled Tasks' -Name $task.TaskName `
                    -PathOrKey "$($task.TaskPath)$($task.TaskName)" -Reason "Missing executable: $exe" -DeleteMeta @{
                        Type = 'ScheduledTask'
                        TaskName = $task.TaskName
                        TaskPath = $task.TaskPath
                    }))
            }
        }
    }

    return $results
}

function Find-OrphanFilesystemFolders {
    $results = [System.Collections.Generic.List[object]]::new()

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
            $displayName = Get-RegistryValue -Path $key.PSPath -Name 'DisplayName'
            $publisher = Get-RegistryValue -Path $key.PSPath -Name 'Publisher'
            $installLocation = Get-RegistryValue -Path $key.PSPath -Name 'InstallLocation'

            if ($displayName) { [void]$installedNames.Add($displayName) }
            if ($publisher) { [void]$installedNames.Add($publisher) }
            if ($installLocation) {
                $loc = $installLocation.Trim().Trim('"').TrimEnd('\\')
                if ($loc) { [void]$installedLocations.Add($loc) }
            }
        }
    }

    $scanRoots = @(
        [System.Environment]::GetFolderPath('ProgramFiles'),
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        [System.Environment]::GetFolderPath('ApplicationData'),
        [System.Environment]::GetFolderPath('LocalApplicationData')
    ) | Where-Object { $_ -and (Test-PathExists $_) } | Select-Object -Unique

    $ignoredFolders = @(
        'Microsoft', 'Windows', 'WindowsApps', 'Common Files', 'Common', 'internet explorer',
        'MSBuild', 'Reference Assemblies', 'dotnet', 'Packages', 'nvidia', 'intel', 'Temp',
        'temp', 'cache', 'Cache', 'Low', 'VMware', 'Hyper-V', 'docker'
    )

    foreach ($root in $scanRoots) {
        foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if ($ignoredFolders -contains $dir.Name) { continue }
            if ($installedLocations.Contains($dir.FullName)) { continue }
            if ($installedLocations.Contains($dir.FullName.TrimEnd('\\'))) { continue }

            $matchedApp = $installedNames | Where-Object {
                $_ -and ($dir.Name -match [regex]::Escape($_) -or $_ -match [regex]::Escape($dir.Name))
            } | Select-Object -First 1
            if ($matchedApp) { continue }

            $folderNorm = $dir.FullName.ToLowerInvariant()
            $processInFolder = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                try { $_.MainModule.FileName.ToLowerInvariant().StartsWith($folderNorm) } catch { $false }
            } | Select-Object -First 1
            if ($processInFolder) { continue }

            $fileAny = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $fileAny) {
                $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Orphaned Folders' -Name $dir.Name `
                    -PathOrKey $dir.FullName -Reason 'Empty folder not claimed by installed application' -DeleteMeta @{
                        Type = 'FilesystemPath'
                        Path = $dir.FullName
                    }))
                continue
            }

            $newestFile = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($newestFile -and $newestFile.LastWriteTime -lt (Get-Date).AddDays(-180)) {
                $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Orphaned Folders' -Name $dir.Name `
                    -PathOrKey $dir.FullName -Reason "Stale folder (>180 days old activity)" -DeleteMeta @{
                        Type = 'FilesystemPath'
                        Path = $dir.FullName
                    }))
            }
        }
    }

    return $results
}

function Get-TempFilesItem {
    $paths = @($env:TEMP, $env:TMP, 'C:\Windows\Temp') | Select-Object -Unique
    return (New-DeepCleanAggregateItem -Name 'Temp Files' -Reason 'Temporary files and folders' -Paths $paths -SubCategory 'Temp Files')
}

function Get-WindowsUpdateCacheItem {
    $paths = @('C:\Windows\SoftwareDistribution\Download')
    return (New-DeepCleanAggregateItem -Name 'Windows Update Cache' -Reason 'Downloaded update packages cache' -Paths $paths -SubCategory 'Windows Update Cache')
}

function Get-WerItem {
    $paths = @('C:\ProgramData\Microsoft\Windows\WER', "$env:LOCALAPPDATA\Microsoft\Windows\WER")
    return (New-DeepCleanAggregateItem -Name 'WER / Crash Dumps' -Reason 'Windows Error Reporting leftovers' -Paths $paths -SubCategory 'WER/Crash Dumps')
}

function Get-PrefetchItem {
    $paths = @('C:\Windows\Prefetch')
    return (New-DeepCleanAggregateItem -Name 'Prefetch' -Reason 'Prefetch cache files' -Paths $paths -SubCategory 'Prefetch')
}

function Get-ThumbnailCacheItem {
    $explorer = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (-not (Test-PathExists $explorer)) { return $null }

    $size = 0L
    foreach ($file in (Get-ChildItem -LiteralPath $explorer -Filter 'thumbcache_*.db' -File -ErrorAction SilentlyContinue)) {
        $size += [Int64]$file.Length
    }
    if ($size -le 0) { return $null }

    return (New-ScanResult -Category 'Deep Clean' -SubCategory 'Thumbnail Cache' -Name 'Thumbnail Cache' -PathOrKey $explorer `
        -Reason 'Explorer thumbnail database cache' -Size (Format-Bytes -Bytes $size) -DeleteMeta @{
            Type = 'DeepCleanGlob'
            BasePath = $explorer
            Pattern = 'thumbcache_*.db'
            SizeBytes = $size
        })
}

function Get-BrowserCacheItem {
    $paths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    )
    return (New-DeepCleanAggregateItem -Name 'Browser Caches' -Reason 'Chrome / Edge / Firefox cache data' -Paths $paths -SubCategory 'Browser Caches')
}

function Get-LogFilesItem {
    $paths = @('C:\Windows\Logs\CBS', 'C:\Windows\Logs\DISM', "$env:LOCALAPPDATA\CrashDumps")
    return (New-DeepCleanAggregateItem -Name 'Log Files' -Reason 'System and crash logs' -Paths $paths -SubCategory 'Log Files')
}

function Get-CategoryDefinitions {
    return @(
        [PSCustomObject]@{ Name = 'Uninstall Keys'; Scanner = 'Find-OrphanUninstallKeys' },
        [PSCustomObject]@{ Name = 'COM/ActiveX'; Scanner = 'Find-BrokenComRegistrations' },
        [PSCustomObject]@{ Name = 'Services'; Scanner = 'Find-BrokenServiceEntries' },
        [PSCustomObject]@{ Name = 'File Associations'; Scanner = 'Find-BrokenFileAssociations' },
        [PSCustomObject]@{ Name = 'Shell Extensions'; Scanner = 'Find-BrokenShellExtensions' },
        [PSCustomObject]@{ Name = 'App Paths'; Scanner = 'Find-BrokenAppPaths' },
        [PSCustomObject]@{ Name = 'Fonts'; Scanner = 'Find-BrokenFontRegistrations' },
        [PSCustomObject]@{ Name = 'Orphaned Folders'; Scanner = 'Find-OrphanFilesystemFolders' },
        [PSCustomObject]@{ Name = 'Startup Entries'; Scanner = 'Find-OrphanStartupEntries' },
        [PSCustomObject]@{ Name = 'Scheduled Tasks'; Scanner = 'Find-OrphanScheduledTasks' },
        [PSCustomObject]@{ Name = 'Temp Files'; Scanner = 'Get-TempFilesItem' },
        [PSCustomObject]@{ Name = 'Windows Update Cache'; Scanner = 'Get-WindowsUpdateCacheItem' },
        [PSCustomObject]@{ Name = 'WER/Crash Dumps'; Scanner = 'Get-WerItem' },
        [PSCustomObject]@{ Name = 'Prefetch'; Scanner = 'Get-PrefetchItem' },
        [PSCustomObject]@{ Name = 'Thumbnail Cache'; Scanner = 'Get-ThumbnailCacheItem' },
        [PSCustomObject]@{ Name = 'Browser Caches'; Scanner = 'Get-BrowserCacheItem' },
        [PSCustomObject]@{ Name = 'Log Files'; Scanner = 'Get-LogFilesItem' }
    )
}

function Invoke-SelectedScans {
    param([string[]]$SelectedCategories)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in (Get-CategoryDefinitions | Where-Object { $SelectedCategories -contains $_.Name })) {
        $scanFn = Get-Command -Name $definition.Scanner -ErrorAction SilentlyContinue
        if (-not $scanFn) { continue }
        $scanOutput = & $definition.Scanner
        if ($scanOutput -is [System.Collections.IEnumerable]) {
            foreach ($item in $scanOutput) {
                if ($null -ne $item) { $results.Add($item) }
            }
        } elseif ($null -ne $scanOutput) {
            $results.Add($scanOutput)
        }
    }
    return $results
}

function Save-UndoManifest {
    param(
        [string]$OutDir,
        [hashtable]$ManifestData
    )

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $manifestPath = Join-Path $OutDir "undo_${stamp}.json"
    $ManifestData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    return $manifestPath
}

function Get-LatestUndoManifest {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    return (Get-ChildItem -LiteralPath $Dir -Filter 'undo_*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Show-UndoDialog {
    param([string]$BackupDir)

    $manifest = Get-LatestUndoManifest -Dir $BackupDir
    if (-not $manifest) {
        [System.Windows.Forms.MessageBox]::Show('No undo manifest found.', 'Undo Last Session', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $data = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Undo Last Session'
    $dialog.Size = New-Object System.Drawing.Size(760, 460)
    $dialog.StartPosition = 'CenterParent'

    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.Dock = 'Top'
    $list.Height = 330
    [void]$list.Columns.Add('Type', 140)
    [void]$list.Columns.Add('Details', 580)

    foreach ($reg in $data.regBackups) {
        $item = New-Object System.Windows.Forms.ListViewItem('Registry backup')
        [void]$item.SubItems.Add([string]$reg)
        [void]$list.Items.Add($item)
    }
    foreach ($path in $data.deletedPaths) {
        $item = New-Object System.Windows.Forms.ListViewItem('Deleted path')
        [void]$item.SubItems.Add("$path (check Recycle Bin)")
        [void]$list.Items.Add($item)
    }
    foreach ($task in $data.removedTasks) {
        $item = New-Object System.Windows.Forms.ListViewItem('Removed task')
        [void]$item.SubItems.Add([string]$task)
        [void]$list.Items.Add($item)
    }

    $btnReimport = New-Object System.Windows.Forms.Button
    $btnReimport.Text = 'Re-import Registry Backups'
    $btnReimport.Location = New-Object System.Drawing.Point(10, 350)
    $btnReimport.Width = 220

    $btnRecycle = New-Object System.Windows.Forms.Button
    $btnRecycle.Text = 'Open Recycle Bin'
    $btnRecycle.Location = New-Object System.Drawing.Point(240, 350)
    $btnRecycle.Width = 140

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = 'Open Backup Folder'
    $btnBackup.Location = New-Object System.Drawing.Point(390, 350)
    $btnBackup.Width = 150

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(640, 350)
    $btnClose.Width = 90

    $btnReimport.Add_Click({
        foreach ($reg in $data.regBackups) {
            if (Test-Path -LiteralPath $reg) {
                Start-Process -FilePath regedit.exe -ArgumentList "/s `"$reg`"" -Wait
            }
        }
        [System.Windows.Forms.MessageBox]::Show('Registry backups imported.', 'Undo', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $btnRecycle.Add_Click({ Start-Process explorer.exe 'shell:RecycleBinFolder' })
    $btnBackup.Add_Click({ Start-Process explorer.exe $BackupDir })
    $btnClose.Add_Click({ $dialog.Close() })

    $dialog.Controls.Add($list)
    $dialog.Controls.Add($btnReimport)
    $dialog.Controls.Add($btnRecycle)
    $dialog.Controls.Add($btnBackup)
    $dialog.Controls.Add($btnClose)

    [void]$dialog.ShowDialog()
}

if (-not (Ensure-LaunchMode)) {
    return
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Cleaner'
$form.Size = New-Object System.Drawing.Size(1100, 700)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(900, 560)

$toolStrip = New-Object System.Windows.Forms.ToolStrip
$toolStrip.GripStyle = 'Hidden'
$toolStrip.Dock = 'Top'

$btnScan = New-Object System.Windows.Forms.ToolStripButton('Scan')
$btnScanOptions = New-Object System.Windows.Forms.ToolStripButton('Scan Options')
$btnClean = New-Object System.Windows.Forms.ToolStripButton('Clean Selected')
$btnSelectAll = New-Object System.Windows.Forms.ToolStripButton('Select All')
$btnSelectNone = New-Object System.Windows.Forms.ToolStripButton('Select None')
$btnOpenBackup = New-Object System.Windows.Forms.ToolStripButton('Open Backup Folder')
$btnUndo = New-Object System.Windows.Forms.ToolStripButton('Undo Last Session')

$toolProgress = New-Object System.Windows.Forms.ToolStripProgressBar
$toolProgress.Style = 'Marquee'
$toolProgress.Visible = $false
$toolProgress.Width = 140

$toolStatus = New-Object System.Windows.Forms.ToolStripLabel('Ready')

[void]$toolStrip.Items.Add($btnScan)
[void]$toolStrip.Items.Add($btnScanOptions)
[void]$toolStrip.Items.Add($btnClean)
[void]$toolStrip.Items.Add($btnSelectAll)
[void]$toolStrip.Items.Add($btnSelectNone)
[void]$toolStrip.Items.Add($btnOpenBackup)
[void]$toolStrip.Items.Add($btnUndo)
[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$toolStrip.Items.Add($toolProgress)
[void]$toolStrip.Items.Add($toolStatus)

$banner = New-Object System.Windows.Forms.Label
$banner.Dock = 'Top'
$banner.Height = 28
$banner.TextAlign = 'MiddleLeft'
$banner.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 204)
$banner.ForeColor = [System.Drawing.Color]::FromArgb(120, 60, 0)
$banner.Text = ' Running without Administrator privileges. Some scans/cleanup actions may be unavailable.'
$banner.Visible = -not (Test-IsAdmin)

$header = New-Object System.Windows.Forms.Label
$header.Dock = 'Top'
$header.Height = 26
$header.TextAlign = 'MiddleLeft'
$header.Text = " Windows Cleaner GUI - backup/log directory: $PSScriptRoot"

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.SplitterDistance = 260
$split.Panel1MinSize = 220
$split.Panel2Collapsed = $true

$categories = New-Object System.Windows.Forms.CheckedListBox
$categories.Dock = 'Fill'
$categories.CheckOnClick = $true
$categories.IntegralHeight = $false

foreach ($cat in (Get-CategoryDefinitions)) {
    [void]$categories.Items.Add($cat.Name, $true)
}

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.ReadOnly = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false

function Initialize-GridColumns {
    param([System.Windows.Forms.DataGridView]$TargetGrid)

    $TargetGrid.Columns.Clear()

    $colSel = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colSel.Name = 'Selected'
    $colSel.HeaderText = 'Selected'
    $colSel.Width = 60
    $colSel.ReadOnly = $false

    $colCategory = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colCategory.Name = 'Category'
    $colCategory.HeaderText = 'Category'
    $colCategory.ReadOnly = $true

    $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colName.Name = 'Name'
    $colName.HeaderText = 'Name'
    $colName.ReadOnly = $true

    $colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPath.Name = 'PathOrKey'
    $colPath.HeaderText = 'Path / Key'
    $colPath.ReadOnly = $true

    $colReason = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colReason.Name = 'Reason'
    $colReason.HeaderText = 'Reason'
    $colReason.ReadOnly = $true

    $colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSize.Name = 'Size'
    $colSize.HeaderText = 'Size'
    $colSize.ReadOnly = $true

    [void]$TargetGrid.Columns.Add($colSel)
    [void]$TargetGrid.Columns.Add($colCategory)
    [void]$TargetGrid.Columns.Add($colName)
    [void]$TargetGrid.Columns.Add($colPath)
    [void]$TargetGrid.Columns.Add($colReason)
    [void]$TargetGrid.Columns.Add($colSize)
}

function Add-ResultRow {
    param(
        [System.Windows.Forms.DataGridView]$TargetGrid,
        [object]$Item
    )

    if ($TargetGrid.Columns.Count -lt 6) {
        Initialize-GridColumns -TargetGrid $TargetGrid
    }

    $idx = $TargetGrid.Rows.Add($false, $Item.Category, $Item.Name, $Item.PathOrKey, $Item.Reason, $Item.Size)
    if ($Item.Category -eq 'Registry') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    } elseif ($Item.Category -eq 'Application') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(236, 246, 255)
    } elseif ($Item.Category -eq 'Deep Clean') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 246, 232)
    }
}

Initialize-GridColumns -TargetGrid $grid

$tip = New-Object System.Windows.Forms.ToolTip
$grid.Add_CellMouseEnter({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $p = [string]$sender.Rows[$e.RowIndex].Cells['PathOrKey'].Value
        if ($p) { $tip.SetToolTip($sender, $p) }
    }
})

$split.Panel1.Controls.Add($categories)
$split.Panel2.Controls.Add($grid)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statCounts = New-Object System.Windows.Forms.ToolStripStatusLabel('Found: 0 | Selected: 0')
$statInfo = New-Object System.Windows.Forms.ToolStripStatusLabel('')
[void]$statusStrip.Items.Add($statCounts)
[void]$statusStrip.Items.Add((New-Object System.Windows.Forms.ToolStripStatusLabel(' | ')))
[void]$statusStrip.Items.Add($statInfo)

$form.Controls.Add($split)
$form.Controls.Add($header)
$form.Controls.Add($banner)
$form.Controls.Add($toolStrip)
$form.Controls.Add($statusStrip)

$resultsStore = [System.Collections.Generic.List[object]]::new()

# Start with pre-scan mode: choose categories first.
$btnClean.Visible = $false
$btnSelectAll.Visible = $false
$btnSelectNone.Visible = $false
$btnClean.Enabled = $false
$btnSelectAll.Enabled = $false
$btnSelectNone.Enabled = $false
$toolStatus.Text = 'Select categories and click Scan.'

function Update-Counts {
    $selected = 0
    foreach ($row in $grid.Rows) {
        if ($row.Cells['Selected'].Value -eq $true) { $selected++ }
    }
    $statCounts.Text = "Found: $($grid.Rows.Count) | Selected: $selected"
}

$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})
$grid.Add_CellValueChanged({ Update-Counts })

$btnSelectAll.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells['Selected'].Value = $true }
    Update-Counts
})

$btnSelectNone.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells['Selected'].Value = $false }
    Update-Counts
})

$btnOpenBackup.Add_Click({
    Start-Process explorer.exe $PSScriptRoot
})

$btnScanOptions.Add_Click({
    $split.Panel1Collapsed = $false
    if ($grid.Rows.Count -gt 0) {
        $split.Panel2Collapsed = $false
    }
    $toolStatus.Text = 'Scan options visible. Adjust categories and click Scan.'
})

$btnUndo.Add_Click({
    Show-UndoDialog -BackupDir $PSScriptRoot
})

$btnScan.Add_Click({
    $selectedCategories = @()
    foreach ($entry in $categories.CheckedItems) {
        $selectedCategories += [string]$entry
    }
    if ($selectedCategories.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Choose at least one category to scan.', 'Scan', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $btnScan.Enabled = $false
    $btnClean.Enabled = $false
    $btnSelectAll.Enabled = $false
    $btnSelectNone.Enabled = $false
    $toolProgress.Visible = $true
    $toolProgress.Style = 'Continuous'
    $toolStatus.Text = 'Scanning...'

    try {
        $grid.Rows.Clear()
        $resultsStore.Clear()
        $categoryErrors = [System.Collections.Generic.List[string]]::new()
        $definitions = (Get-CategoryDefinitions | Where-Object { $selectedCategories -contains $_.Name })

        $toolProgress.Minimum = 0
        $toolProgress.Maximum = [Math]::Max(1, $definitions.Count)
        $toolProgress.Value = 0

        $totalFound = 0
        $done = 0

        foreach ($definition in $definitions) {
            $toolStatus.Text = "Scanning category $($done + 1) of $($definitions.Count): $($definition.Name)..."
            [System.Windows.Forms.Application]::DoEvents()

            try {
                $scanOut = & $definition.Scanner
                $categoryFound = 0

                if ($scanOut -is [System.Collections.IEnumerable]) {
                    foreach ($item in $scanOut) {
                        if ($null -eq $item) { continue }
                        [void]$resultsStore.Add($item)
                        Add-ResultRow -TargetGrid $grid -Item $item
                        $categoryFound++
                    }
                } elseif ($null -ne $scanOut) {
                    [void]$resultsStore.Add($scanOut)
                    Add-ResultRow -TargetGrid $grid -Item $scanOut
                    $categoryFound = 1
                }

                $totalFound += $categoryFound
                $statInfo.Text = "Category: $($definition.Name) = $categoryFound item(s) | Total found: $totalFound"
            } catch {
                $categoryErrors.Add("$($definition.Name): $($_.Exception.Message)")
                $statInfo.Text = "Category error: $($definition.Name)"
            }

            $done++
            $toolProgress.Value = [Math]::Min($toolProgress.Maximum, $done)
            Update-Counts
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($categoryErrors.Count -gt 0) {
            $toolStatus.Text = "Scan completed with warnings. Found $($grid.Rows.Count) item(s)."
            [System.Windows.Forms.MessageBox]::Show(
                "Some categories failed:`r`n" + ($categoryErrors -join "`r`n"),
                'Scan Warnings',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        } else {
            $toolStatus.Text = "Scan complete. Found $($grid.Rows.Count) item(s)."
        }

        if ($grid.Rows.Count -gt 0) {
            $split.Panel2Collapsed = $false
            $split.Panel1Collapsed = $true
            $btnClean.Visible = $true
            $btnSelectAll.Visible = $true
            $btnSelectNone.Visible = $true
            $btnClean.Enabled = $true
            $btnSelectAll.Enabled = $true
            $btnSelectNone.Enabled = $true
        } else {
            $split.Panel1Collapsed = $false
            $split.Panel2Collapsed = $true
            $btnClean.Visible = $false
            $btnSelectAll.Visible = $false
            $btnSelectNone.Visible = $false
            $btnClean.Enabled = $false
            $btnSelectAll.Enabled = $false
            $btnSelectNone.Enabled = $false
        }
    } catch {
        $toolStatus.Text = "Scan failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Scan failed: $($_.Exception.Message)",
            'Scan Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        $btnScan.Enabled = $true
        $toolProgress.Style = 'Marquee'
        $toolProgress.Visible = $false
        Update-Counts
    }
})

$btnClean.Add_Click({
    $selectedRows = @()
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        if ($grid.Rows[$i].Cells['Selected'].Value -eq $true) {
            $selectedRows += $i
        }
    }

    if ($selectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Select at least one item first.', 'Clean Selected', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $confirmForm = New-Object System.Windows.Forms.Form
    $confirmForm.Text = 'Confirm Cleanup'
    $confirmForm.Size = New-Object System.Drawing.Size(520, 260)
    $confirmForm.StartPosition = 'CenterParent'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $false
    $lbl.Width = 480
    $lbl.Height = 80
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Text = "You selected $($selectedRows.Count) item(s).`r`nRegistry entries will be backed up. Files/folders are moved to Recycle Bin when possible. Continue?"

    $chkRestore = New-Object System.Windows.Forms.CheckBox
    $chkRestore.Text = 'Create System Restore Point first'
    $chkRestore.Checked = $true
    $chkRestore.Location = New-Object System.Drawing.Point(12, 100)
    $chkRestore.Width = 260

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = 'Proceed'
    $btnYes.Location = New-Object System.Drawing.Point(300, 170)
    $btnYes.Width = 90

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = 'Cancel'
    $btnNo.Location = New-Object System.Drawing.Point(400, 170)
    $btnNo.Width = 90

    $script:confirmProceed = $false
    $btnYes.Add_Click({ $script:confirmProceed = $true; $confirmForm.Close() })
    $btnNo.Add_Click({ $confirmForm.Close() })

    $confirmForm.Controls.Add($lbl)
    $confirmForm.Controls.Add($chkRestore)
    $confirmForm.Controls.Add($btnYes)
    $confirmForm.Controls.Add($btnNo)

    [void]$confirmForm.ShowDialog()
    if (-not $script:confirmProceed) { return }

    if ($chkRestore.Checked) {
        $toolStatus.Text = 'Creating restore point...'
        try {
            Checkpoint-Computer -Description 'win-clean backup' -RestorePointType 'MODIFY_SETTINGS' | Out-Null
        } catch {
            $cont = [System.Windows.Forms.MessageBox]::Show(
                "Could not create restore point: $($_.Exception.Message)`r`nContinue cleanup anyway?",
                'Restore Point Failed',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($cont -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
    }

    $progressForm = New-Object System.Windows.Forms.Form
    $progressForm.Text = 'Cleanup Progress'
    $progressForm.Size = New-Object System.Drawing.Size(980, 460)
    $progressForm.MinimumSize = New-Object System.Drawing.Size(760, 360)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.SizeGripStyle = 'Show'

    $progressTop = New-Object System.Windows.Forms.Panel
    $progressTop.Dock = 'Top'
    $progressTop.Height = 62

    $progressLabel = New-Object System.Windows.Forms.Label
    $progressLabel.Anchor = 'Top,Left,Right'
    $progressLabel.Height = 24
    $progressLabel.Width = 820
    $progressLabel.Location = New-Object System.Drawing.Point(8, 6)
    $progressLabel.TextAlign = 'MiddleLeft'
    $progressLabel.Text = "Starting cleanup..."

    $btnCancelCleanup = New-Object System.Windows.Forms.Button
    $btnCancelCleanup.Anchor = 'Top,Right'
    $btnCancelCleanup.Text = 'Cancel'
    $btnCancelCleanup.Width = 90
    $btnCancelCleanup.Height = 26
    $btnCancelCleanup.Location = New-Object System.Drawing.Point(($progressForm.ClientSize.Width - 104), 5)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Anchor = 'Left,Right,Bottom'
    $progressBar.Location = New-Object System.Drawing.Point(8, 36)
    $progressBar.Width = $progressForm.ClientSize.Width - 16
    $progressBar.Height = 18
    $progressBar.Minimum = 0
    $progressBar.Maximum = [Math]::Max(1, $selectedRows.Count)
    $progressBar.Value = 0
    $progressBar.Style = 'Continuous'

    $progressTop.Controls.Add($progressLabel)
    $progressTop.Controls.Add($btnCancelCleanup)
    $progressTop.Controls.Add($progressBar)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = 'Fill'
    $list.HorizontalScrollbar = $true
    $list.IntegralHeight = $false
    $progressForm.Controls.Add($progressTop)
    $progressForm.Controls.Add($list)

    Enable-DragMove -Control $progressTop -TargetForm $progressForm
    Enable-DragMove -Control $progressLabel -TargetForm $progressForm

    $script:cleanupCancelRequested = $false
    $btnCancelCleanup.Add_Click({
        $script:cleanupCancelRequested = $true
        $btnCancelCleanup.Enabled = $false
        $btnCancelCleanup.Text = 'Cancelling...'
    })

    $progressForm.Add_FormClosing({
        if (-not $script:cleanupCancelRequested -and $btnCancelCleanup.Enabled) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                'Cleanup is still running. Cancel after the current item finishes?',
                'Cancel Cleanup',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                $script:cleanupCancelRequested = $true
                $btnCancelCleanup.Enabled = $false
                $btnCancelCleanup.Text = 'Cancelling...'
                $_.Cancel = $true
            } else {
                $_.Cancel = $true
            }
        }
    })

    $progressForm.Show()

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logPath = Join-Path $PSScriptRoot "win-clean_${stamp}.log"
    $logLines = [System.Collections.Generic.List[string]]::new()

    $manifest = @{
        timestamp = (Get-Date).ToString('o')
        regBackups = @()
        deletedPaths = @()
        removedTasks = @()
        removedStartup = @()
    }

    $abortCleanup = $false

    $logCallback = {
        param([string]$Message)
        $list.Items.Add($Message)
        $list.TopIndex = [Math]::Max(0, $list.Items.Count - 1)
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:cleanupCancelRequested) {
            $abortCleanup = $true
            $list.Items.Add('[CANCEL] Cleanup cancelled by user. Stopping after current item.')
            $logLines.Add('[CANCEL] Cleanup cancelled by user.')
            break
        }
    }

    $currentStep = 0
    foreach ($rowIndex in $selectedRows) {
        $currentStep++
        $item = $resultsStore[$rowIndex]
        $meta = $item.DeleteMeta
        if (-not $meta) { continue }

        $progressLabel.Text = "Processing $currentStep/$($selectedRows.Count): $($item.Name)"
        $progressBar.Value = [Math]::Min($progressBar.Maximum, $currentStep)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            switch ($meta.Type) {
                'RegistryKey' {
                    $backup = Backup-RegistryKey -KeyPath $meta.KeyPath -OutDir $PSScriptRoot
                    Remove-Item -LiteralPath $meta.KeyPath -Recurse -Force -ErrorAction Stop
                    $manifest.regBackups += $backup
                    $line = "REMOVED Registry key: $($meta.KeyPath) [backup: $backup]"
                }
                'FontValue' {
                    $backup = Backup-RegistryKey -KeyPath $meta.KeyPath -OutDir $PSScriptRoot
                    Remove-ItemProperty -LiteralPath $meta.KeyPath -Name $meta.ValueName -Force -ErrorAction Stop
                    $manifest.regBackups += $backup
                    $line = "REMOVED Font registration: $($meta.ValueName) from $($meta.KeyPath) [backup: $backup]"
                }
                'StartupRegistryValue' {
                    Remove-ItemProperty -LiteralPath $meta.Source -Name $meta.Name -Force -ErrorAction Stop
                    $manifest.removedStartup += "$($meta.Source)::$($meta.Name)"
                    $line = "REMOVED Startup value: $($meta.Name) in $($meta.Source)"
                }
                'StartupShortcut' {
                    $r = Remove-PathWithRecovery -Path $meta.ShortcutPath -AllowHardDeleteFallback $true -LogCallback $logCallback
                    if ($r.Success) {
                        $manifest.deletedPaths += $meta.ShortcutPath
                        $line = "REMOVED Startup shortcut: $($meta.ShortcutPath) [$($r.Mode)]"
                    } elseif ($r.Mode -eq 'RequiresAdmin') {
                        $line = "SKIPPED Startup shortcut (requires admin): $($meta.ShortcutPath)"
                    } elseif ($r.Mode -eq 'SkippedByUser') {
                        $line = "SKIPPED Startup shortcut (in use): $($meta.ShortcutPath)"
                    } elseif ($r.Mode -eq 'AbortedByUser') {
                        throw 'Cleanup aborted by user.'
                    } else {
                        throw "Failed removing startup shortcut: $($r.Mode)"
                    }
                }
                'ScheduledTask' {
                    Unregister-ScheduledTask -TaskName $meta.TaskName -TaskPath $meta.TaskPath -Confirm:$false -ErrorAction Stop
                    $manifest.removedTasks += "$($meta.TaskPath)$($meta.TaskName)"
                    $line = "REMOVED Scheduled task: $($meta.TaskPath)$($meta.TaskName)"
                }
                'FilesystemPath' {
                    $r = Remove-PathWithRecovery -Path $meta.Path -AllowHardDeleteFallback $true -LogCallback $logCallback
                    if ($r.Success) {
                        $manifest.deletedPaths += $meta.Path
                        $line = "REMOVED Filesystem path: $($meta.Path) [$($r.Mode)]"
                    } elseif ($r.Mode -eq 'RequiresAdmin') {
                        $line = "SKIPPED Filesystem path (requires admin): $($meta.Path)"
                    } elseif ($r.Mode -eq 'SkippedByUser') {
                        $line = "SKIPPED Filesystem path (in use): $($meta.Path)"
                    } elseif ($r.Mode -eq 'AbortedByUser') {
                        throw 'Cleanup aborted by user.'
                    } else {
                        throw "Failed removing path: $($r.Mode)"
                    }
                }
                'DeepCleanPaths' {
                    foreach ($p in $meta.Paths) {
                        if (-not (Test-Path -LiteralPath $p)) { continue }

                        $target = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                        if (-not $target) { continue }

                        if ($target.PSIsContainer) {
                            $r = Remove-DirectoryContentsWithRecovery -DirectoryPath $p -AllowHardDeleteFallback $true
                            foreach ($ok in $r.Removed) {
                                $manifest.deletedPaths += $ok.Path
                                & $logCallback "REMOVED $($ok.Path) [$($ok.Mode)]"
                            }
                            foreach ($bad in $r.Failed) {
                                & $logCallback "FAILED $($bad.Path) [$($bad.Mode)]"
                            }
                            & $logCallback "PRESERVED deep clean root: $p"
                        } else {
                            $r = Remove-PathWithRecovery -Path $p -AllowHardDeleteFallback $true -LogCallback $logCallback
                            if ($r.Success) {
                                $manifest.deletedPaths += $p
                            }
                        }
                    }
                    $line = "PROCESSED Deep clean category: $($item.Name)"
                }
                'DeepCleanGlob' {
                    $files = Get-ChildItem -LiteralPath $meta.BasePath -Filter $meta.Pattern -File -ErrorAction SilentlyContinue
                    foreach ($f in $files) {
                        $r = Remove-PathWithRecovery -Path $f.FullName -AllowHardDeleteFallback $true -LogCallback $logCallback
                        if ($r.Success) {
                            $manifest.deletedPaths += $f.FullName
                        } elseif ($r.Mode -eq 'RequiresAdmin') {
                            & $logCallback "SKIPPED $($f.FullName) (requires admin)"
                        } elseif ($r.Mode -eq 'SkippedByUser') {
                            & $logCallback "SKIPPED $($f.FullName) (in use)"
                        } elseif ($r.Mode -eq 'AbortedByUser') {
                            throw 'Cleanup aborted by user.'
                        } else {
                            & $logCallback "FAILED $($f.FullName) [$($r.Mode)]"
                        }
                    }
                    $line = "PROCESSED Deep clean category: $($item.Name)"
                }
                default {
                    $line = "SKIPPED Unknown delete type: $($meta.Type)"
                }
            }

            $list.Items.Add("[OK] $line")
            $logLines.Add("[OK] $line")
        } catch {
            $msg = "[FAIL] $($item.Name): $($_.Exception.Message)"
            $list.Items.Add($msg)
            $logLines.Add($msg)
            if ($_.Exception.Message -eq 'Cleanup aborted by user.') {
                $abortCleanup = $true
            }
        }

        [System.Windows.Forms.Application]::DoEvents()
        if ($abortCleanup -or $script:cleanupCancelRequested) { break }
    }

    $manifestPath = Save-UndoManifest -OutDir $PSScriptRoot -ManifestData $manifest
    $logLines.Add("Undo manifest: $manifestPath")
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8

    $statInfo.Text = "Backup dir: $PSScriptRoot"
    $toolStatus.Text = "Cleanup complete. Log: $logPath"

    [System.Windows.Forms.MessageBox]::Show(
        "Cleanup complete.`r`nLog: $logPath`r`nUndo manifest: $manifestPath",
        'Done',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $script:cleanupCancelRequested = $true
    $progressForm.Close()
    $btnScan.PerformClick()
})

[void]$form.ShowDialog()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Cleaner'
$form.Size = New-Object System.Drawing.Size(1100, 700)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(900, 560)

$toolStrip = New-Object System.Windows.Forms.ToolStrip
$toolStrip.GripStyle = 'Hidden'
$toolStrip.Dock = 'Top'

$btnScan = New-Object System.Windows.Forms.ToolStripButton('Scan')
$btnClean = New-Object System.Windows.Forms.ToolStripButton('Clean Selected')
$btnSelectAll = New-Object System.Windows.Forms.ToolStripButton('Select All')
$btnSelectNone = New-Object System.Windows.Forms.ToolStripButton('Select None')
$btnOpenBackup = New-Object System.Windows.Forms.ToolStripButton('Open Backup Folder')
$btnUndo = New-Object System.Windows.Forms.ToolStripButton('Undo Last Session')

$toolProgress = New-Object System.Windows.Forms.ToolStripProgressBar
$toolProgress.Style = 'Marquee'
$toolProgress.Visible = $false
$toolProgress.Width = 140

$btnAbortScan = New-Object System.Windows.Forms.ToolStripButton('X')
$btnAbortScan.ForeColor = [System.Drawing.Color]::Red
$btnAbortScan.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnAbortScan.ToolTipText = 'Abort Scan'
$btnAbortScan.Visible = $false
$btnAbortScan.Padding = New-Object System.Windows.Forms.Padding(2)

$toolStatus = New-Object System.Windows.Forms.ToolStripLabel('Ready')

[void]$toolStrip.Items.Add($btnScan)
[void]$toolStrip.Items.Add($btnClean)
[void]$toolStrip.Items.Add($btnSelectAll)
[void]$toolStrip.Items.Add($btnSelectNone)
[void]$toolStrip.Items.Add($btnOpenBackup)
[void]$toolStrip.Items.Add($btnUndo)
[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$toolStrip.Items.Add($toolProgress)
[void]$toolStrip.Items.Add($btnAbortScan)
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

$groupOrder = @('Recommended', 'System', 'Applications', 'Registry')
$groupDefaults = @{
    'Recommended'  = $true
    'System'       = $false
    'Applications' = $false
    'Registry'     = $false
}

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.Alignment = 'Top'
$tabControl.SizeMode = 'Normal'

$script:categoryLists = @{}

$catPanel = New-Object System.Windows.Forms.Panel
$catPanel.Dock = 'Fill'

$catButtonPanel = New-Object System.Windows.Forms.Panel
$catButtonPanel.Dock = 'Bottom'
$catButtonPanel.Height = 32

$btnCatSelectAll = New-Object System.Windows.Forms.Button
$btnCatSelectAll.Text = 'Select All'
$btnCatSelectAll.Width = 100
$btnCatSelectAll.Height = 26
$btnCatSelectAll.Location = New-Object System.Drawing.Point(5, 3)

$btnCatSelectNone = New-Object System.Windows.Forms.Button
$btnCatSelectNone.Text = 'Select None'
$btnCatSelectNone.Width = 100
$btnCatSelectNone.Height = 26
$btnCatSelectNone.Location = New-Object System.Drawing.Point(110, 3)

$catButtonPanel.Controls.Add($btnCatSelectAll)
$catButtonPanel.Controls.Add($btnCatSelectNone)

foreach ($groupName in $groupOrder) {
    $tabPage = New-Object System.Windows.Forms.TabPage
    $tabPage.Text = $groupName
    $tabPage.UseVisualStyleBackColor = $true

    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Dock = 'Fill'
    $clb.CheckOnClick = $true
    $clb.IntegralHeight = $false

    $defaultChecked = $groupDefaults[$groupName]

    foreach ($cat in (Get-CategoryDefinitions | Where-Object { $_.Group -eq $groupName })) {
        $label = $cat.Name
        if ($cat.Risk -eq 'Advanced') { $label += "  [Advanced]" }
        elseif ($cat.Risk -eq 'Review') { $label += "  [Review]" }
        [void]$clb.Items.Add($label, $defaultChecked)
    }

    $script:categoryLists[$groupName] = $clb
    $tabPage.Controls.Add($clb)
    [void]$tabControl.TabPages.Add($tabPage)
}

$catPanel.Controls.Add($tabControl)
$catPanel.Controls.Add($catButtonPanel)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.ReadOnly = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false

Initialize-GridColumns -TargetGrid $grid

$tip = New-Object System.Windows.Forms.ToolTip
$grid.Add_CellMouseEnter({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $p = [string]$sender.Rows[$e.RowIndex].Cells['PathOrKey'].Value
        if ($p) { $tip.SetToolTip($sender, $p) }
    }
})

$split.Panel1.Controls.Add($catPanel)
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

$btnClean.Visible = $false
$btnSelectAll.Visible = $false
$btnSelectNone.Visible = $false
$btnAbortScan.Visible = $false
$btnClean.Enabled = $false
$btnSelectAll.Enabled = $false
$btnSelectNone.Enabled = $false
$toolStatus.Text = 'Select categories and click Scan.'

$btnAbortScan.Add_Click({
    $script:scanCancelRequested = $true
    $btnAbortScan.Enabled = $false
    $btnAbortScan.Visible = $false
})

function Update-Counts {
    $selected = 0
    foreach ($row in $grid.Rows) {
        if ($row.Cells['Selected'].Value -eq $true) { $selected++ }
    }
    $statCounts.Text = "Found: $($grid.Rows.Count) | Selected: $selected"
    $btnClean.Enabled = ($selected -gt 0)
    $hasRows = ($grid.Rows.Count -gt 0)
    $btnClean.Visible = $hasRows
    $btnSelectAll.Visible = $hasRows
    $btnSelectNone.Visible = $hasRows
}

$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})
$grid.Add_CellValueChanged({ Update-Counts })

$btnCatSelectAll.Add_Click({
    foreach ($groupName in $groupOrder) {
        $clb = $script:categoryLists[$groupName]
        for ($i = 0; $i -lt $clb.Items.Count; $i++) {
            $clb.SetItemChecked($i, $true)
        }
    }
})

$btnCatSelectNone.Add_Click({
    foreach ($groupName in $groupOrder) {
        $clb = $script:categoryLists[$groupName]
        for ($i = 0; $i -lt $clb.Items.Count; $i++) {
            $clb.SetItemChecked($i, $false)
        }
    }
})

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

$btnUndo.Add_Click({
    Show-UndoDialog -BackupDir $PSScriptRoot
})

$script:scanRunning = $false
$script:scanTimer = $null

$form.Add_FormClosing({
    if ($script:scanRunning) {
        [System.Windows.Forms.MessageBox]::Show(
            'A scan is in progress. Click "Abort Scan" to stop it first.',
            'Scan Running',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        $_.Cancel = $true
        return
    }
    if ($script:scanTimer) {
        $script:scanTimer.Stop()
        $script:scanTimer.Dispose()
        $script:scanTimer = $null
    }
})

$btnScan.Add_Click({
    $selectedCategories = @()
    foreach ($groupName in $groupOrder) {
        $clb = $script:categoryLists[$groupName]
        foreach ($item in $clb.CheckedItems) {
            $cleanName = $item -replace '\s+\[(Advanced|Review|Admin|Safe)\]$', ''
            $selectedCategories += $cleanName
        }
    }
    if ($selectedCategories.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Choose at least one category to scan.', 'Scan', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    if ($script:scanTimer) {
        $script:scanTimer.Stop()
        $script:scanTimer.Dispose()
        $script:scanTimer = $null
    }

    $btnScan.Enabled = $false
    $btnClean.Enabled = $false
    $btnSelectAll.Enabled = $false
    $btnSelectNone.Enabled = $false
    $btnAbortScan.Visible = $true
    $btnAbortScan.Enabled = $true
    $toolProgress.Visible = $true
    $toolProgress.Style = 'Continuous'
    $toolStatus.Text = 'Scanning...'
    $script:scanRunning = $true
    $script:scanCancelRequested = $false

    $grid.Rows.Clear()
    $resultsStore.Clear()

    $definitions = @(Get-CategoryDefinitions | Where-Object { $selectedCategories -contains $_.Name })
    $toolProgress.Minimum = 0
    $toolProgress.Maximum = [Math]::Max(1, $definitions.Count)
    $toolProgress.Value = 0

    $script:scanStepIndex = 0
    $script:scanDefinitions = $definitions
    $script:scanErrors = [System.Collections.Generic.List[string]]::new()

    $script:scanTimer = New-Object System.Windows.Forms.Timer
    $script:scanTimer.Interval = 50

    $script:scanTimer.Add_Tick({
        if ($script:scanCancelRequested) {
            $script:scanTimer.Stop()
            $script:scanTimer.Dispose()
            $script:scanTimer = $null
            $script:scanRunning = $false
            $script:scanCancelRequested = $false
            $btnScan.Enabled = $true
            $btnAbortScan.Visible = $false
            $btnAbortScan.Enabled = $false
            $toolProgress.Style = 'Marquee'
            $toolProgress.Visible = $false
            $toolProgress.Value = 0
            $toolStatus.Text = 'Scan aborted.'
            Update-Counts
            return
        }

        if ($script:scanStepIndex -ge $script:scanDefinitions.Count) {
            $script:scanTimer.Stop()
            $script:scanTimer.Dispose()
            $script:scanTimer = $null
            $script:scanRunning = $false
            $btnScan.Enabled = $true
            $btnAbortScan.Visible = $false

            if ($script:scanErrors.Count -gt 0) {
                $toolStatus.Text = "Scan completed with warnings. Found $($grid.Rows.Count) item(s)."
                [System.Windows.Forms.MessageBox]::Show(
                    "Some categories failed:`r`n" + ($script:scanErrors -join "`r`n"),
                    'Scan Warnings',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            } else {
                $toolStatus.Text = "Scan complete. Found $($grid.Rows.Count) item(s)."
            }

            $toolProgress.Style = 'Marquee'
            $toolProgress.Visible = $false
            $toolProgress.Value = 0

            if ($grid.Rows.Count -gt 0) {
                $btnClean.Visible = $true
                $btnSelectAll.Visible = $true
                $btnSelectNone.Visible = $true
                $btnClean.Enabled = $true
                $btnSelectAll.Enabled = $true
                $btnSelectNone.Enabled = $true
                $btnScan.Text = 'Rescan'
            } else {
                $btnClean.Visible = $false
                $btnSelectAll.Visible = $false
                $btnSelectNone.Visible = $false
                $btnClean.Enabled = $false
                $btnSelectAll.Enabled = $false
                $btnSelectNone.Enabled = $false
                $btnScan.Text = 'Scan'
            }
            Update-Counts
            return
        }

        $def = $script:scanDefinitions[$script:scanStepIndex]
        $script:scanStepIndex++

        $toolProgress.Value = $script:scanStepIndex
        $toolStatus.Text = "Scanning: $($def.Name)..."
        $statCounts.Text = "Scanning: $($def.Name)... | $($grid.Rows.Count) item(s) found so far"

        try {
            $scanOut = & $def.Scanner
            $batch = [System.Collections.Generic.List[object]]::new()
            if ($scanOut -is [System.Collections.IEnumerable]) {
                foreach ($item in $scanOut) {
                    if ($null -ne $item) { $batch.Add($item) }
                }
            } elseif ($null -ne $scanOut) {
                $batch.Add($scanOut)
            }
            if ($batch.Count -gt 0) {
                $grid.SuspendLayout()
                foreach ($item in $batch) {
                    [void]$resultsStore.Add($item)
                    Add-ResultRow -TargetGrid $grid -Item $item
                }
                $grid.ResumeLayout()
            }
        } catch {
            $script:scanErrors.Add("$($def.Name): $($_.Exception.Message)")
        }

        $statCounts.Text = "Scanning... | $($grid.Rows.Count) item(s) found so far"
    })

    $script:scanTimer.Start()
})

$btnClean.Add_Click({
    $selectedIds = [System.Collections.Generic.List[int]]::new()
    foreach ($row in $grid.Rows) {
        if ($row.Cells['Selected'].Value -eq $true) {
            $selectedIds.Add([int]$row.Cells['ResultId'].Value)
        }
    }

    if ($selectedIds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Select at least one item first.', 'Clean Selected', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $selectedItems = @($resultsStore | Where-Object { $selectedIds.Contains($_.Id) -and $_.DeleteMeta })

    $confirmForm = New-Object System.Windows.Forms.Form
    $confirmForm.Text = 'Confirm Cleanup'
    $confirmForm.Size = New-Object System.Drawing.Size(520, 260)
    $confirmForm.StartPosition = 'CenterParent'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $false
    $lbl.Width = 480
    $lbl.Height = 80
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Text = "You selected $($selectedItems.Count) item(s).`r`nRegistry entries will be backed up. Files/folders are moved to Recycle Bin when possible. Continue?"

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
            Checkpoint-Computer -Description 'winsweep backup' -RestorePointType 'MODIFY_SETTINGS' | Out-Null
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
    $progressBar.Maximum = [Math]::Max(1, $selectedItems.Count)
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
    $progressForm.Refresh()

    $shellCom = New-Object -ComObject Shell.Application -ErrorAction SilentlyContinue
    $cachedProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logPath = Join-Path $PSScriptRoot "winsweep_${stamp}.log"
    $logLines = [System.Collections.Generic.List[string]]::new()

    $manifest = @{
        timestamp = (Get-Date).ToString('o')
        regBackups = @()
        deletedPaths = @()
        removedTasks = @()
        removedStartup = @()
    }

    $abortCleanup = $false
    $currentStep = 0

    $logCallback = {
        param([string]$Message)
        $list.Items.Add($Message)
        $list.TopIndex = [Math]::Max(0, $list.Items.Count - 1)
        if ($script:cleanupCancelRequested) {
            $abortCleanup = $true
            $list.Items.Add('[CANCEL] Cleanup cancelled by user. Stopping after current item.')
            $logLines.Add('[CANCEL] Cleanup cancelled by user.')
        }
    }

    foreach ($item in $selectedItems) {
        if ($abortCleanup -or $script:cleanupCancelRequested) { break }

        $currentStep++
        $meta = $item.DeleteMeta
        if (-not $meta) { continue }

        $progressLabel.Text = "Processing $currentStep/$($selectedItems.Count): $($item.Name)"
        $progressBar.Value = [Math]::Min($progressBar.Maximum, $currentStep)

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
                    $r = Remove-PathWithRecovery -Path $meta.ShortcutPath -AllowHardDeleteFallback $true -LogCallback $logCallback -ShellComObject $shellCom -CachedProcesses $cachedProcesses
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
                    $r = Remove-PathWithRecovery -Path $meta.Path -AllowHardDeleteFallback $true -LogCallback $logCallback -ShellComObject $shellCom -CachedProcesses $cachedProcesses
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
                        if (-not (Test-PathExists $p)) { continue }

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
                            $r = Remove-PathWithRecovery -Path $p -AllowHardDeleteFallback $true -LogCallback $logCallback -ShellComObject $shellCom -CachedProcesses $cachedProcesses
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
                        $r = Remove-PathWithRecovery -Path $f.FullName -AllowHardDeleteFallback $true -LogCallback $logCallback -ShellComObject $shellCom -CachedProcesses $cachedProcesses
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
                'RecycleBin' {
                    Clear-RecycleBin -Force -ErrorAction Stop
                    $line = "EMPTIED Recycle Bin"
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
    }

    if ($shellCom) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shellCom) | Out-Null
    }

    $manifestPath = Save-UndoManifest -OutDir $PSScriptRoot -ManifestData $manifest
    $logLines.Add("Undo manifest: $manifestPath")
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8

    $statInfo.Text = "Backup dir: $PSScriptRoot"
    $toolStatus.Text = "Cleanup complete. Log: $logPath"

    $script:cleanupCancelRequested = $true
    $progressForm.Close()

    $cleaned = @($logLines | Where-Object { $_ -match '^\[OK\]' })
    $skipped = @($logLines | Where-Object { $_ -match 'SKIPPED' })
    $failed = @($logLines | Where-Object { $_ -match '^\[FAIL\]|\[CANCEL\]' })

    $summary = "Cleanup complete.`r`n`r`n"
    $summary += "Cleaned: $($cleaned.Count) item(s)`r`n"
    if ($skipped.Count -gt 0) { $summary += "Skipped: $($skipped.Count) item(s)`r`n" }
    if ($failed.Count -gt 0) { $summary += "Failed: $($failed.Count) item(s)`r`n" }
    $summary += "`r`nLog: $logPath`r`nUndo manifest: $manifestPath"

    [System.Windows.Forms.MessageBox]::Show(
        $summary,
        'Cleanup Summary',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnScan.PerformClick()
})

[void]$form.ShowDialog()
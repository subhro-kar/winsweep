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
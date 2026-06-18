function Initialize-GridColumns {
    param([System.Windows.Forms.DataGridView]$TargetGrid)

    $TargetGrid.Columns.Clear()

    $colId = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colId.Name = 'ResultId'
    $colId.HeaderText = 'ResultId'
    $colId.ReadOnly = $true
    $colId.Visible = $false

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

    [void]$TargetGrid.Columns.Add($colId)
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

    if ($TargetGrid.Columns.Count -lt 7) {
        Initialize-GridColumns -TargetGrid $TargetGrid
    }

    $idx = $TargetGrid.Rows.Add($Item.Id, $Item.Selected, $Item.Category, $Item.Name, $Item.PathOrKey, $Item.Reason, $Item.Size)
    if ($Item.Category -eq 'Registry') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 235)
    } elseif ($Item.Category -eq 'Application') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(236, 246, 255)
    } elseif ($Item.Category -eq 'Deep Clean') {
        $TargetGrid.Rows[$idx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(232, 245, 233)
    }
}
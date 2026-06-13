function New-ScanResult {
    param(
        [string]$Category,
        [string]$SubCategory,
        [string]$Name,
        [string]$PathOrKey,
        [string]$Reason,
        [string]$Size = '',
        [hashtable]$DeleteMeta
    )

    [PSCustomObject]@{
        Selected = $false
        Category = $Category
        SubCategory = $SubCategory
        Name = $Name
        PathOrKey = $PathOrKey
        Reason = $Reason
        Size = $Size
        DeleteMeta = $DeleteMeta
    }
}

function New-DeepCleanAggregateItem {
    param(
        [string]$Name,
        [string]$Reason,
        [string[]]$Paths,
        [string]$SubCategory
    )

    $sizeBytes = Get-FolderBytes -Paths $Paths
    if ($sizeBytes -le 0) { return $null }

    return (New-ScanResult -Category 'Deep Clean' -SubCategory $SubCategory -Name $Name -PathOrKey ($Paths -join '; ') `
        -Reason $Reason -Size (Format-Bytes -Bytes $sizeBytes) -DeleteMeta @{
            Type = 'DeepCleanPaths'
            Paths = $Paths
            SizeBytes = $sizeBytes
        })
}

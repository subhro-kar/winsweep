function Get-CategoryDefinitions {
    return @(
        [PSCustomObject]@{ Name = 'Temp Files'; Scanner = 'Get-TempFilesItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Thumbnail Cache'; Scanner = 'Get-ThumbnailCacheItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Browser Caches'; Scanner = 'Get-BrowserCacheItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Log Files'; Scanner = 'Get-LogFilesItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'WER/Crash Dumps'; Scanner = 'Get-WerItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Recycle Bin'; Scanner = 'Get-RecycleBinItem'; Group = 'Recommended'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Stale Downloads'; Scanner = 'Find-StaleDownloads'; Group = 'Recommended'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Windows Update Cache'; Scanner = 'Get-WindowsUpdateCacheItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Delivery Optimization'; Scanner = 'Get-DeliveryOptimizationItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'DirectX Shader Cache'; Scanner = 'Get-DirectXShaderCacheItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Microsoft Store Cache'; Scanner = 'Get-MicrosoftStoreCacheItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Defender History/Logs'; Scanner = 'Get-DefenderHistoryItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Old WU Backups'; Scanner = 'Get-OldWUBackupsItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Prefetch'; Scanner = 'Get-PrefetchItem'; Group = 'System'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Orphaned Folders'; Scanner = 'Find-OrphanFilesystemFolders'; Group = 'Applications'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Startup Entries'; Scanner = 'Find-OrphanStartupEntries'; Group = 'Applications'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Scheduled Tasks'; Scanner = 'Find-OrphanScheduledTasks'; Group = 'Applications'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'Broken Shortcuts'; Scanner = 'Find-BrokenShortcuts'; Group = 'Applications'; Risk = 'Review' },
        [PSCustomObject]@{ Name = 'VS Code Cache'; Scanner = 'Get-VSCodeCacheItem'; Group = 'Applications'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Discord Cache'; Scanner = 'Get-DiscordCacheItem'; Group = 'Applications'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'npm Cache'; Scanner = 'Get-NpmCacheItem'; Group = 'Applications'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'pip Cache'; Scanner = 'Get-PipCacheItem'; Group = 'Applications'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'NuGet Cache'; Scanner = 'Get-NuGetCacheItem'; Group = 'Applications'; Risk = 'Safe' },
        [PSCustomObject]@{ Name = 'Uninstall Keys'; Scanner = 'Find-OrphanUninstallKeys'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'COM/ActiveX'; Scanner = 'Find-BrokenComRegistrations'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'Services'; Scanner = 'Find-BrokenServiceEntries'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'File Associations'; Scanner = 'Find-BrokenFileAssociations'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'Shell Extensions'; Scanner = 'Find-BrokenShellExtensions'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'App Paths'; Scanner = 'Find-BrokenAppPaths'; Group = 'Registry'; Risk = 'Advanced' },
        [PSCustomObject]@{ Name = 'Fonts'; Scanner = 'Find-BrokenFontRegistrations'; Group = 'Registry'; Risk = 'Review' }
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
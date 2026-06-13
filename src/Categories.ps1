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

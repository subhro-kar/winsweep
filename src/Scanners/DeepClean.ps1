function Get-TempFilesItem {
    $paths = @($env:TEMP, $env:TMP, 'C:\Windows\Temp') | Select-Object -Unique
    return (New-DeepCleanAggregateItem -Name 'Temp Files' -Reason 'Temporary files and folders' -Paths $paths -SubCategory 'Temp Files')
}

function Get-WindowsUpdateCacheItem {
    $paths = @('C:\Windows\SoftwareDistribution\Download')
    return (New-DeepCleanAggregateItem -Name 'Windows Update Cache' -Reason 'Downloaded update packages cache' -Paths $paths -SubCategory 'Windows Update Cache')
}

function Get-RecycleBinItem {
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.NameSpace(0x0A)
    $count = $bin.Items().Count
    if ($count -le 0) { return $null }
    $sizeBytes = 0L
    foreach ($item in $bin.Items()) {
        try { $sizeBytes += [Int64]$item.Size } catch { }
    }
    $sizeStr = if ($sizeBytes -gt 0) { Format-Bytes -Bytes $sizeBytes } else { 'Unknown' }
    return (New-ScanResult -Category 'Deep Clean' -SubCategory 'Recycle Bin' -Name 'Recycle Bin' -PathOrKey 'shell:RecycleBinFolder' `
        -Reason "$count item(s) in Recycle Bin" -Size $sizeStr -DeleteMeta @{
            Type = 'RecycleBin'
            SizeBytes = $sizeBytes
        })
}

function Get-WerItem {
    $paths = @('C:\ProgramData\Microsoft\Windows\WER', "$env:LOCALAPPDATA\Microsoft\Windows\WER")
    return (New-DeepCleanAggregateItem -Name 'WER / Crash Dumps' -Reason 'Windows Error Reporting leftovers' -Paths $paths -SubCategory 'WER/Crash Dumps')
}

function Get-PrefetchItem {
    $paths = @('C:\Windows\Prefetch')
    return (New-DeepCleanAggregateItem -Name 'Prefetch' -Reason 'Prefetch cache files' -Paths $paths -SubCategory 'Prefetch')
}

function Get-DeliveryOptimizationItem {
    $paths = @('C:\Windows\SoftwareDistribution\DeliveryOptimization')
    return (New-DeepCleanAggregateItem -Name 'Delivery Optimization' -Reason 'Windows Delivery Optimization cache' -Paths $paths -SubCategory 'Delivery Optimization')
}

function Get-DirectXShaderCacheItem {
    $paths = @("$env:LOCALAPPDATA\D3DSCache", 'C:\Windows\System32\config\systemprofile\AppData\Local\D3DSCache')
    return (New-DeepCleanAggregateItem -Name 'DirectX Shader Cache' -Reason 'DirectX shader cache files' -Paths $paths -SubCategory 'DirectX Shader Cache')
}

function Get-MicrosoftStoreCacheItem {
    $paths = @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache", "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\Settings")
    return (New-DeepCleanAggregateItem -Name 'Microsoft Store Cache' -Reason 'Microsoft Store local cache and settings' -Paths $paths -SubCategory 'Microsoft Store Cache')
}

function Get-DefenderHistoryItem {
    $paths = @('C:\ProgramData\Microsoft\Windows Defender\Scans\History\Store', 'C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service')
    return (New-DeepCleanAggregateItem -Name 'Defender History/Logs' -Reason 'Windows Defender scan history and service logs' -Paths $paths -SubCategory 'Defender History/Logs')
}

function Get-OldWUBackupsItem {
    $paths = @('C:\Windows\SoftwareDistribution\DataStore')
    return (New-DeepCleanAggregateItem -Name 'Old WU Backups' -Reason 'Old Windows Update datastore and backup files' -Paths $paths -SubCategory 'Old WU Backups')
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

function Get-VSCodeCacheItem {
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\vscode-cpptools",
        "$env:LOCALAPPDATA\Microsoft\VS Code\Cache",
        "$env:LOCALAPPDATA\Microsoft\VS Code\CachedData",
        "$env:LOCALAPPDATA\Microsoft\VS Code\CachedExtensions",
        "$env:LOCALAPPDATA\Microsoft\VS Code\CachedExtensionVSIXs",
        "$env:LOCALAPPDATA\Microsoft\VS Code\logs"
    ) | Where-Object { Test-PathExists $_ }
    if ($paths.Count -eq 0) { return $null }
    return (New-DeepCleanAggregateItem -Name 'VS Code Cache' -Reason 'VS Code extension cache and logs' -Paths $paths -SubCategory 'VS Code Cache')
}

function Get-DiscordCacheItem {
    $discordPath = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Discord" -Filter 'app-*' -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $discordPath) { return $null }
    $paths = @(
        (Join-Path $discordPath.FullName 'Cache'),
        (Join-Path $discordPath.FullName 'Code Cache'),
        (Join-Path $discordPath.FullName 'GPUCache')
    ) | Where-Object { Test-PathExists $_ }
    if ($paths.Count -eq 0) { return $null }
    return (New-DeepCleanAggregateItem -Name 'Discord Cache' -Reason 'Discord cache and GPU cache' -Paths $paths -SubCategory 'Discord Cache')
}

function Get-NpmCacheItem {
    $npmCache = Join-Path $env:LOCALAPPDATA 'npm-cache'
    if (-not (Test-PathExists $npmCache)) { return $null }
    return (New-DeepCleanAggregateItem -Name 'npm Cache' -Reason 'npm package download cache' -Paths @($npmCache) -SubCategory 'npm Cache')
}

function Get-PipCacheItem {
    $pipCache = Join-Path $env:LOCALAPPDATA 'pip\cache'
    if (-not (Test-PathExists $pipCache)) { return $null }
    return (New-DeepCleanAggregateItem -Name 'pip Cache' -Reason 'pip package download cache' -Paths @($pipCache) -SubCategory 'pip Cache')
}

function Get-NuGetCacheItem {
    $paths = @(
        "$env:LOCALAPPDATA\NuGet\v3-cache",
        "$env:LOCALAPPDATA\NuGet\plugins-cache"
    ) | Where-Object { Test-PathExists $_ }
    if ($paths.Count -eq 0) { return $null }
    return (New-DeepCleanAggregateItem -Name 'NuGet Cache' -Reason 'NuGet package download cache' -Paths $paths -SubCategory 'NuGet Cache')
}

function Find-StaleDownloads {
    $results = [System.Collections.Generic.List[object]]::new()

    $downloadsPath = [System.Environment]::GetFolderPath('UserProfile')
    if (-not $downloadsPath) { return $results }
    $downloadsPath = Join-Path $downloadsPath 'Downloads'
    if (-not (Test-PathExists $downloadsPath)) { return $results }

    $staleExtensions = @('.exe', '.msi', '.msix', '.msu', '.7z', '.zip', '.rar')
    $cutoffDate = (Get-Date).AddDays(-30)

    foreach ($file in (Get-ChildItem -LiteralPath $downloadsPath -File -ErrorAction SilentlyContinue)) {
        if ($file.LastWriteTime -ge $cutoffDate) { continue }
        if ($staleExtensions -notcontains $file.Extension.ToLowerInvariant()) { continue }

        $sizeStr = if ($file.Length -gt 1MB) { Format-Bytes -Bytes $file.Length } else { '' }
        $results.Add((New-ScanResult -Category 'Recommended' -SubCategory 'Stale Downloads' -Name $file.Name `
            -PathOrKey $file.FullName -Reason "Downloaded installer older than 30 days ($($file.LastWriteTime.ToString('yyyy-MM-dd')))" -Size $sizeStr -DeleteMeta @{
                Type = 'FilesystemPath'
                Path = $file.FullName
            }))
    }

    return $results
}
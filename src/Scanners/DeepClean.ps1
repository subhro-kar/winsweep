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

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

    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in $startupFolders) {
        if (-not (Test-PathExists $folder)) { continue }
        $shortcuts = Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -ErrorAction SilentlyContinue
        foreach ($lnk in $shortcuts) {
            try {
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

    $nameParts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $installedNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        [void]$nameParts.Add([regex]::Escape($name))
    }
    $installedNamesRegex = if ($nameParts.Count -gt 0) {
        [regex]::New(($nameParts -join '|'), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    } else { $null }

    $cachedProcesses = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.MainModule.FileName.ToLowerInvariant() } catch { '' }
    } | Where-Object { $_ })

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

    $cutoffDate = (Get-Date).AddDays(-180)

    foreach ($root in $scanRoots) {
        foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if ($ignoredFolders -contains $dir.Name) { continue }
            if ($installedLocations.Contains($dir.FullName)) { continue }
            if ($installedLocations.Contains($dir.FullName.TrimEnd('\\'))) { continue }

            $dirNameNorm = $dir.Name.ToLowerInvariant()
            if ($installedNamesRegex -and $installedNamesRegex.IsMatch($dirNameNorm)) { continue }
            $folderNorm = $dir.FullName.ToLowerInvariant()
            $processInFolder = $false
            foreach ($procPath in $cachedProcesses) {
                if ($procPath.StartsWith($folderNorm) -or $folderNorm.StartsWith($procPath.TrimEnd('\\'))) {
                    $processInFolder = $true
                    break
                }
            }
            if ($processInFolder) { continue }

            $allFiles = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue)
            if ($allFiles.Count -eq 0) {
                $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Orphaned Folders' -Name $dir.Name `
                    -PathOrKey $dir.FullName -Reason 'Empty folder not claimed by installed application' -DeleteMeta @{
                        Type = 'FilesystemPath'
                        Path = $dir.FullName
                    }))
                continue
            }

            $newestFile = ($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($newestFile -and $newestFile.LastWriteTime -lt $cutoffDate) {
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

function Find-BrokenShortcuts {
    $results = [System.Collections.Generic.List[object]]::new()

    $scanRoots = @(
        [System.Environment]::GetFolderPath('Desktop'),
        [System.Environment]::GetFolderPath('DesktopDirectory'),
        [System.Environment]::GetFolderPath('CommonDesktopDirectory'),
        [System.Environment]::GetFolderPath('StartMenu'),
        [System.Environment]::GetFolderPath('CommonStartMenu'),
        [System.Environment]::GetFolderPath('Programs'),
        [System.Environment]::GetFolderPath('CommonPrograms'),
        [System.Environment]::GetFolderPath('Recent'),
        [System.Environment]::GetFolderPath('SendTo')
    ) | Where-Object { $_ -and (Test-PathExists $_) } | Select-Object -Unique

    $shell = New-Object -ComObject WScript.Shell

    foreach ($root in $scanRoots) {
        foreach ($lnk in (Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
            try {
                $shortcut = $shell.CreateShortcut($lnk.FullName)
                $target = $shortcut.TargetPath
            } catch {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            if ($target -match '^https?://') { continue }
            $expandedTarget = [System.Environment]::ExpandEnvironmentVariables($target)
            if (Test-PathExists $expandedTarget) { continue }

            $results.Add((New-ScanResult -Category 'Application' -SubCategory 'Broken Shortcuts' -Name $lnk.Name `
                -PathOrKey $lnk.FullName -Reason "Target not found: $target" -DeleteMeta @{
                    Type = 'FilesystemPath'
                    Path = $lnk.FullName
                }))
        }
    }

    return $results
}
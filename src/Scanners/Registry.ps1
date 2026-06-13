function Find-OrphanUninstallKeys {
    $results = [System.Collections.Generic.List[object]]::new()

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($basePath in $uninstallPaths) {
        if (-not (Test-Path $basePath)) { continue }

        foreach ($key in (Get-ChildItem -LiteralPath $basePath -ErrorAction SilentlyContinue)) {
            $displayName = Get-RegistryValue -Path $key.PSPath -Name 'DisplayName'
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

            $installLoc = Get-RegistryValue -Path $key.PSPath -Name 'InstallLocation'
            $uninstStr = Get-RegistryValue -Path $key.PSPath -Name 'UninstallString'
            $displayIcon = Get-RegistryValue -Path $key.PSPath -Name 'DisplayIcon'

            $orphaned = $false
            $missing = ''
            $reason = ''

            if (-not [string]::IsNullOrWhiteSpace($installLoc)) {
                $cleanLoc = $installLoc.Trim().Trim('"')
                if (-not (Test-PathExists $cleanLoc)) {
                    $orphaned = $true
                    $missing = $cleanLoc
                    $reason = 'InstallLocation does not exist'
                }
            }

            if (-not $orphaned -and -not [string]::IsNullOrWhiteSpace($uninstStr)) {
                $exe = Resolve-ExecutablePath -CommandString $uninstStr
                if ($exe -and -not (Test-PathExists $exe)) {
                    if ($exe -notmatch 'msiexec(\.exe)?$' -and $exe -notmatch '^{') {
                        $orphaned = $true
                        $missing = $exe
                        $reason = 'Uninstall executable not found'
                    }
                }
            }

            if (-not $orphaned -and -not [string]::IsNullOrWhiteSpace($displayIcon)) {
                $iconPath = [Environment]::ExpandEnvironmentVariables(($displayIcon -split ',')[0].Trim().Trim('"'))
                if ($iconPath -match '\.(exe|dll)$' -and -not (Test-PathExists $iconPath)) {
                    if ($iconPath -notmatch '^%SystemRoot%' -and
                        $iconPath -notmatch '^C:\\Windows' -and
                        $iconPath -notmatch 'msiexec') {
                        $orphaned = $true
                        $missing = $iconPath
                        $reason = 'DisplayIcon executable not found'
                    }
                }
            }

            if ($orphaned) {
                $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'Uninstall Keys' -Name $displayName `
                    -PathOrKey $key.PSPath -Reason $reason -DeleteMeta @{
                        Type = 'RegistryKey'
                        KeyPath = $key.PSPath
                    }))
            }
        }
    }

    return $results
}

function Find-BrokenComRegistrations {
    $results = [System.Collections.Generic.List[object]]::new()
    $clsidRoot = 'HKCR:\CLSID'
    if (-not (Test-Path $clsidRoot)) { return $results }

    foreach ($clsid in (Get-ChildItem -LiteralPath $clsidRoot -ErrorAction SilentlyContinue)) {
        foreach ($sub in @('InprocServer32', 'LocalServer32')) {
            $path = Join-Path $clsid.PSPath $sub
            if (-not (Test-Path $path)) { continue }
            $value = Get-PropertyValue -Object (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue) -Name '(default)'
            if (-not $value) { continue }
            $exe = Resolve-ExecutablePath -CommandString ([Environment]::ExpandEnvironmentVariables($value))
            if (-not $exe) { continue }
            if ($exe -match '^C:\\Windows\\') { continue }
            if (-not (Test-PathExists $exe)) {
                $name = "COM $($clsid.PSChildName)"
                $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'COM/ActiveX' -Name $name `
                    -PathOrKey $path -Reason "Missing server: $exe" -DeleteMeta @{
                        Type = 'RegistryKey'
                        KeyPath = $clsid.PSPath
                    }))
            }
        }
    }

    return $results
}

function Find-BrokenServiceEntries {
    $results = [System.Collections.Generic.List[object]]::new()
    $svcRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    if (-not (Test-Path $svcRoot)) { return $results }

    foreach ($svc in (Get-ChildItem -LiteralPath $svcRoot -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $svc.PSPath -ErrorAction SilentlyContinue
        $imagePath = Get-PropertyValue -Object $props -Name 'ImagePath'
        $svcType = [int](Get-PropertyValue -Object $props -Name 'Type' -Default 0)
        if ($svcType -lt 16) { continue }
        if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }

        $exe = Resolve-ExecutablePath -CommandString ([Environment]::ExpandEnvironmentVariables($imagePath))
        if (-not $exe) { continue }
        if ($exe -match '^C:\\Windows\\') { continue }
        if (-not (Test-PathExists $exe)) {
            $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'Services' -Name $svc.PSChildName `
                -PathOrKey $svc.PSPath -Reason "Missing ImagePath executable: $exe" -DeleteMeta @{
                    Type = 'RegistryKey'
                    KeyPath = $svc.PSPath
                }))
        }
    }

    return $results
}

function Find-BrokenFileAssociations {
    $results = [System.Collections.Generic.List[object]]::new()
    $hkcr = 'HKCR:\'
    if (-not (Test-Path $hkcr)) { return $results }

    foreach ($root in (Get-ChildItem -LiteralPath $hkcr -ErrorAction SilentlyContinue)) {
        $cmdPath = Join-Path $root.PSPath 'shell\open\command'
        if (-not (Test-Path $cmdPath)) { continue }

        $command = Get-PropertyValue -Object (Get-ItemProperty -LiteralPath $cmdPath -ErrorAction SilentlyContinue) -Name '(default)'
        if ([string]::IsNullOrWhiteSpace($command)) { continue }

        $exe = Resolve-ExecutablePath -CommandString ([Environment]::ExpandEnvironmentVariables($command))
        if (-not $exe) { continue }

        if ($exe -match '%SystemRoot%' -or
            $exe -match '^C:\\Windows\\' -or
            $exe -match '(explorer|rundll32|msiexec)(\.exe)?$') {
            continue
        }

        if (-not (Test-PathExists $exe)) {
            $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'File Associations' -Name $root.PSChildName `
                -PathOrKey $cmdPath -Reason "Missing open command executable: $exe" -DeleteMeta @{
                    Type = 'RegistryKey'
                    KeyPath = $cmdPath
                }))
        }
    }

    return $results
}

function Find-BrokenShellExtensions {
    $results = [System.Collections.Generic.List[object]]::new()

    $handlerRoots = @(
        'HKCR:\*\shellex\ContextMenuHandlers',
        'HKCR:\Directory\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
    )

    $clsids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($root in $handlerRoots) {
        if (-not (Test-Path $root)) { continue }

        if ($root -like '*Approved') {
            $props = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
            foreach ($name in $props.PSObject.Properties.Name) {
                if ($name -match '^\{[0-9A-Fa-f\-]+\}$') { [void]$clsids.Add($name) }
            }
            continue
        }

        foreach ($entry in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $val = Get-PropertyValue -Object (Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue) -Name '(default)'
            if ($val -match '^\{[0-9A-Fa-f\-]+\}$') { [void]$clsids.Add($val) }
            if ($entry.PSChildName -match '^\{[0-9A-Fa-f\-]+\}$') { [void]$clsids.Add($entry.PSChildName) }
        }
    }

    foreach ($clsid in $clsids) {
        $dllKey = "HKCR:\CLSID\$clsid\InprocServer32"
        if (-not (Test-Path $dllKey)) { continue }
        $dll = Get-PropertyValue -Object (Get-ItemProperty -LiteralPath $dllKey -ErrorAction SilentlyContinue) -Name '(default)'
        if ([string]::IsNullOrWhiteSpace($dll)) { continue }
        $dll = [Environment]::ExpandEnvironmentVariables($dll.Trim('"'))
        if ($dll -match '^C:\\Windows\\') { continue }
        if (-not (Test-PathExists $dll)) {
            $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'Shell Extensions' -Name $clsid `
                -PathOrKey $dllKey -Reason "Missing shell extension DLL: $dll" -DeleteMeta @{
                    Type = 'RegistryKey'
                    KeyPath = "HKCR:\CLSID\$clsid"
                }))
        }
    }

    return $results
}

function Find-BrokenAppPaths {
    $results = [System.Collections.Generic.List[object]]::new()
    $appPaths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    if (-not (Test-Path $appPaths)) { return $results }

    foreach ($key in (Get-ChildItem -LiteralPath $appPaths -ErrorAction SilentlyContinue)) {
        $default = Get-PropertyValue -Object (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue) -Name '(default)'
        if ([string]::IsNullOrWhiteSpace($default)) { continue }
        $exe = [Environment]::ExpandEnvironmentVariables($default.Trim('"'))
        if (-not (Test-PathExists $exe)) {
            $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'App Paths' -Name $key.PSChildName `
                -PathOrKey $key.PSPath -Reason "Missing executable: $exe" -DeleteMeta @{
                    Type = 'RegistryKey'
                    KeyPath = $key.PSPath
                }))
        }
    }

    return $results
}

function Find-BrokenFontRegistrations {
    $results = [System.Collections.Generic.List[object]]::new()
    $fontsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $fontsKey)) { return $results }

    $fontProps = Get-ItemProperty -LiteralPath $fontsKey -ErrorAction SilentlyContinue
    foreach ($prop in $fontProps.PSObject.Properties) {
        if ($prop.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
        $fontPath = [string]$prop.Value
        if ([string]::IsNullOrWhiteSpace($fontPath)) { continue }

        if ($fontPath -notmatch '^[A-Za-z]:\\') {
            $fontPath = Join-Path $env:WINDIR "Fonts\$fontPath"
        }
        $fontPath = [Environment]::ExpandEnvironmentVariables($fontPath)

        if (-not (Test-PathExists $fontPath)) {
            $results.Add((New-ScanResult -Category 'Registry' -SubCategory 'Fonts' -Name $prop.Name `
                -PathOrKey $fontsKey -Reason "Missing font file: $fontPath" -DeleteMeta @{
                    Type = 'FontValue'
                    KeyPath = $fontsKey
                    ValueName = $prop.Name
                }))
        }
    }

    return $results
}

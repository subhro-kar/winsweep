if (-not ([System.Management.Automation.PSTypeName]'WinClean.NativeWindow').Type) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

namespace WinClean {
    public static class NativeWindow {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);
    }
}
'@
}

function Enable-DragMove {
    param(
        [System.Windows.Forms.Control]$Control,
        [System.Windows.Forms.Form]$TargetForm
    )

    $Control.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        [WinClean.NativeWindow]::ReleaseCapture() | Out-Null
        [WinClean.NativeWindow]::SendMessage($TargetForm.Handle, 0xA1, 0x2, 0) | Out-Null
    })
}

function Test-PathExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath $Path)
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Default = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return $Default
    }

    try {
        return (Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop)
    } catch {
        return $Default
    }
}

function Resolve-ExecutablePath {
    param([string]$CommandString)
    if ([string]::IsNullOrWhiteSpace($CommandString)) { return $null }

    $cmd = $CommandString.Trim()
    if ($cmd -match '^"([^"]+)"') {
        return [Environment]::ExpandEnvironmentVariables($Matches[1])
    }

    $tokens = $cmd -split '\s+'
    $candidate = ''
    foreach ($tok in $tokens) {
        $candidate = if ($candidate) { "$candidate $tok" } else { $tok }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-Path -LiteralPath $expanded -PathType Leaf) {
            return $expanded
        }
    }

    if ($tokens.Count -gt 0) {
        return [Environment]::ExpandEnvironmentVariables($tokens[0])
    }
    return $null
}

function Backup-RegistryKey {
    param(
        [string]$KeyPath,
        [string]$OutDir
    )

    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $regPath = $KeyPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\\' `
                        -replace '^HKCU:\\', 'HKEY_CURRENT_USER\\' `
                        -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\\' `
                        -replace '^HKU:\\', 'HKEY_USERS\\'

    $safe = ($regPath -replace '[\\/:*?"<>|]', '_').Substring(0, [Math]::Min(80, $regPath.Length))
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile = Join-Path $OutDir "backup_${stamp}_${safe}.reg"

    & reg.exe export $regPath $outFile /y 2>$null | Out-Null
    return $outFile
}

function Format-Bytes {
    param([Int64]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Get-FolderBytes {
    param([string[]]$Paths)
    $total = 0L
    foreach ($path in ($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        try {
            $sum = Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum
            if ($sum -and $sum.Sum) {
                $total += [Int64]$sum.Sum
            }
        } catch {
        }
    }
    return $total
}

function Move-PathToRecycleBin {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $true }

    try {
        $shell = New-Object -ComObject Shell.Application -ErrorAction Stop
        $parent = Split-Path -Path $item.FullName -Parent
        $name = Split-Path -Path $item.FullName -Leaf
        $folder = $shell.NameSpace($parent)
        if (-not $folder) { return $false }

        $target = $folder.ParseName($name)
        if (-not $target) { return $false }

        $recycle = $shell.NameSpace(10)
        if (-not $recycle) { return $false }

        $recycle.MoveHere($target, 0x0454)
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
        return (-not (Test-Path -LiteralPath $item.FullName))
    } catch {
        return $false
    }
}

function Get-LockCandidateProcesses {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\\')
    $norm = $full.ToLowerInvariant()
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $exe = [string]$p.ExecutablePath
        $cmd = [string]$p.CommandLine

        $exeNorm = if ($exe) { $exe.ToLowerInvariant() } else { '' }
        $cmdNorm = if ($cmd) { $cmd.ToLowerInvariant() } else { '' }

        $match = $false
        if ($exeNorm -and ($exeNorm.StartsWith($norm) -or $norm.StartsWith($exeNorm))) { $match = $true }
        if (-not $match -and $cmdNorm -and $cmdNorm.Contains($norm)) { $match = $true }

        if ($match) {
            $candidates.Add([PSCustomObject]@{
                Name = [string]$p.Name
                Id = [int]$p.ProcessId
                ExecutablePath = $exe
            })
        }
    }

    return ($candidates | Sort-Object Id -Unique)
}

function Prompt-LockResolution {
    param(
        [string]$Path,
        [object[]]$Candidates
    )

    $lines = @()
    foreach ($p in ($Candidates | Select-Object -First 8)) {
        $lines += "$($p.Name) (PID $($p.Id))"
    }
    if ($Candidates.Count -gt 8) {
        $lines += "...and $($Candidates.Count - 8) more"
    }

    $msg = "Path is in use and could not be removed:`r`n$Path`r`n`r`nLikely processes:`r`n$($lines -join "`r`n")`r`n`r`nYes = Force close processes and retry`r`nNo = Skip this item`r`nCancel = Abort cleanup"
    $choice = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Path In Use',
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) { return 'ForceCloseRetry' }
    if ($choice -eq [System.Windows.Forms.DialogResult]::No) { return 'Skip' }
    return 'Abort'
}

function Stop-LockCandidateProcesses {
    param([object[]]$Candidates)

    foreach ($p in $Candidates) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
        } catch {
        }
    }
}

function Test-PathLikelyRequiresAdmin {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $full = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $protectedRoots = @(
        [Environment]::GetFolderPath('Windows'),
        [Environment]::GetFolderPath('ProgramFiles'),
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    ) | Where-Object { $_ } | ForEach-Object { ([System.IO.Path]::GetFullPath($_)).ToLowerInvariant().TrimEnd('\\') }

    foreach ($root in $protectedRoots) {
        if ($full.StartsWith($root + '\\') -or $full -eq $root) {
            return $true
        }
    }

    return $false
}

function Remove-PathWithRecovery {
    param(
        [string]$Path,
        [bool]$AllowHardDeleteFallback = $true,
        [int]$LockResolutionAttempts = 0,
        [scriptblock]$LogCallback = $null
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $true; Mode = 'MissingAlready' }
    }

    if (-not (Test-IsAdmin) -and (Test-PathLikelyRequiresAdmin -Path $Path)) {
        if ($LogCallback) { & $LogCallback "SKIPPED $Path (requires admin)" }
        return @{ Success = $false; Mode = 'RequiresAdmin'; Error = 'Path likely requires Administrator privileges.' }
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        return @{ Success = $false; Mode = 'AccessFailed' }
    }

    $sizeBytes = 0L
    if ($item.PSIsContainer) {
        $sizeBytes = Get-FolderBytes -Paths @($item.FullName)
    } else {
        $sizeBytes = [Int64]$item.Length
    }

    if ($sizeBytes -gt 2GB -and $AllowHardDeleteFallback) {
        $msg = "Item appears large ($((Format-Bytes -Bytes $sizeBytes))). Recycle Bin move may fail. Continue with permanent delete?`n`n$Path"
        $answer = [System.Windows.Forms.MessageBox]::Show($msg, 'Large Item', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
                return @{ Success = $true; Mode = 'HardDelete' }
            } catch {
                return @{ Success = $false; Mode = 'HardDeleteFailed'; Error = $_.Exception.Message }
            }
        }
    }

    $moved = Move-PathToRecycleBin -Path $Path
    if ($moved) {
        if ($LogCallback) { & $LogCallback "REMOVED $Path (recycle bin)" }
        return @{ Success = $true; Mode = 'RecycleBin' }
    }

    $fallbackError = $null
    if ($AllowHardDeleteFallback) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $Path)) {
                if ($LogCallback) { & $LogCallback "REMOVED $Path (hard delete)" }
                return @{ Success = $true; Mode = 'HardDeleteFallback' }
            }
        } catch {
            $fallbackError = $_.Exception.Message
        }
    }

    if ($LockResolutionAttempts -lt 1) {
        $candidates = Get-LockCandidateProcesses -Path $Path
        if ($candidates.Count -gt 0) {
            if ($LogCallback) { & $LogCallback "SKIPPED $Path (in use by $($candidates[0].Name))" }
            return @{ Success = $false; Mode = 'SkippedByUser'; LockCandidates = $candidates }
        }
    }

    if ($fallbackError) {
        if ($LogCallback) { & $LogCallback "FAILED $Path ($fallbackError)" }
        return @{ Success = $false; Mode = 'FallbackFailed'; Error = $fallbackError }
    }

    if ($LogCallback) { & $LogCallback "FAILED $Path (recycle and delete both failed)" }
    return @{ Success = $false; Mode = 'RecycleFailed' }
}

function Remove-DirectoryContentsWithRecovery {
    param(
        [string]$DirectoryPath,
        [bool]$AllowHardDeleteFallback = $true
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return @{ Success = $true; Removed = @(); Failed = @(); Mode = 'MissingAlready' }
    }

    $dir = Get-Item -LiteralPath $DirectoryPath -Force -ErrorAction SilentlyContinue
    if (-not $dir -or -not $dir.PSIsContainer) {
        return @{ Success = $false; Removed = @(); Failed = @(); Mode = 'NotDirectory' }
    }

    $children = Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction SilentlyContinue
    if (-not $children) {
        return @{ Success = $true; Removed = @(); Failed = @(); Mode = 'AlreadyEmpty' }
    }

    $removed = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()

    foreach ($child in $children) {
        $r = Remove-PathWithRecovery -Path $child.FullName -AllowHardDeleteFallback $AllowHardDeleteFallback
        if ($r.Success) {
            $removed.Add([PSCustomObject]@{ Path = $child.FullName; Mode = $r.Mode })
        } else {
            $failed.Add([PSCustomObject]@{ Path = $child.FullName; Mode = $r.Mode; Error = $r.Error })
        }
    }

    return @{
        Success = ($failed.Count -eq 0)
        Removed = $removed
        Failed = $failed
        Mode = 'ContentsOnly'
    }
}

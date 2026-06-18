function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
    $psHostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psHostPath)) {
        $psHostPath = 'powershell.exe'
    }

    if ([string]::IsNullOrWhiteSpace($script:WinCleanEntryScript)) {
        throw 'Cannot self-elevate because script path is unavailable.'
    }

    $argList = @(
        '-NoProfile',
        '-STA',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$script:WinCleanEntryScript`"",
        '-Elevated'
    )

    if ($RequireAdmin) { $argList += '-RequireAdmin' }
    if ($NoElevationPrompt) { $argList += '-NoElevationPrompt' }

    Start-Process -FilePath $psHostPath -Verb RunAs -WindowStyle Hidden -ArgumentList $argList | Out-Null
}

function Ensure-LaunchMode {
    if (Test-IsAdmin) { return $true }

    if ($NoElevationPrompt -and -not $RequireAdmin) {
        return $true
    }

    if ($RequireAdmin) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            'This run requires Administrator privileges. Relaunch as Administrator now?',
            'Administrator Required',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Start-ElevatedSelf
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not relaunch elevated: $($_.Exception.Message)",
                    'Elevation Failed',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        }

        return $false
    }

    if (-not $NoElevationPrompt) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "Run with Administrator privileges?`r`n`r`nYes: Relaunch elevated (full access) `r`nNo: Continue in limited mode`r`nCancel: Exit",
            'Choose Launch Mode',
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Start-ElevatedSelf
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not relaunch elevated: $($_.Exception.Message)",
                    'Elevation Failed',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            return $false
        }

        if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            return $false
        }
    }

    return $true
}
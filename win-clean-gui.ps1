#Requires -Version 5.1

param(
    [switch]$RequireAdmin,
    [switch]$NoElevationPrompt,
    [switch]$Elevated
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$script:WinCleanEntryScript = $PSCommandPath
$script:WinCleanRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot 'src\Core\Helpers.ps1')
. (Join-Path $PSScriptRoot 'src\Core\Admin.ps1')
. (Join-Path $PSScriptRoot 'src\Models\ScanResult.ps1')
. (Join-Path $PSScriptRoot 'src\Scanners\Registry.ps1')
. (Join-Path $PSScriptRoot 'src\Scanners\Applications.ps1')
. (Join-Path $PSScriptRoot 'src\Scanners\DeepClean.ps1')
. (Join-Path $PSScriptRoot 'src\Categories.ps1')
. (Join-Path $PSScriptRoot 'src\Cleanup\Recovery.ps1')
. (Join-Path $PSScriptRoot 'src\Ui\Grid.ps1')

if (-not (Ensure-LaunchMode)) {
    return
}

. (Join-Path $PSScriptRoot 'src\Ui\MainForm.ps1')

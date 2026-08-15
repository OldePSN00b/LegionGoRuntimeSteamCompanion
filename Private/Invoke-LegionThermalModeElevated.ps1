<#
.SYNOPSIS
    Applies a Legion thermal mode from an elevated Windows PowerShell 5.1 process.

.DESCRIPTION
    This private helper is launched with RunAs by the Legion Go Runtime Steam
    Companion module. It imports LegionGoRuntime and applies the requested mode.
    It should not be launched directly during normal use.

.PARAMETER Mode
    Thermal mode to apply. Supported values are Quiet, Balanced, and Performance.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Quiet', 'Balanced', 'Performance')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module LegionGoRuntime -ErrorAction Stop
    $result = Set-LegionThermalMode -ModeName $Mode
    if (-not $result.Success) {
        throw ("LegionGoRuntime reported that {0} mode was not applied. Actual mode: {1}." -f $Mode, $result.ActualName)
    }
    Write-Output ("Legion thermal mode set to {0}." -f $Mode)
}
catch {
    Write-Error ("Failed to set Legion thermal mode to {0}: {1}" -f $Mode, $_.Exception.Message)
    exit 1
}

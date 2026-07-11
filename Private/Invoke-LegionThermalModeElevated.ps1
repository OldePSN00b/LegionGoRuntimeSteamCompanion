<#
.SYNOPSIS
    Applies a Legion thermal mode from an elevated Windows PowerShell 5.1 process.

.DESCRIPTION
    This private helper is launched with RunAs by the Legion Go Runtime Steam Companion module. It
    intentionally relies on Set-LegionThermalMode being available from the current
    user's Windows PowerShell 5.1 profile. It should not be launched directly during
    normal use.

.PARAMETER Mode
    Thermal mode to apply. Supported values are Balanced and Performance.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Balanced', 'Performance')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

try {
    # The function belongs to the user's Windows PowerShell 5.1 profile. The helper
    # deliberately does not redefine it, keeping one authoritative implementation.
    if (-not (Get-Command -Name Set-LegionThermalMode -ErrorAction SilentlyContinue)) {
        throw 'Set-LegionThermalMode is not available in the elevated Windows PowerShell 5.1 session. Confirm it is defined by your Windows PowerShell profile.'
    }

    Set-LegionThermalMode $Mode
    Write-Output "Legion thermal mode set to $Mode."
}
catch {
    Write-Error ("Failed to set Legion thermal mode to {0}: {1}" -f $Mode, $_.Exception.Message)
    exit 1
}

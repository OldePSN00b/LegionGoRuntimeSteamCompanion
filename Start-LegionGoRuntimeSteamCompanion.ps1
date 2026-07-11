<#
.SYNOPSIS
    Starts the interactive Legion Go Runtime Steam Companion.

.DESCRIPTION
    Imports LegionGoRuntimeSteamCompanion.psd1 from the same directory as this script and opens
    the interactive game-selection menu. Run this script from a normal, unelevated
    Windows PowerShell 5.1 session. The module elevates only the Legion thermal-mode
    helper when required.

.EXAMPLE
    .\Start-LegionGoRuntimeSteamCompanion.ps1

.NOTES
    Lossless Scaling must be configured to launch as administrator in its own settings
    for reliable operation with this workflow.
#>
[CmdletBinding()]
param()

# Resolve the manifest relative to this script so the folder can be moved anywhere.
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LegionGoRuntimeSteamCompanion.psd1'

Import-Module -Name $modulePath -Force
Show-LegionGoRuntimeSteamCompanion

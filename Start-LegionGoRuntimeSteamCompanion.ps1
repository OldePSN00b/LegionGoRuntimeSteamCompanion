<#
.SYNOPSIS
    Starts the Legion Go Runtime Steam Companion interactively or launches one Steam game directly.

.DESCRIPTION
    With no game selection parameters, opens the interactive Steam companion menu.
    With -AppId or -Name, launches the selected Steam game through the normal Steam
    session flow. -ThermalProfile can override the resolved thermal profile for that
    session only; otherwise saved per-game and global settings are used.

    Steam remains responsible for the game's launch behavior and arguments.

.PARAMETER AppId
    Steam App ID to launch directly.

.PARAMETER Name
    Installed Steam game name to resolve for direct launch. Wildcards are supported;
    the selection must resolve to exactly one installed title.

.PARAMETER ThermalProfile
    Optional one-session thermal override: Quiet, Balanced, or Performance.

.EXAMPLE
    .\Start-LegionGoRuntimeSteamCompanion.ps1

.EXAMPLE
    .\Start-LegionGoRuntimeSteamCompanion.ps1 -AppId 2191500

.EXAMPLE
    .\Start-LegionGoRuntimeSteamCompanion.ps1 -Name 'Vampire Survivors' -ThermalProfile Performance
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
    [string]$AppId,

    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [string]$Name,

    [Parameter(ParameterSetName = 'ByAppId')]
    [Parameter(ParameterSetName = 'ByName')]
    [Alias('TDProfile')]
    [ValidateSet('Quiet', 'Balanced', 'Performance')]
    [string]$ThermalProfile
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LegionGoRuntimeSteamCompanion.psd1'
Import-Module -Name $modulePath -Force

if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    Show-LegionGoRuntimeSteamCompanion
    return
}

$sessionParameters = @{}
if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
    $sessionParameters.ThermalProfile = $ThermalProfile
}

if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
    Start-SteamGameSession -AppId $AppId @sessionParameters
    return
}

[object[]]$games = @(Get-SteamInstalledGame -Name $Name)
if (@($games).Count -eq 0) {
    throw "No installed Steam game matched '$Name'."
}
if (@($games).Count -gt 1) {
    $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
    throw "The Steam game name '$Name' matched more than one installed title: $matchedNames. Use -AppId or a more specific -Name."
}

Start-SteamGameSession -Game $games[0] @sessionParameters

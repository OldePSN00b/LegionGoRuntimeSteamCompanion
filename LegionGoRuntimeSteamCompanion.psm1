# Legion Go Runtime Steam Companion module for Windows PowerShell 5.1.
#
# Public commands are exported at the bottom of this file. Helper functions remain
# private to the module. StrictMode is intentionally enabled so programming errors
# fail early instead of producing unpredictable launcher behavior.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Module-scoped paths used by settings, the elevation helper, and Windows PowerShell.
$script:SettingsDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'LegionGoRuntimeSteamCompanion'
$script:SettingsPath = Join-Path -Path $script:SettingsDirectory -ChildPath 'Settings.json'
$script:LegacySettingsPaths = @(
    (Join-Path -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SteamGameLauncher') -ChildPath 'Settings.json'),
    (Join-Path -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'UniversalGameLauncher') -ChildPath 'Settings.json')
)
$script:ThermalHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private\Invoke-LegionThermalModeElevated.ps1'
$script:WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-DefaultGameLauncherSetting {
    <#
    .SYNOPSIS
        Creates the default Legion Go Runtime Steam Companion settings object.

    .DESCRIPTION
        Returns the baseline settings used when no Settings.json file exists or when
        a newer module version introduces a setting that is missing from an older file.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        DefaultThermalProfile        = 'Balanced'
        UseLosslessScaling            = $true
        CloseLosslessScalingAfterGame = $true
        LosslessScalingPathOverride   = ''
        GameStartTimeoutSeconds       = 300
        PollIntervalSeconds           = 2
        GameOverrides                 = [pscustomobject]@{}
    }
}

function Write-GameLauncherSetting {
    <#
    .SYNOPSIS
        Writes launcher settings to the current user's profile.

    .DESCRIPTION
        Serializes the supplied settings object to JSON beneath
        %LOCALAPPDATA%\LegionGoRuntimeSteamCompanion. This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Setting
    )

    if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
        New-Item -Path $script:SettingsDirectory -ItemType Directory -Force | Out-Null
    }

    $temporaryPath = Join-Path -Path $script:SettingsDirectory -ChildPath ("Settings.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    try {
        $Setting | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        if (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $script:SettingsPath, $null)
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $script:SettingsPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-NormalizedGameLauncherSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    $validThermalProfiles = @('Quiet', 'Balanced', 'Performance')
    if ([string]$Setting.DefaultThermalProfile -notin $validThermalProfiles) {
        throw "DefaultThermalProfile must be Quiet, Balanced, or Performance."
    }

    foreach ($booleanName in @('UseLosslessScaling', 'CloseLosslessScalingAfterGame')) {
        $value = $Setting.$booleanName
        if ($value -is [bool]) { continue }
        $parsedBoolean = $false
        if ($value -is [string] -and [bool]::TryParse($value, [ref]$parsedBoolean)) {
            $Setting.$booleanName = $parsedBoolean
            continue
        }
        throw "$booleanName must be true or false."
    }

    foreach ($range in @(
        @{ Name = 'GameStartTimeoutSeconds'; Minimum = 30; Maximum = 3600 },
        @{ Name = 'PollIntervalSeconds'; Minimum = 1; Maximum = 30 }
    )) {
        $parsedInteger = 0
        if (-not [int]::TryParse([string]$Setting.($range.Name), [ref]$parsedInteger) -or
            $parsedInteger -lt $range.Minimum -or $parsedInteger -gt $range.Maximum) {
            throw ("{0} must be an integer from {1} through {2}." -f $range.Name, $range.Minimum, $range.Maximum)
        }
        $Setting.($range.Name) = $parsedInteger
    }

    $Setting.LosslessScalingPathOverride = [string]$Setting.LosslessScalingPathOverride
    if ($null -eq $Setting.GameOverrides) {
        $Setting.GameOverrides = [pscustomobject]@{}
    }
    elseif ($Setting.GameOverrides -is [string] -or $Setting.GameOverrides -is [System.Array] -or
        $Setting.GameOverrides.GetType().IsValueType) {
        throw 'GameOverrides must be a JSON object.'
    }

    foreach ($property in @($Setting.GameOverrides.PSObject.Properties)) {
        $override = $property.Value
        if ($null -eq $override -or $override -is [string] -or $override -is [System.Array] -or $override.GetType().IsValueType) {
            throw "GameOverrides.$($property.Name) must be a JSON object."
        }
        if ($override.PSObject.Properties['ThermalProfile'] -and
            [string]$override.ThermalProfile -notin $validThermalProfiles) {
            throw "GameOverrides.$($property.Name).ThermalProfile must be Quiet, Balanced, or Performance."
        }
        if ($override.PSObject.Properties['UseLosslessScaling']) {
            $overrideBoolean = $override.UseLosslessScaling
            if ($overrideBoolean -isnot [bool]) {
                $parsedOverrideBoolean = $false
                if ($overrideBoolean -is [string] -and [bool]::TryParse($overrideBoolean, [ref]$parsedOverrideBoolean)) {
                    $override.UseLosslessScaling = $parsedOverrideBoolean
                }
                else {
                    throw "GameOverrides.$($property.Name).UseLosslessScaling must be true or false."
                }
            }
        }
        if ($override.PSObject.Properties['ProcessName']) {
            $override.ProcessName = [string[]]@($override.ProcessName | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    return $Setting
}

function Get-GameLauncherSetting {
    <#
    .SYNOPSIS
        Gets the current Legion Go Runtime Steam Companion settings.

    .DESCRIPTION
        Reads Settings.json from %LOCALAPPDATA%\LegionGoRuntimeSteamCompanion. If no settings
        file exists, defaults are created. Settings from the former SteamGameLauncher
        or UniversalGameLauncher locations are migrated automatically. Missing properties
        are added in memory from the current defaults.

    .OUTPUTS
        PSCustomObject containing the current launcher settings.

    .EXAMPLE
        Get-GameLauncherSetting
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) {
        $legacySettingsPath = $script:LegacySettingsPaths |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1

        if ($legacySettingsPath) {
            if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
                New-Item -Path $script:SettingsDirectory -ItemType Directory -Force | Out-Null
            }
            Copy-Item -LiteralPath $legacySettingsPath -Destination $script:SettingsPath -Force
        }
        else {
            $setting = Get-DefaultGameLauncherSetting
            Write-GameLauncherSetting -Setting $setting
            return $setting
        }
    }

    try {
        $setting = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
        $default = Get-DefaultGameLauncherSetting

        foreach ($property in $default.PSObject.Properties) {
            if (-not $setting.PSObject.Properties[$property.Name]) {
                $setting | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
            }
        }

        return ConvertTo-NormalizedGameLauncherSetting -Setting $setting
    }
    catch {
        throw "Unable to read launcher settings at '$script:SettingsPath': $($_.Exception.Message)"
    }
}

function Set-GameLauncherSetting {
    <#
    .SYNOPSIS
        Changes one or more Legion Go Runtime Steam Companion settings.

    .DESCRIPTION
        Updates only the settings explicitly supplied, preserves all other values,
        saves the result to Settings.json, and returns the updated settings object.

    .PARAMETER DefaultThermalProfile
        Default thermal profile used when a game has no saved profile and no CLI override.

    .PARAMETER UseLosslessScaling
        Enables or disables Lossless Scaling by default.

    .PARAMETER CloseLosslessScalingAfterGame
        Controls whether a Lossless Scaling instance started by this module is closed
        after the game exits. A pre-existing instance is never closed by the module.

    .PARAMETER LosslessScalingPathOverride
        Optional full path to LosslessScaling.exe. Leave blank to use automatic Steam
        library discovery.

    .PARAMETER GameStartTimeoutSeconds
        Maximum time to wait for the selected game's process to appear.

    .PARAMETER PollIntervalSeconds
        Number of seconds between process detection checks.

    .EXAMPLE
        Set-GameLauncherSetting -UseLosslessScaling $false

    .EXAMPLE
        Set-GameLauncherSetting -GameStartTimeoutSeconds 600 -PollIntervalSeconds 3
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$DefaultThermalProfile,
        [bool]$UseLosslessScaling,
        [bool]$CloseLosslessScalingAfterGame,
        [string]$LosslessScalingPathOverride,
        [ValidateRange(30, 3600)]
        [int]$GameStartTimeoutSeconds,
        [ValidateRange(1, 30)]
        [int]$PollIntervalSeconds
    )

    $setting = Get-GameLauncherSetting

    foreach ($name in @(
        'DefaultThermalProfile',
        'UseLosslessScaling',
        'CloseLosslessScalingAfterGame',
        'LosslessScalingPathOverride',
        'GameStartTimeoutSeconds',
        'PollIntervalSeconds'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $setting.$name = $PSBoundParameters[$name]
        }
    }

    Write-GameLauncherSetting -Setting $setting
    return $setting
}

function Get-SteamLibraryPath {
    <#
    .SYNOPSIS
        Discovers Steam installation and library folders.

    .DESCRIPTION
        Checks the common Steam registry locations, default installation paths, and
        libraryfolders.vdf. Duplicate paths are removed before output. This function
        is private to the module.
    #>
    [CmdletBinding()]
    param()

    $steamRoots = New-Object System.Collections.Generic.List[string]
    $registryPaths = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\Software\WOW6432Node\Valve\Steam',
        'HKLM:\Software\Valve\Steam'
    )

    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $properties) { continue }

        foreach ($propertyName in @('SteamPath', 'InstallPath')) {
            $property = $properties.PSObject.Properties[$propertyName]
            if (-not $property) { continue }

            $value = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($value) -and
                (Test-Path -LiteralPath $value -PathType Container)) {
                $steamRoots.Add($value)
            }
        }
    }

    foreach ($defaultRoot in @(
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Steam'),
        (Join-Path -Path $env:ProgramFiles -ChildPath 'Steam')
    )) {
        if (Test-Path -LiteralPath $defaultRoot -PathType Container) {
            $steamRoots.Add($defaultRoot)
        }
    }

    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in ($steamRoots | Select-Object -Unique)) {
        $libraries.Add($steamRoot)
        $libraryFile = Join-Path -Path $steamRoot -ChildPath 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }

        foreach ($line in (Get-Content -LiteralPath $libraryFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*"path"\s+"(?<Path>.+)"\s*$') {
                $path = $Matches.Path -replace '\\\\', '\'
                if (Test-Path -LiteralPath $path -PathType Container) {
                    $libraries.Add($path)
                }
            }
        }
    }

    $libraries | Select-Object -Unique
}

function Get-SteamInstalledGame {
    <#
    .SYNOPSIS
        Gets games currently installed in registered Steam libraries.

    .DESCRIPTION
        Parses Steam appmanifest_*.acf files and returns each installed game's name,
        App ID, installation path, library path, and manifest path. Duplicate entries
        are collapsed by Steam App ID.

    .PARAMETER Name
        Filters results using a case-insensitive wildcard match against the game name.

    .PARAMETER AppId
        Filters results to one Steam App ID.

    .OUTPUTS
        PSCustomObject for each installed Steam game.

    .EXAMPLE
        Get-SteamInstalledGame

    .EXAMPLE
        Get-SteamInstalledGame -Name 'Vampire'

    .EXAMPLE
        Get-SteamInstalledGame -AppId 2191500
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$AppId
    )

    # Parse each appmanifest file rather than querying Steam's online catalog, so the
    # result reflects games that are installed locally right now.
    $games = foreach ($library in (Get-SteamLibraryPath)) {
        $steamAppsPath = Join-Path -Path $library -ChildPath 'steamapps'
        if (-not (Test-Path -LiteralPath $steamAppsPath -PathType Container)) { continue }

        foreach ($manifest in (Get-ChildItem -LiteralPath $steamAppsPath -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            $content = Get-Content -LiteralPath $manifest.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            $manifestAppId = if ($content -match '"appid"\s+"(?<Value>\d+)"') { $Matches.Value } else { $null }
            $gameName = if ($content -match '"name"\s+"(?<Value>.*?)"') { $Matches.Value } else { $null }
            $installDir = if ($content -match '"installdir"\s+"(?<Value>.*?)"') { $Matches.Value } else { $null }
            if (-not $manifestAppId -or -not $gameName -or -not $installDir) { continue }

            # Steamworks Common Redistributables is a shared Steam component rather
            # than a user-launchable game. Exclude it at discovery time so it does
            # not appear in game searches, the picker, or profile-management menus.
            if ($manifestAppId -eq '228980' -or $gameName -eq 'Steamworks Common Redistributables') {
                continue
            }

            [pscustomobject]@{
                Name        = $gameName
                AppId       = $manifestAppId
                InstallPath = Join-Path -Path $steamAppsPath -ChildPath "common\$installDir"
                LibraryPath = $library
                Manifest    = $manifest.FullName
            }
        }
    }

    # The same Steam library can be discovered through more than one registry or
    # libraryfolders.vdf path. Collapse duplicate manifests by Steam App ID before
    # applying filters or building the interactive menu.
    $games = @(
        $games |
            Sort-Object AppId, Manifest |
            Group-Object AppId |
            ForEach-Object {
                $_.Group |
                    Sort-Object @{ Expression = { if (Test-Path -LiteralPath $_.InstallPath -PathType Container) { 0 } else { 1 } } }, Manifest |
                    Select-Object -First 1
            }
    )

    if ($AppId) { $games = $games | Where-Object AppId -EQ $AppId }
    if ($Name) { $games = $games | Where-Object Name -Like "*$Name*" }
    $games | Sort-Object Name, AppId
}

function Get-LosslessScalingPath {
    <#
    .SYNOPSIS
        Locates the Lossless Scaling executable.

    .DESCRIPTION
        Uses the configured override first, then the Steam uninstall registry entry,
        and finally all discovered Steam libraries. This function is private to the
        module.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if ($Setting.LosslessScalingPathOverride) {
        if (Test-Path -LiteralPath $Setting.LosslessScalingPathOverride -PathType Leaf) {
            return $Setting.LosslessScalingPathOverride
        }
        throw "The Lossless Scaling override does not exist: $($Setting.LosslessScalingPathOverride)"
    }

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090'
    )

    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($properties.DisplayIcon) {
            $path = ($properties.DisplayIcon -replace ',\d+$', '').Trim('"')
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }

    foreach ($library in (Get-SteamLibraryPath)) {
        foreach ($fileName in @('LosslessScaling.exe', 'Lossless Scaling.exe')) {
            $candidate = Join-Path -Path $library -ChildPath "steamapps\common\Lossless Scaling\$fileName"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }

    return $null
}

function Set-ElevatedLegionThermalMode {
    <#
    .SYNOPSIS
        Runs the Legion thermal-mode helper with elevation.

    .DESCRIPTION
        Starts Windows PowerShell 5.1 with RunAs so only the thermal-mode change is
        elevated. The Steam game continues to launch from the original user context.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$Mode
    )

    if (-not (Test-Path -LiteralPath $script:ThermalHelperPath -PathType Leaf)) {
        throw "Thermal helper was not found: $script:ThermalHelperPath"
    }

    Write-Host "Requesting $Mode thermal mode..."
    $process = Start-Process -FilePath $script:WindowsPowerShellPath -Verb RunAs -ArgumentList @(
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $script:ThermalHelperPath),
        '-Mode', $Mode
    ) -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "The elevated thermal helper failed to set $Mode mode. Exit code: $($process.ExitCode)"
    }
}

function Get-GameOverride {
    <#
    .SYNOPSIS
        Gets a per-game settings override by Steam App ID.

    .DESCRIPTION
        Returns the matching GameOverrides entry from Settings.json, when present.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Setting,
        [Parameter(Mandatory)][string]$AppId
    )

    if ($Setting.GameOverrides -and $Setting.GameOverrides.PSObject.Properties[$AppId]) {
        return $Setting.GameOverrides.$AppId
    }
    return $null
}

function Get-GameProcess {
    <#
    .SYNOPSIS
        Finds processes associated with a selected Steam game.

    .DESCRIPTION
        Uses explicit process names when supplied. Otherwise, it identifies processes
        whose executable path is beneath the selected game's Steam installation folder.
        Access-denied process path checks are ignored. This function is private to the
        module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Game,
        [string[]]$ProcessName
    )

    if ($ProcessName) {
        return Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    }

    $prefix = [System.IO.Path]::GetFullPath($Game.InstallPath).TrimEnd('\') + '\'
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -and $process.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $process
            }
        }
        catch { }
    }
}


function Get-ResolvedSteamGameProfile {
    <#
    .SYNOPSIS
        Resolves the effective profile for one installed Steam game.

    .DESCRIPTION
        Combines the saved per-game profile with the global defaults so the caller can
        see exactly which thermal profile and Lossless Scaling preference will be used.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Game,
        [Parameter(Mandatory)][psobject]$Setting
    )

    $override = Get-GameOverride -Setting $Setting -AppId $Game.AppId
    $hasSavedProfile = [bool]$override

    $thermalProfile = if ($override -and $override.PSObject.Properties['ThermalProfile'] -and $override.ThermalProfile) {
        [string]$override.ThermalProfile
    }
    else {
        [string]$Setting.DefaultThermalProfile
    }

    $useLosslessScaling = if ($override -and $override.PSObject.Properties['UseLosslessScaling']) {
        [bool]$override.UseLosslessScaling
    }
    else {
        [bool]$Setting.UseLosslessScaling
    }

    [pscustomobject]@{
        AppId                    = [string]$Game.AppId
        Name                     = [string]$Game.Name
        ThermalProfile           = $thermalProfile
        UseLosslessScaling       = $useLosslessScaling
        HasSavedProfile          = $hasSavedProfile
        ThermalProfileSource     = if ($override -and $override.PSObject.Properties['ThermalProfile']) { 'Game' } else { 'Global' }
        LosslessScalingSource    = if ($override -and $override.PSObject.Properties['UseLosslessScaling']) { 'Game' } else { 'Global' }
    }
}

function Get-SteamGameProfile {
    <#
    .SYNOPSIS
        Gets saved per-game profiles.

    .DESCRIPTION
        Returns saved thermal, Lossless Scaling, and process-name overrides from the
        GameOverrides section of Settings.json. Supply an App ID to return one profile.

    .PARAMETER AppId
        Optional Steam App ID to retrieve.

    .EXAMPLE
        Get-SteamGameProfile

    .EXAMPLE
        Get-SteamGameProfile -AppId 2191500
    #>
    [CmdletBinding()]
    param([string]$AppId)

    $setting = Get-GameLauncherSetting
    $profiles = @()
    if ($setting.GameOverrides) {
        foreach ($property in $setting.GameOverrides.PSObject.Properties) {
            $value = $property.Value
            $profileProcessNames = [string[]]@()
            if ($value.PSObject.Properties['ProcessName']) {
                $profileProcessNames = [string[]]@($value.ProcessName)
            }
            $profiles += [pscustomobject]@{
                AppId              = $property.Name
                ThermalProfile     = if ($value.PSObject.Properties['ThermalProfile']) { $value.ThermalProfile } else { $null }
                UseLosslessScaling = if ($value.PSObject.Properties['UseLosslessScaling']) { $value.UseLosslessScaling } else { $null }
                ProcessName        = $profileProcessNames
            }
        }
    }

    if ($AppId) { $profiles = @($profiles | Where-Object AppId -EQ $AppId) }
    $profiles | Sort-Object AppId
}

function Set-SteamGameProfile {
    <#
    .SYNOPSIS
        Creates or updates a saved profile for one Steam game.

    .DESCRIPTION
        Stores per-game thermal profile, Lossless Scaling preference, and optional
        process-name overrides. Only explicitly supplied properties are changed.

    .PARAMETER AppId
        Steam App ID to configure.

    .PARAMETER ThermalProfile
        Saved thermal profile: Quiet, Balanced, or Performance.

    .PARAMETER UseLosslessScaling
        Saved Lossless Scaling preference for this game.

    .PARAMETER ProcessName
        Optional process names without .exe for games requiring detection overrides.

    .EXAMPLE
        Set-SteamGameProfile -AppId 2191500 -ThermalProfile Performance -UseLosslessScaling $true

    .EXAMPLE
        Set-SteamGameProfile -AppId 413150 -ThermalProfile Balanced -UseLosslessScaling $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [ValidateSet('Quiet', 'Balanced', 'Performance')][string]$ThermalProfile,
        [Nullable[bool]]$UseLosslessScaling,
        [string[]]$ProcessName
    )

    if (-not ($PSBoundParameters.ContainsKey('ThermalProfile') -or
        $PSBoundParameters.ContainsKey('UseLosslessScaling') -or
        $PSBoundParameters.ContainsKey('ProcessName'))) {
        throw 'Specify at least one profile value: ThermalProfile, UseLosslessScaling, or ProcessName.'
    }

    $setting = Get-GameLauncherSetting
    if (-not $setting.GameOverrides) {
        $setting.GameOverrides = [pscustomobject]@{}
    }

    $existing = Get-GameOverride -Setting $setting -AppId $AppId
    if (-not $existing) { $existing = [pscustomobject]@{} }

    if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
        if ($existing.PSObject.Properties['ThermalProfile']) { $existing.ThermalProfile = $ThermalProfile }
        else { $existing | Add-Member -MemberType NoteProperty -Name ThermalProfile -Value $ThermalProfile }
    }
    if ($PSBoundParameters.ContainsKey('UseLosslessScaling')) {
        if ($existing.PSObject.Properties['UseLosslessScaling']) { $existing.UseLosslessScaling = [bool]$UseLosslessScaling }
        else { $existing | Add-Member -MemberType NoteProperty -Name UseLosslessScaling -Value ([bool]$UseLosslessScaling) }
    }
    if ($PSBoundParameters.ContainsKey('ProcessName')) {
        if ($existing.PSObject.Properties['ProcessName']) { $existing.ProcessName = [string[]]@($ProcessName) }
        else { $existing | Add-Member -MemberType NoteProperty -Name ProcessName -Value ([string[]]@($ProcessName)) }
    }

    if ($setting.GameOverrides.PSObject.Properties[$AppId]) {
        $setting.GameOverrides.$AppId = $existing
    }
    else {
        $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name $AppId -Value $existing
    }

    Write-GameLauncherSetting -Setting $setting
    Get-SteamGameProfile -AppId $AppId
}

function Remove-SteamGameProfile {
    <#
    .SYNOPSIS
        Removes a saved profile for one Steam game.

    .PARAMETER AppId
        Steam App ID whose saved profile should be removed.

    .EXAMPLE
        Remove-SteamGameProfile -AppId 2191500
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$AppId)

    $setting = Get-GameLauncherSetting
    if (-not $setting.GameOverrides -or -not $setting.GameOverrides.PSObject.Properties[$AppId]) {
        return
    }

    if ($PSCmdlet.ShouldProcess("Steam App ID $AppId", 'Remove saved game profile')) {
        $setting.GameOverrides.PSObject.Properties.Remove($AppId)
        Write-GameLauncherSetting -Setting $setting
    }
}

function Start-SteamGameSession {
    <#
    .SYNOPSIS
        Launches and monitors one installed Steam game.

    .DESCRIPTION
        Resolves a thermal profile and Lossless Scaling preference using this order:
        explicit CLI override, saved per-game profile, then global defaults. Balanced
        is the default baseline and does not require a thermal elevation call. Quiet
        and Performance are applied before launch and Balanced is restored afterward.

    .PARAMETER Game
        An installed-game object returned by Get-SteamInstalledGame.

    .PARAMETER AppId
        Steam App ID of an installed game.

    .PARAMETER ThermalProfile
        Thermal profile override for this launch: Quiet, Balanced, or Performance.
        TDProfile is provided as a shorter alias for scripts and shortcuts.

    .PARAMETER ProcessName
        Optional process names without .exe for game detection.

    .PARAMETER UseLosslessScaling
        Lossless Scaling override for this launch.

    .EXAMPLE
        Start-SteamGameSession -AppId 2191500 -ThermalProfile Performance

    .EXAMPLE
        Start-SteamGameSession -AppId 2191500 -TDProfile Quiet -UseLosslessScaling $false
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)][psobject]$Game,
        [Parameter(Mandatory, ParameterSetName = 'ById')][string]$AppId,
        [Alias('TDProfile')]
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$ThermalProfile,
        [string[]]$ProcessName,
        [Nullable[bool]]$UseLosslessScaling
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $Game = Get-SteamInstalledGame -AppId $AppId | Select-Object -First 1
            if (-not $Game) { throw "Steam App ID $AppId is not installed." }
        }

        $setting = Get-GameLauncherSetting
        $override = Get-GameOverride -Setting $setting -AppId $Game.AppId

        $resolvedProcessName = if ($PSBoundParameters.ContainsKey('ProcessName')) {
            @($ProcessName)
        }
        elseif ($override -and $override.PSObject.Properties['ProcessName'] -and $override.ProcessName) {
            @($override.ProcessName)
        }
        else {
            @()
        }

        if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
            $resolvedThermalProfile = $ThermalProfile
        }
        elseif ($override -and $override.PSObject.Properties['ThermalProfile'] -and $override.ThermalProfile) {
            $resolvedThermalProfile = [string]$override.ThermalProfile
        }
        else {
            $resolvedThermalProfile = [string]$setting.DefaultThermalProfile
        }

        if ($PSBoundParameters.ContainsKey('UseLosslessScaling')) {
            $useLs = [bool]$UseLosslessScaling
        }
        elseif ($override -and $override.PSObject.Properties['UseLosslessScaling']) {
            $useLs = [bool]$override.UseLosslessScaling
        }
        else {
            $useLs = [bool]$setting.UseLosslessScaling
        }

        $lsWasRunning = $false
        $lsStartedProcess = $null
        $thermalModeChanged = $false

        try {
            Write-Host "Thermal profile for this session: $resolvedThermalProfile"
            if ($resolvedThermalProfile -ne 'Balanced') {
                Set-ElevatedLegionThermalMode -Mode $resolvedThermalProfile
                $thermalModeChanged = $true
            }
            else {
                Write-Host 'Balanced is the baseline; no thermal mode change is required.'
            }

            if ($useLs) {
                $lsWasRunning = [bool](Get-Process -Name 'LosslessScaling' -ErrorAction SilentlyContinue)
                if (-not $lsWasRunning) {
                    $lsPath = Get-LosslessScalingPath -Setting $setting
                    if (-not $lsPath) { throw 'Lossless Scaling could not be located.' }
                    Write-Host "Starting Lossless Scaling: $lsPath"
                    $lsStartedProcess = Start-Process -FilePath $lsPath -ArgumentList '-StartMinimized' -PassThru
                }
                else { Write-Host 'Lossless Scaling is already running.' }
            }
            else { Write-Host 'Lossless Scaling is disabled for this launch.' }

            Write-Host "Launching $($Game.Name) through Steam..."
            $preExistingProcessIds = @(
                Get-GameProcess -Game $Game -ProcessName $resolvedProcessName |
                    ForEach-Object { $_.Id }
            )
            Start-Process -FilePath "steam://rungameid/$($Game.AppId)"

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $gameProcesses = @(
                    Get-GameProcess -Game $Game -ProcessName $resolvedProcessName |
                        Where-Object { $_.Id -notin $preExistingProcessIds }
                )
                if ($gameProcesses.Count -gt 0) { break }
                if ($stopwatch.Elapsed.TotalSeconds -ge [int]$setting.GameStartTimeoutSeconds) {
                    throw "No game process was detected for '$($Game.Name)' within $($setting.GameStartTimeoutSeconds) seconds. Add a ProcessName override for App ID $($Game.AppId)."
                }
                Start-Sleep -Seconds ([int]$setting.PollIntervalSeconds)
            } while ($true)

            Write-Host 'Game process detected. Waiting for the game to close...'
            do {
                Start-Sleep -Seconds ([int]$setting.PollIntervalSeconds)
                $gameProcesses = @(
                    Get-GameProcess -Game $Game -ProcessName $resolvedProcessName |
                        Where-Object { $_.Id -notin $preExistingProcessIds }
                )
            } while ($gameProcesses.Count -gt 0)

            Write-Host "$($Game.Name) has closed."
        }
        finally {
            if ($useLs -and $setting.CloseLosslessScalingAfterGame -and $lsStartedProcess -and -not $lsWasRunning) {
                Write-Host 'Closing Lossless Scaling...'
                Get-Process -Id $lsStartedProcess.Id -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
            }
            if ($thermalModeChanged) {
                try { Set-ElevatedLegionThermalMode -Mode Balanced }
                catch { Write-Warning ("Failed to restore Balanced mode: {0}" -f $_.Exception.Message) }
            }
        }
    }
}

function Show-LegionGoRuntimeSteamCompanion {
    <#
    .SYNOPSIS
        Opens the interactive Steam Companion menu.

    .DESCRIPTION
        Searches installed Steam games, starts selected sessions, and provides settings
        for global defaults and saved per-game profiles.
    #>
    [CmdletBinding()]
    param()

    $games = @(Get-SteamInstalledGame)
    if ($games.Count -eq 0) { throw 'No installed Steam games were found.' }

    while ($true) {
        Clear-Host
        Write-Host '=== Legion Go Runtime Steam Companion ==='
        Write-Host 'Type part of a game name to filter, A for all games, S for settings, or Q to quit.'
        $choice = Read-Host 'Selection'

        if ($choice -match '^(?i)q$') { return }
        if ($choice -match '^(?i)s$') {
            $returnToMain = $false
            while (-not $returnToMain) {
                $setting = Get-GameLauncherSetting
                Clear-Host
                Write-Host '=== Steam Companion Settings ==='
                Write-Host "[1] Default thermal profile: $($setting.DefaultThermalProfile)"
                Write-Host "[2] Lossless Scaling enabled: $($setting.UseLosslessScaling)"
                Write-Host '[3] Configure a game profile'
                Write-Host '[4] View saved game profiles'
                Write-Host '[5] Remove a game profile'
                Write-Host '[6] Return'
                $settingsChoice = Read-Host 'Selection'

                switch ($settingsChoice) {
                    '1' {
                        Write-Host '[1] Quiet  [2] Balanced  [3] Performance'
                        $profileChoice = Read-Host 'Default thermal profile'
                        $profile = switch ($profileChoice) { '1' { 'Quiet' } '2' { 'Balanced' } '3' { 'Performance' } default { $null } }
                        if ($profile) { Set-GameLauncherSetting -DefaultThermalProfile $profile | Out-Null }
                    }
                    '2' { Set-GameLauncherSetting -UseLosslessScaling (-not [bool]$setting.UseLosslessScaling) | Out-Null }
                    '3' {
                        $filter = Read-Host 'Enter part of the game name'
                        $profileGames = @(Get-SteamInstalledGame -Name $filter)
                        if ($profileGames.Count -eq 0) { Read-Host 'No matching games. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt $profileGames.Count; $i++) { Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$profileGames[$i].Name,$profileGames[$i].AppId) }
                        $selection = 0
                        $value = Read-Host 'Game number'
                        if (-not [int]::TryParse($value,[ref]$selection) -or $selection -lt 1 -or $selection -gt $profileGames.Count) { continue }
                        $selectedGame = $profileGames[$selection-1]
                        Write-Host '[1] Quiet  [2] Balanced  [3] Performance'
                        $thermalChoice = Read-Host 'Thermal profile'
                        $thermal = switch ($thermalChoice) { '1' {'Quiet'} '2' {'Balanced'} '3' {'Performance'} default {$null} }
                        if (-not $thermal) { continue }
                        $lsChoice = Read-Host 'Use Lossless Scaling for this game? (Y/N)'
                        $gameLs = $lsChoice -match '^(?i)y$'
                        Set-SteamGameProfile -AppId $selectedGame.AppId -ThermalProfile $thermal -UseLosslessScaling $gameLs | Out-Null
                    }
                    '4' {
                        $profiles = @(Get-SteamGameProfile)
                        if ($profiles.Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        Clear-Host
                        Write-Host '=== Saved Steam Game Profiles ==='
                        foreach ($profile in $profiles) {
                            $game = Get-SteamInstalledGame -AppId $profile.AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            $lsText = if ($profile.UseLosslessScaling) { 'On' } else { 'Off' }
                            Write-Host ('{0} (App ID {1})' -f $name,$profile.AppId)
                            Write-Host ('  Thermal profile: {0}' -f $profile.ThermalProfile)
                            Write-Host ('  Lossless Scaling: {0}' -f $lsText)
                            if (@($profile.ProcessName).Count -gt 0) {
                                Write-Host ('  Process override: {0}' -f ($profile.ProcessName -join ', '))
                            }
                            Write-Host ''
                        }
                        Read-Host 'Press Enter to return' | Out-Null
                    }
                    '5' {
                        $profiles = @(Get-SteamGameProfile)
                        if ($profiles.Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt $profiles.Count; $i++) {
                            $game = Get-SteamInstalledGame -AppId $profiles[$i].AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$name,$profiles[$i].AppId)
                        }
                        $selection = 0
                        $value = Read-Host 'Profile number to remove'
                        if ([int]::TryParse($value,[ref]$selection) -and $selection -ge 1 -and $selection -le $profiles.Count) {
                            Remove-SteamGameProfile -AppId $profiles[$selection-1].AppId -Confirm:$false
                        }
                    }
                    '6' { $returnToMain = $true }
                }
            }
            continue
        }

        $matches = @(if ($choice -match '^(?i)a$' -or [string]::IsNullOrWhiteSpace($choice)) { $games } else { $games | Where-Object Name -Like "*$choice*" })
        if ($matches.Count -eq 0) { Write-Host 'No matching games found.'; Read-Host 'Press Enter to continue' | Out-Null; continue }
        $setting = Get-GameLauncherSetting
        for ($index=0; $index -lt $matches.Count; $index++) {
            $resolved = Get-ResolvedSteamGameProfile -Game $matches[$index] -Setting $setting
            $lsText = if ($resolved.UseLosslessScaling) { 'On' } else { 'Off' }
            $sourceText = if ($resolved.HasSavedProfile) { 'Saved profile' } else { 'Global defaults' }
            Write-Host ('[{0}] {1} (App ID {2}) [Thermal: {3} | Lossless Scaling: {4} | {5}]' -f ($index+1),$matches[$index].Name,$matches[$index].AppId,$resolved.ThermalProfile,$lsText,$sourceText)
        }
        $number = Read-Host 'Enter game number or press Enter to search again'
        if ([string]::IsNullOrWhiteSpace($number)) { continue }
        $selectedNumber = 0
        if (-not [int]::TryParse($number,[ref]$selectedNumber) -or $selectedNumber -lt 1 -or $selectedNumber -gt $matches.Count) { Write-Host 'Invalid selection.'; Start-Sleep 1; continue }
        $selectedGame = $matches[$selectedNumber-1]
        $selectedProfile = Get-ResolvedSteamGameProfile -Game $selectedGame -Setting (Get-GameLauncherSetting)
        $selectedLsText = if ($selectedProfile.UseLosslessScaling) { 'On' } else { 'Off' }
        Write-Host ''
        Write-Host ('Selected profile for {0}:' -f $selectedGame.Name)
        Write-Host ('  Thermal profile: {0} ({1})' -f $selectedProfile.ThermalProfile,$selectedProfile.ThermalProfileSource)
        Write-Host ('  Lossless Scaling: {0} ({1})' -f $selectedLsText,$selectedProfile.LosslessScalingSource)
        Write-Host ''
        Start-SteamGameSession -Game $selectedGame
        Read-Host 'Press Enter to return to the launcher' | Out-Null
    }
}

# Export only the supported public surface. All other functions remain private.
Export-ModuleMember -Function @(
    'Get-SteamInstalledGame',
    'Get-SteamGameProfile',
    'Get-GameLauncherSetting',
    'Set-GameLauncherSetting',
    'Set-SteamGameProfile',
    'Remove-SteamGameProfile',
    'Start-SteamGameSession',
    'Show-LegionGoRuntimeSteamCompanion'
)

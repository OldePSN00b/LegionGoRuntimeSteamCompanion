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

    $Setting | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
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

        return $setting
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
        [ValidateSet('Balanced', 'Performance')]
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

function Start-SteamGameSession {
    <#
    .SYNOPSIS
        Launches and monitors one installed Steam game.

    .DESCRIPTION
        Sets Legion Performance mode through an elevated helper, optionally starts
        Lossless Scaling, launches the selected game through Steam in the current user
        context, waits for the game to close, optionally closes Lossless Scaling, and
        restores Legion Balanced mode.

        The module normally detects game processes by executable path beneath the Steam
        installation folder. Use ProcessName or a GameOverrides entry for games that use
        external launchers, anti-cheat wrappers, or executables outside that folder.

    .PARAMETER Game
        An installed-game object returned by Get-SteamInstalledGame. Accepts pipeline
        input.

    .PARAMETER AppId
        Steam App ID of an installed game.

    .PARAMETER ProcessName
        Optional one or more process names without the .exe extension. Overrides path-
        based process detection for this launch.

    .PARAMETER UseLosslessScaling
        Overrides the saved Lossless Scaling setting for this launch only.

    .EXAMPLE
        Start-SteamGameSession -AppId 2191500

    .EXAMPLE
        Start-SteamGameSession -AppId 2191500 -UseLosslessScaling $false

    .EXAMPLE
        Get-SteamInstalledGame -Name 'Vampires' | Start-SteamGameSession

    .EXAMPLE
        Start-SteamGameSession -AppId 2191500 -ProcessName 'VBR-Win64-Shipping'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [psobject]$Game,
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$AppId,
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
        if (-not $ProcessName -and $override -and $override.ProcessName) {
            $ProcessName = @($override.ProcessName)
        }

        $useLs = if ($PSBoundParameters.ContainsKey('UseLosslessScaling')) { [bool]$UseLosslessScaling } else { [bool]$setting.UseLosslessScaling }
        $lsWasRunning = $false
        $lsStarted = $false
        $performanceSet = $false

        try {
            # Elevate only the hardware thermal-mode change. Steam and the game remain
            # in the normal interactive user session.
            Set-ElevatedLegionThermalMode -Mode Performance
            $performanceSet = $true

            if ($useLs) {
                $lsWasRunning = [bool](Get-Process -Name 'LosslessScaling' -ErrorAction SilentlyContinue)
                if (-not $lsWasRunning) {
                    $lsPath = Get-LosslessScalingPath -Setting $setting
                    if (-not $lsPath) { throw 'Lossless Scaling could not be located.' }
                    Write-Host "Starting Lossless Scaling: $lsPath"
                    Start-Process -FilePath $lsPath -ArgumentList '-StartMinimized'
                    $lsStarted = $true
                }
                else { Write-Host 'Lossless Scaling is already running.' }
            }
            else { Write-Host 'Lossless Scaling is disabled for this launch.' }

            # Steam URI launch returns immediately, so process detection below is used
            # to determine when the actual game starts and exits.
            Write-Host "Launching $($Game.Name) through Steam..."
            Start-Process -FilePath "steam://rungameid/$($Game.AppId)"

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $gameProcesses = @(Get-GameProcess -Game $Game -ProcessName $ProcessName)
                if ($gameProcesses.Count -gt 0) { break }
                if ($stopwatch.Elapsed.TotalSeconds -ge [int]$setting.GameStartTimeoutSeconds) {
                    throw "No game process was detected for '$($Game.Name)' within $($setting.GameStartTimeoutSeconds) seconds. Add a ProcessName override for App ID $($Game.AppId)."
                }
                Start-Sleep -Seconds ([int]$setting.PollIntervalSeconds)
            } while ($true)

            Write-Host 'Game process detected. Waiting for the game to close...'
            do {
                Start-Sleep -Seconds ([int]$setting.PollIntervalSeconds)
                $gameProcesses = @(Get-GameProcess -Game $Game -ProcessName $ProcessName)
            } while ($gameProcesses.Count -gt 0)

            Write-Host "$($Game.Name) has closed."
        }
        finally {
            # Cleanup is intentionally centralized here so Balanced mode is restored
            # even when game launch or process detection fails.
            if ($useLs -and $setting.CloseLosslessScalingAfterGame -and $lsStarted -and -not $lsWasRunning) {
                Write-Host 'Closing Lossless Scaling...'
                Get-Process -Name 'LosslessScaling' -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
            }
            if ($performanceSet) {
                try { Set-ElevatedLegionThermalMode -Mode Balanced }
                catch { Write-Warning ("Failed to restore Balanced mode: {0}" -f $_.Exception.Message) }
            }
        }
    }
}

function Show-LegionGoRuntimeSteamCompanion {
    <#
    .SYNOPSIS
        Opens the interactive Legion Go Runtime Steam Companion menu.

    .DESCRIPTION
        Loads the installed Steam library, allows filtering by partial game name, and
        starts the selected game through Start-SteamGameSession. The Settings menu can
        toggle the global Lossless Scaling preference.

    .EXAMPLE
        Show-LegionGoRuntimeSteamCompanion
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
            $setting = Get-GameLauncherSetting
            Write-Host "Lossless Scaling enabled: $($setting.UseLosslessScaling)"
            $toggle = Read-Host 'Toggle Lossless Scaling? (Y/N)'
            if ($toggle -match '^(?i)y$') {
                Set-GameLauncherSetting -UseLosslessScaling (-not [bool]$setting.UseLosslessScaling) | Out-Null
            }
            continue
        }

        $matches = @(
            if ($choice -match '^(?i)a$' -or [string]::IsNullOrWhiteSpace($choice)) {
                $games
            }
            else {
                $games | Where-Object Name -Like "*$choice*"
            }
        )

        if ($matches.Count -eq 0) {
            Write-Host 'No matching games found.'
            Read-Host 'Press Enter to continue' | Out-Null
            continue
        }

        for ($index = 0; $index -lt $matches.Count; $index++) {
            Write-Host ('[{0}] {1} (App ID {2})' -f ($index + 1), $matches[$index].Name, $matches[$index].AppId)
        }

        $number = Read-Host 'Enter game number or press Enter to search again'
        if ([string]::IsNullOrWhiteSpace($number)) { continue }
        $selectedNumber = 0
        if (-not [int]::TryParse($number, [ref]$selectedNumber) -or $selectedNumber -lt 1 -or $selectedNumber -gt $matches.Count) {
            Write-Host 'Invalid selection.'
            Start-Sleep -Seconds 1
            continue
        }

        Start-SteamGameSession -Game $matches[$selectedNumber - 1]
        Read-Host 'Press Enter to return to the launcher' | Out-Null
    }
}

# Export only the supported public surface. All other functions remain private.
Export-ModuleMember -Function @(
    'Get-SteamInstalledGame',
    'Get-GameLauncherSetting',
    'Set-GameLauncherSetting',
    'Start-SteamGameSession',
    'Show-LegionGoRuntimeSteamCompanion'
)

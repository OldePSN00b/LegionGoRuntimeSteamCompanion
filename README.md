# Legion Go Runtime Steam Companion

**Legion Go Runtime Steam Companion** is a Windows PowerShell 5.1 companion module for **Legion Go Runtime**. It discovers locally installed Steam games, lets you choose a game interactively or by Steam App ID, temporarily switches the Legion Go to Performance thermal mode, optionally starts Lossless Scaling, waits for the game to close, and restores Balanced mode afterward.

## Why this exists

Legion Space already controls the Legion Go's normal hardware and gaming settings. This project does not replace Legion Space and does not claim to manage controls that Legion Space already handles.

The gap addressed here is automatic thermal-mode switching around a Steam game session. Legion Go Runtime exposes `Set-LegionThermalMode`; this companion module uses that function in a repeatable launch, monitor, and cleanup workflow.

## Features

- Discovers installed games across all registered Steam libraries.
- Filters the installed library by partial game name.
- Launches Steam and the selected game in the normal interactive user context.
- Elevates only the Windows PowerShell helper that changes Legion thermal mode.
- Optionally starts Lossless Scaling minimized.
- Waits for the selected game to start and fully exit.
- Restores Legion Balanced mode after the game closes or when launch monitoring fails.
- Supports per-game process-name overrides for unusual launchers and anti-cheat wrappers.
- Stores settings under `%LOCALAPPDATA%\LegionGoRuntimeSteamCompanion`.
- Migrates settings from earlier SteamGameLauncher and UniversalGameLauncher releases.

## Requirements

- Windows PowerShell 5.1.
- Steam for Windows.
- Legion Go Runtime, with `Set-LegionThermalMode` available from the current user's Windows PowerShell 5.1 profile.
- Optional: Lossless Scaling installed through Steam.

## First-time setup

1. Install Steam and confirm that the games you want to launch are installed.
2. Install Legion Go Runtime.
3. Confirm that `Set-LegionThermalMode` is available from your Windows PowerShell 5.1 profile.
4. Optional: install Lossless Scaling.
5. Optional: open Lossless Scaling and create or edit a profile for each game you intend to use with the companion.
6. Optional: associate each Lossless Scaling profile with the correct game executable and configure the desired scaling, frame generation, rendering, and performance options.
7. Optional: enable **Run as administrator** in Lossless Scaling settings.
8. Start the companion from a normal, unelevated Windows PowerShell 5.1 session.

## Important caveats

### User Account Control

The companion must elevate Windows PowerShell to change Legion thermal mode before and after a game session.

When User Account Control is enabled, Windows can display an elevation prompt when switching to Performance mode and another prompt when restoring Balanced mode. Those prompts can interrupt an otherwise hands-off launch workflow. This may be uncommon on a dedicated gaming tablet, but the module does not assume UAC is disabled.

Steam and the game are not launched elevated by the module. They remain in the normal logged-in user context.

### Lossless Scaling

When Lossless Scaling integration is enabled, open Lossless Scaling settings and turn on **Run as administrator**.

Without that option enabled, Lossless Scaling may start but fail to hook or interact correctly with the game because the processes can run at different Windows integrity levels.

The companion does not configure Lossless Scaling profiles. Before using the integration, create or edit a profile for the game in the Lossless Scaling GUI, associate that profile with the game's executable, and save your preferred scaling and frame-generation settings.

When the companion starts Lossless Scaling, Lossless Scaling is responsible for detecting the running game and applying the matching profile. If no matching profile exists, Lossless Scaling may still start, but the intended game-specific settings will not be applied.

The companion does not change the **Run as administrator** setting or create, edit, or select Lossless Scaling profiles automatically.

## Security

The companion requests administrator privileges only for the thermal-mode changes performed by the private helper script. Steam and the selected game are launched from the original unelevated PowerShell session and remain in the normal user context.

The module does not store credentials, add persistent elevated tasks, or keep an elevated PowerShell process running for the duration of gameplay.

## Known limitations

- UAC prompts can interrupt the launch and cleanup workflow when UAC is enabled.
- Lossless Scaling profiles must be created and associated with game executables manually in the Lossless Scaling GUI.
- Lossless Scaling must have **Run as administrator** enabled for reliable integration.
- Games that use external launchers, anti-cheat wrappers, or executables outside the Steam installation directory may require a process-name override.

## Installation

1. Download and extract the release ZIP.
2. Keep the complete `LegionGoRuntimeSteamCompanion` folder together.
3. Run the launcher from a normal, unelevated Windows PowerShell 5.1 session:

```powershell
.\Start-LegionGoRuntimeSteamCompanion.ps1
```

## Module usage

```powershell
Import-Module .\LegionGoRuntimeSteamCompanion.psd1 -Force
Show-LegionGoRuntimeSteamCompanion
```

List every installed Steam game:

```powershell
Get-SteamInstalledGame
```

Find games by partial name:

```powershell
Get-SteamInstalledGame -Name 'Vampire'
```

Launch by Steam App ID:

```powershell
Start-SteamGameSession -AppId 2191500
```

Disable Lossless Scaling for one launch:

```powershell
Start-SteamGameSession -AppId 2191500 -UseLosslessScaling $false
```

Use an explicit process name for a game with unusual process behavior:

```powershell
Start-SteamGameSession -AppId 2191500 -ProcessName 'VBR-Win64-Shipping'
```

## Settings

The settings file is created at:

```text
%LOCALAPPDATA%\LegionGoRuntimeSteamCompanion\Settings.json
```

View current settings:

```powershell
Get-GameLauncherSetting
```

Disable Lossless Scaling globally:

```powershell
Set-GameLauncherSetting -UseLosslessScaling $false
```

Change process polling and startup timeout:

```powershell
Set-GameLauncherSetting -GameStartTimeoutSeconds 600 -PollIntervalSeconds 3
```

Set a manual Lossless Scaling executable path:

```powershell
Set-GameLauncherSetting -LosslessScalingPathOverride 'D:\SteamLibrary\steamapps\common\Lossless Scaling\LosslessScaling.exe'
```

## Per-game process overrides

Most games are detected by finding processes whose executable path is beneath the selected Steam installation directory. Games that use external launchers, anti-cheat wrappers, or executables outside that directory may need an override.

Example `GameOverrides` entry in `Settings.json`:

```json
{
  "GameOverrides": {
    "2191500": {
      "ProcessName": [
        "VBR-Win64-Shipping"
      ]
    }
  }
}
```

Process names should normally be entered without `.exe`.

## Approved PowerShell verbs

Every module function name uses a verb returned by `Get-Verb`. The current function set uses only:

- `Get`
- `Set`
- `Show`
- `Start`
- `Write`

Unapproved-verb warnings are treated as bugs.

## Getting command help

```powershell
Get-Help Get-SteamInstalledGame -Full
Get-Help Get-GameLauncherSetting -Full
Get-Help Set-GameLauncherSetting -Full
Get-Help Start-SteamGameSession -Full
Get-Help Show-LegionGoRuntimeSteamCompanion -Full
```

## How it works

1. The module requests Performance mode through an elevated Windows PowerShell 5.1 helper.
2. Lossless Scaling is optionally started in the logged-in user's session.
3. Steam launches the selected game in the normal user context.
4. The module waits for the game process to appear and then fully exit.
5. Lossless Scaling is closed only when the module started it.
6. Balanced mode is requested from a `finally` block.

## Scope

This release supports Steam. Support for other gaming platforms may be considered later, but this release does not claim or imply support for them.

## License

Released under the MIT License. See `LICENSE`.

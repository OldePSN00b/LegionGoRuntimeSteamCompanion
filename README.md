# Legion Go Runtime Steam Companion

**Legion Go Runtime Steam Companion** is a Windows PowerShell 5.1 companion module for **Legion Go Runtime**. It discovers locally installed Steam games, launches them in the normal user context, applies an optional per-game Legion thermal profile, optionally starts Lossless Scaling, waits for the game to close, and returns the Legion Go to Balanced mode afterward.

## Why this exists

Legion Space already handles the Legion Go's normal hardware and gaming settings. This project does not replace Legion Space.

The gap addressed here is automatic thermal-mode switching around Steam game sessions. Legion Go Runtime exposes `Set-LegionThermalMode`; this companion uses that function to apply Quiet, Balanced, or Performance profiles while Steam and the game remain in the standard logged-in user context.

## Features

- Discovers installed games across all registered Steam libraries.
- Interactive game search and selection.
- Direct CLI launching by Steam App ID.
- Global thermal baseline with **Balanced** as the default.
- Per-game Quiet, Balanced, or Performance profiles.
- Visible resolved thermal and Lossless Scaling settings in the game picker before launch.
- Interactive viewing of all saved game profiles.
- CLI thermal override with `-ThermalProfile` or the shorter `-TDProfile` alias.
- Per-game and per-launch Lossless Scaling preferences.
- Optional automatic Lossless Scaling startup and cleanup.
- Game process monitoring with optional process-name overrides.
- Session process isolation that ignores matching processes already running before launch.
- Validated settings with interruption-resistant file updates.
- Automatic restoration to Balanced after Quiet or Performance sessions.
- Balanced sessions skip thermal elevation entirely.
- Settings migration from earlier SteamGameLauncher and UniversalGameLauncher releases.

## Requirements

- Windows PowerShell 5.1.
- Steam for Windows.
- Legion Go Runtime, with `Set-LegionThermalMode` available from the current user's Windows PowerShell 5.1 profile.
- Optional: Lossless Scaling installed through Steam.

## First-time setup

1. Install Steam and confirm your games are installed.
2. Install Legion Go Runtime.
3. Confirm `Set-LegionThermalMode` is available in Windows PowerShell 5.1.
4. Optional: install Lossless Scaling.
5. Optional: create a Lossless Scaling profile in its GUI for each game you intend to use.
6. Optional: associate each profile with the correct game executable and configure the desired scaling and frame-generation settings.
7. Optional: enable **Run as administrator** in Lossless Scaling settings.
8. Start the companion from a normal, unelevated Windows PowerShell 5.1 session.

## Important caveats

### User Account Control

Quiet and Performance sessions elevate Windows PowerShell to change the Legion thermal mode before the game starts and restore Balanced after it closes. If UAC is enabled, Windows can display a prompt for each change.

Balanced is the baseline. A session resolved to Balanced performs no thermal-mode elevation, so lightweight games can launch without thermal UAC prompts.

Steam and the game are never launched elevated by this module.

### Lossless Scaling

The companion starts and stops Lossless Scaling, but it does not configure profiles.

Before using Lossless Scaling integration:

1. Open Lossless Scaling.
2. Create or edit a profile for the game.
3. Associate it with the game's executable.
4. Save the desired settings.
5. Enable **Run as administrator** in Lossless Scaling settings.

Without a matching profile, Lossless Scaling may start but will not apply the intended game-specific configuration.

## Installation

1. Download and extract the release ZIP.
2. Keep the complete `LegionGoRuntimeSteamCompanion` folder together.
3. Run:

```powershell
.\Start-LegionGoRuntimeSteamCompanion.ps1
```

## Module usage

```powershell
Import-Module .\LegionGoRuntimeSteamCompanion.psd1 -Force
Show-LegionGoRuntimeSteamCompanion
```

List installed games:

```powershell
Get-SteamInstalledGame
```

Launch using saved settings and profiles:

```powershell
Start-SteamGameSession -AppId 2191500
```

Force Performance for one launch:

```powershell
Start-SteamGameSession -AppId 2191500 -ThermalProfile Performance
```

Use the shorter CLI alias:

```powershell
Start-SteamGameSession -AppId 2191500 -TDProfile Quiet
```

Force Balanced and disable Lossless Scaling for one launch:

```powershell
Start-SteamGameSession -AppId 2191500 -TDProfile Balanced -UseLosslessScaling $false
```

PowerShell parameter syntax does not use an equals sign. Use `-TDProfile Performance`, not `-TDProfile = Performance`.

## Profile resolution order

For each session, settings are resolved in this order:

1. Explicit CLI parameters.
2. Saved per-game profile.
3. Global defaults.

The global thermal default is Balanced.

## Global settings

View settings:

```powershell
Get-GameLauncherSetting
```

Set the global thermal default:

```powershell
Set-GameLauncherSetting -DefaultThermalProfile Balanced
```

Set the global Lossless Scaling preference:

```powershell
Set-GameLauncherSetting -UseLosslessScaling $true
```

Settings are stored at:

```text
%LOCALAPPDATA%\LegionGoRuntimeSteamCompanion\Settings.json
```

Settings loaded from disk are validated before use. Updates use a same-directory atomic
replacement with temporary backup cleanup. Legacy string representations of
Boolean and numeric values are normalized when unambiguous; invalid values produce a
clear error instead of being silently coerced.

## Per-game profiles

Create or update a profile:

```powershell
Set-SteamGameProfile `
    -AppId 2191500 `
    -ThermalProfile Performance `
    -UseLosslessScaling $true
```

At least one of `-ThermalProfile`, `-UseLosslessScaling`, or `-ProcessName` must be
provided when creating or updating a profile.

Configure a lightweight game:

```powershell
Set-SteamGameProfile `
    -AppId 413150 `
    -ThermalProfile Balanced `
    -UseLosslessScaling $false
```

View saved profiles:

```powershell
Get-SteamGameProfile
Get-SteamGameProfile -AppId 2191500
```

Remove a saved profile:

```powershell
Remove-SteamGameProfile -AppId 2191500
```

Per-game profiles can also be configured, viewed, or removed from the interactive Settings menu. The game picker displays the effective thermal profile and Lossless Scaling state for each game, including whether the values come from a saved profile or the global defaults.

## Process overrides

Games using external launchers, anti-cheat wrappers, or executables outside their Steam installation folder may require explicit process names:

```powershell
Set-SteamGameProfile `
    -AppId 2191500 `
    -ProcessName 'VBR-Win64-Shipping'
```

Process names should normally omit `.exe`.

Processes with a matching name that were already running before Steam was launched are
not treated as part of the new game session.

## Tests

The Pester suite supports Windows PowerShell 5.1 and the bundled Pester 3.4.0:

```powershell
Invoke-Pester .\tests
```

## Security

Administrator privileges are requested only for thermal-mode changes. The companion does not store credentials, create persistent elevated scheduled tasks, or keep an elevated PowerShell process running during gameplay.

## Known limitations

- UAC prompts can interrupt Quiet and Performance workflows.
- Lossless Scaling profiles must be configured manually in its GUI.
- Lossless Scaling must have **Run as administrator** enabled for reliable integration.
- Some games require process-name overrides.
- The companion assumes Balanced is the post-session baseline; it does not query and restore an arbitrary pre-launch thermal mode.

## Approved PowerShell verbs

Every module function uses a verb returned by `Get-Verb`. Unapproved-verb warnings are treated as bugs.

## Command help

```powershell
Get-Help Start-SteamGameSession -Full
Get-Help Set-SteamGameProfile -Full
Get-Help Get-SteamGameProfile -Full
Get-Help Remove-SteamGameProfile -Full
Get-Help Set-GameLauncherSetting -Full
```

## License

Released under the MIT License. See `LICENSE`.

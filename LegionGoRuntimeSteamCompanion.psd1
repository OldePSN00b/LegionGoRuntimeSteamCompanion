@{
    RootModule        = 'LegionGoRuntimeSteamCompanion.psm1'
    ModuleVersion     = '1.2.6'
    GUID              = '5a3fb632-7fd6-4d5b-9536-4e08930ebc80'
    Author            = '0ldePSN00b'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 0ldePSN00b. All rights reserved.'
    Description       = 'Companion module for Legion Go Runtime that launches installed Steam games with global, per-game, or CLI-selected thermal profiles and optional Lossless Scaling integration.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-SteamInstalledGame',
        'Get-SteamGameProfile',
        'Get-GameLauncherSetting',
        'Set-GameLauncherSetting',
        'Set-SteamGameProfile',
        'Remove-SteamGameProfile',
        'Start-SteamGameSession',
        'Show-LegionGoRuntimeSteamCompanion'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Steam', 'LegionGo', 'LegionGoRuntime', 'SteamCompanion', 'LosslessScaling', 'Gaming')
            ProjectUri   = ''
            ReleaseNotes = 'Hides the elevated thermal-mode helper console while preserving visible UAC consent and the interactive companion window.'
        }
    }
}

@{
    RootModule        = 'LegionGoRuntimeSteamCompanion.psm1'
    ModuleVersion     = '1.1.1'
    GUID              = '5a3fb632-7fd6-4d5b-9536-4e08930ebc80'
    Author            = '0ldePSN00b'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 0ldePSN00b. All rights reserved.'
    Description       = 'Companion module for Legion Go Runtime that launches installed Steam games, temporarily applies Legion Performance thermal mode, optionally starts Lossless Scaling, and restores Balanced mode after the game exits.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-SteamInstalledGame',
        'Get-GameLauncherSetting',
        'Set-GameLauncherSetting',
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
            ReleaseNotes = 'Documents first-time setup, Lossless Scaling profile requirements, the Run as administrator requirement, security behavior, and known limitations. No intended game-session behavior changes.'
        }
    }
}

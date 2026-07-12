$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\LegionGoRuntimeSteamCompanion.psd1'
Import-Module -Name $modulePath -Force

Describe 'Module contract' {
    It 'exports exactly the commands declared by the manifest' {
        $manifest = Test-ModuleManifest -Path $modulePath
        $actual = @(Get-Command -Module LegionGoRuntimeSteamCompanion -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $expected = @($manifest.ExportedFunctions.Keys | Sort-Object)

        @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count | Should Be 0
    }

    It 'uses approved verbs for every exported command' {
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $unapproved = @(
            Get-Command -Module LegionGoRuntimeSteamCompanion -CommandType Function |
                Where-Object { ($_.Name -split '-')[0] -notin $approvedVerbs }
        )

        $unapproved.Count | Should Be 0
    }
}

Describe 'Settings validation' {
    InModuleScope LegionGoRuntimeSteamCompanion {
        It 'normalizes Boolean strings and numeric values from legacy settings' {
            $setting = Get-DefaultGameLauncherSetting
            $setting.UseLosslessScaling = 'false'
            $setting.GameStartTimeoutSeconds = '600'

            $result = ConvertTo-NormalizedGameLauncherSetting -Setting $setting

            $result.UseLosslessScaling | Should Be $false
            $result.GameStartTimeoutSeconds | Should Be 600
        }

        It 'rejects invalid Boolean values instead of coercing them to true' {
            $setting = Get-DefaultGameLauncherSetting
            $setting.UseLosslessScaling = 'not-a-boolean'

            { ConvertTo-NormalizedGameLauncherSetting -Setting $setting } | Should Throw
        }

        It 'rejects invalid timeout ranges' {
            $setting = Get-DefaultGameLauncherSetting
            $setting.GameStartTimeoutSeconds = 0

            { ConvertTo-NormalizedGameLauncherSetting -Setting $setting } | Should Throw
        }
    }
}

Describe 'Settings persistence' {
    InModuleScope LegionGoRuntimeSteamCompanion {
        It 'atomically replaces an existing settings file under Windows PowerShell 5.1' {
            $originalDirectory = $script:SettingsDirectory
            $originalPath = $script:SettingsPath
            $testDirectory = Join-Path -Path $TestDrive -ChildPath 'Settings'
            $script:SettingsDirectory = $testDirectory
            $script:SettingsPath = Join-Path -Path $testDirectory -ChildPath 'Settings.json'

            try {
                $setting = Get-DefaultGameLauncherSetting
                Write-GameLauncherSetting -Setting $setting
                $setting.DefaultThermalProfile = 'Performance'
                Write-GameLauncherSetting -Setting $setting

                $saved = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
                $saved.DefaultThermalProfile | Should Be 'Performance'
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.tmp').Count | Should Be 0
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.bak').Count | Should Be 0
            }
            finally {
                $script:SettingsDirectory = $originalDirectory
                $script:SettingsPath = $originalPath
            }
        }
    }
}

Describe 'Saved game profiles' {
    InModuleScope LegionGoRuntimeSteamCompanion {
        It 'rejects an empty saved profile' {
            { Set-SteamGameProfile -AppId '12345' } | Should Throw
        }

        It 'keeps a single process override as a collection' {
            Mock Get-GameLauncherSetting {
                $setting = Get-DefaultGameLauncherSetting
                $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name '12345' -Value ([pscustomobject]@{
                    ProcessName = @('ExampleGame')
                })
                $setting
            }

            $profile = Get-SteamGameProfile -AppId '12345'

            @($profile.ProcessName).Count | Should Be 1
            $profile.ProcessName[0] | Should Be 'ExampleGame'
        }
    }
}

Describe 'Game session process resolution' {
    InModuleScope LegionGoRuntimeSteamCompanion {
        It 'resolves process overrides independently for each piped game' {
            $script:processNamesObserved = @()
            $script:processCall = 0
            $setting = Get-DefaultGameLauncherSetting
            $setting.UseLosslessScaling = $false
            $setting.GameOverrides | Add-Member NoteProperty '1' ([pscustomobject]@{ ProcessName = @('FirstGame') })
            $setting.GameOverrides | Add-Member NoteProperty '2' ([pscustomobject]@{ ProcessName = @('SecondGame') })

            Mock Get-GameLauncherSetting { $setting }
            Mock Start-Process { }
            Mock Start-Sleep { }
            Mock Get-GameProcess {
                $script:processNamesObserved += (@($ProcessName) -join ',')
                $script:processCall++
                if (($script:processCall % 3) -eq 2) {
                    [pscustomobject]@{ Id = 100 + $script:processCall }
                }
            }

            @(
                [pscustomobject]@{ Name = 'First'; AppId = '1'; InstallPath = 'C:\Games\First' },
                [pscustomobject]@{ Name = 'Second'; AppId = '2'; InstallPath = 'C:\Games\Second' }
            ) | Start-SteamGameSession

            @($script:processNamesObserved[0..2] | Where-Object { $_ -ne 'FirstGame' }).Count | Should Be 0
            @($script:processNamesObserved[3..5] | Where-Object { $_ -ne 'SecondGame' }).Count | Should Be 0
        }
    }
}

Describe 'Thermal helper launch behavior' {
    InModuleScope LegionGoRuntimeSteamCompanion {
        It 'hides the elevated PowerShell console while preserving UAC elevation' {
            Mock Test-Path { $true }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

            Set-ElevatedLegionThermalMode -Mode Performance

            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and
                $WindowStyle -eq 'Hidden' -and
                $Wait -and
                $PassThru
            }
        }
    }
}

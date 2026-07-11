# Changelog

All notable changes to Legion Go Runtime Steam Companion are documented here.

## 1.2.4

- Isolated saved process-name overrides for each piped game session.
- Excluded matching processes that were already running before a game launch from session detection.
- Limited Lossless Scaling cleanup to the process started by the current session.
- Rejected empty saved game profiles and invalid persisted setting values with clear errors.
- Normalized supported legacy Boolean strings, numeric settings, and process-name collections.
- Wrote settings through a same-directory temporary file to reduce the risk of partial JSON writes.
- Added Windows PowerShell 5.1-compatible Pester regression tests for the module contract, approved verbs, settings validation, profile collections, and piped sessions.

## 1.2.3

- Fixed a StrictMode `.Count` error when viewing a saved game profile with no process override or a single process override.
- Normalized the process override value to an array before checking its count.

## 1.2.2

- Added a Settings option to view all saved per-game profiles.
- Added thermal profile and Lossless Scaling status to every game-picker entry.
- Added an explicit resolved-profile summary before the selected game launches.
- Profile displays identify whether each effective value comes from a saved game profile or global defaults.

## 1.2.1

- Filtered Steamworks Common Redistributables (Steam App ID 228980) from installed-game discovery.
- The shared redistributable component no longer appears in the game picker, search results, or profile-management menus.

## 1.2.0

- Added global thermal-profile settings with Balanced as the default baseline.
- Added per-game Quiet, Balanced, and Performance profiles.
- Added `Get-SteamGameProfile`, `Set-SteamGameProfile`, and `Remove-SteamGameProfile`.
- Added `-ThermalProfile` and the `-TDProfile` alias to `Start-SteamGameSession`.
- Added per-game Lossless Scaling preferences.
- Added interactive profile configuration and removal.
- Balanced sessions now skip thermal elevation and post-session restoration.
- Quiet and Performance sessions restore Balanced after the game exits.
- Updated documentation, help, examples, and manifest metadata.

## 1.1.1

- Added a first-time setup section.
- Documented that Lossless Scaling profiles must be created and associated with each game in the Lossless Scaling GUI before integration is used.
- Clarified that the companion starts and stops Lossless Scaling but does not create, edit, or select profiles.
- Expanded the Lossless Scaling caveat to explain the **Run as administrator** requirement and profile matching behavior.
- Added security and known-limitations sections.
- Updated module manifest metadata and release notes for the documentation release.
- No intended game-session behavior changes from v1.1.0.

## 1.1.0

- Renamed the project and module to **Legion Go Runtime Steam Companion**.
- Renamed the interactive entry point to `Show-LegionGoRuntimeSteamCompanion`.
- Renamed the launcher script and module files to match the new project identity.
- Preserved concise Steam-specific commands such as `Get-SteamInstalledGame` and `Start-SteamGameSession`.
- Added automatic settings migration from `%LOCALAPPDATA%\SteamGameLauncher` and `%LOCALAPPDATA%\UniversalGameLauncher`.
- Rewrote the README to describe the project honestly as a Steam companion for Legion Go Runtime.
- Retained the UAC caveat and the Lossless Scaling **Run as administrator** requirement.
- Updated inline comments, comment-based help, manifest metadata, tags, and release notes.
- Audited all function names against `Get-Verb`; no unapproved verbs are used.
- No intended game-session behavior changes from v1.0.7.

## 1.0.7

- Repositioned Steam Game Launcher honestly as a companion module for Legion Go Runtime.
- Clarified that Legion Space remains responsible for normal Legion Go controls and that this module focuses on automated thermal-mode switching.
- Added a prominent UAC caveat explaining the possible elevation prompts before and after a game session.
- Documented that Lossless Scaling must have **Run as administrator** enabled for reliable operation.
- Audited every module function against `Get-Verb`; all function names use approved verbs.
- Expanded module manifest tags and release notes.
- Added the MIT license file.
- No intended functional changes from v1.0.6.

## 1.0.6

- Added comment-based help to all public commands.
- Added inline maintenance comments throughout the module and helper scripts.
- Added a GitHub-ready Markdown README with installation, usage, settings, and troubleshooting guidance.
- Added this changelog.
- Updated module metadata and version information.
- No intended functional changes from v1.0.5.

## 1.0.5

- Fixed Windows PowerShell 5.1 handling of the optional `UseLosslessScaling` Boolean override.
- Replaced nullable `.HasValue` checking with `PSBoundParameters.ContainsKey()`.

## 1.0.4

- Fixed a StrictMode error when a game search returned exactly one result.
- Forced filtered menu results into an array before checking `.Count`.

## 1.0.3

- Removed duplicate installed-game entries by grouping Steam manifests by App ID.

## 1.0.2

- Fixed Steam registry discovery when `InstallPath` is not present.
- Safely checks registry properties before reading them under StrictMode.

## 1.0.1

- Renamed Universal Game Launcher to Steam Game Launcher.
- Added migration from the former settings path.

## 1.0.0

- Initial module release.
- Added installed Steam library discovery, interactive selection, Legion thermal-mode integration, optional Lossless Scaling support, process monitoring, and settings persistence.

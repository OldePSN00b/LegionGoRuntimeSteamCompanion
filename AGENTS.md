# Repository Instructions

These instructions apply to the entire repository.

## PowerShell compatibility

- Support Windows PowerShell 5.1 only. Do not introduce syntax, modules, APIs, or behaviors that require PowerShell 6+ or PowerShell 7+.
- Use only approved PowerShell verbs. Validate new command names against `Get-Verb`.
- Test relevant code while `Set-StrictMode -Version Latest` is enabled.
- PowerShell may unwrap a single-item result. Wrap potential single-object collections in `@()` before reading `.Count`.

## Output behavior

- Use `Write-Host` for interactive menus, prompts, status displays, and other user-interface text.
- Keep pipeline output clean. Commands should emit only their intended data objects to the success output stream.

## Compatibility and documentation

- Preserve public command names, parameters, accepted inputs, output shapes, and behavior unless an API change is explicitly approved.
- Update `README.md` and `CHANGELOG.md` for every user-visible change.
- Follow semantic versioning for releases and version changes.
- Prepare release notes before creating a release tag.

## Validation

- Run applicable tests or focused validation after making changes.
- Perform compatibility validation with Windows PowerShell 5.1 (`powershell.exe`), not only PowerShell 7 (`pwsh.exe`).
- As the project grows, maintain Pester tests in a `tests` directory and add regression coverage with relevant changes.
- Prioritize Pester coverage for duplicate Steam game results, single-object `.Count` behavior, path normalization consistency, missing exported commands, and unapproved PowerShell verbs.

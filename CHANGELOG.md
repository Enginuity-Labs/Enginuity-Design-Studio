# Changelog

All notable changes to Enginuity Design Studio will be documented in this file.

## [Unreleased]

### Changed
- **Installer rewritten for the current application.** It had gone stale against
  the product: it installed `enginuity_launcher.exe`, a `server\` directory and a
  Flutter `enginuity_design_studio\` directory, and stopped three process names
  that no longer exist. The application now ships as `eds_app.exe` with its
  CalculiX and Gmsh runtime, so the installer would have failed on any current
  release.
- Installs by mirroring the payload rather than copying named files, so a library
  dropped from a later release is removed instead of lingering and being loaded.
  `logs\` is preserved across updates.
- The payload is checked for `runtime\ccx` and `runtime\gmsh` before anything is
  written. A package missing them installs cleanly and then fails at the user's
  first solve, which is a worse outcome than refusing to install.
- Repository references now use the canonical `Enginuity-Labs` path rather than
  relying on GitHub's rename redirect.
- Only processes belonging to the installation being written are stopped, so
  updating one installation no longer terminates another — or a developer's build
  running from a source tree.

### Added
- **Unattended mode**, for the in-app updater: `-Silent`, `-WaitForPid`,
  `-Launch`/`-NoLaunch`, meaningful exit codes, and a transcript under
  `%LOCALAPPDATA%\Enginuity Labs\Design Studio\update\`. The application cannot
  replace its own running executable, so it hands off to this script, which waits
  for the application to exit before touching a file.
- `install.json` is written beside the executable. It records the installed
  version and is what tells the application it is a managed installation; without
  it the in-app updater stays inactive.

### Fixed
- **Uninstalling from Add/Remove Programs.** The registered command was
  `irm ... | iex -Action uninstall`, which fails outright — `Invoke-Expression`
  has no `-Action` parameter — so Windows Settings could not uninstall the
  application. It now uses a scriptblock, which accepts arguments.
- The installer no longer aborts when its output is redirected. Clearing the
  screen writes through a console handle that does not exist in a piped or
  application-started run, and that failure stopped the run before it began.
- A `-WaitForPid` whose process had already exited is now handled as the ordinary
  case it is, rather than as an error.

## [0.0.0.1] - 2025-01-02

### Added
- Initial public release
- AI-powered CAD design automation
- Onshape integration
- Fusion360 integration
- KiCad integration
- Local Python server for processing
- Flutter desktop application
- WebSocket-based communication
- Supabase database integration
- One-command PowerShell installation
- Automatic update support
- User-level installation (no admin required)

---

[Unreleased]: https://github.com/Enginuity-Labs/Enginuity-Design-Studio/compare/v0.0.0.1...HEAD
[0.0.0.1]: https://github.com/Enginuity-Labs/Enginuity-Design-Studio/releases/tag/v0.0.0.1

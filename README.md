# Enginuity Design Studio

> AI-Powered Design Automation Platform for CAD, PCB Design, and Simulations

[![Latest Release](https://img.shields.io/github/v/release/Enginuity-Labs/Enginuity-Design-Studio)](https://github.com/Enginuity-Labs/Enginuity-Design-Studio/releases/latest)

## 🚀 Quick Install (Windows)

Open **PowerShell** and run:
```powershell
irm https://raw.githubusercontent.com/Enginuity-Labs/Enginuity-Design-Studio/main/install.ps1 | iex
```

That's it! The installer will:
- ✅ Download the latest release
- ✅ Install to your user directory (no admin needed)
- ✅ Create desktop & start menu shortcuts
- ✅ Register the application in Windows

## 📋 Features

- 🤖 **AI-Powered CAD** - Intelligent design automation
- 🔌 **AI-Powered PCB Design** - Integrated circuit board layout
- 📊 **AI-Powered Simulations** - Real-time design validation

## 💻 System Requirements

- **OS:** Windows 10 (1809+) or Windows 11, 64-bit
- **RAM:** 8GB minimum, 16GB recommended for meshing and solves
- **Disk:** 2GB free space
- **Internet:** Required for installation and AI features

## 🔄 Updating

**From inside the application.** Enginuity Design Studio checks for new releases
on its own and offers them under **Account → Check for Updates**. Accepting the
prompt closes the application, installs the update, and reopens it — the
application cannot replace its own running executable, so this script does it.

**Manually.** Re-run the installation command; it detects an existing
installation and upgrades in place, keeping your logs:
```powershell
irm https://raw.githubusercontent.com/Enginuity-Labs/Enginuity-Design-Studio/main/install.ps1 | iex
```

## 🗑️ Uninstall

Uninstalling also removes your saved sign-in from Windows Credential Manager
and deletes the application's local data. Updating never does.

**Method 1:** Windows Settings
- Settings → Apps → Enginuity Design Studio → Uninstall

**Method 2:** PowerShell
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Enginuity-Labs/Enginuity-Design-Studio/main/install.ps1))) -Action uninstall
```

The scriptblock form is needed to pass arguments. `irm ... | iex -Action uninstall`
does **not** work: `Invoke-Expression` has no `-Action` parameter, so the argument
is rejected.

### Execution Policy
If you get an execution policy error:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## ⚙️ Advanced Usage

Download the script first, then pass parameters:

```powershell
irm https://raw.githubusercontent.com/Enginuity-Labs/Enginuity-Design-Studio/main/install.ps1 -OutFile install.ps1

# A specific release, to a custom location
.\install.ps1 -Action install -Version v1.0.0.1 -InstallPath "D:\Apps\EDS"

# Reinstall the current release over a damaged installation
.\install.ps1 -Action repair
```

| Parameter | Purpose |
| --- | --- |
| `-Action` | `install`, `update`, `repair`, `uninstall`, or `menu` (default) |
| `-Version` | A release tag such as `v1.0.0.1`, or `latest` (default) |
| `-InstallPath` | Installation directory. `Program Files` is refused; the install is per-user |
| `-Silent` | Never prompt; every question takes its default and the exit code carries the outcome |
| `-WaitForPid` | Wait for this process to exit before touching any file |
| `-Launch` / `-NoLaunch` | Start, or do not start, the application on success |

`-Silent`, `-WaitForPid`, and `-Launch` exist for the in-app updater, which hands
off to this script and then quits so its own executable can be replaced. A silent
run writes a transcript to
`%LOCALAPPDATA%\Enginuity Labs\Enginuity Design Studio\data\update\install-<tag>.log`.

### Exit Codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Unexpected failure |
| 10 | Release or asset not found |
| 11 | Download failed |
| 12 | Package could not be extracted, or is missing part of its payload |
| 13 | Files could not be copied (locked file, disk full) |
| 14 | A running process would not exit |

## 🐛 Troubleshooting

### Installation Fails
1. Check your internet connection
2. Verify you're not installing to Program Files
3. Close any running Enginuity Design Studio windows
4. Read the application log at
   `%LOCALAPPDATA%\Enginuity Labs\Enginuity Design Studio\data\logs\eds_app.log`,
   and for a silent run the installer transcript beside it under `...\data\update\`
5. Check [Issues](https://github.com/Enginuity-Labs/Enginuity-Design-Studio/issues)

## 📖 Documentation

- Website: [enginuitylabs.org](https://enginuitylabs.org)
- Support: support@enginuitylabs.org

## 📜 License

Copyright © 2024-2026 Enginuity Labs. All rights reserved.

## 🔗 Links

- [Official Website](https://enginuitylabs.org)
- [Releases](https://github.com/Enginuity-Labs/Enginuity-Design-Studio/releases)

---

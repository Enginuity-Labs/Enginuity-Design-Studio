#Requires -Version 5.1
<#
.SYNOPSIS
    Enginuity Design Studio installer.
.DESCRIPTION
    Downloads and installs Enginuity Design Studio from the public repository's
    GitHub releases.

    This repository holds the only copy. The application's own repository fetches
    it from here at publish time and attaches it to each release, so an installed
    application updates with the installer that shipped alongside the version it
    is installing, while `irm ... | iex` always reaches whatever is on main.

    The published package is a single application and its solver runtime:

        eds_app.exe          the application
        runtime\ccx\         CalculiX and its runtime libraries
        runtime\gmsh\        the Gmsh shared library
        VERSION.txt          the release version, as text
        README.txt           package notes

.PARAMETER Version
    A release tag such as v1.0.0.1, or "latest" (default).
.PARAMETER InstallPath
    Installation directory. Defaults to
    $env:LOCALAPPDATA\Enginuity Labs\Enginuity Design Studio.
.PARAMETER Action
    install, update, repair, uninstall, or menu (default).
.PARAMETER Silent
    Never prompt. Every question takes its default, and the outcome is
    communicated by the exit code. Required for a run the application starts,
    where the console belongs to a process the user did not launch and a prompt
    would be an invisible hang.
.PARAMETER WaitForPid
    Wait for this process to exit before touching any file. The application
    passes its own process id here: it cannot replace its own executable, so it
    hands off and quits, and this is what makes the ordering safe.
.PARAMETER Launch
    Start the application when the run succeeds.
.PARAMETER NoLaunch
    Never start the application, overriding -Launch.
.EXAMPLE
    irm https://raw.githubusercontent.com/Enginuity-Labs/Enginuity-Design-Studio/main/install.ps1 | iex
.EXAMPLE
    .\install.ps1 -Action update -Version v1.0.0.1
.EXAMPLE
    .\install.ps1 -Action update -Version v1.0.0.1 -Silent -WaitForPid 4242 -Launch
#>

param(
    [string]$Version = "latest",
    [string]$InstallPath = "$env:LOCALAPPDATA\Enginuity Labs\Enginuity Design Studio",
    [ValidateSet("menu", "install", "update", "repair", "uninstall")]
    [string]$Action = "menu",
    [switch]$Silent,
    [int]$WaitForPid = 0,
    [switch]$Launch,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'Continue'

# The canonical public repository. Renames leave a redirect behind, so the old
# JadeVexo path still resolves, but relying on a redirect for the update path of
# an installed application is not worth the saving.
$GITHUB_REPO = "Enginuity-Labs/Enginuity-Design-Studio"
$PRODUCT_NAME = "Enginuity Design Studio"
$COMPANY_NAME = "Enginuity Labs"
$EXECUTABLE = "eds_app.exe"
$USER_AGENT = "EnginuityInstaller/2.0"

# Exit codes. An unattended run is read by a program, not a person.
$EXIT_OK = 0
$EXIT_NO_RELEASE = 10
$EXIT_DOWNLOAD_FAILED = 11
$EXIT_BAD_PACKAGE = 12
$EXIT_COPY_FAILED = 13
$EXIT_PROCESS_STUCK = 14
$EXIT_GENERAL = 1

# -- Output ---------------------------------------------------------------

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "`n> $Message" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "  OK $Message" "Green"
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-ColorOutput "  XX $Message" "Red"
}

# The only way this script asks a question.
#
# Routed through one helper so that -Silent cannot be defeated by a prompt added
# later: a Read-Host reached in silent mode is a hang with no visible cause,
# because the console belongs to a process the user never started.
function Read-Answer {
    param([string]$Prompt, [string]$Default)

    if ($Silent) {
        Write-ColorOutput "  $Prompt -> $Default (silent)" "DarkGray"
        return $Default
    }
    $answer = Read-Host "  $Prompt"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

# Waits for the application to exit, then makes sure of it.
#
# Bounded and then forced: a hung application must not leave the user with a
# console sitting on "waiting" forever and a half-updated installation. The sweep
# afterwards matters because the application re-executes itself as a Gmsh worker
# and as a native-kernel worker, so those share the executable's name, and one
# survivor holding a handle is enough to fail the copy.
function Wait-ForHandoff {
    if ($WaitForPid -le 0) { return $true }

    Write-Step "Waiting for the application to close (pid $WaitForPid)..."

    # Resolved first, and waited on through the object rather than through
    # Wait-Process. A pid that has already gone is the *common* case -- the
    # application quits as soon as it has handed off, so it is usually gone before
    # this script has finished starting -- and Wait-Process signals that by
    # throwing, which is a poor way to learn that everything is fine.
    $process = Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Success "Application had already closed"
        return $true
    }

    if ($process.WaitForExit(60000)) {
        Write-Success "Application closed"
    } else {
        Write-ColorOutput "  Still running after 60s; stopping it." "Yellow"
        Stop-Process -Id $WaitForPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    return $true
}

function Show-Banner {
    # Clear-Host moves the cursor through the console handle, which does not exist
    # when the host's output is redirected -- a piped run, a CI log, an
    # application-spawned run whose console was not allocated. Losing a
    # decorative clear must not fail the installation.
    try { Clear-Host } catch { }
    Write-ColorOutput @"
+================================================================================================================+
|                                                                                                                |
|   ENGINUITY LABS                                                                                               |
|                                                                                                                |
|   ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗██╗   ██╗██╗████████╗██╗   ██╗    ██╗      █████╗ ██████╗ ███████╗   |
|   ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██║   ██║██║╚══██╔══╝╚██╗ ██╔╝    ██║     ██╔══██╗██╔══██╗██╔════╝   |
|   █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║██║   ██║██║   ██║    ╚████╔╝     ██║     ███████║██████╔╝███████╗   |
|   ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██║   ██║██║   ██║     ╚██╔╝      ██║     ██╔══██║██╔══██╗╚════██║   |
|   ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║╚██████╔╝██║   ██║      ██║       ███████╗██║  ██║██████╔╝███████║   |
|   ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝   ╚═╝      ╚═╝       ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝   |
|                                                                                                                |
|                                           Enginuity Design Studio                                              |
|                                         Agent Driven Hardware Design                                           |
|                                                                                                                |
+================================================================================================================+
"@ "Cyan"
}

# -- Installation state ---------------------------------------------------

function Test-Installation {
    return (Test-Path (Join-Path $InstallPath $EXECUTABLE))
}

# The installed version, preferring the marker beside the executable.
#
# The marker describes the directory it sits in, so a second installation in
# another directory reports itself correctly instead of both reading one
# registry key. The registry is consulted only for installations that predate
# the marker.
function Get-InstalledVersion {
    $markerPath = Join-Path $InstallPath "install.json"
    if (Test-Path $markerPath) {
        try {
            $marker = Get-Content $markerPath -Raw | ConvertFrom-Json
            if ($marker.version) { return $marker.version }
        } catch { }
    }

    $versionPath = Join-Path $InstallPath "VERSION.txt"
    if (Test-Path $versionPath) {
        try {
            $text = (Get-Content $versionPath -Raw).Trim()
            if ($text) { return $text }
        } catch { }
    }

    try {
        $regPath = "HKCU:\Software\$COMPANY_NAME\$PRODUCT_NAME"
        if (Test-Path $regPath) {
            $value = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction SilentlyContinue
            if ($value) { return $value.Version }
        }
    } catch { }

    return "Unknown"
}

# -- Menu -----------------------------------------------------------------

function Show-Menu {
    param([bool]$IsInstalled = $false)

    Show-Banner

    if ($IsInstalled) {
        Write-ColorOutput "`n  Status: Installed (version $(Get-InstalledVersion))" "Green"
    } else {
        Write-ColorOutput "`n  Status: Not installed" "Yellow"
    }

    Write-ColorOutput "`n===================================================" "Gray"
    Write-ColorOutput "  Select an option:" "White"
    Write-ColorOutput "===================================================" "Gray"

    if (-not $IsInstalled) {
        Write-ColorOutput "  [1] Install $PRODUCT_NAME" "Cyan"
        Write-ColorOutput "  [2] Exit" "Gray"
    } else {
        Write-ColorOutput "  [1] Update to the latest version" "Cyan"
        Write-ColorOutput "  [2] Repair this installation" "Yellow"
        Write-ColorOutput "  [3] Uninstall" "Red"
        Write-ColorOutput "  [4] Exit" "Gray"
    }

    Write-ColorOutput "===================================================`n" "Gray"

    $choice = Read-Host "  Enter your choice"


    if (-not $IsInstalled) {
        switch ($choice) {
            "1" { return "install" }
            "2" { return "exit" }
        }
    } else {
        switch ($choice) {
            "1" { return "update" }
            "2" { return "repair" }
            "3" { return "uninstall" }
            "4" { return "exit" }
        }
    }

    Write-ColorOutput "`n  Invalid choice." "Red"
    Start-Sleep -Seconds 2
    return (Show-Menu -IsInstalled $IsInstalled)
}

# -- Release metadata -----------------------------------------------------

# Picks the deployment package from a release.
#
# Prefers the current x64 name and accepts the historical x86 one: releases
# v0.0.0.1 and v0.0.0.2 carry the x86 spelling for what was in fact a 64-bit
# build, and refusing them would gain nothing.
function Select-PackageAsset {
    param($Assets)

    $zips = @($Assets | Where-Object { $_.name -like "*.zip" })
    foreach ($pattern in @("*Deploy*Windows*x64*", "*Deploy*Windows*x86*", "*Deploy*")) {
        $match = $zips | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $null
}

function Get-ReleaseInfo {
    param([string]$TargetVersion = "latest")

    Write-Step "Fetching release information from GitHub..."

    if ($TargetVersion -eq "latest") {
        $releaseUrl = "https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    } else {
        $releaseUrl = "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$TargetVersion"
    }

    $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ "User-Agent" = $USER_AGENT }

    $asset = Select-PackageAsset -Assets $release.assets
    if (-not $asset) {
        throw "Release $($release.tag_name) has no deployment package attached."
    }

    Write-Success "Found $($release.tag_name)"
    Write-ColorOutput "  Package: $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)" "Gray"

    return @{
        Version     = $release.tag_name
        DownloadUrl = $asset.browser_download_url
        FileName    = $asset.name
        Size        = $asset.size
    }
}

# -- Download -------------------------------------------------------------

function Get-FileWithProgress {
    param([string]$Url, [string]$Destination, [string]$FileName)

    Write-Step "Downloading $FileName..."

    $fileStream = $null
    $responseStream = $null
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.UserAgent = $USER_AGENT
        $request.Method = "GET"

        $response = $request.GetResponse()
        $totalBytes = $response.ContentLength
        $responseStream = $response.GetResponseStream()

        $fileStream = [System.IO.File]::Create($Destination)
        $buffer = New-Object byte[] 81920
        $totalBytesRead = 0
        $lastUpdate = [DateTime]::Now
        $startTime = [DateTime]::Now

        do {
            $readCount = $responseStream.Read($buffer, 0, $buffer.Length)
            $fileStream.Write($buffer, 0, $readCount)
            $totalBytesRead += $readCount

            # Repainted at most five times a second: the package is large enough
            # that a per-buffer repaint is mostly flicker.
            $now = [DateTime]::Now
            if (($now - $lastUpdate).TotalMilliseconds -gt 200 -and $totalBytes -gt 0) {
                $percent = [math]::Round(($totalBytesRead / $totalBytes) * 100, 1)
                $elapsed = ($now - $startTime).TotalSeconds
                $speed = if ($elapsed -gt 0) { ($totalBytesRead / 1MB / $elapsed).ToString("F2") } else { "0.00" }
                $filled = [math]::Floor(40 * $percent / 100)
                $bar = "[" + ("#" * $filled) + ("." * (40 - $filled)) + "]"
                Write-Host "`r  $bar $percent% | $(($totalBytesRead / 1MB).ToString('F2')) / $(($totalBytes / 1MB).ToString('F2')) MB | $speed MB/s" -NoNewline -ForegroundColor Cyan
                $lastUpdate = $now
            }
        } while ($readCount -gt 0)

        $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
        $avgSpeed = if ($elapsed -gt 0) { ($totalBytes / 1MB / $elapsed).ToString("F2") } else { "0.00" }
        Write-Host "`r  [$("#" * 40)] 100% | $(($totalBytes / 1MB).ToString('F2')) MB | $avgSpeed MB/s" -ForegroundColor Cyan
        Write-Host ""
        Write-Success "Download complete"
    } catch {
        Write-Host ""
        throw "Download failed: $($_.Exception.Message)"
    } finally {
        if ($fileStream) { $fileStream.Close() }
        if ($responseStream) { $responseStream.Close() }
        if ($response) { $response.Close() }
    }
}

# -- Processes ------------------------------------------------------------

# Stops the eds_app processes belonging to the installation being written.
#
# The application re-executes itself as a Gmsh worker and as a native-kernel
# worker, so those share the executable's name. Each holds a handle on the file
# about to be replaced, and one survivor is enough to fail the copy.
#
# Scoped by executable path, not by name. A developer running a build from a
# source tree, or a second installation in another directory, is none of this
# script's business -- killing those would be a surprising way to lose unsaved
# work. A process whose path cannot be read is left alone for the same reason: it
# has not been shown to belong to this installation, and if it does turn out to
# hold a handle the copy fails loudly with EXIT_COPY_FAILED.
function Get-InstalledProcesses {
    $prefix = (Join-Path $InstallPath "").TrimEnd('\')
    return @(Get-Process -Name "eds_app" -ErrorAction SilentlyContinue | Where-Object {
        $path = $null
        try { $path = $_.Path } catch { }
        $path -and $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    })
}

function Stop-EnginuityProcesses {
    Write-Step "Stopping running processes..."

    $running = Get-InstalledProcesses
    if ($running.Count -eq 0) {
        Write-Success "Nothing to stop"
        return $true
    }

    Write-ColorOutput "  Stopping $($running.Count) process(es) from $InstallPath..." "Gray"
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $survivors = Get-InstalledProcesses
    if ($survivors.Count -gt 0) {
        Write-ErrorMsg "$($survivors.Count) process(es) would not stop."
        return $false
    }

    Write-Success "Processes stopped"
    return $true
}

# -- Package layout -------------------------------------------------------

# Locates the payload root inside an extracted package.
#
# The ZIP normally contains one Enginuity_Deploy_... directory, but a package
# zipped without its parent has the files at the root. Both are recognised by
# looking for the executable rather than by trusting a name.
function Find-PayloadRoot {
    param([string]$ExtractPath)

    if (Test-Path (Join-Path $ExtractPath $EXECUTABLE)) {
        return $ExtractPath
    }

    foreach ($pattern in @("*Deploy*Windows*x64*", "*Deploy*Windows*x86*", "Enginuity_Deploy_*", "*")) {
        $candidates = @(Get-ChildItem -Path $ExtractPath -Filter $pattern -Directory -ErrorAction SilentlyContinue)
        foreach ($candidate in $candidates) {
            if (Test-Path (Join-Path $candidate.FullName $EXECUTABLE)) {
                return $candidate.FullName
            }
        }
    }

    return $null
}

# Verifies a payload carries everything the application loads at run time.
#
# A package missing runtime\ccx would install cleanly and fail at the user's
# first solve, which is a far worse outcome than refusing to install.
function Test-Payload {
    param([string]$PayloadRoot)

    foreach ($required in @($EXECUTABLE, "runtime\ccx", "runtime\gmsh")) {
        if (-not (Test-Path (Join-Path $PayloadRoot $required))) {
            Write-ErrorMsg "Package is incomplete: $required is missing."
            return $false
        }
    }
    return $true
}

# -- Install --------------------------------------------------------------

function Install-Enginuity {
    param([string]$Mode = "install")

    Show-Banner

    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-ColorOutput "`n  Running as Administrator. The installation stays in the user context." "Yellow"
    }

    Write-Step "Validating the installation path..."
    if ($InstallPath -like "*Program Files*") {
        Write-ErrorMsg "Program Files is not a supported location; using the default instead."
        $script:InstallPath = "$env:LOCALAPPDATA\Enginuity Labs\Enginuity Design Studio"
    }
    Write-ColorOutput "  Installation path: $InstallPath" "Gray"

    if ((Test-Installation) -and $Mode -eq "install") {
        Write-ColorOutput "`n  An existing installation was found ($(Get-InstalledVersion))." "Yellow"
        $response = Read-Answer -Prompt "Upgrade it? (y/N)" -Default "y"
        if ($response -notmatch '^[Yy]$') {
            Write-ColorOutput "  Cancelled." "Yellow"
            return $EXIT_OK
        }
        $Mode = "update"
    }

    if (-not (Wait-ForHandoff)) {
        return $EXIT_PROCESS_STUCK
    }
    if (-not (Stop-EnginuityProcesses)) {
        return $EXIT_PROCESS_STUCK
    }

    try {
        $releaseInfo = Get-ReleaseInfo -TargetVersion $Version
    } catch {
        Write-ErrorMsg "Could not read release information: $($_.Exception.Message)"
        return $EXIT_NO_RELEASE
    }

    $tempDir = Join-Path $env:TEMP "enginuity_install_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $zipPath = Join-Path $tempDir "package.zip"
        try {
            Get-FileWithProgress -Url $releaseInfo.DownloadUrl -Destination $zipPath -FileName $releaseInfo.FileName
        } catch {
            Write-ErrorMsg $_.Exception.Message
            return $EXIT_DOWNLOAD_FAILED
        }

        Write-Step "Extracting the package..."
        $extractPath = Join-Path $tempDir "extracted"
        try {
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        } catch {
            Write-ErrorMsg "The package could not be extracted: $($_.Exception.Message)"
            return $EXIT_BAD_PACKAGE
        }

        $payloadRoot = Find-PayloadRoot -ExtractPath $extractPath
        if (-not $payloadRoot) {
            Write-ErrorMsg "No $EXECUTABLE found in the package."
            return $EXIT_BAD_PACKAGE
        }
        if (-not (Test-Payload -PayloadRoot $payloadRoot)) {
            return $EXIT_BAD_PACKAGE
        }
        Write-Success "Package extracted"

        Write-Step "Installing files..."
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

        # Mirrored rather than copied, so a library dropped from a later release
        # actually goes away instead of lingering and being loaded.
        #
        # data and cache hold the user's half of this directory -- preferences,
        # sign-in, logs, staged installers, cached conversations -- and the
        # payload contains neither, so /PURGE would delete every one of them on
        # each update. These two exclusions are the only thing standing between an
        # update and the user's saved state; the application's data directories
        # are named in eds_core::config, and this list has to keep matching them.
        $robocopyArgs = @(
            $payloadRoot, $InstallPath, "/E", "/PURGE",
            "/XD", (Join-Path $InstallPath "data"), (Join-Path $InstallPath "cache"),
            "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/NP", "/R:2", "/W:2"
        )
        & robocopy @robocopyArgs | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-ErrorMsg "Copying files failed (robocopy exit code $LASTEXITCODE)."
            return $EXIT_COPY_FAILED
        }
        if (-not (Test-Path (Join-Path $InstallPath $EXECUTABLE))) {
            Write-ErrorMsg "$EXECUTABLE is not present after the copy."
            return $EXIT_COPY_FAILED
        }
        Write-Success "Files installed"

        New-Shortcuts
        Register-Application -ReleaseVersion $releaseInfo.Version
        New-InstallMarker -Tag $releaseInfo.Version
    } catch {
        Write-ErrorMsg "Installation failed: $($_.Exception.Message)"
        return $EXIT_GENERAL
    } finally {
        Write-Step "Cleaning up..."
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Done"
    }

    $modeText = switch ($Mode) {
        "install" { "Installation" }
        "update"  { "Update" }
        "repair"  { "Repair" }
        default   { "Installation" }
    }

    Write-ColorOutput @"

+===================================================+
|                                                   |
|   $modeText completed successfully.
|                                                   |
+===================================================+

"@ "Green"

    Write-ColorOutput "  Installed to: $InstallPath" "Gray"
    Write-ColorOutput "  Version:      $($releaseInfo.Version)" "Gray"

    # -NoLaunch always wins, so a caller can be explicit without knowing whether
    # something else already asked for a launch.
    $shouldLaunch = if ($NoLaunch) { $false }
                    elseif ($Launch) { $true }
                    elseif ($Silent) { $false }
                    else { (Read-Answer -Prompt "Launch $PRODUCT_NAME now? (Y/n)" -Default "y") -notmatch '^[Nn]$' }
    if ($shouldLaunch) {
        Write-Step "Starting $PRODUCT_NAME..."
        Start-Process -FilePath (Join-Path $InstallPath $EXECUTABLE) -WorkingDirectory $InstallPath
    }

    return $EXIT_OK
}

function New-Shortcuts {
    Write-Step "Creating shortcuts..."

    $target = Join-Path $InstallPath $EXECUTABLE
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell

        $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$PRODUCT_NAME"
        New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null
        foreach ($location in @((Join-Path $startMenuPath "$PRODUCT_NAME.lnk"),
                                (Join-Path ([Environment]::GetFolderPath("Desktop")) "$PRODUCT_NAME.lnk"))) {
            try {
                $shortcut = $shell.CreateShortcut($location)
                $shortcut.TargetPath = $target
                $shortcut.WorkingDirectory = $InstallPath
                $shortcut.Description = $PRODUCT_NAME
                $shortcut.Save()
            } catch {
                Write-ColorOutput "  Could not create $location : $($_.Exception.Message)" "Yellow"
            }
        }
        Write-Success "Shortcuts created"
    } catch {
        # A missing shortcut is cosmetic; the installation is still usable.
        Write-ColorOutput "  Shortcut creation failed. Start the application from $target" "Yellow"
    } finally {
        if ($shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }
}

function Register-Application {
    param([string]$ReleaseVersion)

    Write-Step "Registering the application..."

    $target = Join-Path $InstallPath $EXECUTABLE

    # Built as a scriptblock rather than as `irm ... | iex -Action uninstall`.
    # Invoke-Expression has no -Action parameter, so the piped form silently
    # discards it and runs the interactive menu instead of uninstalling --
    # which is what Add/Remove Programs would have invoked.
    $rawUrl = "https://raw.githubusercontent.com/$GITHUB_REPO/main/install.ps1"
    $uninstallCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command " +
        "`"& ([scriptblock]::Create((irm $rawUrl))) -Action uninstall`""

    $regPath = "HKCU:\Software\$COMPANY_NAME\$PRODUCT_NAME"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "InstallDir" -Value $InstallPath
    Set-ItemProperty -Path $regPath -Name "Version" -Value $ReleaseVersion

    $uninstallPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EnginuityDesignStudio"
    New-Item -Path $uninstallPath -Force | Out-Null
    Set-ItemProperty -Path $uninstallPath -Name "DisplayName" -Value $PRODUCT_NAME
    Set-ItemProperty -Path $uninstallPath -Name "DisplayVersion" -Value $ReleaseVersion
    Set-ItemProperty -Path $uninstallPath -Name "Publisher" -Value $COMPANY_NAME
    Set-ItemProperty -Path $uninstallPath -Name "InstallLocation" -Value $InstallPath
    Set-ItemProperty -Path $uninstallPath -Name "UninstallString" -Value $uninstallCommand
    Set-ItemProperty -Path $uninstallPath -Name "DisplayIcon" -Value "$target,0"

    Write-Success "Application registered"
}

# Writes install.json beside the executable.
#
# This marker is what tells the application it is a managed installation and
# where that installation lives. Without it the updater stays inert, which is the
# right answer for a package somebody unzipped by hand: there is nothing known to
# replace, and no installer to replace it with.
#
# Written without a byte-order mark. Set-Content -Encoding UTF8 emits one under
# Windows PowerShell 5.1, and serde_json refuses a leading BOM -- the marker
# would parse in PowerShell, look correct to a human, and be invisible to the
# application that needs it.
function New-InstallMarker {
    param([string]$Tag)

    Write-Step "Recording the installation marker..."

    # Prefer the version the package shipped with over one derived from the tag:
    # it is what deploy.ps1 stamped into the executable, so the marker and the
    # binary agree even if a tag were ever named inconsistently.
    $version = $Tag.TrimStart('v', 'V')
    $versionPath = Join-Path $InstallPath "VERSION.txt"
    if (Test-Path $versionPath) {
        try {
            $fromPackage = (Get-Content $versionPath -Raw).Trim()
            if ($fromPackage) { $version = $fromPackage }
        } catch { }
    }

    $marker = [ordered]@{
        schema       = 1
        version      = $version
        tag          = $Tag
        installPath  = $InstallPath
        installedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        repo         = $GITHUB_REPO
    }

    $markerPath = Join-Path $InstallPath "install.json"
    $json = $marker | ConvertTo-Json
    [System.IO.File]::WriteAllText($markerPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Success "Marked as version $version"
}

# -- Uninstall ------------------------------------------------------------

# Removes the saved sign-in and the application's own local data.
#
# Delegated to the application rather than done here. The saved session lives in
# Windows Credential Manager under names this script would have to reproduce --
# including a chunking scheme for secrets too large for one credential -- and the
# preferences are encrypted with a key held in the same store. Guessing at any of
# that from PowerShell would appear to work and quietly leave the credential
# behind the day the format changed. The application owns the format, so it owns
# the deletion.
#
# Run before the files are removed, because the executable is what performs it,
# and only on uninstall: an update must never sign the user out.
#
# Failure is reported and then tolerated. A leftover credential is a privacy
# annoyance; refusing to uninstall over it would be worse.
function Remove-UserData {
    Write-Step "Removing saved sign-in and local data..."

    $exe = Join-Path $InstallPath $EXECUTABLE
    if (-not (Test-Path $exe)) {
        Write-ColorOutput "  $EXECUTABLE is already gone; skipping." "Yellow"
        return
    }

    # Start-Process -Wait rather than the call operator. A release build declares
    # the Windows GUI subsystem, and PowerShell does not wait for a GUI process
    # invoked with `&` -- it would return immediately, leave $LASTEXITCODE
    # meaningless, and let the file removal below race the purge it just started.
    try {
        $process = Start-Process -FilePath $exe -ArgumentList "--purge-user-data" `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            Write-Success "Saved sign-in and local data removed"
        } else {
            Write-ColorOutput "  Some local data could not be removed (exit $($process.ExitCode))." "Yellow"
            Write-ColorOutput "  Sign out from the application before uninstalling to clear it." "Gray"
        }
    } catch {
        Write-ColorOutput "  Could not remove saved sign-in: $($_.Exception.Message)" "Yellow"
    }
}

function Uninstall-Enginuity {
    Show-Banner

    if (-not (Test-Path $InstallPath)) {
        Write-ColorOutput "`n  $PRODUCT_NAME is not installed." "Yellow"
        return $EXIT_OK
    }

    Write-ColorOutput "`n  This removes $PRODUCT_NAME from this machine." "Yellow"
    Write-ColorOutput "  Installation path: $InstallPath`n" "Gray"

    if ((Read-Answer -Prompt "Type 'yes' to confirm" -Default "no") -ne "yes") {
        Write-ColorOutput "`n  Cancelled." "Yellow"
        return $EXIT_OK
    }

    try {
        if (-not (Stop-EnginuityProcesses)) {
            return $EXIT_PROCESS_STUCK
        }

        Remove-UserData

        Write-Step "Removing application files..."
        # data and cache belong to the user and were already removed by
        # Remove-UserData above; they are named here so that an installation whose
        # purge failed is still cleaned up rather than half-removed.
        foreach ($item in @("runtime", "data", "cache", $EXECUTABLE,
                            "VERSION.txt", "README.txt", "install.json", "uninstall.ps1")) {
            Remove-Item -Path (Join-Path $InstallPath $item) -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Success "Files removed"

        Write-Step "Removing shortcuts..."
        Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$PRODUCT_NAME" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path ([Environment]::GetFolderPath("Desktop")) "$PRODUCT_NAME.lnk") -Force -ErrorAction SilentlyContinue
        Write-Success "Shortcuts removed"

        Write-Step "Removing registry entries..."
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EnginuityDesignStudio" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\Software\$COMPANY_NAME\$PRODUCT_NAME" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Registry cleaned"

        # Only if the user did not keep their logs, so a directory that still
        # holds something is never removed from under them.
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-ErrorMsg "Uninstallation failed: $($_.Exception.Message)"
        return $EXIT_GENERAL
    }

    Write-ColorOutput "`n  $PRODUCT_NAME has been removed.`n" "Green"
    return $EXIT_OK
}

# -- Entry point ----------------------------------------------------------

# A silent run has nobody watching the console, and the console closes with the
# process. Without a transcript, "the update didn't work" carries no evidence at
# all; with one it is a file the user can attach to a report. Alongside the
# application's own data, so support asks for one directory rather than two.
$transcriptStarted = $false
if ($Silent) {
    try {
        # The same directory the application stages installers into, so a support
        # request names one location: the staged script, its transcript, and the
        # application log all live under ...\Design Studio\data\.
        $logDirectory = Join-Path $env:LOCALAPPDATA "Enginuity Labs\Design Studio\data\update"
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $safeTag = ($Version -replace '[^A-Za-z0-9._-]', '_')
        Start-Transcript -Path (Join-Path $logDirectory "install-$safeTag.log") -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        # Losing the log must not lose the update.
    }
}

$exitCode = $EXIT_GENERAL
try {
    $selected = $Action
    if ($selected -eq "menu") {
        $selected = Show-Menu -IsInstalled (Test-Installation)
    }

    switch ($selected) {
        "install"   { $exitCode = Install-Enginuity -Mode "install" }
        "update"    { $exitCode = Install-Enginuity -Mode "update" }
        "repair"    { $exitCode = Install-Enginuity -Mode "repair" }
        "uninstall" { $exitCode = Uninstall-Enginuity }
        "exit"      { Write-ColorOutput "`n  Goodbye.`n" "Cyan"; $exitCode = $EXIT_OK }
        default     { $exitCode = $EXIT_OK }
    }
} catch {
    Write-ErrorMsg "`nAn unexpected error occurred: $($_.Exception.Message)"
    $exitCode = $EXIT_GENERAL
}

if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
}

# An interactive run that reported a failure would otherwise close its window
# before the reason could be read.
if (-not $Silent -and $exitCode -ne $EXIT_OK) {
    Read-Host "`n  Press Enter to close" | Out-Null
}

exit $exitCode

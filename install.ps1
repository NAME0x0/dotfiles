<#
.SYNOPSIS
    One-shot installer for the komorebi + YASB + Rainmeter + Windhawk desktop.

.DESCRIPTION
    Installs every required package with winget, deploys the configs in this
    repo to the locations each app expects, imports the Windhawk mod list,
    registers the crash-resilient autostart task, and then hands off to
    setup-wizard.ps1 for sizing and positioning.

    Safe to re-run. Every file it replaces is backed up as <name>.bak-<timestamp>.

.PARAMETER InstallRoot
    Where to clone/keep the dotfiles repo. Defaults to the repo you ran this
    from, or C:\Users\<you>\dotfiles when bootstrapped from the web.

.PARAMETER Components
    Subset to install. Default is all of them.
    Valid: komorebi, yasb, autohotkey, rainmeter, windhawk, terminal,
           powershell, flowlauncher, autostart

.PARAMETER SkipPackages
    Deploy configs only. Assumes the apps are already installed.

.PARAMETER NonInteractive
    Take every default, never prompt. Implies -SkipWizard.

.PARAMETER SkipWizard
    Do not launch setup-wizard.ps1 at the end.

.EXAMPLE
    irm https://raw.githubusercontent.com/NAME0x0/dotfiles/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Components komorebi,yasb -SkipPackages
#>

[CmdletBinding()]
param(
    [string]$InstallRoot,

    [ValidateSet('komorebi', 'yasb', 'autohotkey', 'rainmeter', 'windhawk',
                 'terminal', 'powershell', 'flowlauncher', 'autostart')]
    [string[]]$Components = @('komorebi', 'yasb', 'autohotkey', 'rainmeter', 'windhawk',
                              'terminal', 'powershell', 'flowlauncher', 'autostart'),

    [switch]$SkipPackages,
    [switch]$NonInteractive,
    [switch]$SkipWizard
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/NAME0x0/dotfiles.git'

# ----------------------------------------------------------- bootstrapping ---
# When piped from the web ($PSScriptRoot is empty) we have no repo yet, so clone
# one first and re-launch this script from inside it.

if (-not $PSScriptRoot) {
    Write-Host ''
    Write-Host '  dotfiles bootstrap' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host '  git is required to bootstrap. Install it with:' -ForegroundColor Red
        Write-Host '    winget install --id Git.Git -e' -ForegroundColor Yellow
        return
    }

    if (-not $InstallRoot) {
        $suggested = Join-Path $env:USERPROFILE 'dotfiles'
        if (-not $NonInteractive) {
            $answer = Read-Host "  Clone the repo where? [$suggested]"
            $InstallRoot = if ([string]::IsNullOrWhiteSpace($answer)) { $suggested } else { $answer.Trim() }
        } else {
            $InstallRoot = $suggested
        }
    }

    if (Test-Path (Join-Path $InstallRoot '.git')) {
        Write-Host "  updating existing clone at $InstallRoot" -ForegroundColor DarkGray
        git -C $InstallRoot pull --ff-only | Out-Null
    } else {
        Write-Host "  cloning into $InstallRoot" -ForegroundColor DarkGray
        git clone --depth 1 $RepoUrl $InstallRoot
    }

    $forwarded = @{
        InstallRoot = $InstallRoot
        Components  = $Components
    }
    if ($SkipPackages)   { $forwarded.SkipPackages   = $true }
    if ($NonInteractive) { $forwarded.NonInteractive = $true }
    if ($SkipWizard)     { $forwarded.SkipWizard     = $true }

    & (Join-Path $InstallRoot 'install.ps1') @forwarded
    return
}

# ------------------------------------------------------------------- setup ---

$RepoRoot = if ($InstallRoot) { $InstallRoot } else { $PSScriptRoot }
. (Join-Path $RepoRoot 'lib\common.ps1')

if ($NonInteractive) { $SkipWizard = $true }

$ConfigRoot = Join-Path $RepoRoot 'config'
$Documents  = [Environment]::GetFolderPath('MyDocuments')   # honours OneDrive redirection
$DotConfig  = Join-Path $env:USERPROFILE '.config'

Write-Banner 'komorebi + YASB desktop installer' "repo: $RepoRoot"

if (-not (Test-Path $ConfigRoot)) {
    Write-Err "No config folder at $ConfigRoot - is this the dotfiles repo?"
    return
}

Write-Info "components: $($Components -join ', ')"
Write-Info "documents : $Documents"

# ---------------------------------------------------------------- packages ---

$PackageMap = @{
    komorebi     = @(
        @{ Id = 'LGUG2Z.komorebi'; Label = 'komorebi' }
        @{ Id = 'LGUG2Z.whkd';     Label = 'whkd' }
    )
    yasb         = @(
        @{ Id = 'AmN.yasb';                     Label = 'YASB' }
        @{ Id = 'DEVCOM.JetBrainsMonoNerdFont'; Label = 'JetBrainsMono Nerd Font' }
    )
    autohotkey   = @( @{ Id = 'AutoHotkey.AutoHotkey';       Label = 'AutoHotkey v2' } )
    rainmeter    = @( @{ Id = 'Rainmeter.Rainmeter';         Label = 'Rainmeter' } )
    windhawk     = @( @{ Id = 'RamenSoftware.Windhawk';      Label = 'Windhawk' } )
    terminal     = @( @{ Id = 'Microsoft.WindowsTerminal';   Label = 'Windows Terminal' } )
    flowlauncher = @( @{ Id = 'Flow-Launcher.Flow-Launcher'; Label = 'Flow Launcher' } )
}

if (-not $SkipPackages) {
    Write-Step 'Installing packages (winget)'
    foreach ($component in $Components) {
        if (-not $PackageMap.ContainsKey($component)) { continue }
        foreach ($pkg in $PackageMap[$component]) {
            Install-WingetPackage -Id $pkg.Id -Label $pkg.Label -NonInteractive:$NonInteractive | Out-Null
        }
    }
} else {
    Write-Step 'Skipping package installation (-SkipPackages)'
}

# Refresh PATH so komorebic/whkd are callable in this same session.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

# ----------------------------------------------------------------- configs ---

Write-Step 'Stopping running desktop processes'
Stop-DesktopProcesses

if ($Components -contains 'komorebi') {
    Write-Step 'komorebi + whkd'
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'komorebi\komorebi.json') `
                       -Destination (Join-Path $env:USERPROFILE 'komorebi.json') | Out-Null
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'komorebi\komorebi.bar.json') `
                       -Destination (Join-Path $env:USERPROFILE 'komorebi.bar.json') | Out-Null
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'whkd\whkdrc') `
                       -Destination (Join-Path $DotConfig 'whkdrc') | Out-Null

    # komorebi's application-specific rules are upstream data, not ours - fetch fresh.
    if (Test-Command 'komorebic') {
        Write-Info 'fetching application-specific configuration ...'
        try {
            komorebic fetch-asc | Out-Null
            Write-Ok 'applications.json'
        } catch {
            Write-Warn "komorebic fetch-asc failed: $($_.Exception.Message)"
        }
    }
}

if ($Components -contains 'yasb') {
    Write-Step 'YASB'
    Install-ConfigTree -Source (Join-Path $ConfigRoot 'yasb') `
                       -Destination (Join-Path $DotConfig 'yasb') | Out-Null
}

if ($Components -contains 'autohotkey') {
    Write-Step 'AutoHotkey (scroll_focus)'
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'autohotkey\scroll_focus.ahk') `
                       -Destination (Join-Path $DotConfig 'komorebi\scroll_focus.ahk') | Out-Null
}

if ($Components -contains 'terminal') {
    Write-Step 'Windows Terminal'
    $wtState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    if (Test-Path $wtState) {
        Install-ConfigFile -Source (Join-Path $ConfigRoot 'terminal\settings.json') `
                           -Destination (Join-Path $wtState 'settings.json') | Out-Null
    } else {
        Write-Warn 'Windows Terminal state folder not found - launch it once, then re-run.'
    }
}

if ($Components -contains 'powershell') {
    Write-Step 'PowerShell profile + winfetch'
    $psDir = Join-Path $Documents 'WindowsPowerShell'
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'powershell\profile.ps1') `
                       -Destination (Join-Path $psDir 'profile.ps1') | Out-Null
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'powershell\Microsoft.PowerShell_profile.ps1') `
                       -Destination (Join-Path $psDir 'Microsoft.PowerShell_profile.ps1') | Out-Null
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'winfetch\config.ps1') `
                       -Destination (Join-Path $DotConfig 'winfetch\config.ps1') | Out-Null
}

if ($Components -contains 'flowlauncher') {
    Write-Step 'Flow Launcher'
    $flowSettings = Join-Path $env:APPDATA 'FlowLauncher\Settings'
    if (Test-Path (Split-Path $flowSettings -Parent)) {
        Install-ConfigTree -Source (Join-Path $ConfigRoot 'flowlauncher') `
                           -Destination $flowSettings -Merge | Out-Null
    } else {
        Write-Warn 'Flow Launcher profile not found - launch it once, then re-run.'
    }
}

if ($Components -contains 'rainmeter') {
    Write-Step 'Rainmeter skins'
    $skinsDir = Join-Path $Documents 'Rainmeter\Skins'
    Install-ConfigTree -Source (Join-Path $ConfigRoot 'rainmeter\skins') `
                       -Destination $skinsDir -Merge | Out-Null

    # Rainmeter.ini carries window positions; the wizard rescales it afterwards.
    $rmIni = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'rainmeter\Rainmeter.ini') `
                       -Destination $rmIni | Out-Null

    # SkinPath must point at THIS machine's Documents, which may or may not be
    # redirected into OneDrive.
    if (Test-Path $rmIni) {
        $iniText = Get-Content $rmIni -Raw
        $iniText = $iniText -replace '(?m)^SkinPath=.*$', "SkinPath=$skinsDir\"
        Set-Content -Path $rmIni -Value $iniText -Encoding utf8
        Write-Info "SkinPath -> $skinsDir"
    }

    Write-Info 'the Notes skin reads %USERPROFILE%\notes.txt - create your own, none ships here'
    Write-Info 'weather skins ship with placeholder API keys - see README "Weather API keys"'
}

if ($Components -contains 'windhawk') {
    Write-Step 'Windhawk mods'
    $modsFile = Join-Path $ConfigRoot 'windhawk\enabled-mods.json'
    if (-not (Test-Path $modsFile)) {
        Write-Warn 'enabled-mods.json missing, skipped'
    } elseif (-not (Test-Elevated)) {
        Write-Warn 'Windhawk settings live under HKLM and need an elevated shell.'
        Write-Info  'Run this afterwards from an admin PowerShell:'
        Write-Info  "  & '$RepoRoot\install.ps1' -Components windhawk -SkipPackages"
    } else {
        $mods = Get-Content $modsFile -Raw | ConvertFrom-Json
        foreach ($mod in $mods.PSObject.Properties) {
            $key = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$($mod.Name)"
            if (-not (Test-Path $key)) {
                Write-Warn "$($mod.Name) is not installed in Windhawk yet - add it from the Windhawk UI, then re-run"
                continue
            }
            $settingsKey = Join-Path $key 'Settings'
            if (-not (Test-Path $settingsKey)) { New-Item -Path $settingsKey -Force | Out-Null }
            foreach ($setting in $mod.Value.settings.PSObject.Properties) {
                Set-ItemProperty -Path $settingsKey -Name $setting.Name -Value $setting.Value -Force
            }
            Set-ItemProperty -Path $key -Name 'Disabled' -Value 0 -Force -ErrorAction SilentlyContinue
            Write-Ok $mod.Name
        }
        Write-Info 'restart Windhawk (or explorer) for mod settings to take effect'
    }
}

# ------------------------------------------------------------ placeholders ---
# The repo carries __USERPROFILE__ / __USERPROFILE__ instead of a real user
# path so it is portable and leaks no username. Resolve them in what we deployed.

Write-Step 'Resolving user paths in deployed configs'

$deployed = @(
    (Join-Path $env:USERPROFILE 'komorebi.json')
    (Join-Path $DotConfig 'whkdrc')
    (Join-Path $DotConfig 'yasb')
    (Join-Path $DotConfig 'winfetch')
    (Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini')
    (Join-Path $Documents 'Rainmeter\Skins')
    (Join-Path $Documents 'WindowsPowerShell')
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
)

foreach ($target in $deployed) { Expand-UserPlaceholder -Path $target }
Write-Ok 'user paths resolved'

# --------------------------------------------------------------- autostart ---

if ($Components -contains 'autostart') {
    Write-Step 'Autostart (Task Scheduler)'

    $autostartDir = Join-Path $DotConfig 'autostart'
    Install-ConfigFile -Source (Join-Path $ConfigRoot 'autostart\start-desktop.ps1') `
                       -Destination (Join-Path $autostartDir 'start-desktop.ps1') | Out-Null

    # The VBS wrapper hardcodes a path, so write it for this machine rather than copying.
    $vbsPath = Join-Path $autostartDir 'start-desktop.vbs'
    $ps1Path = Join-Path $autostartDir 'start-desktop.ps1'
    $q = [string][char]34   # a literal double quote, kept out of the string literals below
    $vbsLines = @(
        "' Windowless wrapper for start-desktop.ps1. Generated by install.ps1."
        "Set shell = CreateObject(${q}WScript.Shell${q})"
        ("shell.Run ${q}powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
         "-File ${q}${q}${ps1Path}${q}${q}${q}, 0, False")
    )
    Set-Content -Path $vbsPath -Value $vbsLines -Encoding ASCII
    Write-Ok 'start-desktop.vbs'

    $template = Join-Path $ConfigRoot 'autostart\Desktop-WM-Autostart.template.xml'
    if (Test-Path $template) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $xml = (Get-Content $template -Raw).
                    Replace('__USER__', $identity.Name).
                    Replace('__SID__',  $identity.User.Value).
                    Replace('__VBS_PATH__', $vbsPath)

        $tmp = Join-Path $env:TEMP 'Desktop-WM-Autostart.xml'
        [IO.File]::WriteAllText($tmp, $xml, [Text.Encoding]::Unicode)

        schtasks /create /tn 'Desktop WM Autostart' /xml $tmp /f | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'scheduled task "Desktop WM Autostart" (logon + shell-crash triggers)'
        } else {
            Write-Err "task registration failed (schtasks exit $LASTEXITCODE)"
        }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warn 'task template missing, skipped'
    }

    # The Startup folder is what this setup deliberately moves away from.
    foreach ($legacy in @('Komorebi.vbs', 'ScrollFocus.vbs')) {
        $p = Join-Path ([Environment]::GetFolderPath('Startup')) $legacy
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-Info "removed legacy Startup entry: $legacy"
        }
    }
}

# ------------------------------------------------------------------ finish ---

Write-Step 'Starting the desktop'
$launcher = Join-Path $DotConfig 'autostart\start-desktop.vbs'
if (Test-Path $launcher) {
    & "$env:SystemRoot\System32\wscript.exe" $launcher
    Write-Ok 'launched'
} else {
    Write-Warn 'autostart launcher not installed - start komorebi manually with: komorebic start --whkd'
}

if (-not $SkipWizard) {
    $wizard = Join-Path $RepoRoot 'setup-wizard.ps1'
    if (Test-Path $wizard) {
        Write-Step 'Handing off to the setup wizard'
        & $wizard -RepoRoot $RepoRoot
    }
} else {
    Write-Banner 'Install complete.' "Run .\setup-wizard.ps1 when you want to tune sizing and positions."
}

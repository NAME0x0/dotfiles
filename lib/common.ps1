<#
    common.ps1 - shared helpers for install.ps1 and setup-wizard.ps1.

    Dot-source this, do not run it directly:
        . "$PSScriptRoot\lib\common.ps1"
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------- output ----

$script:Palette = @{
    Step = 'Cyan'
    Ok   = 'Green'
    Warn = 'Yellow'
    Err  = 'Red'
    Dim  = 'DarkGray'
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor $script:Palette.Step
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor $script:Palette.Dim
}

function Write-Ok   { param([string]$Message) Write-Host "    [ok]   $Message" -ForegroundColor $script:Palette.Ok }
function Write-Warn { param([string]$Message) Write-Host "    [warn] $Message" -ForegroundColor $script:Palette.Warn }
function Write-Err  { param([string]$Message) Write-Host "    [err]  $Message" -ForegroundColor $script:Palette.Err }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor $script:Palette.Dim }

function Write-Banner {
    param([string]$Title, [string]$Subtitle)
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor White
    if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor $script:Palette.Dim }
    Write-Host ''
}

# ----------------------------------------------------------------- input ----

function Read-YesNo {
    <#  Returns [bool]. In non-interactive mode returns $Default without prompting. #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true,
        [switch]$NonInteractive
    )
    if ($NonInteractive) { return $Default }

    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host "    $Prompt $hint"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch -Regex ($answer.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Warn 'Answer y or n.' }
        }
    }
}

function Read-ValueOrDefault {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Default,
        [switch]$NonInteractive
    )
    if ($NonInteractive) { return $Default }

    $answer = Read-Host "    $Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Read-IntOrDefault {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$Default,
        [int]$Min = [int]::MinValue,
        [int]$Max = [int]::MaxValue,
        [switch]$NonInteractive
    )
    if ($NonInteractive) { return $Default }

    while ($true) {
        $answer = Read-Host "    $Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $parsed = 0
        if ([int]::TryParse($answer.Trim(), [ref]$parsed) -and $parsed -ge $Min -and $parsed -le $Max) {
            return $parsed
        }
        Write-Warn "Enter a whole number between $Min and $Max."
    }
}

# ------------------------------------------------------------ environment ----

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PrimaryScreenBounds {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    return [pscustomobject]@{
        Width  = $screen.Bounds.Width
        Height = $screen.Bounds.Height
    }
}

# ------------------------------------------------------------------ files ----

function Backup-Path {
    <#  Renames an existing file/folder to <name>.bak-<timestamp>. Returns the backup
        path, or $null when there was nothing to back up. #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path.bak-$stamp"
    Move-Item -LiteralPath $Path -Destination $backup -Force
    Write-Info "backed up existing -> $(Split-Path $backup -Leaf)"
    return $backup
}

function Install-ConfigFile {
    <#  Copies Source over Destination, backing up whatever was there. #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$NoBackup
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Warn "missing in repo, skipped: $Source"
        return $false
    }

    $parent = Split-Path $Destination -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not $NoBackup) { Backup-Path -Path $Destination | Out-Null }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Ok (Split-Path $Destination -Leaf)
    return $true
}

function Install-ConfigTree {
    <#  Mirrors a folder from the repo into Destination, backing up the old folder. #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Merge
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Warn "missing in repo, skipped: $Source"
        return $false
    }

    if (-not $Merge) { Backup-Path -Path $Destination | Out-Null }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    Write-Ok (Split-Path $Destination -Leaf)
    return $true
}

# --------------------------------------------------------------- packages ----

function Install-WingetPackage {
    <#  Installs a winget package unless already present. Returns $true on success
        or when the package was already installed. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Label = $Id,
        [switch]$NonInteractive
    )

    if (-not (Test-Command 'winget')) {
        Write-Err 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        return $false
    }

    $installed = winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    if ($installed -match [regex]::Escape($Id)) {
        Write-Ok "$Label (already installed)"
        return $true
    }

    Write-Info "installing $Label ..."
    $wingetArgs = @(
        'install', '--id', $Id, '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    winget @wingetArgs | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Ok $Label
        return $true
    }

    # winget returns non-zero for "already installed" and for reboot-required too.
    $recheck = winget list --id $Id --exact 2>$null | Out-String
    if ($recheck -match [regex]::Escape($Id)) {
        Write-Ok "$Label (installed, winget exit $LASTEXITCODE)"
        return $true
    }

    Write-Err "$Label failed (winget exit $LASTEXITCODE)"
    return $false
}

function Expand-UserPlaceholder {
    <#  Rewrites the __USERPROFILE__ placeholder the repo ships in place of a real
        user path, so the committed configs carry no username and work for anyone.

        How the path is written back depends on the file format:
          *.json / *.yaml / *.yml  ->  backslashes doubled, because those are
                                       string literals and a lone \U is an
                                       invalid escape that breaks the file
          everything else          ->  plain Windows path

        Accepts a file or a folder; folders are processed recursively.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Include = @('*.json', '*.yaml', '*.yml', '*.ini', '*.inc', '*.ps1', '*.vbs', '*.css')
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $bs      = [string][char]92
    $plain   = $env:USERPROFILE                       # C:\Users\name
    $escaped = $plain.Replace($bs, $bs + $bs)         # C:\\Users\\name

    $files = if (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Include $Include
    } else {
        Get-Item -LiteralPath $Path
    }

    $touched = 0
    foreach ($file in $files) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 2) { continue }

        # Preserve the file's encoding AND whether it had a byte-order mark.
        # [Text.Encoding]::UTF8 emits a BOM on write, which breaks strict JSON
        # parsers (and komorebi's config loader), so never use it to write.
        $isUtf16LE = ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
        $isUtf16BE = ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)
        $hasUtf8Bom = ($bytes.Length -ge 3 -and
                       $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

        $readEnc = if ($isUtf16LE) { [Text.Encoding]::Unicode }
                   elseif ($isUtf16BE) { [Text.Encoding]::BigEndianUnicode }
                   else { [Text.Encoding]::UTF8 }

        # GetString keeps the BOM as the first CHARACTER of the decoded string.
        # Writing that back with an encoding that also emits a preamble yields
        # two BOMs, which corrupts the file. Drop it here and let the write
        # encoding put back exactly one.
        $text = $readEnc.GetString($bytes).TrimStart([char]0xFEFF)
        if ($text -notlike '*__USERPROFILE__*') { continue }

        $needsEscaping = $file.Extension -in @('.json', '.yaml', '.yml')
        $replacement   = if ($needsEscaping) { $escaped } else { $plain }

        $text = $text.Replace('__USERPROFILE__', $replacement)

        $writeEnc = if ($isUtf16LE) { New-Object Text.UnicodeEncoding $false, $true }
                    elseif ($isUtf16BE) { New-Object Text.UnicodeEncoding $true, $true }
                    else { New-Object Text.UTF8Encoding $hasUtf8Bom }

        [IO.File]::WriteAllText($file.FullName, $text, $writeEnc)
        $touched++
    }

    if ($touched -gt 0) { Write-Info "resolved user paths in $touched file(s)" }
}

function Stop-DesktopProcesses {
    <#  Stops the window manager stack so configs can be replaced safely. #>
    param([string[]]$Names = @('komorebi', 'whkd', 'yasb', 'AutoHotkey64', 'Rainmeter'))
    foreach ($n in $Names) {
        if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
            Stop-Process -Name $n -Force -ErrorAction SilentlyContinue
            Write-Info "stopped $n"
        }
    }
    Start-Sleep -Seconds 1
}

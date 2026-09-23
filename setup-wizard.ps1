<#
.SYNOPSIS
    Interactive sizing/positioning wizard for the komorebi + YASB desktop.

.DESCRIPTION
    install.ps1 puts the configs in place; this tunes them for the machine
    actually running them. It edits the DEPLOYED configs in your profile, not
    the copies in the repo, so re-running install.ps1 will not clobber your
    answers - and re-running this wizard is always safe.

    It covers:
      * gaps          - komorebi workspace + container padding
      * borders       - width and the accent colour, kept in sync with YASB
      * bar           - YASB bar height and base font size
      * font          - the font family used across the bar
      * rainmeter     - rescales every skin's position for your resolution

.PARAMETER RepoRoot
    Path to the dotfiles repo. Defaults to the folder this script lives in.

.PARAMETER NonInteractive
    Accept every default and apply without prompting.

.PARAMETER SkipRainmeter
    Leave Rainmeter.ini positions alone.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,
    [switch]$NonInteractive,
    [switch]$SkipRainmeter
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'lib\common.ps1')

# The resolution the shipped Rainmeter.ini positions were authored at.
$BaselineWidth  = 1920
$BaselineHeight = 1200

$DotConfig   = Join-Path $env:USERPROFILE '.config'
$KomorebiCfg = Join-Path $env:USERPROFILE 'komorebi.json'
$YasbCfg     = Join-Path $DotConfig 'yasb\config.yaml'
$YasbCss     = Join-Path $DotConfig 'yasb\styles.css'
$RainmeterIni= Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'

Write-Banner 'Quick setup wizard' 'Tunes sizing, colour and positions for this machine.'

# ------------------------------------------------------------- environment ---

Write-Step 'Detecting display'
$screen = Get-PrimaryScreenBounds
Write-Info "primary display : $($screen.Width) x $($screen.Height)"
Write-Info "config baseline : $BaselineWidth x $BaselineHeight"

$scaleX = [math]::Round($screen.Width  / $BaselineWidth,  4)
$scaleY = [math]::Round($screen.Height / $BaselineHeight, 4)
if ($scaleX -ne 1 -or $scaleY -ne 1) {
    Write-Info "scale factor    : x$scaleX horizontally, x$scaleY vertically"
}

# ------------------------------------------------------------------ answers ---

Write-Step 'Layout'
$workspacePadding = Read-IntOrDefault -Prompt 'Outer gap (workspace padding, px)' -Default 8  -Min 0 -Max 64 -NonInteractive:$NonInteractive
$containerPadding = Read-IntOrDefault -Prompt 'Inner gap (container padding, px)' -Default 8  -Min 0 -Max 64 -NonInteractive:$NonInteractive
$borderWidth      = Read-IntOrDefault -Prompt 'Focus border width (px, 0 disables)' -Default 2 -Min 0 -Max 12 -NonInteractive:$NonInteractive

Write-Step 'Appearance'
$accent = Read-ValueOrDefault -Prompt 'Accent colour (hex)' -Default '#FC3D21' -NonInteractive:$NonInteractive
if ($accent -notmatch '^#[0-9A-Fa-f]{6}$') {
    Write-Warn "'$accent' is not a #RRGGBB hex colour - keeping #FC3D21."
    $accent = '#FC3D21'
}
$barHeight = Read-IntOrDefault -Prompt 'Bar height (px)' -Default 40 -Min 20 -Max 96 -NonInteractive:$NonInteractive
$fontSize  = Read-IntOrDefault -Prompt 'Bar base font size (px)' -Default 13 -Min 8 -Max 32 -NonInteractive:$NonInteractive
$fontName  = Read-ValueOrDefault -Prompt 'Bar font family' -Default 'JetBrainsMono NF' -NonInteractive:$NonInteractive

# ----------------------------------------------------------------- komorebi ---

Write-Step 'Applying komorebi settings'

if (-not (Test-Path $KomorebiCfg)) {
    Write-Warn "komorebi.json not found at $KomorebiCfg - run install.ps1 first."
} else {
    Backup-Path -Path $KomorebiCfg | Out-Null
    $backup = Get-ChildItem "$KomorebiCfg.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $json = Get-Content $backup.FullName -Raw | ConvertFrom-Json

    # Placeholder left by the repo copy; point it at this user's profile.
    if ($json.app_specific_configuration_path -like '*__USERPROFILE__*') {
        $json.app_specific_configuration_path =
            $json.app_specific_configuration_path.Replace('__USERPROFILE__', $env:USERPROFILE.Replace('\', '/'))
    }

    $json.default_workspace_padding = $workspacePadding
    $json.default_container_padding = $containerPadding
    $json.border_width              = $borderWidth
    $json.border_enabled            = ($borderWidth -gt 0)
    $json.border_colours.single     = $accent

    $json | ConvertTo-Json -Depth 12 | Set-Content -Path $KomorebiCfg -Encoding utf8
    Write-Ok "gaps $workspacePadding/$containerPadding, border ${borderWidth}px, accent $accent"
}

# --------------------------------------------------------------------- yasb ---

Write-Step 'Applying YASB settings'

if (-not (Test-Path $YasbCfg)) {
    Write-Warn "config.yaml not found at $YasbCfg - run install.ps1 first."
} else {
    Backup-Path -Path $YasbCfg | Out-Null
    $latestCfg = Get-ChildItem "$YasbCfg.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Targeted line edit rather than a YAML round-trip: YASB's config carries
    # comments and ordering that a naive parse-and-rewrite would destroy.
    $lines = Get-Content $latestCfg.FullName
    $inDimensions = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*dimensions:\s*$') { $inDimensions = $true; continue }
        if ($inDimensions) {
            if ($lines[$i] -match '^(\s*)height:\s*\d+\s*$') {
                $lines[$i] = "$($Matches[1])height: $barHeight"
                $inDimensions = $false
            } elseif ($lines[$i] -notmatch '^\s+') {
                $inDimensions = $false
            }
        }
    }
    $lines | Set-Content -Path $YasbCfg -Encoding utf8
    Write-Ok "bar height ${barHeight}px"
}

if (-not (Test-Path $YasbCss)) {
    Write-Warn "styles.css not found at $YasbCss"
} else {
    Backup-Path -Path $YasbCss | Out-Null
    $latestCss = Get-ChildItem "$YasbCss.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $css = Get-Content $latestCss.FullName -Raw
    $css = $css -replace '(--orange:\s*)#[0-9A-Fa-f]{6}', "`${1}$accent"
    $css = $css -replace '(\.yasb-bar\s*\{[^}]*?height:\s*)\d+px', "`${1}${barHeight}px"
    # Only the global rule's size, so per-widget overrides stay intact.
    $css = $css -replace '(?m)(^\*\s*\{[^}]*?font-size:\s*)\d+px', "`${1}${fontSize}px"
    $css = $css -replace '"JetBrainsMono NF"', "`"$fontName`""
    # Centering guard: equal side columns keep the island dead center. Sized from
    # the screen width (logical px - this process is not DPI-aware) minus the bar
    # padding (2 x 15) and room for the island + visualizer (~330).
    $sideWidth = [math]::Max(0, [math]::Floor(($screen.Width - 30 - 330) / 2))
    $css = $css -replace '(\.container-right\s*\{\s*min-width:\s*)\d+px', "`${1}${sideWidth}px"

    Set-Content -Path $YasbCss -Value $css -Encoding utf8 -NoNewline
    Write-Ok "accent $accent, font $fontName ${fontSize}px, side columns ${sideWidth}px"
}

# ---------------------------------------------------------------- rainmeter ---

if (-not $SkipRainmeter) {
    Write-Step 'Rescaling Rainmeter skin positions'

    if (-not (Test-Path $RainmeterIni)) {
        Write-Warn "Rainmeter.ini not found at $RainmeterIni - skipped."
    } elseif ($scaleX -eq 1 -and $scaleY -eq 1) {
        Write-Ok "display matches the baseline, positions left as-is"
    } else {
        $apply = Read-YesNo -Prompt "Rescale skin positions by x$scaleX / x$scaleY?" -Default $true -NonInteractive:$NonInteractive
        if ($apply) {
            Backup-Path -Path $RainmeterIni | Out-Null
            $latestIni = Get-ChildItem "$RainmeterIni.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

            $moved = 0
            $out = foreach ($line in Get-Content $latestIni.FullName) {
                if ($line -match '^(\s*WindowX=)(-?\d+)\s*$') {
                    $moved++
                    "$($Matches[1])$([math]::Round([int]$Matches[2] * $scaleX))"
                } elseif ($line -match '^(\s*WindowY=)(-?\d+)\s*$') {
                    "$($Matches[1])$([math]::Round([int]$Matches[2] * $scaleY))"
                } else {
                    $line
                }
            }
            $out | Set-Content -Path $RainmeterIni -Encoding utf8
            Write-Ok "repositioned $moved skins"
        } else {
            Write-Info 'left unchanged'
        }
    }
}

# ------------------------------------------------------------------ restart ---

Write-Step 'Restarting the desktop'

$restart = Read-YesNo -Prompt 'Restart komorebi, YASB and Rainmeter now?' -Default $true -NonInteractive:$NonInteractive
if ($restart) {
    Stop-DesktopProcesses

    $launcher = Join-Path $DotConfig 'autostart\start-desktop.vbs'
    if (Test-Path $launcher) {
        & "$env:SystemRoot\System32\wscript.exe" $launcher
    } elseif (Test-Command 'komorebic') {
        komorebic start --whkd | Out-Null
    }

    $rainmeter = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'
    if (Test-Path $rainmeter) { Start-Process $rainmeter }

    Start-Sleep -Seconds 6
}

# ------------------------------------------------------------------- verify ---

Write-Step 'Verifying'

$expected = @{
    komorebi     = 'tiling window manager'
    whkd         = 'hotkey daemon'
    yasb         = 'status bar'
    AutoHotkey64 = 'scroll_focus.ahk'
    Rainmeter    = 'desktop widgets'
}

$missing = @()
foreach ($name in $expected.Keys) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
        Write-Ok "$name - $($expected[$name])"
    } else {
        Write-Warn "$name not running - $($expected[$name])"
        $missing += $name
    }
}

if (Test-Command 'komorebic') {
    $check = komorebic check 2>&1 | Out-String
    if ($check -match 'Found komorebi.json') { Write-Ok 'komorebic check passes' }
    else { Write-Warn 'komorebic check reported problems - run it manually' }
}

Write-Host ''
if ($missing.Count -eq 0) {
    Write-Banner 'Setup complete.' 'Alt+H/J/K/L to move focus, Alt+Shift+H/J/K/L to move windows.'
} else {
    Write-Banner 'Setup finished with warnings.' "Not running: $($missing -join ', ')"
    Write-Info 'Check the autostart log:'
    Write-Info '  Get-Content "$env:LOCALAPPDATA\komorebi\autostart.log" -Tail 20'
}

Write-Info "Re-run this wizard any time: .\setup-wizard.ps1"

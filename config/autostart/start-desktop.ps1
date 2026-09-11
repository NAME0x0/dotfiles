<#
    start-desktop.ps1

    Idempotent autostart for the komorebi/YASB desktop.
    Starts komorebi, whkd, YASB and scroll_focus.ahk only if they are not
    already running, so it is safe to invoke repeatedly.

    Invoked by the scheduled task "Desktop WM Autostart" via
    start-desktop.vbs, which triggers at logon and again whenever the
    Explorer shell crashes and is restarted (Winlogon event 1002).

    Replaces the Startup-folder shortcuts Komorebi.vbs / ScrollFocus.vbs,
    which Explorer runs serially and silently abandons if it crashes
    mid-queue.
#>

$ErrorActionPreference = 'SilentlyContinue'

$LogPath = Join-Path $env:LOCALAPPDATA 'komorebi\autostart.log'

function Write-Log([string]$Message) {
    "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message |
        Out-File -FilePath $LogPath -Append -Encoding utf8
}

function Test-ProcessRunning([string]$Name) {
    [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

Write-Log '--- autostart invoked ---'

# komorebi. Started without --whkd so whkd is handled explicitly below;
# letting komorebic spawn it too would race this script into a second instance.
if (Test-ProcessRunning 'komorebi') {
    Write-Log 'komorebi already running'
} else {
    Write-Log 'starting komorebi'
    & "$env:ProgramFiles\komorebi\bin\komorebic.exe" start | Out-Null
}

if (Test-ProcessRunning 'whkd') {
    Write-Log 'whkd already running'
} else {
    Write-Log 'starting whkd'
    Start-Process -FilePath "$env:ProgramFiles\whkd\bin\whkd.exe" -WindowStyle Hidden
}

if (Test-ProcessRunning 'yasb') {
    Write-Log 'yasb already running'
} else {
    Write-Log 'starting yasb'
    Start-Process -FilePath "$env:ProgramFiles\YASB\yasb.exe" -WindowStyle Hidden
}

# Matched on command line rather than process name so that other AutoHotkey v2
# scripts do not count as this one already running.
$scrollFocus = Join-Path $env:USERPROFILE '.config\komorebi\scroll_focus.ahk'
$ahkRunning = Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*scroll_focus.ahk*' }

if ($ahkRunning) {
    Write-Log 'scroll_focus.ahk already running'
} else {
    Write-Log 'starting scroll_focus.ahk'
    Start-Process -FilePath "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey.exe" `
                  -ArgumentList "`"$scrollFocus`"" -WindowStyle Hidden
}

Write-Log '--- autostart done ---'

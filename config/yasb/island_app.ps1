[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# --- detect focused window process -----------------------------------------
if (-not ('Win32_GFW' -as [type])) {
    Add-Type -Namespace Win32 -Name GFW -MemberDefinition @"
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern System.IntPtr GetForegroundWindow();
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern int GetWindowThreadProcessId(System.IntPtr hWnd, out int lpdwProcessId);
"@
}

$procId = 0
$null = [Win32.GFW]::GetWindowThreadProcessId([Win32.GFW]::GetForegroundWindow(), [ref]$procId)
$proc = (Get-Process -Id $procId).ProcessName

# map process name -> Nerd Font glyph
$glyph = switch -Wildcard ($proc) {
    'chrome'              { [char]0xf268 }
    'msedge'              { [char]0xf282 }
    'firefox'             { [char]0xf269 }
    'brave*'              { [char]0xf268 }
    'Code'                { [char]0xe70c }
    'devenv'              { [char]0xe70c }
    'cursor'              { [char]0xe70c }
    'WindowsTerminal'     { [char]0xf489 }
    'pwsh'                { [char]0xf489 }
    'powershell*'         { [char]0xf489 }
    'cmd'                 { [char]0xf489 }
    'explorer'            { [char]0xf07b }
    'Spotify'             { [char]0xf001 }
    'Discord'             { [char]0xf392 }
    'WhatsApp*'           { [char]0xf232 }
    'Telegram*'           { [char]0xf2c6 }
    'Slack'               { [char]0xf198 }
    'Notion*'             { [char]0xe718 }
    'obsidian'            { [char]0xe7ed }
    'figma*'              { [char]0xf306 }
    'steam*'              { [char]0xf1b6 }
    'EpicGamesLauncher'   { [char]0xf1b6 }
    'olk'                 { [char]0xf6ee }
    'OUTLOOK'             { [char]0xf6ee }
    'Teams'               { [char]0xf02d8 }
    'msteams'             { [char]0xf02d8 }
    'WINWORD'             { [char]0xf1c2 }
    'EXCEL'               { [char]0xf1c3 }
    'POWERPNT'            { [char]0xf1c4 }
    'AcroRd32'            { [char]0xf1c1 }
    'Acrobat'             { [char]0xf1c1 }
    'vlc'                 { [char]0xe9be }
    'mpc-hc*'             { [char]0xe9be }
    'zoom'                { [char]0xf03d }
    default               { [char]0xf2db }
}

# --- mode detection --------------------------------------------------------
$mode = 'TIME'

# pomodoro state file (popup writes this)
$pomoFile = Join-Path $env:TEMP 'yasb_pomodoro.json'
$time = $null
if (Test-Path $pomoFile) {
    try {
        $p = Get-Content $pomoFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $endsAt = [datetime]$p.endsAt
        if ((Get-Date) -lt $endsAt) {
            $mode = 'FOCUS'
            $remain = $endsAt - (Get-Date)
            $time = '{0:D2}:{1:D2}' -f [int]$remain.TotalMinutes, $remain.Seconds
        } else {
            Remove-Item $pomoFile -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

# battery low
if ($mode -eq 'TIME') {
    $bat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($bat -and $bat.EstimatedChargeRemaining -lt 20 -and $bat.BatteryStatus -ne 2) {
        $mode = 'ALERT'
    }
}

# media playing detection
if ($mode -eq 'TIME') {
    $mediaProcs = @('Spotify','vlc','AIMP','foobar2000')
    foreach ($m in $mediaProcs) {
        $p = Get-Process -Name $m -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -ne $m }
        if ($p) { $mode = 'NOW'; break }
    }
}

if (-not $time) { $time = (Get-Date).ToString('HH:mm') }

# emit preformatted span string for YASB CustomWidget
# YASB renders <span> via QLabel rich text; HTML escape the quoted mode label
"$glyph `"$mode`" $time"

<#
    island_popup.ps1 - the expanded "dynamic island" panel for the YASB bar.

    Resident: builds its window once, then shows/hides it each time the island is
    clicked. YASB's click runs island_toggle.exe, which signals the named event
    below and exits; paying PowerShell + WPF startup on every click is what made
    the old one-process-per-click popup take about a second.

      -ShowOnStart   show immediately (used when a click finds no resident running)
#>
param([switch]$ShowOnStart, [switch]$ShowShortcuts)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# --- single instance ----------------------------------------------------------
# One resident per session. Starting this script again - the old YASB callback,
# or island_toggle.exe falling back - just toggles the running instance. Kernel
# objects die with their process, so unlike the old lock file there is no stale
# state after a crash and no recycled PID to kill by mistake.
$createdNew = $false
$script:instanceMutex = New-Object System.Threading.Mutex($true, 'Local\YasbIslandResident', [ref]$createdNew)
if (-not $createdNew) {
    $which = if ($ShowShortcuts) { 'Local\YasbShortcutsToggle' } else { 'Local\YasbIslandToggle' }
    try { [void][System.Threading.EventWaitHandle]::OpenExisting($which).Set() } catch {}
    exit
}
# Created now, before the slow startup, so a click during startup is queued
# (auto-reset events stay signalled) rather than lost.
$script:toggleEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\YasbIslandToggle')
$script:sheetEvent  = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\YasbShortcutsToggle')

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Show/hide on each toggle signal. C#, not PowerShell: the wait completes on a
# thread-pool thread, where a PowerShell scriptblock has no runspace to run in,
# so this marshals onto the WPF dispatcher itself.
if (-not ('IslandSignal' -as [type])) {
    Add-Type -ReferencedAssemblies @(
        [System.Windows.Window].Assembly.Location                   # PresentationFramework
        [System.Windows.UIElement].Assembly.Location                # PresentationCore
        [System.Windows.Threading.Dispatcher].Assembly.Location     # WindowsBase
        [System.Reflection.Assembly]::Load('System.Xaml, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089').Location
    ) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;

// Windows Focus Assist ("Do Not Disturb"). Undocumented COM service; the IDs and
// method order come from YASB's own DND widget (src/core/widgets/services/dnd/
// dnd_api.py), where vtable slot 3 reads the profile and slot 4 writes it.
[ComImport, Guid("6BFF4732-81EC-4FFB-AE67-B6C1BC29631F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IQuietHoursSettings {
    [PreserveSig] int GetUserSelectedProfile([MarshalAs(UnmanagedType.LPWStr)] out string profileId);
    [PreserveSig] int SetUserSelectedProfile([MarshalAs(UnmanagedType.LPWStr)] string profileId);
}

public static class IslandSignal {
    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IQuietHoursSettings instance);

    static Guid QuietHoursClsid = new Guid("F53321FA-34F8-4B7F-B9A3-361877CB94CF");
    static Guid QuietHoursIid   = new Guid("6BFF4732-81EC-4FFB-AE67-B6C1BC29631F");
    const uint CLSCTX_LOCAL_SERVER = 4;

    static IQuietHoursSettings QuietHours() {
        IQuietHoursSettings s;
        return CoCreateInstance(ref QuietHoursClsid, IntPtr.Zero, CLSCTX_LOCAL_SERVER, ref QuietHoursIid, out s) == 0 ? s : null;
    }

    // "disabled", "priority", "alarms", or "unknown" if the service is unavailable.
    public static string DndGet() {
        var s = QuietHours();
        if (s == null) return "unknown";
        try {
            string profile;
            if (s.GetUserSelectedProfile(out profile) != 0 || profile == null) return "unknown";
            if (profile.EndsWith(".Unrestricted"))  return "disabled";
            if (profile.EndsWith(".PriorityOnly"))  return "priority";
            if (profile.EndsWith(".AlarmsOnly"))    return "alarms";
            return "unknown";
        } finally { Marshal.ReleaseComObject(s); }
    }

    public static bool DndSet(string mode) {
        string profile =
            mode == "disabled" ? "Microsoft.QuietHoursProfile.Unrestricted" :
            mode == "priority" ? "Microsoft.QuietHoursProfile.PriorityOnly" :
            mode == "alarms"   ? "Microsoft.QuietHoursProfile.AlarmsOnly"   : null;
        if (profile == null) return false;
        var s = QuietHours();
        if (s == null) return false;
        try { return s.SetUserSelectedProfile(profile) == 0; }
        finally { Marshal.ReleaseComObject(s); }
    }

    // Sends a message to an AutoHotkey script's hidden main window and returns its
    // reply, or -1 if the script isn't running or didn't answer within 300 ms.
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l,
        uint flags, uint timeoutMs, out IntPtr result);

    public static int SendToScript(string scriptName, uint msg, int wParam) {
        IntPtr target = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            var cls = new StringBuilder(64); GetClassName(h, cls, 64);
            if (cls.ToString() != "AutoHotkey") return true;
            var title = new StringBuilder(512); GetWindowText(h, title, 512);
            if (title.ToString().IndexOf(scriptName, StringComparison.OrdinalIgnoreCase) < 0) return true;
            target = h; return false;
        }, IntPtr.Zero);
        if (target == IntPtr.Zero) return -1;
        IntPtr reply;
        const uint SMTO_ABORTIFHUNG = 0x0002;
        if (SendMessageTimeout(target, msg, (IntPtr)wParam, IntPtr.Zero, SMTO_ABORTIFHUNG, 300, out reply) == IntPtr.Zero) return -1;
        return (int)reply;
    }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);

    [StructLayout(LayoutKind.Sequential)]
    struct SYSTEM_POWER_STATUS {
        public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
        public int BatteryLifeTime, BatteryFullLifeTime;
    }
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

    public static int ForegroundPid() {
        int pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }

    // Under 20% and not on AC - the rule island_app.ps1 applied through WMI's
    // Win32_Battery, which took 200-450 ms per call; this is a single syscall.
    public static bool BatteryLow() {
        SYSTEM_POWER_STATUS s;
        if (!GetSystemPowerStatus(out s)) return false;
        if (s.BatteryFlag == 128 || s.BatteryLifePercent == 255) return false;   // no battery / unknown
        return s.BatteryLifePercent < 20 && s.ACLineStatus != 1;
    }

    // Set from PowerShell whenever the window hides.
    // Recorded per window (island panel, shortcuts sheet) on every hide.
    static readonly Dictionary<Window, DateTime> lastHidden = new Dictionary<Window, DateTime>();
    // The app that had focus when the island was clicked - what "active task" reports.
    public static int PreviousForeground;

    // Held so they aren't collected: one event + wait registration per window.
    static readonly List<object> keepAlive = new List<object>();

    public static void Listen(string eventName, Window window) {
        var signal = new EventWaitHandle(false, EventResetMode.AutoReset, eventName);
        var registration = ThreadPool.RegisterWaitForSingleObject(signal, delegate {
            window.Dispatcher.BeginInvoke(new Action(delegate { Toggle(window); }));
        }, null, -1, false);
        keepAlive.Add(signal); keepAlive.Add(registration);
        window.IsVisibleChanged += delegate {
            if (!window.IsVisible) lastHidden[window] = DateTime.UtcNow;
        };
    }

    public static void Toggle(Window window) {
        if (window.IsVisible) { window.Hide(); return; }

        // Clicking the bar button while the window is open deactivates the window
        // first, which already hid it. The toggle that click sends means "close",
        // so a signal arriving right after an auto-hide must not reopen it.
        DateTime hidden;
        if (lastHidden.TryGetValue(window, out hidden) &&
            (DateTime.UtcNow - hidden).TotalMilliseconds < 400) return;

        int pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        PreviousForeground = pid;

        window.Show();
        window.Activate();
    }
}
'@
}

# --- helpers ---------------------------------------------------------------
$weatherCache = Join-Path $env:TEMP 'yasb_weather_cache.json'
$pomoFile = Join-Path $env:TEMP 'yasb_pomodoro.json'

function Read-WeatherCache {
    if (Test-Path $weatherCache) {
        try {
            $raw = [System.IO.File]::ReadAllText($weatherCache, [System.Text.Encoding]::UTF8)
            return $raw | ConvertFrom-Json
        } catch {}
    }
    return $null
}

# --- background data gatherer ------------------------------------------------
# Everything slow runs here, on its own runspace: process lookups, network,
# weather, and the one-off C# compile for the native calls. The UI thread only
# copies finished values out of $shared, so the window paints and responds while
# data is still being collected. This used to run on the UI thread - WMI took
# ~3 s on the first pass and ~1.3 s on every 1 s tick, freezing the fade-in and
# every button for as long as the popup was open.
$shared = [hashtable]::Synchronized(@{
    stop = $false; gen = 0; pulse = $null; task = $null; now = $null
    weather = $null; weatherGen = 0; fgPid = 0
    paused = (-not $ShowOnStart)    # idle while the panel is hidden
    wake   = $false                 # set on show: gather now, don't wait out the interval
    # Blocks the paused gatherer in the kernel instead of a polling loop, which
    # cost ~2% of a core just to wait. Set = run, reset = paused.
    resume = New-Object System.Threading.ManualResetEvent([bool]$ShowOnStart)
})

$gatherer = {
    param($shared, $scriptRoot, $fetchWeatherNow, $ownPid)
    $ErrorActionPreference = 'SilentlyContinue'

    if (-not ('IslandNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class IslandNative {
    [StructLayout(LayoutKind.Sequential)]
    struct FILETIME { public uint Low; public uint High; }

    [DllImport("kernel32.dll")]
    static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);

    [StructLayout(LayoutKind.Sequential)]
    class MEMORYSTATUSEX {
        public uint  dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        public uint  dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile;
        public ulong ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll")]
    static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX m);

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);

    static ulong lastIdle, lastTotal;
    static ulong Join(FILETIME f) { return ((ulong)f.High << 32) | f.Low; }

    // Busy CPU % since the previous call. The first call primes the baseline and returns -1.
    public static int CpuPercent() {
        FILETIME i, k, u;
        if (!GetSystemTimes(out i, out k, out u)) return -1;
        ulong idle = Join(i), total = Join(k) + Join(u);   // kernel time already includes idle
        ulong dIdle = idle - lastIdle, dTotal = total - lastTotal;
        bool primed = lastTotal != 0;
        lastIdle = idle; lastTotal = total;
        if (!primed || dTotal == 0) return -1;
        return (int)Math.Round(100.0 * (dTotal - dIdle) / dTotal);
    }

    // { load %, total bytes, available bytes }
    public static ulong[] Memory() {
        var m = new MEMORYSTATUSEX();
        if (!GlobalMemoryStatusEx(m)) return new ulong[] { 0, 0, 0 };
        return new ulong[] { m.dwMemoryLoad, m.ullTotalPhys, m.ullAvailPhys };
    }

    public static int ForegroundPid() {
        int pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }
}
'@
    }

    $null = [IslandNative]::CpuPercent()          # prime the CPU baseline
    Start-Sleep -Milliseconds 250                 # ...so the first reading covers a real interval
    $nextWeather = if ($fetchWeatherNow) { [datetime]::MinValue } else { (Get-Date).AddMinutes(10) }
    $mediaNames  = 'Spotify', 'vlc', 'AIMP', 'foobar2000', 'wmplayer'

    while (-not $shared.stop) {
        if ($shared.paused) { [void]$shared.resume.WaitOne(5000); continue }
        $shared.wake = $false

        # -- system pulse --
        $cpu  = [IslandNative]::CpuPercent(); if ($cpu -lt 0) { $cpu = 0 }
        $mem  = [IslandNative]::Memory()
        $memTotal = [double]$mem[1]; $memUsed = $memTotal - [double]$mem[2]
        $drive = [System.IO.DriveInfo]::new('C')
        $diskTotal = [double]$drive.TotalSize; $diskUsed = $diskTotal - [double]$drive.TotalFreeSpace
        # Prefer the adapter that holds a default gateway - the one actually carrying
        # traffic. Enumeration order is arbitrary: virtual adapters (VirtualBox
        # host-only, Hyper-V switch) are also "Up" and can come first.
        $up = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' -and
                           $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' }
        $nic = $up | Where-Object {
                   $_.GetIPProperties().GatewayAddresses |
                       Where-Object { $_.Address.ToString() -notin '0.0.0.0', '::' }
               } | Select-Object -First 1
        if (-not $nic) { $nic = $up | Select-Object -First 1 }
        $link = if (-not $nic) { '--' }
                elseif ($nic.Speed -ge 1e9) { '{0:0.#} Gbps' -f ($nic.Speed / 1e9) }
                else { '{0:0.#} Mbps' -f ($nic.Speed / 1e6) }

        $shared.pulse = [pscustomobject]@{
            cpuPct      = $cpu
            memPct      = [int]$mem[0]
            memUsed     = [math]::Round($memUsed / 1GB, 1)
            memTotal    = [math]::Round($memTotal / 1GB, 1)
            diskPct     = if ($diskTotal) { [math]::Round($diskUsed / $diskTotal * 100) } else { 0 }
            diskUsedGB  = [math]::Round($diskUsed / 1GB)
            diskTotalGB = [math]::Round($diskTotal / 1GB)
            netName     = if ($nic) { $nic.Name } else { 'OFFLINE' }
            netLink     = $link
        }

        # -- monocle on the focused workspace, for the THEATER toggle --
        $state = (& komorebic.exe state 2>$null) -join "`n" | ConvertFrom-Json
        if ($state) {
            $mon = $state.monitors.elements[$state.monitors.focused]
            $ws  = $mon.workspaces.elements[$mon.workspaces.focused]
            $shared.monocle = ($null -ne $ws.monocle_container)
        }

        # -- active task: whatever was focused, ignoring this popup itself --
        # Prefer the app captured at click time; once the panel is open it is itself
        # the foreground window, so a live lookup would only ever find this process.
        $fg = [IslandSignal]::PreviousForeground
        if (-not $fg) { $fg = [IslandNative]::ForegroundPid() }
        if ($fg -and $fg -ne $ownPid) { $shared.fgPid = $fg }
        $proc = if ($shared.fgPid) { Get-Process -Id $shared.fgPid -ErrorAction SilentlyContinue }
        $up = if ($proc -and $proc.StartTime) {
            $u = (Get-Date) - $proc.StartTime
            '{0:D2}:{1:D2}:{2:D2}' -f [int]$u.TotalHours, $u.Minutes, $u.Seconds
        } else { '--:--:--' }
        $shared.task = [pscustomobject]@{
            pid   = $shared.fgPid
            name  = if ($proc) { $proc.ProcessName } else { '-' }
            title = if ($proc -and $proc.MainWindowTitle) { $proc.MainWindowTitle } else { 'No active window' }
            mem   = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB) } else { 0 }
            up    = $up
        }

        # -- now playing --
        $np = [pscustomobject]@{ source = 'IDLE'; title = 'No media playing' }
        foreach ($mp in $mediaNames) {
            $mproc = Get-Process -Name $mp -ErrorAction SilentlyContinue |
                     Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -ne $mp }
            if ($mproc) { $np = [pscustomobject]@{ source = $mp.ToUpper(); title = $mproc[0].MainWindowTitle }; break }
        }
        $shared.now = $np
        $shared.gen++

        # -- weather: on open only if the cache was empty, then every 10 min --
        if ((Get-Date) -ge $nextWeather) {
            $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'weather.ps1') 2>$null
            if ($out) {
                $raw = if ($out -is [array]) { $out -join '' } else { "$out" }
                $w = $raw | ConvertFrom-Json
                if ($w) { $shared.weather = $w; $shared.weatherGen++ }
            }
            $nextWeather = (Get-Date).AddMinutes(10)
        }

        # 2 s between passes, in short slices so hide/show/stop take effect promptly
        for ($s = 0; $s -lt 20 -and -not ($shared.stop -or $shared.paused -or $shared.wake); $s++) {
            Start-Sleep -Milliseconds 100
        }
    }
}

function Get-Histogram($pct) {
    $blocks = @([char]0x2581,[char]0x2582,[char]0x2583,[char]0x2584,[char]0x2585,[char]0x2586,[char]0x2587,[char]0x2588)
    $idx = [math]::Min(7, [math]::Floor($pct / 12.5))
    $out = ''
    for ($i = 0; $i -lt 8; $i++) {
        $j = [math]::Min(7, [math]::Max(0, $idx - 7 + $i + (Get-Random -Min 0 -Max 2)))
        $out += $blocks[$j]
    }
    $out
}

function Get-StatColor($pct) {
    if ($pct -ge 90) { '#FC3D21' } elseif ($pct -ge 50) { '#D4A04A' } else { '#7A9E7A' }
}

function Get-Pomodoro {
    $active = $false
    $label = '25:00'
    if (Test-Path $pomoFile) {
        try {
            $p = [System.IO.File]::ReadAllText($pomoFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $endsAt = [datetime]$p.endsAt
            if ((Get-Date) -lt $endsAt) {
                $active = $true
                $remain = $endsAt - (Get-Date)
                # Floor, not [int]: [int] rounds, so 24:40 left used to read "25:40".
                $label = '{0:D2}:{1:D2}' -f [int][math]::Floor($remain.TotalMinutes), $remain.Seconds
            } else {
                Remove-Item $pomoFile -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    [pscustomobject]@{ active = $active; label = $label }
}

function Get-Mode($hour) {
    if ($hour -ge 22 -or $hour -lt 6) { return 'REST' }
    if ($hour -lt 9)                   { return 'WAKE' }
    if ($hour -lt 12)                  { return 'DEEP WORK' }
    if ($hour -lt 14)                  { return 'BREAK' }
    if ($hour -lt 17)                  { return 'FOCUS' }
    if ($hour -lt 19)                  { return 'SHIP' }
    'WIND DOWN'
}

# --- initial data (fast paths only) ----------------------------------------
$now = Get-Date
$weather = Read-WeatherCache
$weatherStale = ($null -eq $weather)
if (-not $weather) {
    $weather = [pscustomobject]@{ icon='-'; temp='--'; condition='Loading'; min_temp='--'; max_temp='--'; humidity='--'; location='Detecting'; wind='--' }
}

# Start gathering now so it overlaps the XAML build instead of following it. The
# foreground window at this moment is still the app you clicked away from.
$gatherPs = [powershell]::Create()
$null = $gatherPs.AddScript($gatherer).AddArgument($shared).AddArgument($PSScriptRoot).AddArgument($weatherStale).AddArgument($PID)
$null = $gatherPs.BeginInvoke()

# --- bar label (formerly island_app.ps1) ----------------------------------------
# The island's text on the YASB bar: focused-app glyph, mode, time. Always running,
# whether or not the panel is open. It writes to a file; YASB's poll runs
# "island_toggle.exe --label", which just prints that file. This replaces YASB
# starting cmd.exe -> powershell.exe every 5 s: ~750 ms of CPU each time (it
# recompiled C# and queried WMI on every run), about 15% of one core, all day.
$labelPath = Join-Path $env:TEMP 'yasb_island_label.txt'

$labeler = {
    param($shared, $ownPid, $labelPath)
    $ErrorActionPreference = 'SilentlyContinue'

    function Get-Glyph([string]$name) {
        switch -Wildcard ($name) {
            'chrome'            { return [char]0xf268 }
            'msedge'            { return [char]0xf282 }
            'firefox'           { return [char]0xf269 }
            'brave*'            { return [char]0xf268 }
            'Code'              { return [char]0xe70c }
            'devenv'            { return [char]0xe70c }
            'cursor'            { return [char]0xe70c }
            'WindowsTerminal'   { return [char]0xf489 }
            'pwsh'              { return [char]0xf489 }
            'powershell*'       { return [char]0xf489 }
            'cmd'               { return [char]0xf489 }
            'explorer'          { return [char]0xf07b }
            'Spotify'           { return [char]0xf001 }
            'Discord'           { return [char]0xf392 }
            'WhatsApp*'         { return [char]0xf232 }
            'Telegram*'         { return [char]0xf2c6 }
            'Slack'             { return [char]0xf198 }
            'Notion*'           { return [char]0xe718 }
            'obsidian'          { return [char]0xe7ed }
            'figma*'            { return [char]0xf306 }
            'steam*'            { return [char]0xf1b6 }
            'EpicGamesLauncher' { return [char]0xf1b6 }
            'olk'               { return [char]0xf6ee }
            'OUTLOOK'           { return [char]0xf6ee }
            # U+F02D8 is outside the BMP. The old script cast it with [char], which
            # throws, so Teams silently got no glyph at all.
            'Teams'             { return [char]::ConvertFromUtf32(0xf02d8) }
            'msteams'           { return [char]::ConvertFromUtf32(0xf02d8) }
            'WINWORD'           { return [char]0xf1c2 }
            'EXCEL'             { return [char]0xf1c3 }
            'POWERPNT'          { return [char]0xf1c4 }
            'AcroRd32'          { return [char]0xf1c1 }
            'Acrobat'           { return [char]0xf1c1 }
            'vlc'               { return [char]0xe9be }
            'mpc-hc*'           { return [char]0xe9be }
            'zoom'              { return [char]0xf03d }
        }
        return [char]0xf2db
    }

    $pomoFile   = Join-Path $env:TEMP 'yasb_pomodoro.json'
    $mediaNames = 'Spotify', 'vlc', 'AIMP', 'foobar2000'
    $utf8       = New-Object Text.UTF8Encoding $false     # no BOM: YASB would show it
    $written    = $null
    $tick       = 0
    $batteryLow = $false
    $mediaOn    = $false

    # ---- AI usage (Claude, Codex) for the bar's hover labels ---------------------
    # YASB's usage widgets have fixed one-line tooltips, so the bar pairs each one
    # with a custom label whose hover text is written here. It formats what those
    # widgets already fetched (their caches in %LOCALAPPDATA%\YASB), so nothing here
    # reads credentials. Runs every 30 s; Claude's public status page every 5 min.
    # Non-ASCII goes in as character codes: this file has no BOM, and Windows
    # PowerShell would read a literal middle dot as ANSI mojibake.
    $yasbCache  = Join-Path $env:LOCALAPPDATA 'YASB'
    $aiStatus   = $null
    $aiStatusAt = [datetime]::MinValue
    $dot        = [string][char]0x00B7

    function Format-Left([datetime]$when) {
        $d = $when - (Get-Date)
        if ($d.TotalMinutes -lt 1) { return 'now' }
        if ($d.TotalHours -lt 1)   { return '{0}m' -f $d.Minutes }
        if ($d.TotalHours -lt 24)  { return '{0}h {1:D2}m' -f [int][math]::Floor($d.TotalHours), $d.Minutes }
        return $when.ToString('ddd HH:mm')
    }
    function Format-Tokens($n) {
        $n = [double]$n
        if ($n -ge 1e9) { return '{0:0.0}B' -f ($n / 1e9) }
        if ($n -ge 1e6) { return '{0:0.0}M' -f ($n / 1e6) }
        if ($n -ge 1e3) { return '{0:0.0}K' -f ($n / 1e3) }
        return '{0:0}' -f $n
    }
    # A pie that fills in eighths with usage (Nerd Font circle-slice glyphs).
    function Get-Pie($pct) {
        $pct = [double]$pct
        if ($pct -le 0) { return [char]::ConvertFromUtf32(0xF0766) }
        $i = [int][math]::Min(8, [math]::Max(1, [math]::Ceiling($pct / 12.5)))
        return [char]::ConvertFromUtf32(0xF0A9E + $i - 1)
    }
    function Write-JsonAtomic([string]$path, $obj) {
        $tmp = "$path.tmp"
        [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress), $utf8)
        if (Test-Path $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) }
        else                 { [IO.File]::Move($tmp, $path) }
    }
    function Update-AiStatus {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $r = Invoke-RestMethod 'https://status.claude.com/api/v2/status.json' -TimeoutSec 3
            $script:aiStatus = $r.status.description
        } catch { $script:aiStatus = $null }
    }
    function Update-ClaudeAi {
        $c = [IO.File]::ReadAllText((Join-Path $yasbCache 'claude_usage_cache.json')) | ConvertFrom-Json
        $five  = [double]$c.five
        $seven = [double]$c.seven
        $fiveAt  = [datetimeoffset]::Parse($c.five_reset_iso).LocalDateTime
        $sevenAt = [datetimeoffset]::Parse($c.seven_reset_iso).LocalDateTime
        $lines = @(
            'CLAUDE CODE'
            ''
            ('5-hour   {0,3:0}% used    resets in {1}  (at {2})' -f $five, (Format-Left $fiveAt), $fiveAt.ToString('HH:mm'))
            ('7-day    {0,3:0}% used    resets {1}' -f $seven, $sevenAt.ToString('ddd dd MMM, HH:mm'))
        )
        if ($aiStatus) { $lines += ''; $lines += ('API      {0}' -f $aiStatus) }
        $lines += ('updated  {0}' -f [DateTimeOffset]::FromUnixTimeSeconds([long]$c.fetched_at).LocalDateTime.ToString('HH:mm'))
        if ($c.token_expired) { $lines += ''; $lines += 'Login expired - run claude once to refresh it' }
        $lines += ''
        $lines += 'click the icon for the full breakdown'
        Write-JsonAtomic (Join-Path $env:TEMP 'yasb_ai_claude.json') ([ordered]@{
            # collapsed: name only; click expands to the 5-hour window (7-day is in the tooltip)
            label     = '"CLAUDE"'
            label_alt = '{0} "CLAUDE" {1:0}% {2} {3}' -f (Get-Pie $five), $five, $dot, (Format-Left $fiveAt)
            tooltip   = $lines -join "`n"
        })
    }
    function Update-CodexAi {
        $c = [IO.File]::ReadAllText((Join-Path $yasbCache 'codex_usage_widget_cache.json')) | ConvertFrom-Json
        function Get-WindowName($mins) {
            $mins = [int]$mins
            if ($mins -eq 300)   { return '5-hour' }
            if ($mins -eq 10080) { return 'weekly' }
            if ($mins -ge 1440)  { return '{0}-day' -f [int]($mins / 1440) }
            return '{0}-hour' -f [int]($mins / 60)
        }
        $p = $c.primary; $s = $c.secondary
        $pAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$p.resets_at).LocalDateTime
        $lines = @(
            ('CODEX  {0} {1}' -f $dot, ([string]$c.plan).ToUpper())
            ''
            ('{0,-8} {1,3:0}% used    resets in {2}  (at {3})' -f (Get-WindowName $p.duration_mins), [double]$p.used, (Format-Left $pAt), $pAt.ToString('HH:mm'))
        )
        if ($s) {
            $sAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$s.resets_at).LocalDateTime
            $lines += ('{0,-8} {1,3:0}% used    resets {2}' -f (Get-WindowName $s.duration_mins), [double]$s.used, $sAt.ToString('ddd dd MMM, HH:mm'))
        }
        $t = $c.tokens.periods
        if ($t) {
            $lines += ''
            $lines += ('tokens   today {0}   week {1}   month {2}' -f (Format-Tokens $t.today), (Format-Tokens $t.week), (Format-Tokens $t.month))
        }
        if ($null -ne $c.credits) { $lines += ('credits  {0}' -f $c.credits) }
        $lines += ('updated  {0}' -f [DateTimeOffset]::FromUnixTimeSeconds([long]$c.fetched_at).LocalDateTime.ToString('HH:mm'))
        if ($c.stale) { $lines += ''; $lines += ('showing cached data: {0}' -f $(if ($c.error) { $c.error } else { 'refresh pending' })) }
        $lines += ''
        $lines += 'click the icon for the full breakdown'
        Write-JsonAtomic (Join-Path $env:TEMP 'yasb_ai_codex.json') ([ordered]@{
            label     = '"CODEX"'
            label_alt = '{0} "CODEX" {1:0}% {2} {3}' -f (Get-Pie $p.used), [double]$p.used, $dot, (Format-Left $pAt)
            tooltip   = $lines -join "`n"
        })
    }

    while (-not $shared.stop) {
        try {
            # Focused app. While the panel is open it is the focused window itself,
            # so describe the app behind it instead.
            $fg = [IslandSignal]::ForegroundPid()
            if ($fg -eq $ownPid) { $fg = [IslandSignal]::PreviousForeground }
            $name = try { [Diagnostics.Process]::GetProcessById($fg).ProcessName } catch { '' }
            $glyph = Get-Glyph $name

            # Battery and media every 5 s - the costlier checks, and slow-moving anyway.
            if ($tick % 5 -eq 0) {
                $batteryLow = [IslandSignal]::BatteryLow()
                $mediaOn = $false
                foreach ($p in [Diagnostics.Process]::GetProcesses()) {      # one enumeration, not one per name
                    if ($mediaNames -contains $p.ProcessName -and
                        $p.MainWindowTitle -and $p.MainWindowTitle -ne $p.ProcessName) { $mediaOn = $true; break }
                }
            }
            $tick++

            # AI usage hover labels: every 30 s (offset from the 5 s checks above).
            if ($tick % 30 -eq 2) {
                if ((Get-Date) -ge $aiStatusAt) { Update-AiStatus; $aiStatusAt = (Get-Date).AddMinutes(5) }
                foreach ($job in 'Update-ClaudeAi', 'Update-CodexAi') {
                    try { & $job }
                    catch { try { [IO.File]::WriteAllText((Join-Path $env:TEMP 'yasb_ai.err'), ('{0:u}  {1}: {2}' -f (Get-Date), $job, $_.Exception.Message)) } catch {} }
                }
            }

            $mode = 'TIME'; $time = $null
            if (Test-Path $pomoFile) {
                $pomo = [IO.File]::ReadAllText($pomoFile) | ConvertFrom-Json
                $remain = [datetime]$pomo.endsAt - (Get-Date)
                if ($remain.TotalSeconds -gt 0) {
                    $mode = 'FOCUS'
                    $time = '{0:D2}:{1:D2}' -f [int][math]::Floor($remain.TotalMinutes), $remain.Seconds
                }
            }
            # FOCUS switched DND on for a pomodoro. Whenever that pomodoro stops being
            # active - FOCUS off, the STOP button, or it runs out - switch DND back
            # off. Lives here because this loop runs even while the panel is closed.
            if ($shared.focusOwnsDnd -and $mode -ne 'FOCUS') {
                [void][IslandSignal]::DndSet('disabled')
                $shared.focusOwnsDnd = $false
                [pscustomobject]@{ scroll = [bool]$shared.scroll; focusOwnsDnd = $false } |
                    ConvertTo-Json | Set-Content (Join-Path $env:TEMP 'yasb_toggles.json') -Encoding UTF8
            }

            if ($mode -eq 'TIME' -and $batteryLow) { $mode = 'ALERT' }
            if ($mode -eq 'TIME' -and $mediaOn)    { $mode = 'NOW' }
            if (-not $time) { $time = (Get-Date).ToString('HH:mm') }

            $label = '{0} "{1}" {2}' -f $glyph, $mode, $time

            # Write only on change, atomically: the reader must never catch a half
            # written file. A failed replace (reader holding it) retries next tick.
            if ($label -ne $written) {
                $tmp = "$labelPath.tmp"
                [IO.File]::WriteAllText($tmp, $label, $utf8)
                # [NullString]::Value, not $null: PowerShell turns $null into "" for a .NET
                # string parameter, and Replace rejects "" as an illegal backup path.
                if (Test-Path $labelPath) { [IO.File]::Replace($tmp, $labelPath, [NullString]::Value) }
                else                      { [IO.File]::Move($tmp, $labelPath) }
                $written = $label
            }
        } catch {
            # One bad tick must never end the loop - a frozen label is worse. But leave
            # a trace: a failure here used to be completely silent.
            try { [IO.File]::WriteAllText("$labelPath.err", ('{0:u}  {1}' -f (Get-Date), $_.Exception.Message)) } catch {}
        }
        Start-Sleep -Milliseconds 1000
    }
}

$labelPs = [powershell]::Create()
$null = $labelPs.AddScript($labeler).AddArgument($shared).AddArgument($PID).AddArgument($labelPath)
$null = $labelPs.BeginInvoke()

$weekNum = [System.Globalization.CultureInfo]::InvariantCulture.Calendar.GetWeekOfYear(
    $now, [System.Globalization.CalendarWeekRule]::FirstDay, [System.DayOfWeek]::Monday)
$daysLeft = (New-Object datetime $now.Year, 12, 31).DayOfYear - $now.DayOfYear

# --- build calendar grid cells ---------------------------------------------
$daysHeader = @('MON','TUE','WED','THU','FRI','SAT','SUN')
$firstOfMonth = Get-Date -Year $now.Year -Month $now.Month -Day 1
$firstDow = [int]$firstOfMonth.DayOfWeek
if ($firstDow -eq 0) { $firstDow = 7 }
$daysInMonth = [datetime]::DaysInMonth($now.Year, $now.Month)
$today = $now.Day

$calCells = ''
$col = 0
foreach ($d in $daysHeader) {
    $calCells += "<TextBlock Grid.Row=`"0`" Grid.Column=`"$col`" Text=`"$d`" Foreground=`"#58564f`" FontFamily=`"JetBrainsMono NF`" FontSize=`"9`" FontWeight=`"Bold`" HorizontalAlignment=`"Center`" Margin=`"0,0,0,6`"/>"
    $col++
}
$row = 1
$col = $firstDow - 1
for ($d = 1; $d -le $daysInMonth; $d++) {
    if ($d -eq $today) {
        $calCells += "<Border Grid.Row=`"$row`" Grid.Column=`"$col`" Background=`"#FC3D21`" CornerRadius=`"6`" Margin=`"2`" Width=`"24`" Height=`"22`"><TextBlock Text=`"$d`" Foreground=`"#1c1c1e`" FontFamily=`"JetBrainsMono NF`" FontSize=`"11`" FontWeight=`"Bold`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/></Border>"
    } else {
        $calCells += "<TextBlock Grid.Row=`"$row`" Grid.Column=`"$col`" Text=`"$d`" Foreground=`"#c7c4bf`" FontFamily=`"JetBrainsMono NF`" FontSize=`"11`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`" Margin=`"0,4,0,4`"/>"
    }
    $col++
    if ($col -ge 7) { $col = 0; $row++ }
}

# --- XAML (with x:Name on every dynamic field) ------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="YASB_Island" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="Manual" Opacity="0">
    <Window.Resources>
        <Storyboard x:Key="OpenAnim">
            <DoubleAnimation Storyboard.TargetProperty="Opacity"
                             From="0" To="1" Duration="0:0:0.28">
                <DoubleAnimation.EasingFunction>
                    <CubicEase EasingMode="EaseOut"/>
                </DoubleAnimation.EasingFunction>
            </DoubleAnimation>
            <DoubleAnimation Storyboard.TargetName="RootBorder"
                             Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.Y)"
                             From="-12" To="0" Duration="0:0:0.32">
                <DoubleAnimation.EasingFunction>
                    <CubicEase EasingMode="EaseOut"/>
                </DoubleAnimation.EasingFunction>
            </DoubleAnimation>
            <DoubleAnimation Storyboard.TargetName="RootBorder"
                             Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)"
                             From="0.96" To="1" Duration="0:0:0.32">
                <DoubleAnimation.EasingFunction>
                    <CubicEase EasingMode="EaseOut"/>
                </DoubleAnimation.EasingFunction>
            </DoubleAnimation>
        </Storyboard>
    </Window.Resources>
    <Border x:Name="RootBorder" Background="#1c1c1e" CornerRadius="14" BorderBrush="#2a2a2c"
            BorderThickness="1" Padding="22,18,22,22" MinWidth="780">
        <Border.RenderTransform>
            <TransformGroup>
                <ScaleTransform CenterX="380" CenterY="0" ScaleY="0.96"/>
                <TranslateTransform Y="-12"/>
            </TransformGroup>
        </Border.RenderTransform>
        <StackPanel>

            <!-- HEADER -->
            <DockPanel Margin="0,0,0,16">
                <TextBlock x:Name="CloseBtn" Text="x" DockPanel.Dock="Right"
                           Foreground="#8e8c88" FontFamily="JetBrainsMono NF" FontSize="13"
                           Cursor="Hand" VerticalAlignment="Center" Margin="12,0,0,0"/>
                <TextBlock x:Name="HeaderDateTime" DockPanel.Dock="Right"
                           Foreground="#c7c4bf" FontFamily="JetBrainsMono NF" FontSize="10"
                           FontWeight="Medium" VerticalAlignment="Center"/>
                <TextBlock Text="&quot;DYNAMIC ISLAND&quot;" Foreground="#FC3D21"
                           FontFamily="JetBrainsMono NF" FontSize="11" FontWeight="Bold"
                           VerticalAlignment="Center" Margin="0,0,18,0"/>
            </DockPanel>

            <!-- ROW 1: WEATHER + MODE + WEEK -->
            <Grid Margin="0,0,0,14">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="2*"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Background="#242426" CornerRadius="10" Padding="14,12,14,12">
                    <StackPanel>
                        <TextBlock Text="&quot;WEATHER&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                                   Margin="0,0,0,6"/>
                        <DockPanel>
                            <TextBlock x:Name="WeatherIcon" Foreground="#f0ede8"
                                       FontFamily="JetBrainsMono NF" FontSize="28"
                                       VerticalAlignment="Center" Margin="0,0,12,0"/>
                            <StackPanel>
                                <TextBlock FontFamily="JetBrainsMono NF" FontSize="20" FontWeight="Bold">
                                    <Run x:Name="WeatherTemp" Foreground="#f0ede8"/>
                                    <Run Text="&#176;C" Foreground="#8e8c88"/>
                                </TextBlock>
                                <TextBlock x:Name="WeatherCondition" Foreground="#c7c4bf"
                                           FontFamily="JetBrainsMono NF" FontSize="10" Margin="0,2,0,0"/>
                                <TextBlock x:Name="WeatherDetail" Foreground="#8e8c88"
                                           FontFamily="JetBrainsMono NF" FontSize="9" Margin="0,4,0,0"/>
                            </StackPanel>
                        </DockPanel>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" Background="#242426" CornerRadius="10" Padding="14,12,14,12">
                    <StackPanel>
                        <TextBlock Text="&quot;MODE&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                                   Margin="0,0,0,6"/>
                        <DockPanel>
                            <Ellipse Width="9" Height="9" Fill="#FC3D21" VerticalAlignment="Center"
                                     Margin="0,0,8,0"/>
                            <TextBlock x:Name="ModeLabel" Foreground="#f0ede8" FontFamily="JetBrainsMono NF"
                                       FontSize="16" FontWeight="Bold" VerticalAlignment="Center"/>
                        </DockPanel>
                        <TextBlock Text="ROTATES BY HOUR" Foreground="#58564f"
                                   FontFamily="JetBrainsMono NF" FontSize="8" Margin="0,8,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="4" Background="#242426" CornerRadius="10" Padding="14,12,14,12">
                    <StackPanel>
                        <TextBlock Text="&quot;WEEK&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                                   Margin="0,0,0,6"/>
                        <TextBlock x:Name="WeekLabel" Foreground="#f0ede8" FontFamily="JetBrainsMono NF"
                                   FontSize="20" FontWeight="Bold"/>
                        <TextBlock x:Name="DaysLeftLabel" Foreground="#8e8c88"
                                   FontFamily="JetBrainsMono NF" FontSize="9" Margin="0,4,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- CALENDAR -->
            <Border Background="#242426" CornerRadius="10" Padding="14,12,14,14" Margin="0,0,0,14">
                <StackPanel>
                    <DockPanel Margin="0,0,0,10">
                        <TextBlock Text="&quot;CALENDAR&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"/>
                        <TextBlock Text="$($now.ToString('MMMM yyyy').ToUpper())" Foreground="#c7c4bf"
                                   FontFamily="JetBrainsMono NF" FontSize="10" FontWeight="Medium"
                                   HorizontalAlignment="Right"/>
                    </DockPanel>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition/><RowDefinition/><RowDefinition/>
                            <RowDefinition/><RowDefinition/><RowDefinition/>
                            <RowDefinition/>
                        </Grid.RowDefinitions>
                        $calCells
                    </Grid>
                </StackPanel>
            </Border>

            <!-- SYSTEM PULSE -->
            <Border Background="#242426" CornerRadius="10" Padding="14,12,14,12" Margin="0,0,0,14">
                <StackPanel>
                    <TextBlock Text="&quot;SYSTEM PULSE&quot;" Foreground="#FC3D21"
                               FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                               Margin="0,0,0,8"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0">
                            <TextBlock Text="CPU" Foreground="#8e8c88" FontFamily="JetBrainsMono NF"
                                       FontSize="9" FontWeight="Bold"/>
                            <TextBlock x:Name="CpuHist" FontFamily="JetBrainsMono NF" FontSize="14"
                                       Margin="0,2,0,2"/>
                            <TextBlock FontFamily="JetBrainsMono NF" FontSize="14" FontWeight="Bold">
                                <Run x:Name="CpuPct" Foreground="#f0ede8"/>
                                <Run Text="%" Foreground="#8e8c88"/>
                            </TextBlock>
                        </StackPanel>

                        <StackPanel Grid.Column="1">
                            <TextBlock Text="MEM" Foreground="#8e8c88" FontFamily="JetBrainsMono NF"
                                       FontSize="9" FontWeight="Bold"/>
                            <TextBlock x:Name="MemHist" FontFamily="JetBrainsMono NF" FontSize="14"
                                       Margin="0,2,0,2"/>
                            <TextBlock FontFamily="JetBrainsMono NF" FontSize="14" FontWeight="Bold">
                                <Run x:Name="MemPct" Foreground="#f0ede8"/>
                                <Run Text="%" Foreground="#8e8c88"/>
                                <Run x:Name="MemDetail" Foreground="#58564f" FontSize="9"/>
                            </TextBlock>
                        </StackPanel>

                        <StackPanel Grid.Column="2">
                            <TextBlock Text="DISK C" Foreground="#8e8c88" FontFamily="JetBrainsMono NF"
                                       FontSize="9" FontWeight="Bold"/>
                            <TextBlock x:Name="DiskHist" FontFamily="JetBrainsMono NF" FontSize="14"
                                       Margin="0,2,0,2"/>
                            <TextBlock FontFamily="JetBrainsMono NF" FontSize="14" FontWeight="Bold">
                                <Run x:Name="DiskPct" Foreground="#f0ede8"/>
                                <Run Text="%" Foreground="#8e8c88"/>
                                <Run x:Name="DiskDetail" Foreground="#58564f" FontSize="9"/>
                            </TextBlock>
                        </StackPanel>

                        <StackPanel Grid.Column="3">
                            <TextBlock Text="NET" Foreground="#8e8c88" FontFamily="JetBrainsMono NF"
                                       FontSize="9" FontWeight="Bold"/>
                            <TextBlock Text="$([char]0xeb01)" Foreground="#7A9E7A"
                                       FontFamily="JetBrainsMono NF" FontSize="16" Margin="0,0,0,2"/>
                            <TextBlock x:Name="NetName" Foreground="#f0ede8" FontFamily="JetBrainsMono NF"
                                       FontSize="11" FontWeight="Bold" TextTrimming="CharacterEllipsis"
                                       MaxWidth="160"/>
                            <TextBlock x:Name="NetLink" Foreground="#58564f" FontFamily="JetBrainsMono NF"
                                       FontSize="9" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- NOW PLAYING -->
            <Border Background="#242426" CornerRadius="10" Padding="14,12,14,12" Margin="0,0,0,14">
                <DockPanel>
                    <TextBlock Text="$([char]0xf001)" DockPanel.Dock="Left"
                               Foreground="#FC3D21" FontFamily="JetBrainsMono NF" FontSize="22"
                               VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <StackPanel>
                        <DockPanel>
                            <TextBlock Text="&quot;NOW PLAYING&quot;" Foreground="#FC3D21"
                                       FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"/>
                            <TextBlock x:Name="NowSrc" Foreground="#58564f"
                                       FontFamily="JetBrainsMono NF" FontSize="9"
                                       HorizontalAlignment="Right"/>
                        </DockPanel>
                        <TextBlock x:Name="NowTitle" Foreground="#f0ede8"
                                   FontFamily="JetBrainsMono NF" FontSize="12" FontWeight="Medium"
                                   Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                </DockPanel>
            </Border>

            <!-- ACTIVE TASK -->
            <Border Background="#242426" CornerRadius="10" Padding="14,12,14,12" Margin="0,0,0,14">
                <StackPanel>
                    <DockPanel Margin="0,0,0,4">
                        <TextBlock Text="&quot;ACTIVE TASK&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"/>
                        <TextBlock x:Name="ActPid" Foreground="#58564f"
                                   FontFamily="JetBrainsMono NF" FontSize="9"
                                   HorizontalAlignment="Right"/>
                    </DockPanel>
                    <TextBlock x:Name="ActName" Foreground="#f0ede8"
                               FontFamily="JetBrainsMono NF" FontSize="13" FontWeight="Bold"/>
                    <TextBlock x:Name="ActTitle" Foreground="#c7c4bf"
                               FontFamily="JetBrainsMono NF" FontSize="10" Margin="0,2,0,0"
                               TextTrimming="CharacterEllipsis" MaxWidth="700"/>
                    <TextBlock x:Name="ActMeta" Foreground="#58564f"
                               FontFamily="JetBrainsMono NF" FontSize="9" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>

            <!-- POMODORO + TOGGLES ROW -->
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="2*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Background="#242426" CornerRadius="10" Padding="14,12,14,12">
                    <StackPanel>
                        <TextBlock Text="&quot;POMODORO&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                                   Margin="0,0,0,8"/>
                        <DockPanel>
                            <Border x:Name="PomoBtn" CornerRadius="6"
                                    Padding="10,5,10,5" Cursor="Hand" DockPanel.Dock="Left"
                                    Margin="0,0,12,0">
                                <TextBlock x:Name="PomoBtnText" Foreground="#1c1c1e"
                                           FontFamily="JetBrainsMono NF" FontSize="10"
                                           FontWeight="Bold"/>
                            </Border>
                            <TextBlock x:Name="PomoTime" Foreground="#f0ede8"
                                       FontFamily="JetBrainsMono NF" FontSize="18" FontWeight="Bold"
                                       VerticalAlignment="Center"/>
                        </DockPanel>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" Background="#242426" CornerRadius="10" Padding="14,12,14,12">
                    <StackPanel>
                        <TextBlock Text="&quot;TOGGLES&quot;" Foreground="#FC3D21"
                                   FontFamily="JetBrainsMono NF" FontSize="9" FontWeight="Bold"
                                   Margin="0,0,0,8"/>
                        <WrapPanel>
                            <Border x:Name="TogDND" Background="#1c1c1e" BorderBrush="#3a3a3c"
                                    BorderThickness="1" CornerRadius="6" Padding="10,5,10,5"
                                    Cursor="Hand" Margin="0,0,8,0">
                                <TextBlock Text="DND" Foreground="#c7c4bf"
                                           FontFamily="JetBrainsMono NF" FontSize="10" FontWeight="Bold"/>
                            </Border>
                            <Border x:Name="TogFocus" Background="#1c1c1e" BorderBrush="#3a3a3c"
                                    BorderThickness="1" CornerRadius="6" Padding="10,5,10,5"
                                    Cursor="Hand" Margin="0,0,8,0">
                                <TextBlock Text="FOCUS" Foreground="#c7c4bf"
                                           FontFamily="JetBrainsMono NF" FontSize="10" FontWeight="Bold"/>
                            </Border>
                            <Border x:Name="TogTheater" Background="#1c1c1e" BorderBrush="#3a3a3c"
                                    BorderThickness="1" CornerRadius="6" Padding="10,5,10,5"
                                    Cursor="Hand" Margin="0,0,8,0">
                                <TextBlock Text="THEATER" Foreground="#c7c4bf"
                                           FontFamily="JetBrainsMono NF" FontSize="10" FontWeight="Bold"/>
                            </Border>
                            <Border x:Name="TogScroll" Background="#1c1c1e" BorderBrush="#3a3a3c"
                                    BorderThickness="1" CornerRadius="6" Padding="10,5,10,5"
                                    Cursor="Hand">
                                <TextBlock Text="SCROLL FOCUS" Foreground="#c7c4bf"
                                           FontFamily="JetBrainsMono NF" FontSize="10" FontWeight="Bold"/>
                            </Border>
                        </WrapPanel>
                    </StackPanel>
                </Border>
            </Grid>

        </StackPanel>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# --- look up named elements -------------------------------------------------
$el = @{}
foreach ($n in @('CloseBtn','HeaderDateTime',
                 'WeatherIcon','WeatherTemp','WeatherCondition','WeatherDetail',
                 'ModeLabel','WeekLabel','DaysLeftLabel',
                 'CpuHist','CpuPct','MemHist','MemPct','MemDetail',
                 'DiskHist','DiskPct','DiskDetail','NetName','NetLink',
                 'NowSrc','NowTitle',
                 'ActPid','ActName','ActTitle','ActMeta',
                 'PomoBtn','PomoBtnText','PomoTime',
                 'TogDND','TogFocus','TogTheater','TogScroll')) {
    $el[$n] = $window.FindName($n)
}

# --- update functions -------------------------------------------------------
function Update-Weather($w) {
    $el.WeatherIcon.Text = $w.icon
    $el.WeatherTemp.Text = $w.temp
    $el.WeatherCondition.Text = ($w.condition.ToString().ToUpper())
    $el.WeatherDetail.Text = "$($w.location.ToString().ToUpper()) - H $($w.max_temp)$([char]0xb0) L $($w.min_temp)$([char]0xb0) - $($w.wind) km/h"
}

function Update-Clock {
    # cheap: just clock + countdown — runs at high frequency
    $n = Get-Date
    $el.HeaderDateTime.Text = ($n.ToString('dddd dd MMMM yyyy').ToUpper() + '  ' + $n.ToString('HH:mm:ss'))
    $el.ModeLabel.Text = (Get-Mode $n.Hour)
    $el.WeekLabel.Text = "W$([System.Globalization.CultureInfo]::InvariantCulture.Calendar.GetWeekOfYear($n, [System.Globalization.CalendarWeekRule]::FirstDay, [System.DayOfWeek]::Monday))"
    $dl = (New-Object datetime $n.Year, 12, 31).DayOfYear - $n.DayOfYear
    $el.DaysLeftLabel.Text = "$dl DAYS LEFT"

    $pm = Get-Pomodoro
    $el.PomoTime.Text = $pm.label
    Set-ToggleLook 'TogFocus' $pm.active   # stays right when STOP is used or the timer runs out
    if ($pm.active) {
        $el.PomoBtnText.Text = 'STOP'
        $el.PomoBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC3D21')
    } else {
        $el.PomoBtnText.Text = 'START'
        $el.PomoBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#7A9E7A')
    }
}

$script:appliedGen        = -1
$script:appliedWeatherGen = 0

function Apply-Weather {
    if ($shared.weatherGen -eq $script:appliedWeatherGen) { return }
    $script:appliedWeatherGen = $shared.weatherGen
    Update-Weather $shared.weather
}

function Apply-System {
    # cheap: copies whatever the background gatherer last produced, and only if it's new
    if ($shared.gen -eq $script:appliedGen -or -not $shared.pulse) { return }
    $script:appliedGen = $shared.gen

    Set-ToggleLook 'TogTheater' ([bool]$shared.monocle)

    $sp = $shared.pulse
    $el.CpuHist.Text = (Get-Histogram $sp.cpuPct)
    $el.CpuHist.Foreground = (Get-StatColor $sp.cpuPct)
    $el.CpuPct.Text = "$($sp.cpuPct)"
    $el.MemHist.Text = (Get-Histogram $sp.memPct)
    $el.MemHist.Foreground = (Get-StatColor $sp.memPct)
    $el.MemPct.Text = "$($sp.memPct)"
    $el.MemDetail.Text = "  $($sp.memUsed)/$($sp.memTotal) G"
    $el.DiskHist.Text = (Get-Histogram $sp.diskPct)
    $el.DiskHist.Foreground = (Get-StatColor $sp.diskPct)
    $el.DiskPct.Text = "$($sp.diskPct)"
    $el.DiskDetail.Text = "  $($sp.diskUsedGB)/$($sp.diskTotalGB) G"
    $el.NetName.Text = $sp.netName
    $el.NetLink.Text = $sp.netLink

    $np = $shared.now
    $el.NowSrc.Text = $np.source
    $el.NowTitle.Text = $np.title

    $at = $shared.task
    $el.ActPid.Text = "PID $($at.pid)"
    $el.ActName.Text = $at.name
    $el.ActTitle.Text = $at.title
    $el.ActMeta.Text = "$($at.mem) MB - UPTIME $($at.up)"
}

# --- placeholder paint (cheap only) so window renders instantly ------------
Update-Weather $weather
$el.HeaderDateTime.Text = (Get-Date).ToString('dddd dd MMMM yyyy').ToUpper()
$el.ModeLabel.Text = '...'
$el.WeekLabel.Text = "W$weekNum"
$el.DaysLeftLabel.Text = "$daysLeft DAYS LEFT"
foreach ($k in @('CpuHist','MemHist','DiskHist')) { $el[$k].Text = '........' }
foreach ($k in @('CpuPct','MemPct','DiskPct')) { $el[$k].Text = '--' }
$el.MemDetail.Text = ''
$el.DiskDetail.Text = ''
$el.NetName.Text = '...'
$el.NetLink.Text = ''
$el.NowSrc.Text = '...'; $el.NowTitle.Text = '...'
$el.ActPid.Text = ''; $el.ActName.Text = '...'; $el.ActTitle.Text = ''; $el.ActMeta.Text = ''
$el.PomoTime.Text = '25:00'; $el.PomoBtnText.Text = 'START'
$el.PomoBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#7A9E7A')

# --- wire buttons -----------------------------------------------------------
# Hide rather than close: the process stays resident for the next click.
$el.CloseBtn.Add_MouseLeftButtonUp({ $window.Hide() })
$window.Add_Deactivated({ $window.Hide() })

$el.PomoBtn.Add_MouseLeftButtonUp({
    if (Test-Path $pomoFile) {
        Remove-Item $pomoFile -Force -ErrorAction SilentlyContinue
    } else {
        $endsAt = (Get-Date).AddMinutes(25)
        @{ endsAt = $endsAt.ToString('o') } | ConvertTo-Json | Set-Content $pomoFile -Encoding UTF8
    }
    Update-Clock
})

# --- toggles -------------------------------------------------------------------
# These four buttons used to be decorative: they flipped a value in
# yasb_toggles.json that nothing ever read. Each now drives the real thing, and
# shows the real state each time the panel opens rather than a remembered one.
#
#   DND      Windows Focus Assist, priority only (QuietHours COM - see IslandSignal)
#   FOCUS    a 25-minute pomodoro plus DND; DND goes back off when it ends, however
#            it ends - FOCUS off, the pomodoro STOP button, or simply running out
#   THEATER  komorebi monocle on the focused workspace
#   SCROLL   Alt+Wheel focus scrolling in scroll_focus.ahk; accents unaffected
#
# Only two things are persisted: the scroll setting (scroll_focus.ahk reads it at
# startup) and whether FOCUS is the one that switched DND on.
$togFile = Join-Path $env:TEMP 'yasb_toggles.json'
$shared.scroll = $true
$shared.focusOwnsDnd = $false
if (Test-Path $togFile) {
    try {
        $saved = Get-Content $togFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $saved.scroll)       { $shared.scroll       = [bool]$saved.scroll }
        if ($null -ne $saved.focusOwnsDnd) { $shared.focusOwnsDnd = [bool]$saved.focusOwnsDnd }
    } catch {}
}
function Save-Toggles {
    [pscustomobject]@{ scroll = [bool]$shared.scroll; focusOwnsDnd = [bool]$shared.focusOwnsDnd } |
        ConvertTo-Json | Set-Content $togFile -Encoding UTF8
}

$brushConv  = [System.Windows.Media.BrushConverter]::new()
$togOnBg    = $brushConv.ConvertFromString('#FC3D21'); $togOnFg  = $brushConv.ConvertFromString('#1c1c1e')
$togOffBg   = $brushConv.ConvertFromString('#1c1c1e'); $togOffFg = $brushConv.ConvertFromString('#c7c4bf')
function Set-ToggleLook([string]$name, [bool]$on) {
    $el[$name].Background       = if ($on) { $togOnBg } else { $togOffBg }
    $el[$name].Child.Foreground = if ($on) { $togOnFg } else { $togOffFg }
}

function Test-PomodoroActive {
    if (-not (Test-Path $pomoFile)) { return $false }
    try { return [datetime]((Get-Content $pomoFile -Raw | ConvertFrom-Json).endsAt) -gt (Get-Date) } catch { return $false }
}

function Update-Toggles {
    Set-ToggleLook 'TogDND'     ([IslandSignal]::DndGet() -in 'priority', 'alarms')
    Set-ToggleLook 'TogFocus'   (Test-PomodoroActive)
    Set-ToggleLook 'TogTheater' ([bool]$shared.monocle)
    # Ask the script itself; -1 means it isn't running, so scrolling is off either way.
    $scroll = [IslandSignal]::SendToScript('scroll_focus.ahk', 0x8051, 2)
    Set-ToggleLook 'TogScroll'  ($scroll -eq 101)
}

# One handler per button, attached once. (The old code attached another handler
# on every click, so each click also re-fired all the earlier ones.)
$el.TogDND.Add_MouseLeftButtonUp({
    $on = [IslandSignal]::DndGet() -in 'priority', 'alarms'
    [void][IslandSignal]::DndSet($(if ($on) { 'disabled' } else { 'priority' }))
    if ($on) { $shared.focusOwnsDnd = $false; Save-Toggles }   # switched off by hand - FOCUS no longer owns it
    Update-Toggles
})

$el.TogFocus.Add_MouseLeftButtonUp({
    if (Test-PomodoroActive) {
        Remove-Item $pomoFile -Force -ErrorAction SilentlyContinue
        if ($shared.focusOwnsDnd) { [void][IslandSignal]::DndSet('disabled'); $shared.focusOwnsDnd = $false; Save-Toggles }
    } else {
        @{ endsAt = (Get-Date).AddMinutes(25).ToString('o') } | ConvertTo-Json | Set-Content $pomoFile -Encoding UTF8
        # Only take ownership if DND was off - never switch off a DND you set yourself.
        if ([IslandSignal]::DndGet() -eq 'disabled') {
            [void][IslandSignal]::DndSet('priority'); $shared.focusOwnsDnd = $true; Save-Toggles
        }
    }
    Update-Clock; Update-Toggles
})

$el.TogTheater.Add_MouseLeftButtonUp({
    Start-Process komorebic.exe -ArgumentList 'toggle-monocle' -WindowStyle Hidden
    $shared.monocle = -not $shared.monocle     # optimistic; the next gatherer pass reads the truth
    $shared.wake = $true
    Update-Toggles
})

$el.TogScroll.Add_MouseLeftButtonUp({
    $want  = if ($shared.scroll) { 0 } else { 1 }
    $reply = [IslandSignal]::SendToScript('scroll_focus.ahk', 0x8051, $want)
    if ($reply -ge 100) { $shared.scroll = ($reply -eq 101); Save-Toggles }
    Update-Toggles
})

# --- timers -----------------------------------------------------------------
$clockTimer = New-Object System.Windows.Threading.DispatcherTimer
$clockTimer.Interval = [timespan]::FromMilliseconds(100)
$clockTimer.Add_Tick({ Update-Clock })          # started/stopped with the panel's visibility

# Copies gatherer output onto the UI. Cheap, so it can check often; the data itself
# refreshes every 2 s in the background.
$systemTimer = New-Object System.Windows.Threading.DispatcherTimer
$systemTimer.Interval = [timespan]::FromMilliseconds(250)
$systemTimer.Add_Tick({ Apply-System; Apply-Weather })   # likewise

# --- position ---------------------------------------------------------------
# Centre under the bar. SizeChanged covers the first show, where the width is only
# known after layout; later shows re-centre from the settled width.
function Set-PanelPosition {
    $screen = [System.Windows.SystemParameters]::WorkArea
    if ($window.ActualWidth -gt 0) { $window.Left = ($screen.Width - $window.ActualWidth) / 2 }
    $window.Top = 48
}
$window.Add_SizeChanged({ Set-PanelPosition })

# --- show / hide ------------------------------------------------------------
$openAnim = $window.Resources['OpenAnim']
$window.Add_IsVisibleChanged({
    if ($window.IsVisible) {
        Set-PanelPosition
        $openAnim.Begin($window, $true)                  # controllable, so hide can stop it
        Update-Clock
        Update-Toggles                                   # real DND / scroll / focus state, every open
        Apply-System; Apply-Weather                      # last-known values, instantly
        $clockTimer.Start(); $systemTimer.Start()
        $shared.paused = $false; $shared.wake = $true    # ...and a fresh pass straight away
        [void]$shared.resume.Set()
    } else {
        $clockTimer.Stop(); $systemTimer.Stop()
        $shared.paused = $true
        [void]$shared.resume.Reset()
        $openAnim.Stop($window)                          # drop the held Opacity=1 so the next show fades in
    }
})

$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Hide() } })

# Create the window handle and lay it out now, so a click only has to show it.
[void](New-Object System.Windows.Interop.WindowInteropHelper $window).EnsureHandle()
$window.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
$window.Arrange([System.Windows.Rect]::new($window.DesiredSize))

[IslandSignal]::Listen('Local\YasbIslandToggle', $window)

# --- keybinding cheatsheet ---------------------------------------------------
# The bar's keyboard button. Lives here so a click only shows a window that is
# already built, instead of starting PowerShell and WPF (~1.5 s) every time.
$sheetPath = Join-Path $PSScriptRoot 'shortcuts.xaml'
if (Test-Path $sheetPath) {
    try {
        [xml]$sheetXaml = [System.IO.File]::ReadAllText($sheetPath, [System.Text.Encoding]::UTF8)
        $sheet = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $sheetXaml))
        $sheet.Left = 260
        $sheet.Top  = [System.Windows.SystemParameters]::WorkArea.Top + 8
        $sheet.FindName('CloseBtn').Add_MouseLeftButtonDown({ $sheet.Hide() })
        $sheet.Add_KeyDown({ if ($_.Key -eq 'Escape') { $sheet.Hide() } })
        $sheet.Add_Deactivated({ $sheet.Hide() })
        [void](New-Object System.Windows.Interop.WindowInteropHelper $sheet).EnsureHandle()
        [IslandSignal]::Listen('Local\YasbShortcutsToggle', $sheet)
    } catch {
        [System.IO.File]::WriteAllText((Join-Path $env:TEMP 'yasb_shortcuts.err'), $_.ToString())
    }
}

if ($ShowOnStart) { [IslandSignal]::Toggle($window) }
if ($ShowShortcuts -and $sheet) { [IslandSignal]::Toggle($sheet) }

# Resident: pump messages until the process is ended. Hiding never exits.
[System.Windows.Threading.Dispatcher]::Run()

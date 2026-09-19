<#
    island_popup.ps1 - the expanded "dynamic island" panel for the YASB bar.

    Resident: builds its window once, then shows/hides it each time the island is
    clicked. YASB's click runs island_toggle.exe, which signals the named event
    below and exits; paying PowerShell + WPF startup on every click is what made
    the old one-process-per-click popup take about a second.

      -ShowOnStart   show immediately (used when a click finds no resident running)
#>
param([switch]$ShowOnStart)

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
    try { [void][System.Threading.EventWaitHandle]::OpenExisting('Local\YasbIslandToggle').Set() } catch {}
    exit
}
# Created now, before the slow startup, so a click during startup is queued
# (auto-reset events stay signalled) rather than lost.
$script:toggleEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\YasbIslandToggle')

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
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;

public static class IslandSignal {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);

    // Set from PowerShell whenever the window hides.
    public static DateTime LastHidden = DateTime.MinValue;
    // The app that had focus when the island was clicked - what "active task" reports.
    public static int PreviousForeground;

    static EventWaitHandle toggle;
    static RegisteredWaitHandle registration;   // held so it isn't collected

    public static void Listen(string eventName, Window window) {
        toggle = new EventWaitHandle(false, EventResetMode.AutoReset, eventName);
        registration = ThreadPool.RegisterWaitForSingleObject(toggle, delegate {
            window.Dispatcher.BeginInvoke(new Action(delegate { Toggle(window); }));
        }, null, -1, false);
    }

    public static void Toggle(Window window) {
        if (window.IsVisible) { window.Hide(); return; }

        // Clicking the island while the panel is open deactivates the panel first,
        // which already hid it. The toggle that click sends means "close", so a
        // signal arriving right after an auto-hide must not reopen it.
        if ((DateTime.UtcNow - LastHidden).TotalMilliseconds < 400) return;

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
                $label = '{0:D2}:{1:D2}' -f [int]$remain.TotalMinutes, $remain.Seconds
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

$togFile = Join-Path $env:TEMP 'yasb_toggles.json'
$togState = if (Test-Path $togFile) { Get-Content $togFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{ dnd=$false; focus=$false; theater=$false; scroll=$false } }
function Apply-Toggle($btnName, $key) {
    $btn = $el[$btnName]
    if ($togState.$key) {
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC3D21')
        $btn.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1c1c1e')
    } else {
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1c1c1e')
        $btn.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#c7c4bf')
    }
    $btn.Add_MouseLeftButtonUp({
        $togState.$key = -not $togState.$key
        $togState | ConvertTo-Json | Set-Content $togFile -Encoding UTF8
        Apply-Toggle $btnName $key
    }.GetNewClosure())
}
Apply-Toggle 'TogDND' 'dnd'
Apply-Toggle 'TogFocus' 'focus'
Apply-Toggle 'TogTheater' 'theater'
Apply-Toggle 'TogScroll' 'scroll'

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
        Apply-System; Apply-Weather                      # last-known values, instantly
        $clockTimer.Start(); $systemTimer.Start()
        $shared.paused = $false; $shared.wake = $true    # ...and a fresh pass straight away
        [void]$shared.resume.Set()
    } else {
        $clockTimer.Stop(); $systemTimer.Stop()
        $shared.paused = $true
        [void]$shared.resume.Reset()
        $openAnim.Stop($window)                          # drop the held Opacity=1 so the next show fades in
        [IslandSignal]::LastHidden = [DateTime]::UtcNow
    }
})

$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Hide() } })

# Create the window handle and lay it out now, so a click only has to show it.
[void](New-Object System.Windows.Interop.WindowInteropHelper $window).EnsureHandle()
$window.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
$window.Arrange([System.Windows.Rect]::new($window.DesiredSize))

[IslandSignal]::Listen('Local\YasbIslandToggle', $window)
if ($ShowOnStart) { [IslandSignal]::Toggle($window) }

# Resident: pump messages until the process is ended. Hiding never exits.
[System.Windows.Threading.Dispatcher]::Run()

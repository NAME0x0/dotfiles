[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- single-instance lock ---------------------------------------------------
$lockFile = Join-Path $env:TEMP 'yasb_island.lock'
if (Test-Path $lockFile) {
    try {
        $existingPid = [int](Get-Content $lockFile -ErrorAction Stop)
        Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
    } catch {}
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    exit
}
Set-Content $lockFile $PID

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

function Get-Weather-Sync {
    # synchronous, blocks ~3-5s if cache cold
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\weather.ps1" 2>$null
        if ($out) {
            $raw = if ($out -is [array]) { $out -join '' } else { "$out" }
            return $raw | ConvertFrom-Json
        }
    } catch {}
    return $null
}

function Get-SystemPulse {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $memPct = if ($os) { [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100) } else { 0 }
    $memUsed = if ($os) { [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1) } else { 0 }
    $memTotal = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) } else { 0 }
    $cpuPct = try { [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average) } catch { 0 }
    $disk = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $diskPct = if ($disk) { [math]::Round($disk.Used / ($disk.Used + $disk.Free) * 100) } else { 0 }
    $diskUsedGB = if ($disk) { [math]::Round($disk.Used / 1GB) } else { 0 }
    $diskTotalGB = if ($disk) { [math]::Round(($disk.Used + $disk.Free) / 1GB) } else { 0 }
    $netAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
    $netName = if ($netAdapter) { $netAdapter.Name } else { 'OFFLINE' }
    $netLink = if ($netAdapter) { $netAdapter.LinkSpeed } else { '--' }
    [pscustomobject]@{
        cpuPct = $cpuPct; memPct = $memPct; memUsed = $memUsed; memTotal = $memTotal
        diskPct = $diskPct; diskUsedGB = $diskUsedGB; diskTotalGB = $diskTotalGB
        netName = $netName; netLink = $netLink
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

function Get-ActiveTask {
    if (-not ('Win32_GFW2' -as [type])) {
        Add-Type -Namespace Win32 -Name GFW2 -MemberDefinition @"
            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern System.IntPtr GetForegroundWindow();
            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern int GetWindowThreadProcessId(System.IntPtr hWnd, out int lpdwProcessId);
"@
    }
    $apid = 0
    $null = [Win32.GFW2]::GetWindowThreadProcessId([Win32.GFW2]::GetForegroundWindow(), [ref]$apid)
    $proc = Get-Process -Id $apid -ErrorAction SilentlyContinue
    $name = if ($proc) { $proc.ProcessName } else { '-' }
    $title = if ($proc -and $proc.MainWindowTitle) { $proc.MainWindowTitle } else { 'No active window' }
    $mem = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB) } else { 0 }
    $up = if ($proc) {
        $u = (Get-Date) - $proc.StartTime
        '{0:D2}:{1:D2}:{2:D2}' -f [int]$u.TotalHours, $u.Minutes, $u.Seconds
    } else { '--:--:--' }
    [pscustomobject]@{ pid = $apid; name = $name; title = $title; mem = $mem; up = $up }
}

function Get-NowPlaying {
    foreach ($mp in @('Spotify','vlc','AIMP','foobar2000','wmplayer')) {
        $proc = Get-Process -Name $mp -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -ne $mp }
        if ($proc) { return [pscustomobject]@{ source = $mp.ToUpper(); title = $proc[0].MainWindowTitle } }
    }
    [pscustomobject]@{ source = 'IDLE'; title = 'No media playing' }
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

function Update-System {
    # expensive: WMI/Get-Process — runs at low frequency
    $sp = Get-SystemPulse
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

    $np = Get-NowPlaying
    $el.NowSrc.Text = $np.source
    $el.NowTitle.Text = $np.title

    $at = Get-ActiveTask
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
$el.CloseBtn.Add_MouseLeftButtonUp({ $window.Close() })
$window.Add_Deactivated({ $window.Close() })

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
$clockTimer.Add_Tick({ Update-Clock })
$clockTimer.Start()

$systemTimer = New-Object System.Windows.Threading.DispatcherTimer
$systemTimer.Interval = [timespan]::FromMilliseconds(1000)
$systemTimer.Add_Tick({ Update-System })
$systemTimer.Start()

$weatherTimer = New-Object System.Windows.Threading.DispatcherTimer
$weatherTimer.Interval = [timespan]::FromMinutes(10)
$weatherTimer.Add_Tick({
    $w = Get-Weather-Sync
    if ($w) { Update-Weather $w }
})
$weatherTimer.Start()

# --- position popup ---------------------------------------------------------
$window.Add_SourceInitialized({
    $screen = [System.Windows.SystemParameters]::WorkArea
    $window.Left = ($screen.Width - $window.ActualWidth) / 2
    $window.Top = 48
})

# --- run open animation + first system pulse when window rendered -----------
$window.Add_Loaded({
    $sb = $window.Resources['OpenAnim']
    $sb.Begin($window)
    Update-Clock
    # dispatch system data gather to next idle frame so window paints first
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [Action]{ Update-System }
    ) | Out-Null
    if ($weatherStale) {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action]{
                $w = Get-Weather-Sync
                if ($w) { Update-Weather $w }
            }
        ) | Out-Null
    }
})

$window.Add_KeyDown({
    if ($_.Key -eq 'Escape') { $window.Close() }
})
$window.Add_Closed({
    $clockTimer.Stop()
    $systemTimer.Stop()
    $weatherTimer.Stop()
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
})

[void]$window.ShowDialog()

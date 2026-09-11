[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# --- cache: serve fresh cache (<10 min) without hitting network -----------
$cacheFile = Join-Path $env:TEMP 'yasb_weather_cache.json'
if (Test-Path $cacheFile) {
    $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
    if ($age.TotalMinutes -lt 10) {
        $cached = [System.IO.File]::ReadAllText($cacheFile, [System.Text.Encoding]::UTF8)
        [Console]::Out.Write($cached)
        exit
    }
}

# Fetch IP-based geolocation
try {
    $geo = Invoke-RestMethod -Uri "http://ip-api.com/json/" -TimeoutSec 5
    $lat = $geo.lat
    $lon = $geo.lon
    $city = $geo.city
} catch {
    Write-Output '{"icon":"?","temp":"--","condition":"Offline","min_temp":"--","max_temp":"--","humidity":"--","location":"Unknown","wind":"--"}'
    exit
}

# Fetch weather from Open-Meteo
try {
    $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"
    $w = Invoke-RestMethod -Uri $url -TimeoutSec 5
} catch {
    Write-Output "{`"icon`":`"?`",`"temp`":`"--`",`"condition`":`"Error`",`"min_temp`":`"--`",`"max_temp`":`"--`",`"humidity`":`"--`",`"location`":`"$city`",`"wind`":`"--`"}"
    exit
}

$code = $w.current.weather_code
$temp = [math]::Round($w.current.temperature_2m)
$humidity = $w.current.relative_humidity_2m
$wind = [math]::Round($w.current.wind_speed_10m)
$minTemp = [math]::Round($w.daily.temperature_2m_min[0])
$maxTemp = [math]::Round($w.daily.temperature_2m_max[0])

# WMO weather code to Nerd Font icon + condition
$hour = (Get-Date).Hour
$isNight = ($hour -lt 6 -or $hour -ge 19)

switch ($code) {
    0       { $condition = "Clear";         $ic = if ($isNight) { 0xe37b } else { 0xe30d } }
    1       { $condition = "Mostly Clear";  $ic = if ($isNight) { 0xe37b } else { 0xe30d } }
    2       { $condition = "Partly Cloudy"; $ic = if ($isNight) { 0xe379 } else { 0xe302 } }
    3       { $condition = "Overcast";      $ic = 0xe312 }
    {$_ -in 45,48}    { $condition = "Fog";           $ic = 0xe313 }
    {$_ -in 51,53,55} { $condition = "Drizzle";       $ic = 0xe319 }
    {$_ -in 61,63,65} { $condition = "Rain";          $ic = if ($isNight) { 0xe325 } else { 0xe308 } }
    {$_ -in 66,67}    { $condition = "Freezing Rain"; $ic = 0xe321 }
    {$_ -in 71,73,75,77} { $condition = "Snow";       $ic = 0xe31a }
    {$_ -in 80,81,82} { $condition = "Showers";       $ic = if ($isNight) { 0xe325 } else { 0xe308 } }
    {$_ -in 85,86}    { $condition = "Snow Showers";  $ic = 0xe31a }
    {$_ -in 95,96,99} { $condition = "Thunderstorm";  $ic = 0xe31d }
    default { $condition = "Unknown"; $ic = 0xe374 }
}

$icon = [char]::ConvertFromUtf32($ic)

$json = @{
    icon      = $icon
    temp      = "$temp"
    condition = $condition
    min_temp  = "$minTemp"
    max_temp  = "$maxTemp"
    humidity  = "$humidity"
    location  = $city
    wind      = "$wind"
} | ConvertTo-Json -Compress

# write cache (atomic) + emit
[System.IO.File]::WriteAllText($cacheFile, $json, [System.Text.UTF8Encoding]::new($false))
[Console]::Out.Write($json)

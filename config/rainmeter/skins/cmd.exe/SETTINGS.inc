;Please read the comments carefully!
;IMPORTANT! Choose monitor number below (sorry for the inconvenience)

[Variables]

;===== FULLSCREEN RESOLUTION =====  (IMPORTANT! Please choose monitor number that skin will be on (1-32) by changing the number after the @ symbol ONLY) (eg #WorkAreaWidth@N#)
FullScreen_Width = #WorkAreaWidth@1#
FullScreen_Height = #WorkAreaHeight@1#

;===== MAIN SETTINGS =====  (Change the size of the window. Color and Transparency (0-255) are for the border)(All colors are R,G,B)(Transparency=0 is invisible, 255 is opaque))
Window_Width = 680
Window_Height = 1080

Color = 028,028,030
Transparency = 200

;===== METER STYLE =====  (Title Options: 1 = Title with Outline, 2 = Title Only, 3 = Show Directory Path)(Del_system32_Joke = 1 or 0)
MeterStyle = 2
Del_system32_Joke = 1

FontColor = 185,185,185
ImageColor = 255,255,255

;===== WEATHER =====  (Celcius=m, Fahrenheit=f. Please replace your location code. Go to http://www.weather.com/ to find your code. [http://www.weather.com/weather/today/XXXXXXX].)
WeatherCode = NZXX0006
WeatherUnits = m

;===== MUSIC PLAYER =====  (Edit PlayerLocation and Player to suit your preference. A list of available players: http://docs.rainmeter.net/manual/plugins/nowplaying#playerlist
PlayerLocation = "__USERPROFILE__\AppData\Roaming\Spotify\Spotify.exe"
PlayerName = Spotify

;===== METER ORDER =====  (Choose from CPU, TIME, RAM, SWAP, DISKS, NETWORK, WEATHER, BIN, MUSIC)
Meter1 = CPU
Meter2 = RAM
Meter3 = DISKS
Meter4 = BIN
Meter5 = NETWORK
Meter8 = WEATHER
Meter9 = MUSIC

;=====HARD DRIVES=====
NumberOfDrives = 3
Disk1 = C
Disk2 = D
Disk3 = E
Disk4 = F

;=====FIXES=====
;LAN_IP - Edit if LAN IP is incorrect - Values can be 0, 1, 2, etc.
LAN_IP = 0

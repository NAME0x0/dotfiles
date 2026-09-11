[MeasureDirWeather]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineWeather"][!SetOption MeterTitleWeather StringAlign Left][!SetOption MeterTitleWeather X 0r][!SetOption MeterTitleWeather Y 0r][!SetOption MeterUserNameWeather Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameWeather"][!HideMeter "MeterTitleWeather"][!HideMeter "MeterOutlineWeather"][!SetOption MeterUserNameWeather Y -15r]

[MeasureWeatherRSS]
Measure=Plugin
Plugin=Plugins\WebParser.dll
UpdateRate=3600
Url=http://xml.weather.com/weather/local/#WeatherCode#?cc=*&unit=#WeatherUnits#&dayf=6
RegExp="(?siU)<weather ver="(.*)">(.*)<tmp>(.*)</tmp>(.*)<t>(.*)</t>(.*)<icon>(.*)</icon>(.*)<day d="1" t="(.*)" dt="(.*)">(.*)<hi>(.*)</hi>(.*)<low>(.*)</low>(.*)<icon>(.*)</icon>(.*)<t>(.*)</t>(.*)<day d="2" t="(.*)" dt="(.*)">(.*)<hi>(.*)</hi>(.*)<low>(.*)</low>(.*)<icon>(.*)</icon>(.*)<t>(.*)</t>(.*)<day d="3" t="(.*)" dt="(.*)">(.*)<hi>(.*)</hi>(.*)<low>(.*)</low>(.*)<icon>(.*)</icon>(.*)<t>(.*)</t>(.*)"
StringIndex=1
IfAboveValue=1
IfAboveAction=!execute [!RainmeterHideMeter MeterIconNA][!RainmeterHideMeter MeterIconNA2][!RainmeterShowMeter MeterBGWeather2][!RainmeterShowMeter MeterTemp][!RainmeterShowMeter MeterDesc][!RainmeterShowMeter MeterIconWeather][!RainmeterShowMeter MeterTemp2][!RainmeterShowMeter MeterDesc2][!RainmeterShowMeter MeterIconWeather2]
;Debug=1

[MeasureWeatherTemp]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=3
UpdateDivider=60

[MeasureWeatherDesc]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=5
UpdateDivider=60

[MeasureWeatherIcon]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=7
UpdateDivider=60

;==============

[MeasureWeatherTemp2]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=12

[MeasureWeatherDesc2]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=18

[MeasureWeatherIcon2]
Measure=Plugin
Plugin=Plugins\WebParser.dll
Url=[MeasureWeatherRSS]
StringIndex=16

;=======
;METERS
;=======
[MeterOutlineWeather]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleWeather]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="WEATHER:"

[MeterUserNameWeather]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\WEATHER.ini"
ClipString=1
W=#Width#
H=#FontSize#
Hidden=1

;TODAY============

[MeterDay]
Meter=STRING
MeterStyle=StyleText
X=10
Y=#LineSpace#r
Prefix="  TODAY:"

[MeterIconNA]
Meter=IMAGE
Path=#@#Images
ImageName=na.png
X=15
Y=0R
H=45
ImageTint=#ImageColor#

[MeterIconWeather]
Meter=IMAGE
MeasureName=MeasureWeatherIcon
Path=#@#Images
X=0r
Y=0R
H=45
ImageTint=#ImageColor#
Hidden=1

[MeterDay2]
Meter=STRING
MeterStyle=StyleText
X=10
Y=0R
Prefix="  TOMORROW:"

[MeterIconNA2]
Meter=IMAGE
Path=#@#Images
ImageName=na.png
X=15
Y=0R
H=45
ImageTint=#ImageColor#

[MeterIconWeather2]
Meter=IMAGE
MeasureName=MeasureWeatherIcon2
Path=#@#Images
X=0r
Y=0R
H=45
ImageTint=#ImageColor#
Hidden=1

[MeterTemp]
MeasureName=MeasureWeatherTemp
Meter=STRING
MeterStyle=StyleText
X=70
Y=-77r
Postfix=" °"
Hidden=1

[MeterDesc]
MeasureName=MeasureWeatherDesc
Meter=STRING
MeterStyle=StyleText
X=0R
Y=0r
Hidden=1

[MeterTemp2]
MeasureName=MeasureWeatherTemp2
Meter=STRING
MeterStyle=StyleText
X=98
Y=45R
Postfix=" °"
Hidden=1

[MeterDesc2]
MeasureName=MeasureWeatherDesc2
Meter=STRING
MeterStyle=StyleText
X=0R
Y=0r
Hidden=1

[MeterBGWeather]
Meter=IMAGE
SolidColor=0,0,0,1
X=10
Y=-12r
W=60
H=49

[MeterBGWeather2]
Meter=IMAGE
SolidColor=0,0,0,1
X=10
Y=0R
W=60
H=29
Hidden=1
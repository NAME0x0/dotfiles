[MeasureDirNetwork]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineNetwork"][!SetOption MeterTitleNetwork StringAlign Left][!SetOption MeterTitleNetwork X 0r][!SetOption MeterTitleNetwork Y 0r][!SetOption MeterUserNameNetwork Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameNetwork"][!HideMeter "MeterTitleNetwork"][!HideMeter "MeterOutlineNetwork"][!SetOption MeterUserNameNetwork Y -15r]

[MeasureIP]
Measure=Plugin
Plugin=WebParser.dll
Url=http://checkip.dyndns.org
UpdateRate=14400
RegExp="(?siU)Address: (.*)</body>"
StringIndex=1
FinishAction=!execute [!RainmeterShowMeter MeterIPText][!RainmeterShowMeter MeterIP]

[MeasureLAN]
Measure=Plugin
Plugin=Plugins\SysInfo.dll
SysInfoType=IP_ADDRESS
SysInfoData=#LAN_IP#
UpdateRate=14400

[MeasureUpload]
Measure=NetOut
NetOutSpeed=10485760

[MeasureDownload]
Measure=NetIn
NetInSpeed=10485760

;========
;METERS
;========
[MeterOutlineNetwork]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleNetwork]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="NETWORK:"

[MeterUserNameNetwork]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUserName
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\NET.ini"
ClipString=1
W=#Width#
H=#FontSize#
Hidden=1

[MeterLANText]
Meter=String
MeterStyle=StyleText
X=0r
Y=#LineSpace#r
Text="  LAN IP:"
LeftMouseUpAction=[Shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}]

[MeterLAN]
Meter=String
MeasureName=MeasureLAN
MeterStyle=StyleText
X=0R
Y=0r
LeftMouseUpAction=[!SetClip [MeasureLAN]]

[MeterIPText]
Meter=String
MeterStyle=StyleText
X=150r
Y=0r
Text="IP:"
Hidden=1
LeftMouseUpAction=[Shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}]

[MeterIP]
Meter=String
MeasureName=MeasureIP
MeterStyle=StyleText
X=0R
Y=0r
Hidden=1
ClipString=1
W=(#Width#-235)
H=(#FontSize#+2)
LeftMouseUpAction=[!SetClip [MeasureIP]]

[MeterUpload]
Meter=String
MeterStyle=StyleText
MeasureName=MeasureUpload
X=10
Y=#LineSpace#r
NumOfDecimals=2
AutoScale=0
Scale=1000000.00
Text="  UPLOAD:	         %1 MB/s"
Hidden=1

[MeterDownload]
Meter=String
MeterStyle=StyleText
MeasureName=MeasureDownload
X=0r
Y=#LineSpace#r
NumOfDecimals=2
AutoScale=0
Scale=1000000.00
Text="  DOWNLOAD:    %1 MB/s"
Hidden=1
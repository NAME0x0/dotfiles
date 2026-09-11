[MeasureDirCPU]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineCPU"][!SetOption MeterTitleCPU StringAlign Left][!SetOption MeterTitleCPU X 0r][!SetOption MeterTitleCPU Y 0r][!SetOption MeterUserNameCPU Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameCPU"][!HideMeter "MeterTitleCPU"][!HideMeter "MeterOutlineCPU"][!SetOption MeterUserNameCPU Y -15r]

[MeasureCPU]
Measure=CPU
UpdateDivider=2

[MeasureRoundCPU]
Measure=Calc
Formula=((ROUND((MeasureCPU)/(5)))*(5))/100
UpdateDivider=2

[MeasureNameCPU]
Measure=Registry
RegHKey=HKEY_LOCAL_MACHINE
RegKey=HARDWARE\DESCRIPTION\System\CentralProcessor\0
RegValue=ProcessorNameString
UpdateDivider=86400

[MeasureSpeedCPU]
Measure=Plugin
Plugin=Plugins\PowerPlugin.dll
PowerState=MHZ
UpdateDivider=4

;=======
;METERS
;=======
[MeterOutlineCPU]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleCPU]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="PROCESSOR:"

[MeterUserNameCPU]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\CPU.ini"
ClipString=1
W=#Width#
H=(#FontSize#+2)
Hidden=1

[MeterNameCPU]
Meter=STRING
MeterStyle=StyleText
MeasureName=measureNameCPU
X=0r
Y=#LineSpace#r
Text="  %1"
ClipString=1
W=#Width#
H=(#FontSize#+2)

[MeterSpeedCPU]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureSpeedCPU
MeasureName2=MeasureVcoreCPU
X=0r
Y=#LineSpace#r
Text="  Clock Speed: %1MHz"

[MeterTextCPU]
Meter=STRING
MeterStyle=StyleText
X=0r
Y=#LineSpace#r
Text="  CPU:"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarLimitsCPU]
Meter=STRING
MeterStyle=StyleText
X=0R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarCPU]
Meter=BAR
MeasureName=MeasureRoundCPU
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
ImageTint=#ImageColor#

[MeterValueCPU]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureCPU
X=10R
Y=-4r
Text="%1%"
LeftMouseUpAction=!Execute ["taskmgr"]
[MeasureDirSWAP]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineSWAP"][!SetOption MeterTitleSWAP StringAlign Left][!SetOption MeterTitleSWAP X 0r][!SetOption MeterTitleSWAP Y 0r][!SetOption MeterUserNameSWAP Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameSWAP"][!HideMeter "MeterTitleSWAP"][!HideMeter "MeterOutlineSWAP"][!SetOption MeterUserNameSWAP Y -15r]

[MeasureTotalSWAP]
Measure=SWAPMemory
Total=1
UpdateDivider=86400

[MeasureFreeSWAP]
Measure=SWAPMemory
UpdateDivider=20
InvertMeasure=1

[MeasureSWAP]
Measure=SWAPMemory
UpdateDivider=20

[MeasureRoundSWAP]
Measure=Calc
Formula=((Round(((MeasureSWAP/MeasureTotalSWAP)*100)/5))*5)/100
UpdateDivider=20

;=======
;METERS
;=======
[MeterOutlineSWAP]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleSWAP]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="PAGE FILE:"

[MeterUserNameSWAP]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\SWAP.ini"
ClipString=1
W=#Width#
H=(#FontSize#+2)
Hidden=1

[MeterTextSWAP]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureFreeSWAP
MeasureName2=MeasureTotalSWAP
X=0r
Y=#LineSpace#r
Text="  %1B free of %2B"
AutoScale=1

[MeterTextSWAP2]
Meter=STRING
MeterStyle=StyleText
X=0r
Y=#LineSpace#r
Text="  SWAP:"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarLimitsSWAP]
Meter=STRING
MeterStyle=StyleText
X=0R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarSWAP]
Meter=BAR
MeasureName=MeasureRoundSWAP
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
ImageTint=#ImageColor#

[MeterValueSWAP]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureSWAP
X=10R
Y=-4r
Text="%1%"
Percentual=1
LeftMouseUpAction=!Execute ["taskmgr"]
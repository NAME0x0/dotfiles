[MeasureDirRAM]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineRAM"][!SetOption MeterTitleRAM StringAlign Left][!SetOption MeterTitleRAM X 0r][!SetOption MeterTitleRAM Y 0r][!SetOption MeterUserNameRAM Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameRAM"][!HideMeter "MeterTitleRAM"][!HideMeter "MeterOutlineRAM"][!SetOption MeterUserNameRAM Y -15r]

[MeasureTotalRAM]
Measure=PhysicalMemory
Total=1
UpdateDivider=86400

[MeasureFreeRAM]
Measure=PhysicalMemory
UpdateDivider=20
InvertMeasure=1

[MeasureRAM]
Measure=PhysicalMemory
UpdateDivider=20

[MeasureRoundRAM]
Measure=Calc
Formula=((Round(((MeasureRAM/MeasureTotalRAM)*100)/5))*5)/100
UpdateDivider=20

;=======
;METERS
;=======
[MeterOutlineRAM]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleRAM]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="MEMORY:"

[MeterUserNameRAM]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\RAM.ini"
ClipString=1
W=#Width#
H=(#FontSize#+2)
Hidden=1

[MeterTextRAM]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureFreeRAM
MeasureName2=MeasureTotalRAM
X=0r
Y=#LineSpace#r
Text="  %1B free of %2B"
AutoScale=1

[MeterTextRAM2]
Meter=STRING
MeterStyle=StyleText
X=0r
Y=#LineSpace#r
Text="  RAM:"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarLimitsRAM]
Meter=STRING
MeterStyle=StyleText
X=0R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["taskmgr"]

[MeterBarRAM]
Meter=BAR
MeasureName=MeasureRoundRAM
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
ImageTint=#ImageColor#

[MeterValueRAM]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureRAM
X=10R
Y=-4r
Text="%1%"
Percentual=1
LeftMouseUpAction=!Execute ["taskmgr"]
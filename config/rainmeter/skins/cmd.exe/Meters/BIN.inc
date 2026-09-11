[MeasureDirBin]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineBin"][!SetOption MeterTitleBin StringAlign Left][!SetOption MeterTitleBin X 0r][!SetOption MeterTitleBin Y 0r][!SetOption MeterUserNameBin Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameBin"][!HideMeter "MeterTitleBin"][!HideMeter "MeterOutlineBin"][!SetOption MeterUserNameBin Y -15r]

[MeasureBin]
Measure=Plugin
Plugin=RecycleManager
RecycleType=Count
UpdateDivider=5

[MeasureBinSize]
Measure=Plugin
Plugin=RecycleManager
RecycleType=Size
UpdateDivider=5

;=======
;METERS
;=======
[MeterOutlineBin]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleBin]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="RECYCLE BIN:"

[MeterUserNameBin]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUserName
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\BIN.ini"
ClipString=1
W=#Width#
H=#FontSize#
Hidden=1

[MeterBin]
Meter=String
MeterStyle=StyleText
MeasureName=MeasureBin
MeasureName2=MeasureBinSize
X=0r
Y=#LineSpace#r
Text="  BIN:  %1 files  (%2B)"
NumOfDecimals=0
Autoscale=1
LeftMouseUpAction=!CommandMeasure MeasureBinSize OpenBin
RightMouseUpAction=!CommandMeasure MeasureBinSize EmptyBin
ToolTipText="Right Click to Empty Bin"
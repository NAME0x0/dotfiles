[MeasureDirDisks]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineDisks"][!SetOption MeterTitleDisks StringAlign Left][!SetOption MeterTitleDisks X 0r][!SetOption MeterTitleDisks Y 0r][!SetOption MeterUserNameDisks Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameDisks"][!HideMeter "MeterTitleDisks"][!HideMeter "MeterOutlineDisks"][!SetOption MeterUserNameDisks Y -15r]

[MeasureTotalDisk1]
Measure=FreeDiskSpace
Drive=#Disk1#:
Total=1
UpdateDivider=86400

[MeasureUsedDisk1]
Measure=FreeDiskSpace
Drive=#Disk1#:
InvertMeasure=0
UpdateDivider=120

[MeasureRoundDisk1]
Measure=Calc
Formula=((Round(((MeasureUsedDisk1/MeasureTotalDisk1)*100)/5))*5)/100
InvertMeasure=1
UpdateDivider=120

[MeasureTotalDisk2]
Measure=FreeDiskSpace
Drive=#Disk2#:
Total=1
UpdateDivider=86400

[MeasureUsedDisk2]
Measure=FreeDiskSpace
Drive=#Disk2#:
InvertMeasure=0
UpdateDivider=120

[MeasureRoundDisk2]
Measure=Calc
Formula=((Round(((MeasureUsedDisk2/MeasureTotalDisk2)*100)/5))*5)/100
InvertMeasure=1
UpdateDivider=120

[MeasureTotalDisk3]
Measure=FreeDiskSpace
Drive=#Disk3#:
Total=1
UpdateDivider=86400

[MeasureUsedDisk3]
Measure=FreeDiskSpace
Drive=#Disk3#:
InvertMeasure=0
UpdateDivider=120

[MeasureRoundDisk3]
Measure=Calc
Formula=((Round(((MeasureUsedDisk3/MeasureTotalDisk3)*100)/5))*5)/100
InvertMeasure=1

[MeasureTotalDisk4]
Measure=FreeDiskSpace
Drive=#Disk4#:
Total=1
UpdateDivider=86400

[MeasureUsedDisk4]
Measure=FreeDiskSpace
Drive=#Disk4#:
InvertMeasure=0
UpdateDivider=120

[MeasureRoundDisk4]
Measure=Calc
Formula=((Round(((MeasureUsedDisk4/MeasureTotalDisk4)*100)/5))*5)/100
InvertMeasure=1
UpdateDivider=120

[MeasureDiskNumber]
Measure=Calc
IfCondition=#NumberofDrives# >= 1
IfTrueAction=[!SetOption MeterEndDisks Y "(-#FontSize#*3+10)R"]
IfCondition2=#NumberofDrives# >= 2
IfTrueAction2=[!SetOption MeterEndDisks Y "(-#FontSize#*2+10)R"][!ShowMeter "MeterTextDisk2"][!ShowMeter "MeterBarLimitsDisk2"][!ShowMeter "MeterBarDisk2"][!ShowMeter "MeterValueDisk2"]
IfCondition3=#NumberofDrives# >= 3
IfTrueAction3=[!SetOption MeterEndDisks Y "0R"][!ShowMeter "MeterTextDisk3"][!ShowMeter "MeterBarLimitsDisk3"][!ShowMeter "MeterBarDisk3"][!ShowMeter "MeterValueDisk3"]
IfCondition4=#NumberofDrives# >= 4
IfTrueAction4=[!SetOption MeterEndDisks Y "0R"][!ShowMeter "MeterTextDisk4"][!ShowMeter "MeterBarLimitsDisk4"][!ShowMeter "MeterBarDisk4"][!ShowMeter "MeterValueDisk4"]

;=======
;METERS
;=======
[MeterOutlineDisks]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleDisks]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="STORAGE:"

[MeterUserNameDisks]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\DISKS.ini"
ClipString=1
W=#Width#
H=(#FontSize#+2)
Hidden=1

[MeterTextDisk1]
Meter=STRING
MeterStyle=StyleText
X=0r
Y=#LineSpace#r
Text="  #Disk1#:\"
LeftMouseUpAction=!Execute ["#Disk1#:\"]

[MeterBarLimitsDisk1]
Meter=STRING
MeterStyle=StyleText
X=7R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["#Disk1#:\"]

[MeterBarDisk1]
Meter=BAR
MeasureName=MeasureRoundDisk1
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
ImageTint=#ImageColor#

[MeterValueDisk1]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUsedDisk1
MeasureName2=MeasureTotalDisk1
X=10R
Y=-4r
Text="%1B free"
NumOfDecimals=1
AutoScale=1
LeftMouseUpAction=!Execute ["#Disk1#:\"]
ClipString=1
W=(#Width#-225)
H=(#FontSize#+2)

[MeterTextDisk2]
Meter=STRING
MeterStyle=StyleText
X=10
Y=#LineSpace#r
Text="  #Disk2#:\"
LeftMouseUpAction=!Execute ["#Disk2#:\"]
Hidden=1

[MeterBarLimitsDisk2]
Meter=STRING
MeterStyle=StyleText
X=7R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["#Disk2#:\"]
Hidden=1

[MeterBarDisk2]
Meter=BAR
MeasureName=MeasureRoundDisk2
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
Hidden=1
ImageTint=#ImageColor#

[MeterValueDisk2]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUsedDisk2
MeasureName2=MeasureTotalDisk2
X=10R
Y=-4r
Text="%1B free"
NumOfDecimals=1
AutoScale=1
LeftMouseUpAction=!Execute ["#Disk2#:\"]
Hidden=1
ClipString=1
W=(#Width#-225)
H=(#FontSize#+2)

[MeterTextDisk3]
Meter=STRING
MeterStyle=StyleText
X=10
Y=#LineSpace#r
Text="  #Disk3#:\"
LeftMouseUpAction=!Execute ["#Disk3#:\"]
Hidden=1

[MeterBarLimitsDisk3]
Meter=STRING
MeterStyle=StyleText
X=7R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["#Disk3#:\"]
Hidden=1

[MeterBarDisk3]
Meter=BAR
MeasureName=MeasureRoundDisk3
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
Hidden=1
ImageTint=#ImageColor#

[MeterValueDisk3]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUsedDisk3
MeasureName2=MeasureTotalDisk3
X=10R
Y=-4r
Text="%1B free"
NumOfDecimals=1
AutoScale=1
LeftMouseUpAction=!Execute ["#Disk3#:\"]
Hidden=1
ClipString=1
W=(#Width#-225)
H=(#FontSize#+2)

[MeterTextDisk4]
Meter=STRING
MeterStyle=StyleText
X=10
Y=#LineSpace#r
Text="  #Disk4#:\"
LeftMouseUpAction=!Execute ["#Disk4#:\"]
Hidden=1

[MeterBarLimitsDisk4]
Meter=STRING
MeterStyle=StyleText
X=7R
Y=0r
Text="[		             ]"
LeftMouseUpAction=!Execute ["#Disk4#:\"]
Hidden=1
ImageTint=#ImageColor#

[MeterBarDisk4]
Meter=BAR
MeasureName=MeasureRoundDisk4
BarImage=#@#Images\bar1.png
BarOrientation=HORIZONTAL
X=9r
Y=4r
Hidden=1

[MeterValueDisk4]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUsedDisk4
MeasureName2=MeasureTotalDisk4
X=10R
Y=-4r
Text="%1B free"
NumOfDecimals=1
AutoScale=1
LeftMouseUpAction=!Execute ["#Disk4#:\"]
Hidden=1

[MeterEndDisks]
Meter=STRING
MeterStyle=StyleText
X=0r
Text=" "
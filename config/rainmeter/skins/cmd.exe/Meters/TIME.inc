[MeasureDirTime]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineTime"][!SetOption MeterTitleTime StringAlign Left][!SetOption MeterTitleTime X 0r][!SetOption MeterTitleTime Y 0r][!SetOption MeterUserNameTime Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameTime"][!HideMeter "MeterTitleTime"][!HideMeter "MeterOutlineTime"][!SetOption MeterUserNameTime Y -15r]

[MeasureTime]
Measure=Time
Format=%I : %M %p

[MeasureDate]
Measure=Time
Format=%d/%m/%y  -  %A, %d %B %Y

;=========
;METERS
;=========
[MeterOutlineTime]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleTime]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="CLOCK:"

[MeterUserNameTime]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\TIME.ini"
ClipString=1
W=#Width#
H=(#FontSize#+2)
Hidden=1

[MeterTime]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureTime
X=0r
Y=#LineSpace#r
Text="  TIME:  %1"

[MeterDate]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureDate
X=0r
Y=#LineSpace#r
Text="  DATE:  %1"
ClipString=1
W=#Width#
H=(#FontSize#+2)
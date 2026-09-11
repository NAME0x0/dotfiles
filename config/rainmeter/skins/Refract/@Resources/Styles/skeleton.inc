[Variables]
;RAW UNSCALED
width=400
height=120
@include=#@#settings.inc
@include2=#@#Styles/styles.inc


[measureColor1]
Measure=String
String=#GraphColor#.
Substitute=",255.":",240"

[measureColor2]
Measure=String
String=#GraphColor#.
Substitute=",255.":",160"

[MeterBackground0]
Meter=Image
X=0
y=0
W=(#width#*#scale#)
H=(#height#*#scale#)
SolidColor=200,200,200,0
UpdateDivider=-1

[MeterBackground1]
Meter=Image
X=(5*#scale#)
y=(10*#scale#)
W=(390*#scale#)
H=(100*#scale#)
SolidColor=#BGColor#
UpdateDivider=-1

[MeterBorder]
Meter=Shape
MeterStyle=StyleMeterBorder

[MeterTitle]
Meter=String
FontColor=#AccentColor#
FontFace=Moongloss Display Thick
AntiAlias=1
x=(8*#scale#)
y=(15*#scale#)
w=(130*#scale#)
h=(15*#scale#)
FontSize=(10*#scale#)
Text=#title#
StringCase=Upper
UpdateDivider=-1

[meterData]
Meter=String
MeasureName=measureData
MeterStyle=StyleMainText
FontFace=Moongloss Display Thin
X=(155*#scale#)
Y=(49*#scale#)
W=(105*#scale#)
H=(60*#scale#)
Text=%1
fontsize=(45*#scale#)
StringAlign=right
Percentual=#percentual#
AutoScale=#autoscale#
NumOfDecimals=0



[meterGradient]
Meter=Image
X=(0*#scale#)
y=(0*#scale#)
W=(230*#scale#)
H=(80*#scale#)
SolidColor=[measureColor1]
SolidColor2=[measureColor2]
GradientAngle=90
Container=meterFill


[meterFill]
Meter=Histogram
MeasureName=measureData
X=(155*#scale#)
y=(20*#scale#)
W=(230*#scale#)
H=(80*#scale#)
PrimaryColor=255,255,255,64
AntiAlias=1
Autoscale=#autoscale#

[meterLine]
Meter=Line
MeasureName=measureData
X=(155*#scale#)
y=(20*#scale#)
W=(230*#scale#)
H=(80*#scale#)
LineColor=#GraphColor#
LineWidth=1.5
AntiAlias=1
Autoscale=#autoscale#

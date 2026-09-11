[MeterBackground]
Meter=Image
X=0
y=0
W=(400*#scale#)
H=(160*#scale#)
SolidColor=200,200,200,1

[MeterBackground1]
Meter=Image
X=(5*#scale#)
y=(5*#scale#)
W=(390*#scale#)
H=(150*#scale#)
SolidColor=#BGColor#

[meterData]
Meter=String
MeterStyle=StyleMainText
MeasureName=measureData
FontFace=Moongloss Display thin
FontColor=#HighlightTextColor#
X=(200*#scale#)
Y=(45*#scale#)
W=(400*#scale#)
H=(80*#scale#)
Text=%1
FontSize=(90*#scale#)
FontWeight=(200*#scale#)
StringAlign=Center
Percentual=#percentual#

[MeterBorder]
Meter=Shape
MeterStyle=StyleMeterBorderTop

[meterDate1]
Meter=String
MeterStyle=StyleSecondText
MeasureName=measureDate1
X=(200*#scale#)
Y=(27*#scale#)
W=(400*#scale#)
H=(26*#scale#)
FontColor=#HighlightTextColor#
;FontColor=0,0,0,255
Text=%1
FontSize=(13*#scale#)
Percentual=#percentual#
StringCase=Upper
StringAlign=centercenter


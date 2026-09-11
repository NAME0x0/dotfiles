[MeterBackground]
Meter=Image
X=0
y=0
W=(400*#scale#)
H=(120*#scale#)
SolidColor=200,200,200,1

[MeterBackground1]
Meter=Image
X=(5*#scale#)
y=(5*#scale#)
W=(390*#scale#)
H=(110*#scale#)
SolidColor=#BGColor#

[MeterBorder]
Meter=Shape
MeterStyle=StyleMeterBorder


[meterData]
Meter=String
MeterStyle=StyleMainText
MeasureName=measureData
FontFace=Moongloss Display Thin
X=(0*#scale#)
Y=(15*#scale#)
W=(120*#scale#)
H=(60*#scale#)
Text=%1
FontSize=(70*#scale#)
FontWeight=200
Percentual=#percentual#

[meterDate1]
Meter=String
MeterStyle=StyleSecondText
MeasureName=measureDate1
FontColor=#HighlightTextColor#
X=(250*#scale#)
Y=(30*#scale#)
W=(100*#scale#)
H=(20*#scale#)
Text=%1
FontSize=(16*#scale#)
Percentual=#percentual#
StringCase=Upper

[meterDate2]
Meter=String
MeterStyle=StyleSecondText
MeasureName=measureDate2
FontColor=#HighlightTextColor#
X=(250*#scale#)
Y=(65*#scale#)
W=(100*#scale#)
H=(25*#scale#)
Text=%1
FontSize=(16*#scale#)
Percentual=#percentual#
StringCase=Upper

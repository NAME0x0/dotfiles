[MeterBackground0]
Meter=Image
X=0
Y=0
W=(#width#*#scale#)
H=(#height#*#scale#)
SolidColor=200,200,200,1
UpdateDivider=-1

[MeterBackground1]
Meter=Image
X=(5*#scale#)
Y=(5*#scale#)
W=((#width#-10)*#scale#)
H=((#height#-10)*#scale#)
SolidColor=#BGColor#
UpdateDivider=-1

[MeterTitle]
Meter=String
FontColor=#AccentColor#
FontFace=Moongloss Display Thick
AntiAlias=1
X=(5*#scale#)
Y=(5*#scale#)
W=(130*#scale#)
H=(15*#scale#)
FontSize=(10*#scale#)
Text=#title#
StringCase=Upper
UpdateDivider=-1

[MeterTitle2]
Meter=String
FontColor=#HighlightTextColor#
FontFace=Moongloss Display Thick
AntiAlias=1
X=(5*#scale#)
Y=(5*#scale#)
W=(120*#scale#)
H=(15*#scale#)
FontSize=(10*#scale#)
Text=#title2#
StringCase=Upper
UpdateDivider=-1

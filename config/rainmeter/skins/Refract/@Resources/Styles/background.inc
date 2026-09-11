[Variables]
@include=#@#settings.inc
@include2=#@#Styles/styles.inc

[MeterBackground0]
Meter=Image
X=0
y=0
W=(#width#*#scale#)
H=(#height#*#scale#)
SolidColor=200,200,200,1
UpdateDivider=-1

[MeterBackground1]
Meter=Image
X=(5*#scale#)
y=(5*#scale#)
W=((#width#-10)*#scale#))
H=((#height#-10)*#scale#))
SolidColor=#BGColor#
UpdateDivider=-1

[MeterTitle]
Meter=String
FontColor=#AccentColor#
FontFace=Moongloss Display Thick
AntiAlias=1
x=(5*#scale#)
y=(5*#scale#)
w=(130*#scale#)
h=(15*#scale#)
FontSize=(10*#scale#)
Text=#title#
StringCase=Upper
UpdateDivider=-1

[MeterTitle2]
Meter=String
FontColor=#HighlightTextColor#
FontFace=Moongloss Display Thick
AntiAlias=1
x=(5*#scale#)
y=(5*#scale#)
w=(120*#scale#)
h=(15*#scale#)
FontSize=(10*#scale#)
Text=#title2#
StringCase=Upper
UpdateDivider=-1
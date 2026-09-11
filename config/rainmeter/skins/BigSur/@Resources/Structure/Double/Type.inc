

[solA]
Meter=Image
solidcolor=0,255,0,1
W=(320+(10-#Padding#)*2)*#ScaleDpi#
H=(150+(10-#Padding#)*(3-#HideLabels#))*#ScaleDpi#
x=0
y=0

[bgE]
Meter=Image
ImageName=#@#Graphics\Structure\double.png
X=(10-#Padding#)*#ScaleDpi#
Y=(10-#Padding#)*#ScaleDpi#
W=(320)*#ScaleDpi#
H=(150)*#ScaleDpi#
ImageTint=#colorskin#

[Full]
X=(10-#Padding#)*#ScaleDpi#
Y=(10-#Padding#)*#ScaleDpi#
W=(320)*#ScaleDpi#
H=(150)*#ScaleDpi#



[FontStyle]
FontFace=#ThemeFont#
Antialias=1
fontSize=(10)*#scaledpi#
fontcolor=255,255,255

[Text]
Meter=String
Text=#Name#
y=(2)*#scaledpi#R
StringAlign=Center
w=(150)*#scaledpi#
x=((160+(10-#Padding#)))*#scaledpi#
MeterStyle=FontStyle
Hidden=#HideLabels#

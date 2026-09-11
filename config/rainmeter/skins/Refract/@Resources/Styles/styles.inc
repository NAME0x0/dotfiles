[StyleSecondText]
FontColor=#NormalTextColor#
FontFace=Moongloss Display Thick
AntiAlias=1
FontSize=(10*#scale#)
StringCase=Upper

[StyleMainText]
FontColor=#HighlightTextColor#
AntiAlias=1

[StyleButton]
X=(95*#scale#)
Y=(15*#scale#)
W=(190*#scale#)
H=(30*#scale#)
FontColor=#Accentcolor#
FontFace=MoonGloss Display thick
StringAlign=centercenter
SolidColor=0,0,0,0
StringCase=upper
AntiAlias=1
FontSize=(11*#scale#)
MouseOverAction=[!SetOption #CURRENTSECTION# FontColor 0,0,0,255][!SetOption #CURRENTSECTION# SolidColor #AccentColor#][!UpdateMeter #CURRENTSECTION#][!Redraw]
MouseLeaveAction=[!SetOption #CURRENTSECTION# FontColor #AccentColor#][!SetOption #CURRENTSECTION# SolidColor 0,0,0,1][!UpdateMeter #CURRENTSECTION#][!Redraw]


[StyleMask]
W=(190*#scale#)
H=(30*#scale#)
Shape=Rectangle 0,0,(190*#scale#),(30*#scale#),(2*#scale#) | Fill Color #AccentColor#

[StyleBorder]
X=0r
Y=0r
Shape=Rectangle 0,0,(190*#scale#),(30*#scale#),(2*#scale#) | StrokeWidth #scale# | Stroke Color #AccentColor# | Fill Color 0,0,0,0 

[StyleMeterBorderTop]
Shape=Path MyPath | StrokeWidth #scale# | Stroke Color #AccentColor# | Fill Color 0,0,0,0 
Shape2=Path MyPath2 | StrokeWidth #scale# | Stroke Color #AccentColor# | Fill Color 0,0,0,0
MyPath = (5*#scale#),(10*#scale#) | LineTo (395*#scale#),(10*#scale#) | LineTo (395*#scale#),(20*#scale#)
MyPath2= (5*#scale#),(30*#scale#) | LineTo (5*#scale#),(40*#scale#) | LineTo (395*#scale#),(40*#scale#) 
UpdateDivider=-1

[StyleMeterBorder]
Shape=Path MyPath | StrokeWidth #scale# | Stroke Color #AccentColor# | Fill Color 0,0,0,0 
Shape2=Path MyPath2 | StrokeWidth #scale# | Stroke Color #AccentColor# | Fill Color 0,0,0,0
MyPath = (5*#scale#),(10*#scale#) | LineTo ((#width#-5)*#scale#),(10*#scale#) | LineTo ((#width#-5)*#scale#),(20*#scale#) 
MyPath2= (5*#scale#),((#height#-20)*#scale#) | LineTo (5*#scale#),((#height#-10)*#scale#) | LineTo ((#width#-5)*#scale#),((#height#-10)*#scale#)
UpdateDivider=-1
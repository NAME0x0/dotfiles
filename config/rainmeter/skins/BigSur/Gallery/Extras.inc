[block]
w=(100)*#scaledpi#
h=(100)*#scaledpi#
X=5R
y=r

LeftMouseUpAction=!ToggleConfig "BigSur\Extras\#currentsection#" "Item.ini"
ToolTipText=#currentsection#
imagename=#@#\Graphics\Thumbs\Extras\#currentsection#.png
[ClockNews]
Meter=Image
x=(225)*#scaledpi#
y=(40)*#scaledpi#
MeterStyle=block

[MenuHorizontal]
Meter=Image
MeterStyle=block


[DayDate]
Meter=Image
MeterStyle=block

[Visualizer]
Meter=Image
MeterStyle=block

[te]
meter=string
MeterStyle=Default
y=(10)*#scaledpi#R
x=(225)*#scaledpi#
fontsize=(10)*#scaledpi#
text=#GetMoreExtras#
LeftMouseUpACtion=!execute ["http://omnimo.info/?ref=bigsur"]
MouseActionCursor=1
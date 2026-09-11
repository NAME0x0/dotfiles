[MeasureDirMusic]
Measure=Calc
IfCondition=#MeterStyle# = 2
IfTrueAction=[!HideMeter "MeterOutlineMusic"][!SetOption MeterTitleMusic StringAlign Left][!SetOption MeterTitleMusic X 0r][!SetOption MeterTitleMusic Y 0r][!SetOption MeterUserNameMusic Y 0r]
IfCondition2=#MeterStyle# = 3
IfTrueAction2=[!ShowMeter "MeterUserNameMusic"][!HideMeter "MeterTitleMusic"][!HideMeter "MeterOutlineMusic"][!SetOption MeterUserNameMusic Y -15r]

[NowPlaying]
Measure=Plugin
Plugin=NowPlaying
PlayerName=#PlayerName#
PlayerType=TITLE
PlayerPath=#PlayerLocation#

[MeasureArtist]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=ARTIST

[MeasureAlbum]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=ALBUM

[MeasureDuration]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=DURATION

[MeasurePosition]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=POSITION

[MeasureState]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=STATE
Substitute="0":"PLAY","1":"PAUSE","2":"PLAY"

[MeasureVolume]
Measure=Plugin
Plugin=NowPlaying
PlayerName=[NowPlaying]
PlayerType=VOLUME
MaxValue=100

;=========
;METERS
;=========
[MeterOutlineMusic]
Meter=IMAGE
ImageName=#@#Images\outline.png
X=0r
Y=0r
ImageTint=#ImageColor#

[MeterTitleMusic]
Meter=STRING
MeterStyle=StyleText
StringAlign=Center
X=68r
Y=15r
Text="MUSIC:"

[MeterUserNameMusic]
Meter=STRING
MeterStyle=StyleText
X=10
Y=15r
Text="%UserProfile%> #ROOTCONFIGPATH#Meters\MUSIC.ini"
ClipString=1
W=#Width#
H=#FontSize#
Hidden=1

[MeterUserNameMusic]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureUserName
X=10
Y=15r
Text="#PlayerName#"
Hidden=1

[MeterPosition]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasurePosition
X=0r
Y=#LineSpace#r
Text="  %1"

[MeterSlash]
Meter=STRING
MeterStyle=StyleText
X=R
Y=r
Text="/"

[MeterDuration]
Meter=STRING
MeterStyle=StyleText
MeasureName=MeasureDuration
X=R
Y=r
Text="%1"

[MeterPrev]
Meter=STRING
MeterStyle=StyleText
X=130
Y=r
Text="<"
StringStyle=BOLD
LeftMouseUpAction=!CommandMeasure NowPlaying Previous

[MeterPlayPause]
Meter=STRING
MeasureName=MeasureState
MeterStyle=StyleText
StringAlign=Center
X=22R
Y=r
LeftMouseUpAction=!CommandMeasure NowPlaying "PlayPause"
DynamicVariables=1

[MeterNext]
Meter=STRING
MeterStyle=StyleText
X=22r
Y=r
Text=">"
StringStyle=BOLD
LeftMouseUpAction=!CommandMeasure NowPlaying Next

[MeterVolumeUp]
Meter=STRING
MeterStyle=StyleText
X=10R
Y=r
Text="[+]"
LeftMouseUpAction=[!CommandMeasure NowPlaying "SetVolume +5"]

[MeterVolume]
Meter=STRING
MeasureName=MeasureVolume
MeterStyle=StyleText
StringAlign=Center
X=17R
Y=r
Text="%1%"

[MeterVolumeDown]
Meter=STRING
MeterStyle=StyleText
X=17r
Y=r
Text="[-]"
LeftMouseUpAction=[!CommandMeasure NowPlaying "SetVolume -5"]

[MeterTitleSong]
Meter=STRING
MeasureName=NowPlaying
MeterStyle=StyleText
X=15
Y=1R
H=16
W=#Width#
Text="Title:	%1"
Clipstring=1

[MeterArtist]
Meter=STRING
MeasureName=MeasureArtist
MeterStyle=StyleText
X=r
Y=-3R
W=#Width#
H=16
Text="Artist:	%1"
Clipstring=1

[MeterAlbum]
Meter=STRING
MeasureName=MeasureAlbum
MeterStyle=StyleText
X=r
Y=-3R
W=#Width#
H=16
Text="Album:	%1"
Clipstring=1
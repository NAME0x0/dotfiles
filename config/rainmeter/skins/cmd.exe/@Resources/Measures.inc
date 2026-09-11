@includeSettings=#ROOTCONFIGPATH#SETTINGS.inc

[MeasureScreenWidth]
Measure=Plugin
Plugin=SysInfo
SysInfoType=SCREEN_WIDTH
SysInfoData=1
UpdateDivider=86400

[MeasureScreenHeight]
Measure=Plugin
Plugin=SysInfo
SysInfoType=SCREEN_HEIGHT
SysInfoData=1
UpdateDivider=86400

[MeasureOS]
Measure=Plugin
Plugin=SysInfo
SysInfoType=OS_VERSION
UpdateDivider=86400
IfCondition=#Del_system32_Joke# = 0
IfTrueAction=[!HideMeter "MeterJoke1"][!HideMeter "MeterJoke2"][!HideMeter "MeterJoke3"][!HideMeter "MeterJoke4"]

[MeasureOSArch]
Measure=Plugin
Plugin=SysInfo
SysInfoType=OS_BITS
UpdateDivider=86400

[MeasureVersion]
Measure=Registry
RegHKey=HKEY_LOCAL_MACHINE
RegKey=SOFTWARE\Microsoft\Windows NT\CurrentVersion
RegValue=CurrentVersion
UpdateDivider=86400

[MeasureBuild]
Measure=Registry
RegHKey=HKEY_LOCAL_MACHINE
RegKey=SOFTWARE\Microsoft\Windows NT\CurrentVersion
RegValue=CurrentBuildNumber
UpdateDivider=86400

[MeasureServicePack]
Measure=Registry
RegHKey=HKEY_LOCAL_MACHINE
RegKey=SOFTWARE\Microsoft\Windows NT\CurrentVersion
RegValue=CSDVersion
Substitute="0":""
UpdateDivider=86400
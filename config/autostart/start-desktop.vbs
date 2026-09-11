' Windowless wrapper for start-desktop.ps1.
' Task Scheduler invokes this so no console window flashes at logon.
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""__USERPROFILE__\.config\autostart\start-desktop.ps1""", 0, False

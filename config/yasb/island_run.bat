@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0island_app.ps1" > "%TEMP%\yasb_island_state.txt" 2>nul
type "%TEMP%\yasb_island_state.txt"

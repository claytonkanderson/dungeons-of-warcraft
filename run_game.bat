@echo off
rem Launch Dungeons of Warcraft: vanilla WoW dungeons as the D2 Amazon.
rem Sessions launched this way are recorded (--record, see replay.gd) unless
rem the caller passes --no-record, as the capture launchers do. Godot's own
rem options go before "--", the game's after it; "--" is added when absent.
setlocal
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
set SEP=
for %%a in (%*) do if "%%~a"=="--" set SEP=1
if defined SEP (
  "%GODOT%" --path "%~dp0game" %* --record
) else (
  "%GODOT%" --path "%~dp0game" %* -- --record
)

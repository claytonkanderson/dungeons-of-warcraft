@echo off
rem Render a recorded session to video with Godot's movie maker.
rem
rem   render_replay.bat <session.jsonl> [out.mp4]
rem
rem The game replays the log one physics tick per frame at 60 fps and
rem writes an MJPEG AVI beside the output (Godot cannot write MP4); with
rem ffmpeg available the AVI is transcoded to H.264 MP4 and removed. Session
rem logs live in %APPDATA%\Godot\app_userdata\Dungeons of Warcraft\sessions.
rem The window is created unfocusable and off the desktop (it must stay a
rem real, drawable window: a minimized one is never rendered).
setlocal
if "%~1"=="" (
  echo usage: render_replay.bat ^<session.jsonl^> [out.mp4]
  exit /b 1
)
set LOG=%~f1
if "%~2"=="" (set OUTMP4=%~dpn1.mp4) else (set OUTMP4=%~f2)
set AVI=%OUTMP4:.mp4=.avi%
set OVR=%~dp0game\override.cfg
(
echo [display]
echo window/size/no_focus=true
echo window/size/initial_position_type=0
echo window/size/initial_position=Vector2i(-32000, -32000^)
) > "%OVR%"
call "%~dp0run_game.bat" --write-movie "%AVI%" --fixed-fps 60 -- "--replay=%LOG%" --no-record
del "%OVR%"
set FFMPEG=
where ffmpeg >nul 2>nul && set FFMPEG=ffmpeg
rem a winget install this shell's PATH has not picked up yet
if not defined FFMPEG for /d %%p in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*") do for /d %%d in ("%%p\ffmpeg-*") do set "FFMPEG=%%d\bin\ffmpeg.exe"
if not defined FFMPEG (
  echo ffmpeg not found: the video is %AVI%
  echo install ffmpeg ^(winget install Gyan.FFmpeg^) to get an MP4
  exit /b 0
)
"%FFMPEG%" -y -loglevel error -i "%AVI%" -c:v libx264 -preset medium -crf 22 -pix_fmt yuv420p -c:a aac -b:a 192k "%OUTMP4%"
if errorlevel 1 (
  echo ffmpeg failed: the video is %AVI%
  exit /b 1
)
del "%AVI%"
echo wrote %OUTMP4%

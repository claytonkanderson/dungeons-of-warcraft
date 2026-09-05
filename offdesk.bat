@echo off
rem Off-desktop launch for runs that must render real frames (the combat
rem test, the frame-time probe). Like capture.bat the window is created
rem unfocusable and off the desktop, but it stays a normal window rather than
rem minimized, because a minimized window is never rendered.
set OVR=%~dp0game\override.cfg
(
echo [display]
echo window/size/no_focus=true
echo window/size/initial_position_type=0
echo window/size/initial_position=Vector2i(-32000, -32000^)
) > "%OVR%"
call "%~dp0run_game.bat" %* --offscreen
del "%OVR%"

@echo off
rem Offscreen launch for automated captures (--shots, --menu-shot, --ui-test,
rem diagnostics). The window is created already minimized, unfocusable and off
rem the desktop, so it never activates and never disturbs a fullscreen app —
rem minimizing it after creation (what --offscreen alone does) is too late:
rem a normal window has already taken focus for a frame.
set OVR=%~dp0game\override.cfg
(
echo [display]
echo window/size/mode=1
echo window/size/no_focus=true
echo window/size/initial_position_type=0
echo window/size/initial_position=Vector2i(-32000, -32000^)
) > "%OVR%"
call "%~dp0run_game.bat" %* --offscreen
del "%OVR%"

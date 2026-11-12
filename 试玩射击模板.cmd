@echo off
setlocal
set "DRZ_RUNTIME=%LOCALAPPDATA%\Temp\drz-english-shooter-20261103"
set "DRZ_GODOT=%DRZ_RUNTIME%\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%DRZ_GODOT%" (
  echo Godot local runtime is missing. See README.txt to restore it.
  pause
  exit /b 1
)
start "" "%DRZ_GODOT%" --path "%DRZ_RUNTIME%\fps-template" --rendering-method gl_compatibility

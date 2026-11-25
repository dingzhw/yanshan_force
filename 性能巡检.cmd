@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.9.9.4\diagnostics"
if /I "%~1"=="standard" goto standard
if /I "%~1"=="balanced" goto balanced
start "" "%~dp0playtest\windows-v0.9.9.4\YanshanBase.exe" --rendering-method gl_compatibility -- --qa --hardware-check --low-quality
exit /b
:standard
start "" "%~dp0playtest\windows-v0.9.9.4\YanshanBase.exe" -- --qa --hardware-check
exit /b
:balanced
start "" "%~dp0playtest\windows-v0.9.9.4\YanshanBase.exe" -- --qa --hardware-check --low-quality

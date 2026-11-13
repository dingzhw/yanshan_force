@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.5.6\diagnostics"
start "" "%~dp0playtest\windows-v0.5.6\YanshanBase.exe" -- --qa --hardware-check --low-quality

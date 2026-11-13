@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.6.0\diagnostics"
start "" "%~dp0playtest\windows-v0.6.0\YanshanBase.exe" -- --qa --hardware-check --low-quality

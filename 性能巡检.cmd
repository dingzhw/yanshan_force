@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.5.1\diagnostics"
start "" "%~dp0playtest\windows-v0.5.1\YanshanBase.exe" -- --qa --hardware-check --low-quality

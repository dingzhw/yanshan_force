@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.5.4\diagnostics"
start "" "%~dp0playtest\windows-v0.5.4\YanshanBase.exe" -- --qa --hardware-check --low-quality

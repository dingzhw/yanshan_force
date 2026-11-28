@echo off
setlocal
set "DRZ_DIAGNOSTICS_DIR=%~dp0playtest\windows-v0.9.9.6\diagnostics"
echo =========================================================
echo  Yanshan Force - 5700G / Vega 8 iGPU Benchmark Tour
echo  Renderer: gl_compatibility + --low-quality + --auto-quit
echo  Output:   %DRZ_DIAGNOSTICS_DIR%
echo =========================================================
start "" /wait "%~dp0playtest\windows-v0.9.9.6\YanshanBase.exe" --rendering-method gl_compatibility -- --qa --hardware-check --low-quality --auto-quit
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [PASS] Benchmark completed! See latest performance-*.json in:
  echo        %DRZ_DIAGNOSTICS_DIR%
) else (
  echo [FAIL] Benchmark exited with code %RC%. Check diagnostics folder.
)
pause
exit /b %RC%

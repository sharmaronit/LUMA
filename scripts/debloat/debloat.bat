@echo off
rem Double-click launcher for debloat.ps1 (bypasses the .ps1 execution policy for this run only)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0debloat.ps1" %*
pause

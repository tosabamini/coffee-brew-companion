@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py -3) || (set PY=python)
if "%~1"=="" (echo Drag a folder of roast photos onto this file. & pause & exit /b 1)
%PY% analyze.py roast "%~1"
pause

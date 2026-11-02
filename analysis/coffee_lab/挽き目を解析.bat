@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py -3) || (set PY=python)
set TARGET=%~1
if "%TARGET%"=="" set TARGET=%~dp0..\..\grind_samples
%PY% analyze.py grind "%TARGET%"
pause

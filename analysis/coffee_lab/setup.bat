@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py -3) || (set PY=python)
%PY% --version || (echo Python 3.10+ is not installed. Install it from https://www.python.org/ and check "Add python.exe to PATH". & pause & exit /b 1)
%PY% -m pip install -r requirements.txt
echo.
echo Setup finished.
pause

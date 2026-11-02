@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
where py >/dev/null 2>/dev/null && (set PY=py -3) || (set PY=python)
%PY% server.py
pause

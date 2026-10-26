@echo off
rem Rebuild the Flutter SDK cache (old cache is kept as cache_old_YYYYMMDD), then build the APK again.
set "FC=C:\src\flutter\flutter\bin\cache"
set "STAMP=%date:~0,4%%date:~5,2%%date:~8,2%%time:~0,2%%time:~3,2%"
set "STAMP=%STAMP: =0%"
if exist "%FC%" (
  echo Renaming old Flutter cache to cache_old_%STAMP% ...
  ren "%FC%" "cache_old_%STAMP%"
  if errorlevel 1 ( echo Could not rename the cache. Close Android Studio / VS Code / other terminals and try again. & pause & exit /b 1 )
)
echo Downloading Flutter tools again (several minutes)...
call flutter precache --android
if errorlevel 1 ( echo precache FAILED. & pause & exit /b 1 )
echo Cache rebuilt. Starting APK build...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_apk_qrdl.ps1"
pause

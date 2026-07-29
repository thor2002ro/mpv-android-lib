@echo off
setlocal

pushd "%~dp0" >nul
for /f "usebackq delims=" %%i in (`wsl.exe wslpath -a "%CD%"`) do set "WSL_REPO=%%i"
popd >nul
if not defined WSL_REPO (
    echo WSL is required to build the mpv Android AAR.
    exit /b 1
)

wsl.exe bash "%WSL_REPO%/build.sh"
exit /b %ERRORLEVEL%

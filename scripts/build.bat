@echo off
@REM This script automates building distributable artifacts with luapack

setlocal enabledelayedexpansion

@REM echo [1/4] Downloading luapack...
@REM set base_path=%~dp0..\tools
@REM set file_name=luapack-windows-x86_64.zip
@REM set download_url=https://github.com/00fast00/luapack/releases/download/v0.1.1/luapack-windows-x86_64.zip
@REM powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%file_name%'"
@REM tar -xf "%base_path%\%file_name%" -C "%base_path%"

@REM if %ERRORLEVEL% neq 0 (
@REM     echo ERROR: Luapack download failed
@REM     exit /b 1
@REM )

echo [2/4] Cleaning up old build artifacts...
if exist "%~dp0..\dist" rd /s /q "%~dp0..\dist"

echo [3/4] Bundling...
%~dp0..\tools\luapack.exe bundle "%~dp0..\src\raptor-panel\raptor-panel.lua" --config src/raptor-panel/luapack.toml
%~dp0..\tools\luapack.exe bundle "%~dp0..\src\raptor-notifications\raptor-notifications.lua" --config src/raptor-notifications/luapack.toml

if %ERRORLEVEL% neq 0 (
    echo ERROR: Luapack bundling failed
    exit /b 1
)

echo [4/4] Copying assets...
robocopy "%~dp0..\src\raptor-notifications" "%~dp0..\dist\raptor-notifications" /E /XF *.lua *.toml /NFL /NDL /NJH /NJS >nul
robocopy "%~dp0..\src\raptor-panel" "%~dp0..\dist\raptor-panel" /E /XF *.lua *.toml /NFL /NDL /NJH /NJS >nul
REM Robocopy returns 0-7 for success (1=files copied, 0=no files), so reset errorlevel
if %ERRORLEVEL% LEQ 7 set ERRORLEVEL=0

endlocal

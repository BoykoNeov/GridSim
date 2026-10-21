@echo off
rem Double-click to start GridSim: finds Julia, then shows a menu of the windows.
rem The menu itself is ui\scripts\start.jl. Keep this file ASCII with CRLF endings.
setlocal
cd /d "%~dp0"

set "JULIA=julia"
where julia >nul 2>nul
if errorlevel 1 set "JULIA=%LOCALAPPDATA%\Microsoft\WindowsApps\julia.exe"
if not "%JULIA%"=="julia" if not exist "%JULIA%" (
    echo Julia was not found. Install it from https://julialang.org/downloads/
    echo ^(GridSim's windows need Julia 1.11 or newer^), then run this file again.
    pause
    exit /b 1
)

"%JULIA%" --project="%~dp0ui" "%~dp0ui\scripts\start.jl"
if errorlevel 1 (
    echo.
    echo GridSim stopped with an error - see the message above.
    pause
)
endlocal

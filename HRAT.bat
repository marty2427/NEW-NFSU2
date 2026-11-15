@echo off
rem ============================================================
rem  NEON WRECK - spusteni hry (bez otevirani editoru Godot)
rem ============================================================
cd /d "%~dp0"
title NEON WRECK

set "GODOT="
for %%F in ("%~dp0Godot*win64.exe") do if not defined GODOT set "GODOT=%%~fF"
if not defined GODOT for %%F in ("C:\Hry\Godot\Godot*win64.exe") do if not defined GODOT set "GODOT=%%~fF"
if not defined GODOT for /f "delims=" %%F in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%F"
if not defined GODOT goto nogodot

if not exist ".godot\imported" (
  echo Prvni spusteni: Godot pripravuje modely a textury, potrva to par minut...
  "%GODOT%" --path "%~dp0." --import
)
start "" "%GODOT%" --path "%~dp0."
exit /b 0

:nogodot
echo Nenasel jsem Godot.
echo Zkopiruj soubor Godot_v4.7.2-stable_win64.exe do slozky C:\Hry\Godot
echo nebo primo do teto slozky a spust HRAT.bat znovu.
pause
exit /b 1

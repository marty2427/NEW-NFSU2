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

rem --- Po kazde aktualizaci musi Godot projekt znovu pripravit, jinak hra nenabehne. ---
rem     Pozna se to podle oznaceni posledni stazene verze.
set "VER=bez-aktualizaci"
if exist ".git\FETCH_HEAD" for /f "usebackq tokens=1" %%H in (".git\FETCH_HEAD") do set "VER=%%H"
set "OLD=zadna"
if exist ".godot\nw_verze.txt" set /p OLD=<".godot\nw_verze.txt"
if not exist ".godot\imported" set "OLD=zadna"
if not exist ".godot\global_script_class_cache.cfg" set "OLD=zadna"
if "%VER%"=="%OLD%" goto run

echo.
echo  Pripravuji hru po aktualizaci: modely, textury, zvuky.
echo  Poprve to trva par minut, priste jen par vterin.
echo  Nic nemackej, toto okno samo pokracuje.
echo.
"%GODOT%" --headless --path "%~dp0." --import
if not exist ".godot\global_script_class_cache.cfg" goto importfail
>".godot\nw_verze.txt" echo %VER%

:run
echo.
echo  Spoustim hru. Nejdriv se asi 10 az 20 vterin stavi mesto.
start "" "%GODOT%" --path "%~dp0." --log-file "%~dp0hra_log.txt"
exit /b 0

:importfail
echo.
echo  CHYBA: priprava hry se nepovedla.
echo  Napis to Claudovi a posli mu, co je v tomto okne napsano.
pause
exit /b 1

:nogodot
echo Nenasel jsem Godot.
echo Zkopiruj soubor Godot_v4.7.2-stable_win64.exe do slozky C:\Hry\Godot
echo nebo primo do teto slozky a spust HRAT.bat znovu.
pause
exit /b 1

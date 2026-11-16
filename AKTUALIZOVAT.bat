@echo off
rem ============================================================
rem  NEON WRECK - aktualizace hry jednim kliknutim
rem  Stahne z GitHubu jen to, co se zmenilo (nic se nestahuje cele znovu).
rem ============================================================
cd /d "%~dp0"
title NEON WRECK - aktualizace

where git >nul 2>nul
if errorlevel 1 goto nogit

rem Cely zbytek je v jednom bloku: soubor se behem aktualizace muze prepsat sam.
(
  if not exist ".git" (
    echo Prvni spusteni: pripravuji slozku pro aktualizace...
    git init -q
    git remote add origin https://github.com/marty2427/NEW-NFSU2.git
  )
  echo Stahuji zmeny...
  git fetch --depth 1 origin claude/intelligent-pasteur-j1fblf
  if errorlevel 1 (
    echo.
    echo CHYBA: nepodarilo se spojit s GitHubem.
    echo Zkontroluj internet. Pokud se otevrelo okno s prihlasenim, prihlas se v nem ke GitHubu.
    pause
    exit /b 1
  )
  git reset -q --hard FETCH_HEAD
  echo.
  echo HOTOVO - hra je aktualni. Spust ji souborem HRAT.bat
  echo Prvni spusteni po aktualizaci trva o chvili dele - hra se pripravuje.
  echo.
  pause
  exit /b 0
)

:nogit
echo Na pocitaci chybi program Git (potrebny pro aktualizace).
echo Zkusim ho nainstalovat. Pokud se Windows zepta na povoleni, potvrd to.
echo.
winget install --id Git.Git -e --source winget
echo.
echo Az instalace skonci, ZAVRI toto okno a spust AKTUALIZOVAT.bat znovu.
pause
exit /b 1

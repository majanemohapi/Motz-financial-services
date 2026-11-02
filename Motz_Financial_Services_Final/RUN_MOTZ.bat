@echo off
setlocal
cd /d "%~dp0"
title Motz Financial Services - Loan Prediction
echo.
echo ============================================================
echo   MOTZ FINANCIAL SERVICES - LOAN INTELLIGENCE PLATFORM
echo ============================================================
echo.
set "SWIPL_EXE="
where swipl >nul 2>nul
if not errorlevel 1 set "SWIPL_EXE=swipl"
if not defined SWIPL_EXE if exist "%ProgramFiles%\swipl\bin\swipl.exe" set "SWIPL_EXE=%ProgramFiles%\swipl\bin\swipl.exe"
if not defined SWIPL_EXE if exist "C:\Program Files\swipl\bin\swipl.exe" set "SWIPL_EXE=C:\Program Files\swipl\bin\swipl.exe"
if not defined SWIPL_EXE (
  echo ERROR: SWI-Prolog was not found.
  echo Install SWI-Prolog for Windows or add its bin folder to PATH.
  echo.
  pause
  exit /b 1
)
if not exist "data\train.csv" (
  echo ERROR: data\train.csv is missing. Extract the complete ZIP first.
  echo.
  pause
  exit /b 1
)
echo Starting SWI-Prolog, loading Kaggle data and evaluating the model...
start "Motz Dashboard" cmd /c "timeout /t 4 /nobreak ^>nul ^& start http://localhost:8080"
"%SWIPL_EXE%" -q -s main.pl
echo.
echo The Motz server has stopped.
pause

@echo off
title Network Console - yerel ajan
where python >nul 2>nul
if errorlevel 1 (
  echo Python bulunamadi.
  echo Once https://python.org adresinden Python 3'u kurun.
  echo Kurulum ekraninda "Add python.exe to PATH" kutusunu isaretlemeyi unutmayin.
  echo.
  pause
  exit /b 1
)
python "%~dp0ping-agent.py"
echo.
echo Ajan durdu. Pencereyi kapatabilirsiniz.
pause

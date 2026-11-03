@echo off
cd /d "%~dp0"
python -m freeple_cleaner
if errorlevel 1 pause

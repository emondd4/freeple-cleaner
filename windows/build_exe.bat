@echo off
setlocal
cd /d "%~dp0"

echo ==> Installing PyInstaller
python -m pip install --upgrade pip pyinstaller

echo ==> Building FreepleCleaner.exe
python -m PyInstaller --noconfirm freeple_cleaner.spec

if not exist "dist\FreepleCleaner.exe" (
  echo Build failed.
  exit /b 1
)

mkdir ..\dist 2>nul
copy /Y "dist\FreepleCleaner.exe" "..\dist\FreepleCleaner-Windows.exe"
echo ==> Done: ..\dist\FreepleCleaner-Windows.exe
dir "..\dist\FreepleCleaner-Windows.exe"
endlocal

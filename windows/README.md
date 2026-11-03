# Freeple Cleaner for Windows

Companion to the macOS app. Clean reclaimable user data, remap bulky folders with directory junctions, and **move third-party apps** to a portable drive while keeping Microsoft/system apps on `C:`.

## Requirements

- Windows 10/11  
- Python 3.10+ (stdlib only — no pip packages required)

## Run

```bat
cd windows
python -m freeple_cleaner
```

Or double-click `run_freeple.bat`.

## Features

| Feature | Details |
| --- | --- |
| Clean | Temp, local caches, npm/pip/NuGet, browser caches, Recycle Bin |
| Remap Data | Junction selected folders onto a portable drive under `FreepleCleanerData\` |
| Move Apps | Third-party Program Files apps → portable SSD; Microsoft/Windows apps stay |

## Notes

- Moving apps may need the app closed first.  
- Keep the portable drive connected while using remapped apps.  
- Run as a normal user; junctions usually do not need admin.  
- State is stored in `%APPDATA%\FreepleCleaner\`.

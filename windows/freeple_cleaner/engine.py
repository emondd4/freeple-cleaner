"""Core scan / clean / remap / app-move logic for Freeple Cleaner (Windows)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


APP_SUPPORT = Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming"))) / "FreepleCleaner"
REMAP_DB = APP_SUPPORT / "remaps.json"
APP_REMAP_DB = APP_SUPPORT / "app-remaps.json"
DATA_DIR_NAME = "FreepleCleanerData"


MICROSOFT_PUBLISHER_HINTS = (
    "microsoft corporation",
    "microsoft windows",
    "windows publisher",
)

SYSTEM_APP_NAMES = {
    "microsoft edge",
    "microsoft edge update",
    "microsoft edge webview2 runtime",
    "windows security",
    "windows defender",
    "cortana",
    "xbox",
    "xbox game bar",
    "microsoft store",
    "photos",
    "paint",
    "notepad",
    "calculator",
    "snipping tool",
    "clock",
    "camera",
    "mail and calendar",
    "movies & tv",
    "groove music",
}


@dataclass
class CleanCategory:
    id: str
    title: str
    paths: list[str]
    size: int = 0
    selected: bool = False


@dataclass
class RemapRecord:
    id: str
    category_id: str
    title: str
    original: str
    destination: str
    volume: str


@dataclass
class AppInfo:
    name: str
    path: str
    size: int
    is_system: bool
    remapped: bool = False
    selected: bool = False


@dataclass
class AppRemapRecord:
    id: str
    name: str
    original: str
    destination: str
    volume: str
    size: int


def ensure_support() -> None:
    APP_SUPPORT.mkdir(parents=True, exist_ok=True)


def human_size(n: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    f = float(n)
    for u in units:
        if f < 1024 or u == units[-1]:
            return f"{f:.2f} {u}" if u != "B" else f"{int(f)} {u}"
        f /= 1024
    return f"{n} B"


def dir_size(path: Path) -> int:
    total = 0
    try:
        for root, _dirs, files in os.walk(path, onerror=lambda *_: None):
            for name in files:
                try:
                    total += (Path(root) / name).stat().st_size
                except OSError:
                    pass
    except OSError:
        return 0
    return total


def default_categories() -> list[CleanCategory]:
    local = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData/Local")))
    roaming = Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming")))
    temp = Path(tempfile.gettempdir())
    return [
        CleanCategory("temp", "Temporary Files", [str(temp)]),
        CleanCategory("local_temp", "Local App Temp", [str(local / "Temp")]),
        CleanCategory("prefetch_hint", "User Crash Dumps", [str(local / "CrashDumps")]),
        CleanCategory("nuget", "NuGet Cache", [str(Path.home() / ".nuget" / "packages")]),
        CleanCategory("npm", "npm Cache", [str(Path.home() / "AppData/Local/npm-cache"), str(Path.home() / ".npm")]),
        CleanCategory("pip", "pip Cache", [str(local / "pip" / "Cache")]),
        CleanCategory("chrome", "Chrome Cache", [str(local / "Google/Chrome/User Data/Default/Cache")]),
        CleanCategory("edge", "Edge Cache", [str(local / "Microsoft/Edge/User Data/Default/Cache")]),
        CleanCategory("recycle", "Recycle Bin (current user)", []),  # special
    ]


def scan_categories(cats: list[CleanCategory]) -> list[CleanCategory]:
    out = []
    for c in cats:
        size = 0
        if c.id == "recycle":
            size = recycle_bin_size()
        else:
            for p in c.paths:
                path = Path(p)
                if path.exists():
                    size += dir_size(path) if path.is_dir() else path.stat().st_size
        c.size = size
        c.selected = size > 0
        out.append(c)
    return sorted(out, key=lambda x: x.size, reverse=True)


def recycle_bin_size() -> int:
    # Best-effort via shell
    try:
        ps = (
            "(New-Object -ComObject Shell.Application).NameSpace(0xA).Items() "
            "| ForEach-Object { $_.Size } | Measure-Object -Sum | Select -ExpandProperty Sum"
        )
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return int(float(r.stdout.strip() or "0"))
    except Exception:
        return 0


def clean_category(cat: CleanCategory) -> tuple[int, list[str]]:
    warnings: list[str] = []
    freed = 0
    if cat.id == "recycle":
        try:
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"],
                capture_output=True,
                timeout=60,
            )
            freed = cat.size
        except Exception as e:
            warnings.append(str(e))
        return freed, warnings

    for p in cat.paths:
        path = Path(p)
        if not path.exists():
            continue
        try:
            if path.is_file():
                freed += path.stat().st_size
                path.unlink(missing_ok=True)
            else:
                for child in list(path.iterdir()):
                    try:
                        if child.is_dir() and not child.is_symlink():
                            freed += dir_size(child)
                            shutil.rmtree(child, ignore_errors=True)
                        else:
                            if child.exists():
                                freed += child.stat().st_size if child.is_file() else 0
                                if child.is_dir():
                                    shutil.rmtree(child, ignore_errors=True)
                                else:
                                    child.unlink(missing_ok=True)
                    except OSError as e:
                        warnings.append(f"{child.name}: {e}")
        except OSError as e:
            warnings.append(f"{path}: {e}")
    return freed, warnings


def list_removable_drives() -> list[dict]:
    drives = []
    try:
        ps = (
            "Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | "
            "Select-Object DriveLetter, FileSystemLabel, Size, SizeRemaining, DriveType | ConvertTo-Json"
        )
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            capture_output=True,
            text=True,
            timeout=30,
        )
        data = json.loads(r.stdout or "[]")
        if isinstance(data, dict):
            data = [data]
        for item in data:
            letter = item.get("DriveLetter")
            if not letter:
                continue
            root = f"{letter}:\\"
            drives.append(
                {
                    "id": root,
                    "name": item.get("FileSystemLabel") or f"Local Disk ({letter}:)",
                    "path": root,
                    "total": int(item.get("Size") or 0),
                    "free": int(item.get("SizeRemaining") or 0),
                    "portable": str(item.get("DriveType", "")).lower() in {"removable", "2"},
                }
            )
    except Exception:
        for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
            root = f"{letter}:\\"
            if os.path.exists(root):
                usage = shutil.disk_usage(root)
                drives.append(
                    {
                        "id": root,
                        "name": f"Drive ({letter}:)",
                        "path": root,
                        "total": usage.total,
                        "free": usage.free,
                        "portable": True,
                    }
                )
    # Prefer non-C:
    return sorted(drives, key=lambda d: (d["path"].upper().startswith("C:"), -d["free"]))


def load_json(path: Path, default):
    ensure_support()
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, data) -> None:
    ensure_support()
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def create_junction(link: Path, target: Path) -> None:
    # Directory junction does not require admin for many cases
    if link.exists() or link.is_symlink():
        if link.is_dir() and not link.is_symlink():
            shutil.rmtree(link)
        else:
            link.unlink(missing_ok=True)
    subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(link), str(target)],
        check=True,
        capture_output=True,
        text=True,
    )


def remap_folder(title: str, category_id: str, source: Path, volume: Path) -> RemapRecord:
    dest_root = volume / DATA_DIR_NAME / category_id
    dest_root.parent.mkdir(parents=True, exist_ok=True)
    dest = dest_root
    if dest.exists():
        shutil.rmtree(dest, ignore_errors=True)
    shutil.move(str(source), str(dest))
    create_junction(source, dest)
    rec = RemapRecord(
        id=os.urandom(8).hex(),
        category_id=category_id,
        title=title,
        original=str(source),
        destination=str(dest),
        volume=str(volume),
    )
    data = load_json(REMAP_DB, {"records": []})
    data["records"].append(asdict(rec))
    save_json(REMAP_DB, data)
    return rec


def is_system_app(name: str, path: str) -> bool:
    lower = name.lower().strip()
    if lower in SYSTEM_APP_NAMES:
        return True
    if any(h in lower for h in ("microsoft visual c++", "microsoft .net", "windows sdk")):
        return True
    p = path.lower().replace("/", "\\")
    if "\\windowsapps\\" in p:
        return True
    if p.startswith("c:\\windows\\"):
        return True
    # Publisher via PowerShell is slow; path heuristics for Program Files\Windows*
    if "\\windows nt\\" in p or "\\windows mail\\" in p:
        return True
    return False


def scan_installed_apps() -> list[AppInfo]:
    apps: list[AppInfo] = []
    remapped = {r["original"] for r in load_json(APP_REMAP_DB, {"records": []}).get("records", [])}
    roots = []
    for env in ("ProgramFiles", "ProgramFiles(x86)"):
        val = os.environ.get(env)
        if val:
            roots.append(Path(val))
    local = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs"
    if local.exists():
        roots.append(local)

    seen = set()
    for root in roots:
        if not root.exists():
            continue
        try:
            children = list(root.iterdir())
        except OSError:
            continue
        for child in children:
            if not child.is_dir():
                continue
            # Prefer folders that look like apps (contain .exe)
            exe = next(child.glob("*.exe"), None)
            if exe is None:
                nested = list(child.glob("*/*.exe"))
                exe = nested[0] if nested else None
            if exe is None:
                continue
            key = str(child).lower()
            if key in seen:
                continue
            seen.add(key)
            name = child.name
            system = is_system_app(name, str(child))
            size = dir_size(child)
            apps.append(
                AppInfo(
                    name=name,
                    path=str(child),
                    size=size,
                    is_system=system,
                    remapped=str(child) in remapped or child.is_symlink(),
                )
            )
    return sorted(apps, key=lambda a: (a.is_system, -a.size, a.name.lower()))


def move_apps(apps: Iterable[AppInfo], volume: Path) -> tuple[int, list[str]]:
    dest_root = volume / DATA_DIR_NAME / "Apps"
    dest_root.mkdir(parents=True, exist_ok=True)
    moved = 0
    warnings: list[str] = []
    data = load_json(APP_REMAP_DB, {"records": []})
    for app in apps:
        if app.is_system:
            warnings.append(f"Skipped system/Microsoft app: {app.name}")
            continue
        src = Path(app.path)
        if not src.exists():
            warnings.append(f"Missing: {app.name}")
            continue
        dest = dest_root / src.name
        try:
            if dest.exists():
                shutil.rmtree(dest, ignore_errors=True)
            shutil.move(str(src), str(dest))
            create_junction(src, dest)
            rec = AppRemapRecord(
                id=os.urandom(8).hex(),
                name=app.name,
                original=str(src),
                destination=str(dest),
                volume=str(volume),
                size=app.size,
            )
            data["records"].append(asdict(rec))
            moved += 1
        except Exception as e:
            warnings.append(f"{app.name}: {e}")
            if not src.exists() and dest.exists():
                try:
                    create_junction(src, dest)
                except Exception:
                    pass
    save_json(APP_REMAP_DB, data)
    return moved, warnings


def restore_app(record: dict) -> None:
    src = Path(record["original"])
    dest = Path(record["destination"])
    if src.exists() or src.is_symlink():
        if src.is_dir() and not src.is_symlink():
            shutil.rmtree(src, ignore_errors=True)
        else:
            # junction
            subprocess.run(["cmd", "/c", "rmdir", str(src)], capture_output=True)
            src.unlink(missing_ok=True)
    shutil.move(str(dest), str(src))
    data = load_json(APP_REMAP_DB, {"records": []})
    data["records"] = [r for r in data["records"] if r.get("id") != record.get("id")]
    save_json(APP_REMAP_DB, data)


def boot_disk_stats() -> tuple[int, int]:
    usage = shutil.disk_usage(os.environ.get("SystemDrive", "C:") + "\\")
    return usage.total, usage.free

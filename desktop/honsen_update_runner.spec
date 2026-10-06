# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

root = Path(SPEC).resolve().parent.parent
icon_path = root / "logo.ico"
version_info = root / "desktop" / "windows-version-info.txt"

if not icon_path.is_file() or not version_info.is_file():
    raise SystemExit("Build the icon and Windows version metadata before packaging.")

a = Analysis([str(root / "desktop" / "update_runner.py")], pathex=[str(root)], binaries=[], datas=[], hiddenimports=[], hookspath=[], hooksconfig={}, runtime_hooks=[], excludes=[], noarchive=False)
pyz = PYZ(a.pure, a.zipped_data)
exe = EXE(pyz, a.scripts, a.binaries, a.zipfiles, a.datas, [], name="HonsenUpdateRunner", console=False, icon=str(icon_path), version=str(version_info))

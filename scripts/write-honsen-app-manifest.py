"""Write Honsen discovery metadata and PyInstaller Windows version metadata."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA_PATH = ROOT / "desktop" / "honsen-app-metadata.json"


def write_version_info(path: Path, version: str) -> None:
    numbers = [int(part) for part in version.split(".")]
    if len(numbers) != 3:
        raise SystemExit(f"Version must be major.minor.patch: {version}")
    tuple_version = ", ".join(map(str, [*numbers, 0]))
    path.write_text(
        f"""# UTF-8\nVSVersionInfo(\n  ffi=FixedFileInfo(filevers=({tuple_version}), prodvers=({tuple_version}), mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)),\n  kids=[StringFileInfo([StringTable('040904B0', [StringStruct('CompanyName', 'Honsen'), StringStruct('FileDescription', 'Honsen WMS'), StringStruct('FileVersion', '{version}'), StringStruct('InternalName', 'Honsen WMS'), StringStruct('OriginalFilename', 'Honsen WMS.exe'), StringStruct('ProductName', 'Honsen WMS'), StringStruct('ProductVersion', '{version}')])]), VarFileInfo([VarStruct('Translation', [1033, 1200])])]\n)\n""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path, nargs="?")
    parser.add_argument("--version-info", type=Path)
    args = parser.parse_args()

    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    if args.version_info:
        write_version_info(args.version_info, metadata["version"])
        return
    if not args.directory:
        parser.error("directory is required unless --version-info is used")
    executable = args.directory / metadata["executable"]
    runner = args.directory / metadata["updateRunner"]
    if not executable.is_file() or not runner.is_file():
        raise SystemExit(f"Missing built executable: {executable}")

    (args.directory / "honsen.app.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()

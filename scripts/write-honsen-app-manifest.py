"""Write the Honsen Program discovery manifest beside a packaged executable."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA_PATH = ROOT / "desktop" / "honsen-app-metadata.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    executable = args.directory / metadata["executable"]
    if not executable.is_file():
        raise SystemExit(f"Missing built executable: {executable}")

    (args.directory / "honsen.app.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()

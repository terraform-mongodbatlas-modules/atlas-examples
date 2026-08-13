"""Download the HybridRAG AI-governance seed pack into a local cache."""

from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

import yaml

CACHE_DIR = Path(__file__).resolve().parent / "cache"
URLS_YAML = Path(__file__).resolve().parent / "urls.yaml"


def _load_pins() -> dict:
    return yaml.safe_load(URLS_YAML.read_text())


def download(*, dest: Path = CACHE_DIR) -> list[Path]:
    pins = _load_pins()
    dest.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for item in pins["nist"]["files"]:
        written.append(_fetch(item["url"], dest / item["filename"]))
    owasp = pins["owasp"]
    owasp_dir = dest / "owasp-llm-top10"
    owasp_dir.mkdir(parents=True, exist_ok=True)
    for name in owasp["files"]:
        written.append(_fetch(f"{owasp['raw_base']}/{name}", owasp_dir / name))
    return written


def _fetch(url: str, path: Path) -> Path:
    req = urllib.request.Request(url, headers={"User-Agent": "atlas-examples-hybridrag-seed"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        path.write_bytes(resp.read())
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Download the HybridRAG AI-governance seed pack.")
    parser.add_argument("--dest", type=Path, default=CACHE_DIR, help="Cache directory (gitignored).")
    args = parser.parse_args(argv)
    paths = download(dest=args.dest)
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

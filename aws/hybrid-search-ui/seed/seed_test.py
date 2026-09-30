from __future__ import annotations

from pathlib import Path

SEED_DIR = Path(__file__).parent
SEED_FILE = SEED_DIR / "why-mongodb-for-agents.md"


def test_seed_file_present_and_non_empty():
    assert SEED_FILE.exists()
    assert SEED_FILE.suffix in {".md", ".txt"}
    assert SEED_FILE.read_text().strip()

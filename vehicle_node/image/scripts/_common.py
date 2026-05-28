from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ROOT.parent
SRC = ROOT / "src"

for entry in [REPO_ROOT, SRC]:
    if str(entry) not in sys.path:
        sys.path.insert(0, str(entry))

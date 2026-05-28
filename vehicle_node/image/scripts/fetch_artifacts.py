from __future__ import annotations

import argparse
from hashlib import sha256
from pathlib import Path
from urllib.request import urlopen
import tomllib


def _digest_file(path: Path) -> str:
    hasher = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True)
    parser.add_argument("--cache-dir", required=True)
    args = parser.parse_args()

    with Path(args.lock).open("rb") as handle:
        lock = tomllib.load(handle)

    cache_dir = Path(args.cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    for artifact in lock.values():
        target = cache_dir / artifact["filename"]

        if not target.exists():
            with urlopen(artifact["url"]) as response, target.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)

        if _digest_file(target) != artifact["sha256"]:
            raise SystemExit(f"sha256 mismatch for {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

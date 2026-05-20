"""
Validate every JSON file in examples/ against its matching schema in schemas/.

Schema is selected by the `kind` field on each example:
  - kind: "plant"     -> plant.schema.json
  - kind: "fauna"     -> fauna.schema.json
  - kind: "substrate" -> substrate.schema.json

Exits non-zero if any file fails validation.

Run:
    pip install jsonschema
    python3 validate.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("Missing dependency: pip install jsonschema", file=sys.stderr)
    sys.exit(2)


HERE = Path(__file__).parent
SCHEMA_FOR_KIND = {
    "plant": HERE / "schemas" / "plant.schema.json",
    "fauna": HERE / "schemas" / "fauna.schema.json",
    "substrate": HERE / "schemas" / "substrate.schema.json",
}


def load_json(path: Path):
    with path.open() as f:
        return json.load(f)


def main() -> int:
    examples_dir = HERE / "examples"
    if not examples_dir.exists():
        print(f"no examples directory at {examples_dir}", file=sys.stderr)
        return 2

    schemas = {kind: load_json(path) for kind, path in SCHEMA_FOR_KIND.items()}
    validators = {kind: Draft202012Validator(s) for kind, s in schemas.items()}

    failures = 0
    total = 0
    for path in sorted(examples_dir.glob("*.json")):
        total += 1
        doc = load_json(path)
        kind = doc.get("kind")
        if kind not in validators:
            print(f"FAIL {path.name}: unknown kind={kind!r}")
            failures += 1
            continue
        errors = sorted(validators[kind].iter_errors(doc), key=lambda e: list(e.absolute_path))
        if errors:
            failures += 1
            print(f"FAIL {path.name}: {len(errors)} error(s)")
            for err in errors:
                loc = ".".join(str(p) for p in err.absolute_path) or "<root>"
                print(f"  - {loc}: {err.message}")
        else:
            print(f"OK   {path.name} ({kind})")

    print(f"\n{total - failures}/{total} passed.")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

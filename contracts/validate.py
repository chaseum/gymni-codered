"""Validate contract fixtures (default) or JSON lines from stdin against gymai.schema.json.

    python contracts/validate.py                          # every fixture
    python -m fitness_ml sample | python contracts/validate.py --stdin observation
"""
import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

HERE = Path(__file__).parent
SCHEMA = json.loads((HERE / "gymai.schema.json").read_text())
KIND_TO_DEF = {"heart_rate": "heart_rate_sample"}  # fixture step kind -> $defs name when they differ


def validator(kind: str) -> Draft202012Validator:
    name = KIND_TO_DEF.get(kind, kind)
    if name not in SCHEMA["$defs"]:
        raise SystemExit(f"unknown kind {kind!r}")
    return Draft202012Validator({**SCHEMA, "$ref": f"#/$defs/{name}"})


def errors(kind: str, data) -> list[str]:
    return [f"{'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in validator(kind).iter_errors(data)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stdin", metavar="KIND", help="validate JSON lines from stdin as KIND")
    args = ap.parse_args()
    failed = 0
    if args.stdin:
        for n, line in enumerate(sys.stdin, 1):
            if line.strip():
                for err in errors(args.stdin, json.loads(line)):
                    failed += 1
                    print(f"stdin:{n}: {err}")
    else:
        for path in sorted((HERE / "fixtures").glob("*.json")):
            fixture, before = json.loads(path.read_text()), failed
            for i, step in enumerate(fixture["steps"]):
                for err in errors(step["kind"], step["data"]):
                    failed += 1
                    print(f"{path.name} step {i} ({step['kind']}): {err}")
            print(f"{'FAIL' if failed > before else 'ok  '} {path.name}")
    print("all valid" if not failed else f"{failed} error(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

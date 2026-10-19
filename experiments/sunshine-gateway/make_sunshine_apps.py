#!/usr/bin/env python3
"""Merge two selectable cloud gaming apps into a Sunshine apps.json file.

Writes only to stdout. Back up the existing file and review before installing.
Sunshine must be running on the remote compute server to serve Moonlight apps.
"""
import argparse
import json
from pathlib import Path
import sys

APPS = (
    ("GeForce NOW", "geforce-now"),
    ("Xbox Cloud Gaming", "xbox-cloud"),
)

def merge_apps(original):
    if not isinstance(original, dict):
        raise ValueError("Sunshine app configuration must be an object")
    existing = original.get("apps", [])
    if not isinstance(existing, list):
        raise ValueError("'apps' must be an array")
    names = {name for name, _ in APPS}
    merged = [app for app in existing if isinstance(app, dict) and app.get("name") not in names]
    for name, argument in APPS:
        merged.append({
            "name": name,
            "cmd": "$(HOME)/.local/bin/cloudgaming-app " + argument,
            "auto-detach": False,
            "wait-all": False,
            "exit-timeout": 5,
        })
    result = original.copy()
    result["apps"] = merged
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--existing", type=Path, help="Optional existing Sunshine apps.json to preserve")
    args = parser.parse_args()
    original = {}
    if args.existing:
        try:
            original = json.loads(args.existing.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print("Cannot read existing Sunshine apps.json:", exc, file=sys.stderr)
            return 2
    try:
        print(json.dumps(merge_apps(original), ensure_ascii=False, indent=2))
        return 0
    except ValueError as exc:
        print("Invalid Sunshine application list:", exc, file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())

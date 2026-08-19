#!/usr/bin/env python3
import argparse
import datetime as dt
from pathlib import Path

import yaml


def parse_value(value):
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if len(value) > 1 and value.startswith("0") and value.isdigit():
        return value
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def main():
    parser = argparse.ArgumentParser(description="Write a reproducibility manifest for EVK4 data.")
    parser.add_argument("--output", required=True)
    parser.add_argument("--field", action="append", default=[])
    args = parser.parse_args()

    manifest = {
        "manifest_version": 1,
        "created_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    for field in args.field:
        if "=" not in field:
            raise ValueError(f"Expected KEY=VALUE, got: {field}")
        key, value = field.split("=", 1)
        manifest[key] = parse_value(value)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as stream:
        yaml.safe_dump(manifest, stream, sort_keys=False, default_flow_style=False)


if __name__ == "__main__":
    main()

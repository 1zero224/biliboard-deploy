#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Update a single dotenv KEY=VALUE entry.")
    parser.add_argument("--file", required=True, help="Path to dotenv file")
    parser.add_argument("--key", required=True, help="Dotenv key, e.g. BACKEND_REF")
    parser.add_argument("--value", required=True, help="Value to set (no newlines)")
    args = parser.parse_args()

    key = args.key.strip()
    value = args.value

    if not re.fullmatch(r"[A-Z0-9_]+", key):
        raise SystemExit(f"Invalid key: {key!r}")
    if "\n" in value or "\r" in value:
        raise SystemExit("Invalid value: must not contain newlines")

    path = Path(args.file)
    if not path.exists():
        raise SystemExit(f"File not found: {path}")

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    key_line_re = re.compile(rf"^(\s*){re.escape(key)}\s*=.*$")

    found = False
    out: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("#"):
            out.append(line)
            continue

        match = key_line_re.match(line)
        if match:
            indent = match.group(1)
            newline = "\n" if line.endswith("\n") else ""
            out.append(f"{indent}{key}={value}{newline}")
            found = True
            continue

        out.append(line)

    if not found:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.append(f"{key}={value}\n")

    path.write_text("".join(out), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

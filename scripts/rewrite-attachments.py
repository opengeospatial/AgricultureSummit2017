#!/usr/bin/env python3
"""Rewrite Foswiki attachment macros using the generated attachment manifest."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from urllib.parse import quote


def encoded_path(value: str) -> str:
    return "/".join(quote(part, safe="-._~") for part in value.split("/"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", required=True)
    parser.add_argument("--source-web", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()

    text = sys.stdin.read()
    with args.manifest.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))

    rows.sort(key=lambda row: len(row["filename"]), reverse=True)
    for row in rows:
        if row["topic"] != args.topic:
            continue

        if row["role"] == "wiki-image":
            destination = encoded_path(row["target"])
        elif row["role"] == "wiki-doc":
            destination = (
                f"https://raw.githubusercontent.com/{args.repo}/"
                f"{args.branch}/{encoded_path(row['target'])}"
            )
        else:
            raise ValueError(f"Unknown attachment role: {row['role']}")

        filename = re.escape(row["filename"])
        source_web = re.escape(args.source_web)
        topic = re.escape(args.topic)
        patterns = (
            rf"%ATTACHURL(?:PATH)?%/[ \t]*{filename}",
            rf"%PUBURL(?:PATH)?%/{source_web}/{topic}/[ \t]*{filename}",
        )
        for pattern in patterns:
            text = re.sub(pattern, lambda _match, value=destination: value, text)

    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

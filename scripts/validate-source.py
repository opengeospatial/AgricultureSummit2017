#!/usr/bin/env python3
"""Cross-check migrated TML attachment metadata, references, and manifest."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


META_RE = re.compile(r'^%META:FILEATTACHMENT\{[^\n]*\bname="([^"]+)"', re.MULTILINE)
ATTACH_RE = re.compile(r"%ATTACHURL(?:PATH)?%/([^\]\n\"<]+)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--topic", action="append", default=[])
    args = parser.parse_args()

    errors = []
    notices = []
    with args.manifest.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))

    by_topic = {topic: [] for topic in args.topic}
    seen_targets = set()
    for row in rows:
        topic = row["topic"]
        if topic not in by_topic:
            errors.append(f"attachment belongs to a non-migrated topic: {topic}/{row['filename']}")
            continue
        key = (topic, row["filename"])
        if any((item["topic"], item["filename"]) == key for item in by_topic[topic]):
            errors.append(f"duplicate attachment manifest entry: {topic}/{row['filename']}")
        if row["target"] in seen_targets:
            errors.append(f"duplicate attachment target: {row['target']}")
        seen_targets.add(row["target"])
        by_topic[topic].append(row)

    for topic in args.topic:
        source = args.source_root / f"{topic}.txt"
        if not source.is_file():
            errors.append(f"missing migrated source: {source.name}")
            continue
        text = source.read_text(encoding="utf-8")
        metadata = set(META_RE.findall(text))
        manifest_names = {row["filename"] for row in by_topic[topic]}
        if metadata != manifest_names:
            for name in sorted(metadata - manifest_names):
                errors.append(f"{source.name}: metadata attachment has no exported file: {name}")
            for name in sorted(manifest_names - metadata):
                errors.append(f"{source.name}: exported file has no FILEATTACHMENT metadata: {name}")

        body = "\n".join(line for line in text.splitlines() if not line.startswith("%META:"))
        body_refs = {match.strip() for match in ATTACH_RE.findall(body)}
        for name in sorted(body_refs - manifest_names):
            errors.append(f"{source.name}: attachment reference has no exported file: {name}")
        for name in sorted(manifest_names - body_refs):
            notices.append(
                f"{source.name}: attachment is metadata-only; converter will add a link: {name}"
            )

    for notice in notices:
        print(f"NOTE: {notice}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Cross-checked {len(rows)} attachments against migrated TML metadata.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

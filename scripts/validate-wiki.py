#!/usr/bin/env python3
"""Validate generated wiki pages, local links, and attachment coverage."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from urllib.parse import quote, unquote


LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
RESIDUAL_RE = re.compile(
    r"%[A-Z][A-Z0-9]*(?:\{[^\n%]*\})?%|</?(?:sticky|nop)>|\[\[[^\n]+\]\]"
)


def encoded_path(value: str) -> str:
    return "/".join(quote(part, safe="-._~") for part in value.split("/"))


def topic_page(topic: str, home_topic: str) -> str:
    return "Home" if topic == home_topic else topic


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wiki-root", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--home-topic", required=True)
    parser.add_argument("--page", action="append", default=[])
    args = parser.parse_args()

    errors: list[str] = []
    expected_pages = set(args.page)
    actual_pages = {path.stem for path in args.wiki_root.glob("*.md")}
    extras = actual_pages - expected_pages - {"_Sidebar", "_Footer"}
    missing = expected_pages - actual_pages
    if missing:
        errors.append(f"missing wiki pages: {', '.join(sorted(missing))}")
    if extras:
        errors.append(f"unexpected wiki pages: {', '.join(sorted(extras))}")

    page_text: dict[str, str] = {}
    for page in sorted(expected_pages):
        path = args.wiki_root / f"{page}.md"
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        page_text[page] = text
        if not re.search(r"^#{1,6}\s+\S", text, re.MULTILINE):
            errors.append(f"{path.name}: no non-empty heading")
        for match in RESIDUAL_RE.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"{path.name}:{line}: residual Foswiki syntax: {match.group(0)!r}")

        for match in LINK_RE.finditer(text):
            target = match.group(1).strip().split(maxsplit=1)[0].strip("<>")
            if not target or target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path_part = unquote(target.split("#", 1)[0])
            if not path_part:
                continue
            if path_part.startswith(("images/", "./", "../")) or "." in Path(path_part).name:
                local_target = (path.parent / path_part).resolve()
                try:
                    local_target.relative_to(args.wiki_root.resolve())
                except ValueError:
                    errors.append(f"{path.name}: local link escapes wiki tree: {target}")
                    continue
                if not local_target.is_file():
                    errors.append(f"{path.name}: missing local target: {target}")
            else:
                candidate = path_part[:-3] if path_part.endswith(".md") else path_part
                if candidate not in actual_pages:
                    errors.append(f"{path.name}: missing wiki page target: {target}")

    with args.manifest.open(newline="", encoding="utf-8") as stream:
        attachments = list(csv.DictReader(stream, delimiter="\t"))
    for row in attachments:
        page = topic_page(row["topic"], args.home_topic)
        text = page_text.get(page, "")
        if row["role"] == "wiki-doc":
            expected = (
                f"https://raw.githubusercontent.com/{args.repo}/{args.branch}/"
                f"{encoded_path(row['target'])}"
            )
        elif row["role"] == "wiki-image":
            expected = encoded_path(row["target"])
        else:
            errors.append(f"attachment manifest has unknown role: {row['role']}")
            continue
        if expected not in text:
            errors.append(f"{page}.md: attachment is not linked: {expected}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(
        f"Validated {len(expected_pages)} pages and {len(attachments)} attachment references."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

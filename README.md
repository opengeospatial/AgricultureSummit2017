# OGC Agriculture Summit 2017 wiki archive

This repository preserves the non-default topics from the former OGC public
Foswiki web `AgricultureSummit` and publishes them through the
[GitHub Wiki](https://github.com/opengeospatial/AgricultureSummit2017/wiki).

## Repository layout

- `Source2026/` contains the discovered, non-excluded TML snapshot from
  2026-09-17.
- `scripts/` contains the repeatable migration tooling.
- `manifests/` records source and attachment checksums.
- The orphan `wiki-docs` branch contains non-image attachments.
- `AgricultureSummit2017.wiki.git` contains converted Markdown and wiki images.

Generated files under `build/` are intentionally ignored. See
[MIGRATION_PLAYBOOK.md](MIGRATION_PLAYBOOK.md) for the complete dry-run,
review, publishing, and validation workflow.

The original public web is available at
<https://external.ogc.org/twiki_public/AgricultureSummit/WebHome>.

## Historical scope

The migration discovers every current `.txt` topic and excludes only the
configured default Foswiki infrastructure topics. For this snapshot, that
produces `WebHome` and seven Agriculture Summit content topics. RCS `,v` files
are excluded.
The original Foswiki revision numbers remain in each TML file's metadata, but
the GitHub Wiki begins a new revision history at import time.

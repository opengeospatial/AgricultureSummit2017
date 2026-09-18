#!/usr/bin/env bash

# Replace the initialized GitHub Wiki seed with generated Markdown/assets.
# Dry-run is the default. Existing non-seed content is never replaced silently.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PUSH=0
REPLACE=0

usage() {
  cat <<'EOF'
Usage: scripts/stage-for-wiki.sh [--push] [--replace-existing]

The initialized one-page GitHub seed is safe to replace without an extra flag.
Any other differing wiki requires --replace-existing after manual review.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1 ;;
    --replace-existing) REPLACE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

need_cmd git
[[ -d "$WIKI_BUILD_ROOT" ]] || die "Missing build/wiki; run convert-twiki2md.sh"
"$SCRIPT_DIR/validate-migration.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT INT TERM HUP
desired="$work/desired"
repo="$work/repo"
mkdir -p "$desired"
cp -R "$WIKI_BUILD_ROOT"/. "$desired"/
printf '%s\n' "$MIGRATION_ID" >"$desired/.foswiki-migration"

git clone --quiet --single-branch --branch "$TARGET_WIKI_BRANCH" \
  "$TARGET_WIKI_URL" "$repo"

if diff -qr --exclude=.git "$desired" "$repo" >/dev/null 2>&1; then
  log "GitHub Wiki is already up to date."
  exit 0
fi

seed_state=0
tracked="$(git -C "$repo" ls-files)"
repo_name="${TARGET_REPO_SLUG##*/}"
if [[ "$tracked" == "Home.md" ]] && \
   grep -Fxq "Welcome to the $repo_name wiki!" "$repo/Home.md"; then
  seed_state=1
fi

marker="$repo/.foswiki-migration"
marked_state=0
if [[ -f "$marker" && "$(cat "$marker")" == "$MIGRATION_ID" ]]; then
  marked_state=1
fi

if [[ "$seed_state" != "1" && "$marked_state" != "1" && "$REPLACE" != "1" ]]; then
  die "Wiki contains non-seed, unmarked content; use --replace-existing only after review"
fi
if [[ "$marked_state" == "1" && "$REPLACE" != "1" ]]; then
  die "Marked wiki differs; use --replace-existing to restage it"
fi

find "$repo" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
cp -R "$desired"/. "$repo"/
git -C "$repo" add --all
git -C "$repo" status --short

if [[ "$PUSH" != "1" ]]; then
  log "Dry-run only. Rerun with --push to publish the GitHub Wiki."
  exit 0
fi

git -C "$repo" \
  -c "user.name=$GIT_AUTHOR_NAME" \
  -c "user.email=$GIT_AUTHOR_EMAIL" \
  commit --quiet \
  -m "Import $SOURCE_WEB wiki from Foswiki"
git -C "$repo" push origin "$TARGET_WIKI_BRANCH"
log "Published GitHub Wiki: https://github.com/$TARGET_REPO_SLUG/wiki"

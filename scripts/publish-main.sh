#!/usr/bin/env bash

# Stage the migration kit on a review branch in the target main repository.
# Dry-run is the default. --push creates/updates MAIN_IMPORT_BRANCH, never main.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PUSH=0

usage() {
  cat <<'EOF'
Usage: scripts/publish-main.sh [--push]

Stages README, Source2026, manifests, configuration, scripts, and templates on
the configured migration review branch. It never pushes directly to main.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

need_cmd git
[[ -d "$SOURCE_ROOT" ]] || die "Missing Source2026; run prepare-source.sh --apply"
[[ -d "$MANIFEST_ROOT" ]] || die "Missing manifests; run prepare-source.sh --apply"
"$SCRIPT_DIR/validate-migration.sh" --source-only

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT INT TERM HUP
repo="$work/repo"
git clone --quiet "$TARGET_REPO_URL" "$repo"

if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$MAIN_IMPORT_BRANCH"; then
  git -C "$repo" switch --quiet --create "$MAIN_IMPORT_BRANCH" \
    --track "origin/$MAIN_IMPORT_BRANCH"
else
  git -C "$repo" switch --quiet --create "$MAIN_IMPORT_BRANCH" \
    "origin/$TARGET_MAIN_BRANCH"
fi

managed=(
  .gitignore
  README.md
  MIGRATION_PLAYBOOK.md
  migration.conf
  "$SOURCE_DIR"
  "$MANIFEST_DIR"
  scripts
  templates
)
for item in "${managed[@]}"; do
  [[ -e "$PROJECT_ROOT/$item" ]] || die "Missing managed project item: $item"
  rm -rf -- "$repo/$item"
  cp -R "$PROJECT_ROOT/$item" "$repo/$item"
done
# Never publish local editor/interpreter scratch files copied with a directory.
find "$repo/scripts" "$repo/templates" \
  \( -name '*.swp' -o -name '*.pyc' -o -name .DS_Store \) -delete
find "$repo/scripts" "$repo/templates" -type d -name __pycache__ -prune \
  -exec rm -rf -- {} +
printf '%s\n' "$MIGRATION_ID" >"$repo/.foswiki-migration"

git -C "$repo" add -- .foswiki-migration "${managed[@]}"
if git -C "$repo" diff --cached --quiet; then
  log "Main migration branch is already up to date."
  exit 0
fi

git -C "$repo" diff --cached --stat
if [[ "$PUSH" != "1" ]]; then
  log "Dry-run only. Rerun with --push to publish $MAIN_IMPORT_BRANCH."
  exit 0
fi

git -C "$repo" \
  -c "user.name=$GIT_AUTHOR_NAME" \
  -c "user.email=$GIT_AUTHOR_EMAIL" \
  commit --quiet \
  -m "Import $SOURCE_WEB Foswiki source snapshot"
git -C "$repo" push --set-upstream origin "$MAIN_IMPORT_BRANCH"
log "Pushed review branch: $MAIN_IMPORT_BRANCH"
log "Open: https://github.com/$TARGET_REPO_SLUG/compare/$TARGET_MAIN_BRANCH...$MAIN_IMPORT_BRANCH?expand=1"

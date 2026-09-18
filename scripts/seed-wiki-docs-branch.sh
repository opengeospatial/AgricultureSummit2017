#!/usr/bin/env bash

# Create the configured orphan attachment branch from build/wiki-docs.
# Dry-run is the default. Existing content is never replaced implicitly.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PUSH=0
REPLACE=0

usage() {
  cat <<'EOF'
Usage: scripts/seed-wiki-docs-branch.sh [--push] [--replace-existing]

Without --push, constructs the orphan branch in a temporary clone and prints
the staged diff. --replace-existing is required to change an existing marked
wiki-docs branch; an unmarked branch is always refused.
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
need_cmd sed
[[ -d "$WIKI_DOCS_BUILD_ROOT" ]] || die "Missing build/wiki-docs"
[[ -f "$MANIFEST_ROOT/wiki-docs.sha256" ]] || die "Missing wiki-docs manifest"
[[ -f "$PROJECT_ROOT/templates/wiki-docs-README.md" ]] || die "Missing wiki-docs README template"
"$SCRIPT_DIR/validate-migration.sh" --source-only

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT INT TERM HUP
desired="$work/desired"
repo="$work/repo"
mkdir -p "$desired"
cp -R "$WIKI_DOCS_BUILD_ROOT"/. "$desired"/
cp "$MANIFEST_ROOT/wiki-docs.sha256" "$desired/SHA256SUMS"
sed \
  -e "s|{{REPO_SLUG}}|$TARGET_REPO_SLUG|g" \
  -e "s|{{ATTACHMENT_BRANCH}}|$ATTACHMENT_BRANCH|g" \
  "$PROJECT_ROOT/templates/wiki-docs-README.md" >"$desired/README.md"
printf '%s\n' "$MIGRATION_ID" >"$desired/.foswiki-migration"

branch_exists=0
if git ls-remote --exit-code --heads "$TARGET_REPO_URL" "$ATTACHMENT_BRANCH" >/dev/null 2>&1; then
  branch_exists=1
  git clone --quiet --single-branch --branch "$ATTACHMENT_BRANCH" \
    "$TARGET_REPO_URL" "$repo"
  marker="$repo/.foswiki-migration"
  [[ -f "$marker" && "$(cat "$marker")" == "$MIGRATION_ID" ]] || \
    die "Existing $ATTACHMENT_BRANCH branch is not marked for $MIGRATION_ID"
  if diff -qr --exclude=.git "$desired" "$repo" >/dev/null 2>&1; then
    log "$ATTACHMENT_BRANCH is already up to date."
    exit 0
  fi
  [[ "$REPLACE" == "1" ]] || \
    die "$ATTACHMENT_BRANCH differs; inspect it and use --replace-existing"
else
  git clone --quiet "$TARGET_REPO_URL" "$repo"
  git -C "$repo" switch --quiet --orphan "$ATTACHMENT_BRANCH"
fi

find "$repo" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
cp -R "$desired"/. "$repo"/
git -C "$repo" add --all
git -C "$repo" status --short

if [[ "$PUSH" != "1" ]]; then
  log "Dry-run only. Rerun with --push to publish $ATTACHMENT_BRANCH."
  exit 0
fi

git -C "$repo" \
  -c "user.name=$GIT_AUTHOR_NAME" \
  -c "user.email=$GIT_AUTHOR_EMAIL" \
  commit --quiet \
  -m "Import $SOURCE_WEB wiki document attachments"
if [[ "$branch_exists" == "1" ]]; then
  git -C "$repo" push origin "$ATTACHMENT_BRANCH"
else
  git -C "$repo" push --set-upstream origin "$ATTACHMENT_BRANCH"
fi
log "Published orphan branch: $ATTACHMENT_BRANCH"

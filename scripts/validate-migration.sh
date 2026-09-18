#!/usr/bin/env bash

# Validate local generated output and, optionally, the published GitHub state.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CHECK_REMOTE=0
SOURCE_ONLY=0

usage() {
  cat <<'EOF'
Usage: scripts/validate-migration.sh [--source-only | --remote]

Local validation is always performed. --source-only stops after checking the
discovered source and staged attachment checksums. --remote also checks the
published wiki-docs branch, raw attachment URLs, and public Wiki page URLs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) CHECK_REMOTE=1 ;;
    --source-only) SOURCE_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

[[ "$SOURCE_ONLY" != "1" || "$CHECK_REMOTE" != "1" ]] || \
  die "--source-only and --remote cannot be combined"

need_cmd python3
need_cmd shasum

[[ -d "$SOURCE_ROOT" ]] || die "Missing source tree: $SOURCE_ROOT"
[[ -d "$WIKI_DOCS_BUILD_ROOT" ]] || die "Missing staged wiki-docs tree"
[[ -d "$WIKI_IMAGES_BUILD_ROOT" ]] || die "Missing staged wiki-images tree"

source_topics=()
expected_pages=()
while IFS= read -r topic; do
  source_topics+=("$topic")
  expected_pages+=("$(topic_output_name "$topic")")
done < <(list_source_topics)
[[ ${#source_topics[@]} -gt 0 ]] || die "No prepared source topics found"

for topic in "${source_topics[@]}"; do
  ! topic_is_excluded "$topic" || die "Excluded topic leaked into source: $topic"
done
[[ -f "$SOURCE_ROOT/$HOME_TOPIC.txt" ]] || die "Missing configured home topic: $HOME_TOPIC.txt"

verify_sha256_manifest "$SOURCE_ROOT" "$MANIFEST_ROOT/source.sha256"
verify_sha256_manifest "$WIKI_DOCS_BUILD_ROOT" "$MANIFEST_ROOT/wiki-docs.sha256"
verify_sha256_manifest "$WIKI_IMAGES_BUILD_ROOT" "$MANIFEST_ROOT/wiki-images.sha256"

source_validator_args=(
  --source-root "$SOURCE_ROOT"
  --manifest "$MANIFEST_ROOT/attachments.tsv"
)
for topic in "${source_topics[@]}"; do
  source_validator_args+=(--topic "$topic")
done
"$SCRIPT_DIR/validate-source.py" "${source_validator_args[@]}"

if [[ "$SOURCE_ONLY" == "1" ]]; then
  log "Source and attachment staging validation passed."
  exit 0
fi

[[ -d "$WIKI_BUILD_ROOT" ]] || die "Missing generated wiki tree"

validator_args=(
  --wiki-root "$WIKI_BUILD_ROOT"
  --manifest "$MANIFEST_ROOT/attachments.tsv"
  --repo "$TARGET_REPO_SLUG"
  --branch "$ATTACHMENT_BRANCH"
  --home-topic "$HOME_TOPIC"
)
for page in "${expected_pages[@]}"; do
  validator_args+=(--page "$page")
done
"$SCRIPT_DIR/validate-wiki.py" "${validator_args[@]}"

if [[ "$CHECK_REMOTE" != "1" ]]; then
  log "Local migration validation passed."
  exit 0
fi

need_cmd git
need_cmd curl
git ls-remote --exit-code --heads "$TARGET_REPO_URL" "$ATTACHMENT_BRANCH" >/dev/null || \
  die "Remote branch is missing: $ATTACHMENT_BRANCH"
git ls-remote --exit-code "$TARGET_WIKI_URL" HEAD >/dev/null || \
  die "GitHub Wiki repository is not readable"

while IFS=$'\t' read -r role topic filename bytes digest target; do
  [[ "$role" == "wiki-doc" ]] || continue
  url="https://raw.githubusercontent.com/$TARGET_REPO_SLUG/$ATTACHMENT_BRANCH/$(urlencode_path "$target")"
  curl --fail --silent --show-error --location --head "$url" >/dev/null || \
    die "Published attachment is unavailable: $url"
done <"$MANIFEST_ROOT/attachments.tsv"

for page in "${expected_pages[@]}"; do
  encoded_page="$(python3 -c 'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe="-._~"))' "$page")"
  url="https://github.com/$TARGET_REPO_SLUG/wiki/$encoded_page"
  curl --fail --silent --show-error --location --head "$url" >/dev/null || \
    die "Published wiki page is unavailable: $url"
done

log "Local and remote migration validation passed."

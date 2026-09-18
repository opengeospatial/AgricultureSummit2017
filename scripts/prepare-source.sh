#!/usr/bin/env bash

# Extract all non-excluded current TML topics and stage their attachments from
# a Foswiki export. Dry-run is the default; use --apply to write managed output.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

APPLY=0
REPLACE=0
ARCHIVE="$EXPORT_ARCHIVE_PATH"

usage() {
  cat <<'EOF'
Usage: scripts/prepare-source.sh [--apply] [--replace] [--archive PATH]

Without --apply, validates and prints the extraction plan without changing the
repository. --replace permits changes to existing managed source/build trees.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --replace) REPLACE=1 ;;
    --archive)
      [[ $# -ge 2 ]] || die "--archive requires a path"
      ARCHIVE="$2"
      [[ "$ARCHIVE" = /* ]] || ARCHIVE="$PWD/$ARCHIVE"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

need_cmd tar
need_cmd file
need_cmd shasum
need_cmd python3
[[ -f "$ARCHIVE" ]] || die "Export archive not found: $ARCHIVE"

# Reject absolute paths and parent traversal before extraction.
while IFS= read -r member; do
  case "$member" in
    /*|../*|*/../*|*/..) die "Unsafe archive member: $member" ;;
  esac
done < <(tar -tzf "$ARCHIVE")

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT INT TERM HUP
tar -xzf "$ARCHIVE" -C "$work"

export_data="$work/data/$SOURCE_WEB"
export_pub="$work/pub/$SOURCE_WEB"
[[ -d "$export_data" ]] || die "Archive has no data/$SOURCE_WEB directory"
[[ -d "$export_pub" ]] || log "Note: archive has no pub/$SOURCE_WEB directory"

stage_source="$work/stage-source"
stage_docs="$work/stage-wiki-docs"
stage_images="$work/stage-wiki-images"
stage_manifests="$work/stage-manifests"
mkdir -p "$stage_source" "$stage_docs" "$stage_images" "$stage_manifests"

migrated_topics=()
output_names_file="$work/output-names"
: >"$output_names_file"
while IFS= read -r input; do
  topic="$(basename "$input" .txt)"
  if topic_is_excluded "$topic"; then
    log "Excluding default topic: $topic"
    continue
  fi

  case "$topic" in
    *['\/:*?"<>|']*) die "Topic cannot be represented as a GitHub Wiki filename: $topic" ;;
  esac

  output_name="$(topic_output_name "$topic")"
  ! grep -Fxq "$output_name" "$output_names_file" || \
    die "Wiki filename collision for output: $output_name.md"

  migrated_topics+=("$topic")
  printf '%s\n' "$output_name" >>"$output_names_file"
  cp "$input" "$stage_source/$topic.txt"
done < <(find "$export_data" -maxdepth 1 -type f -name '*.txt' -print | LC_ALL=C sort)

[[ ${#migrated_topics[@]} -gt 0 ]] || die "No non-excluded topics found"
[[ -f "$stage_source/$HOME_TOPIC.txt" ]] || \
  die "Home topic was not discovered: $HOME_TOPIC.txt"

# This web has one source-specific WikiWord escape. Apply it to the staged
# source before checksums and all downstream build products are generated.
repo_name="${TARGET_REPO_SLUG##*/}"
[[ -f "$PROJECT_ROOT/scripts/local-fixes-${repo_name}.sh" ]]  && \
  "$PROJECT_ROOT/scripts/local-fixes-${repo_name}.sh" \
  "$stage_source" "$stage_manifests/source.sha256"

topic_is_migrated() {
  local wanted="$1" candidate
  for candidate in "${migrated_topics[@]}"; do
    [[ "$candidate" == "$wanted" ]] && return 0
  done
  return 1
}

printf 'role\ttopic\tfilename\tbytes\tsha256\ttarget\n' \
  >"$stage_manifests/attachments.tsv"

if [[ -d "$export_pub" ]]; then
  while IFS= read -r -d '' attachment; do
    rel="${attachment#$export_pub/}"
    topic="${rel%%/*}"
    filename="${rel#*/}"

    # Attachments without a migrated topic have nowhere to be linked.
    if ! topic_is_migrated "$topic"; then
      log "Skipping attachment for non-migrated topic: $rel"
      continue
    fi

    mime="$(file -b --mime-type "$attachment")"
    bytes="$(stat -f '%z' "$attachment" 2>/dev/null || stat -c '%s' "$attachment")"
    digest="$(shasum -a 256 "$attachment" | awk '{print $1}')"

    if [[ "$mime" == image/* ]]; then
      role="wiki-image"
      target="images/$rel"
      mkdir -p "$(dirname "$stage_images/$target")"
      cp "$attachment" "$stage_images/$target"
    else
      role="wiki-doc"
      target="$rel"
      mkdir -p "$(dirname "$stage_docs/$target")"
      cp "$attachment" "$stage_docs/$target"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$role" "$topic" "$filename" "$bytes" "$digest" "$target" \
      >>"$stage_manifests/attachments.tsv"
  done < <(find "$export_pub" -type f ! -name '*,v' -print0 | sort -z)
fi

write_sha256_manifest "$stage_source" "$stage_manifests/source.sha256"
write_sha256_manifest "$stage_docs" "$stage_manifests/wiki-docs.sha256"
write_sha256_manifest "$stage_images" "$stage_manifests/wiki-images.sha256"

log "Migration ID: $MIGRATION_ID"
log "Archive:      $ARCHIVE"
log "Source web:   $SOURCE_WEB"
log "Topics:       ${#migrated_topics[@]}"
log "Wiki docs:    $(find "$stage_docs" -type f | wc -l | tr -d ' ')"
log "Wiki images:  $(find "$stage_images" -type f | wc -l | tr -d ' ')"

if [[ "$APPLY" != "1" ]]; then
  log "Dry-run only. Rerun with --apply to populate Source2026, build, and manifests."
  exit 0
fi

replace_tree "$stage_source" "$SOURCE_ROOT" "$REPLACE"
replace_tree "$stage_docs" "$WIKI_DOCS_BUILD_ROOT" "$REPLACE"
replace_tree "$stage_images" "$WIKI_IMAGES_BUILD_ROOT" "$REPLACE"
replace_tree "$stage_manifests" "$MANIFEST_ROOT" "$REPLACE"

log "Prepared the discovered source and attachment staging trees."

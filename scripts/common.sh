#!/usr/bin/env bash

# Shared helpers for the Foswiki-to-GitHub migration scripts.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${MIGRATION_CONFIG:-$PROJECT_ROOT/migration.conf}"

[[ -f "$CONFIG_FILE" ]] || {
  printf 'ERROR: migration config not found: %s\n' "$CONFIG_FILE" >&2
  exit 1
}

# shellcheck source=../migration.conf
source "$CONFIG_FILE"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

absolute_path() {
  local value="$1"
  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$PROJECT_ROOT" "$value"
  fi
}

SOURCE_ROOT="$(absolute_path "$SOURCE_DIR")"
BUILD_ROOT="$(absolute_path "$BUILD_DIR")"
MANIFEST_ROOT="$(absolute_path "$MANIFEST_DIR")"
EXPORT_ARCHIVE_PATH="$(absolute_path "$EXPORT_ARCHIVE")"
WIKI_BUILD_ROOT="$BUILD_ROOT/wiki"
WIKI_DOCS_BUILD_ROOT="$BUILD_ROOT/wiki-docs"
WIKI_IMAGES_BUILD_ROOT="$BUILD_ROOT/wiki-images"

# Must contain only lowercase ASCII letters/digits. Mixed-case placeholders
# can turn a preceding word into an accidental Foswiki WikiWord.
UNDERSCORE_SENTINEL="foswikiunderscoresentinelqzxv7391"

topic_is_excluded() {
  local wanted="$1" topic
  for topic in "${EXCLUDE_TOPICS[@]}"; do
    [[ "$topic" == "$wanted" ]] && return 0
  done
  return 1
}

list_source_topics() {
  [[ -d "$SOURCE_ROOT" ]] || return 0
  find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.txt' -print \
    | LC_ALL=C sort \
    | while IFS= read -r source_file; do
        basename "$source_file" .txt
      done
}

topic_output_name() {
  local topic="$1"
  if [[ "$topic" == "$HOME_TOPIC" ]]; then
    printf 'Home\n'
  else
    printf '%s\n' "$topic"
  fi
}

timeout_command() {
  if command -v timeout >/dev/null 2>&1; then
    printf '%s\n' timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    printf '%s\n' gtimeout
  else
    die "GNU timeout is required (install coreutils on macOS)"
  fi
}

assert_safe_managed_path() {
  local path="$1"
  case "$path" in
    "$SOURCE_ROOT"|"$BUILD_ROOT"|"$BUILD_ROOT"/*|"$MANIFEST_ROOT") ;;
    *) die "Refusing to replace unmanaged path: $path" ;;
  esac
  [[ "$path" != "/" && "$path" != "$PROJECT_ROOT" ]] || \
    die "Refusing broad destructive target: $path"
}

replace_tree() {
  local staged="$1" target="$2" allow_replace="$3"
  assert_safe_managed_path "$target"

  if [[ -d "$target" ]]; then
    if diff -qr "$staged" "$target" >/dev/null 2>&1; then
      log "Unchanged: ${target#$PROJECT_ROOT/}"
      return 0
    fi
    [[ "$allow_replace" == "1" ]] || \
      die "${target#$PROJECT_ROOT/} differs; rerun with --replace after review"
    rm -rf -- "$target"
  elif [[ -e "$target" ]]; then
    die "Expected a directory but found: $target"
  fi

  mkdir -p "$(dirname "$target")"
  cp -R "$staged" "$target"
  log "Updated: ${target#$PROJECT_ROOT/}"
}

write_sha256_manifest() {
  local root="$1" output="$2"
  : >"$output"
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  while IFS= read -r file_path; do
    local rel digest
    rel="${file_path#$root/}"
    digest="$(shasum -a 256 "$file_path" | awk '{print $1}')"
    printf '%s  %s\n' "$digest" "$rel" >>"$output"
  done < <(find "$root" -type f -print | LC_ALL=C sort)
}

verify_sha256_manifest() {
  local root="$1" manifest="$2"
  [[ -f "$manifest" ]] || die "Missing checksum manifest: $manifest"
  (
    cd "$root"
    shasum -a 256 -c "$manifest"
  )
}

urlencode_path() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print('/'.join(quote(part, safe='-._~') for part in sys.argv[1].split('/')))
PY
}

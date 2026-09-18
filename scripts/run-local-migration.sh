#!/usr/bin/env bash

# Execute the complete local, non-publishing migration pipeline.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

replace_args=()
if [[ "${1:-}" == "--replace-source" ]]; then
  replace_args+=(--replace)
  shift
fi
[[ $# -eq 0 ]] || {
  printf 'Usage: scripts/run-local-migration.sh [--replace-source]\n' >&2
  exit 1
}


if [ "${#replace_args[@]}" -gt 0 ]; then
      "$SCRIPT_DIR/prepare-source.sh" --apply "${replace_args[@]}"
else
      "$SCRIPT_DIR/prepare-source.sh" --apply
fi

"$SCRIPT_DIR/convert-twiki2md.sh"
"$SCRIPT_DIR/validate-migration.sh"

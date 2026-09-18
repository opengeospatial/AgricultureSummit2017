
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

need_cmd gsed

FIX_SOURCE_ROOT="${1:-$SOURCE_ROOT}"
FIX_MANIFEST="${2:-$MANIFEST_ROOT/source.sha256}"
[[ $# -le 2 ]] || die "Usage: $0 [SOURCE_ROOT [MANIFEST_FILE]]"
[[ -f "$FIX_SOURCE_ROOT/AgSummitBusiness.txt" ]] || \
  die "Missing source topic: $FIX_SOURCE_ROOT/AgSummitBusiness.txt"

# The loop (:a ... ta) ensures multiple occurrences on the same line are replaced.
gsed -E -i ':a; s#(^|[[:space:]])AgGateway([[:space:]]|$)#\1!AgGateway\2#; ta' \
  "$FIX_SOURCE_ROOT/AgSummitBusiness.txt"

# Source2026 changed after extraction, so keep its validation manifest in sync.
write_sha256_manifest "$FIX_SOURCE_ROOT" "$FIX_MANIFEST"

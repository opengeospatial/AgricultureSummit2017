#!/usr/bin/env bash

# Fast tests for script syntax, configuration, archive discovery, and the
# attachment rewriter. Conversion itself is exercised by run-local-migration.sh.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/pandoc"; do
  bash -n "$script"
done

repo_name="${TARGET_REPO_SLUG##*/}"
[[ -f "$PROJECT_ROOT/scripts/local-fixes-${repo_name}.sh" ]]  \
  && bash -n "$PROJECT_ROOT/scripts/local-fixes-${repo_name}.sh"

python3 - \
  "$SCRIPT_DIR/rewrite-attachments.py" \
  "$SCRIPT_DIR/validate-source.py" \
  "$SCRIPT_DIR/validate-wiki.py" <<'PY'
import ast
import pathlib
import sys
for name in sys.argv[1:]:
    ast.parse(pathlib.Path(name).read_text(encoding="utf-8"), filename=name)
PY

"$SCRIPT_DIR/prepare-source.sh" >/dev/null

# Regression for italic text ending in a capitalized word. The guard must not
# create a WikiWord such as GroupPlaceholder, and final restoration must retain
# the original Markdown emphasis markers exactly.
case "$UNDERSCORE_SENTINEL" in
  ""|*[!abcdefghijklmnopqrstuvwxyz0123456789]*)
    die "Underscore sentinel must contain only lowercase ASCII letters and digits"
    ;;
esac
emphasis='### [Introduction](AgSummitIntro) -- _Josh Lieberman, Chair OGC Agriculture Working Group_'
guarded="${emphasis//_/$UNDERSCORE_SENTINEL}"
[[ "$guarded" != *"_"* ]] || die "Underscore guard left an underscore in protected text"
restored="${guarded//$UNDERSCORE_SENTINEL/_}"
[[ "$restored" == "$emphasis" ]] || die "Underscore emphasis round-trip failed"

if [[ -f "$MANIFEST_ROOT/attachments.tsv" ]]; then
  attachment_row="$(awk -F '\t' 'NR == 2 { print; exit }' "$MANIFEST_ROOT/attachments.tsv")"
  IFS=$'\t' read -r role test_topic test_filename bytes digest test_target <<<"$attachment_row"
  rewritten="$(
    printf '[[%%ATTACHURL%%/ %s][attachment]]\n' "$test_filename" \
    | "$SCRIPT_DIR/rewrite-attachments.py" \
        --topic "$test_topic" \
        --source-web "$SOURCE_WEB" \
        --repo "$TARGET_REPO_SLUG" \
        --branch "$ATTACHMENT_BRANCH" \
        --manifest "$MANIFEST_ROOT/attachments.tsv"
  )"
  if [[ "$role" == "wiki-doc" ]]; then
    expected="https://raw.githubusercontent.com/$TARGET_REPO_SLUG/$ATTACHMENT_BRANCH/$(urlencode_path "$test_target")"
  else
    expected="$(urlencode_path "$test_target")"
  fi
  [[ "$rewritten" == *"$expected"* ]] || die "Attachment whitespace rewrite test failed"
fi

log "Migration tool tests passed."

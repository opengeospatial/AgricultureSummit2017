#!/usr/bin/env bash

# Convert every prepared, non-excluded TML topic to GitHub-flavored Markdown.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

need_cmd awk
need_cmd sed
need_cmd iconv
need_cmd python3
need_cmd grep

[[ -d "$SOURCE_ROOT" ]] || die "Missing $SOURCE_DIR; run prepare-source.sh --apply"
[[ -f "$MANIFEST_ROOT/attachments.tsv" ]] || \
  die "Missing attachment manifest; run prepare-source.sh --apply"
[[ -f "$SCRIPT_DIR/force-fences.lua" ]] || die "Missing force-fences.lua"
[[ -x "$SCRIPT_DIR/pandoc" ]] || die "scripts/pandoc is not executable"

TIMEOUT_BIN="$(timeout_command)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT INT TERM HUP
stage="$work/wiki"
mkdir -p "$stage"

if [[ -d "$WIKI_IMAGES_BUILD_ROOT" ]]; then
  cp -R "$WIKI_IMAGES_BUILD_ROOT"/. "$stage"/
fi

convert_to_utf8() {
  local input="$1" output="$2" enc
  if iconv -f UTF-8 -t UTF-8 "$input" >"$output" 2>/dev/null; then
    return 0
  fi
  for enc in WINDOWS-1252 ISO-8859-1 MACROMAN ISO-8859-15; do
    if iconv -f "$enc" -t UTF-8 "$input" >"$output" 2>/dev/null; then
      log "Converted $input from $enc"
      return 0
    fi
  done
  die "Unable to convert source to UTF-8: $input"
}

pre_process() {
  local topic="$1"
  "$SCRIPT_DIR/rewrite-attachments.py" \
    --topic "$topic" \
    --source-web "$SOURCE_WEB" \
    --repo "$TARGET_REPO_SLUG" \
    --branch "$ATTACHMENT_BRANCH" \
    --manifest "$MANIFEST_ROOT/attachments.tsv" \
  | awk '/^%META:/ { next } { print }' \
  | sed -E \
      -e 's/%RED%|%GREEN%|%BLUE%|%BLACK%|%MAROON%|%YELLOW%|%ORANGE%|%ENDCOLOR%//g' \
      -e "s|%WEB%|$SOURCE_WEB|g" \
      -e 's|%HOMETOPIC%|WebHome|g' \
      -e 's|%TWIKIWEB%|TWiki|g' \
      -e 's|%MAINWEB%|Main|g' \
      -e 's|%WIKITOOLNAME%|Foswiki|g' \
      -e 's|%WIKIUSERNAME%||g' \
      -e 's|%WIKIPREFSTOPIC%|TWikiPreferences|g' \
      -e 's|%LOCALSITEPREFS%|TWikiPreferences|g' \
      -e 's|%SYSTEMWEB%|System|g' \
      -e 's|%TOC%||g' \
      -e 's|%TOC\{[^}]*\}%||g' \
      -e 's|%TOPIC%||g' \
      -e 's|%SCRIPTURLPATH\{[^}]*\}%||g' \
      -e 's|%SCRIPTURL\{[^}]*\}%||g' \
      -e 's|%URLPARAM\{[^}]*\}%||g' \
      -e 's|%INCLUDE\{[^}]*\}%||g' \
      -e 's|%IF\{[^}]*\}%||g' \
      -e 's|%WEBTOPICLIST%||g' \
      -e 's|%SEARCH\{[^}]*\}%||g' \
      -e 's|%WEBPREFSTOPIC%|WebPreferences|g' \
      -e 's|<nop>||g' \
      -e 's|</?sticky>||g' \
      -e "s|<span style=['\"][^'\"]*['\"]>||g" \
      -e 's|<span class="WYSIWYG_COLOR"[^>]*>||g' \
      -e 's|</span>||g' \
      -e "s| target=['\"]_blank['\"]||g" \
      -e "s| target=['\"]_self['\"]||g" \
      -e "s|<a href=['\"]([^'\"]+)['\"]>([^<]*)</a>|[[\1][\2]]|g" \
      -e 's/^([[:space:]]{3,})([0-9]+)[[:space:]]/\1\2. /'
}

post_process() {
  sed -E 's|\]\(([^)"]+) "wikilink"\)|](\1)|g' \
  | sed -E 's|<a href="([^"]+)" class="wikilink">([^<]*)</a>|[\2](\1)|g' \
  | sed -E -e 's|\]\(([^):/]+)\.md\)|](\1)|g' -e 's|\]\(([^):/]+)\.md#|](\1#|g' \
  | sed -E 's|\]\(WebHome\)|](Home)|g; s|\]\(WebHome#|](Home#|g' \
  | sed -E 's|\[\[([^]]+)\]\([^)]+\)([^]]*)\]\(([^)]+)\)|[\1\2](\3)|g' \
  | sed -E -e 's|\\<a href=[^>]*\\>||g' -e 's|\\</a\\>||g' \
  | sed -E \
      -e 's|^(-- )Main\.\[([^]]+)\]\([^)]+\)|\1\2|' \
      -e 's|^(-- )Main\.([A-Z][a-zA-Z]+)|\1\2|' \
      -e 's|Main\.\[([^]]+)\]\(([^)]+)\)|[\1](\2)|g' \
  | sed -E 's/^([0-9]+)\\\.( )/\1.\2/g' \
  | sed -E 's|<span id="[^"]*GRmark[^"]*"[^>]*></span>||g' \
  | awk '
      /^- TOPICINFO\{/ { next }
      /^- TOPICPARENT\{/ { next }
      /^- FILEATTACHMENT\{/ { next }
      /^<!-- -->$/ { next }
      /^#[[:space:]]*$/ { next }
      { print }
    ' \
  | sed -E \
      -e 's|\\<nop\\>||g' \
      -e 's|\\<span[^>]*\\>||g' \
      -e 's|\\</span\\>||g' \
      -e 's|\\<form[^>]*\\>||g' \
      -e 's|\\</form\\>||g' \
      -e 's|\\<input[^>]*\\>||g' \
      -e 's|\\<p\\>||g' \
      -e 's|\\</p\\>||g' \
      -e 's|\\<br */\\>||g' \
      -e 's/[[:space:]]+$//' \
  | awk '/^$/ { blank++; if (blank <= 2) print; next } { blank = 0; print }'
}

append_missing_attachments() {
  local topic="$1" output="$2" added=0 role row_topic filename bytes digest target url
  while IFS=$'\t' read -r role row_topic filename bytes digest target; do
    [[ "$role" != "role" && "$row_topic" == "$topic" ]] || continue
    if [[ "$role" == "wiki-doc" ]]; then
      url="https://raw.githubusercontent.com/$TARGET_REPO_SLUG/$ATTACHMENT_BRANCH/$(urlencode_path "$target")"
    else
      url="$(urlencode_path "$target")"
    fi
    if ! grep -Fq "$url" "$output"; then
      if [[ "$added" == "0" ]]; then
        printf '\n## Attachments\n\n' >>"$output"
        added=1
      fi
      if [[ "$role" == "wiki-image" ]]; then
        printf -- '- ![%s](%s)\n' "$filename" "$url" >>"$output"
      else
        printf -- '- [%s](%s)\n' "$filename" "$url" >>"$output"
      fi
      log "Added missing attachment link: $topic/$filename"
    fi
  done <"$MANIFEST_ROOT/attachments.tsv"
}

while IFS= read -r topic; do
  source_file="$SOURCE_ROOT/$topic.txt"
  ! topic_is_excluded "$topic" || \
    die "Excluded topic remains in $SOURCE_DIR: $topic; rerun prepare-source.sh --apply --replace"
  page_name="$(topic_output_name "$topic")"
  utf8="$work/$topic.utf8.txt"
  html="$work/$topic.html"
  output="$stage/$page_name.md"

  log "Converting $topic.txt -> $page_name.md"
  convert_to_utf8 "$source_file" "$utf8"

  if grep -Fq "$UNDERSCORE_SENTINEL" "$utf8"; then
    die "Underscore sentinel unexpectedly occurs in source: $source_file"
  fi

  # Protect underscores from the TWiki reader, including attachment filenames.
  # Do not restore them in the intermediate HTML: the HTML reader would treat
  # TML emphasis markers as literal text and the GFM writer would escape them.
  # Restoring only after the GFM pass preserves `_emphasis_` as Markdown.
  pre_process "$topic" <"$utf8" \
    | sed -E "s/_/$UNDERSCORE_SENTINEL/g" \
    | "$TIMEOUT_BIN" "$PANDOC_TIMEOUT" "$SCRIPT_DIR/pandoc" \
        -f twiki -t html --wrap=none --tab-stop=2 --markdown-headings=atx \
    >"$html"

  [[ -s "$html" ]] || die "Pandoc produced empty HTML for $topic"
  "$TIMEOUT_BIN" "$PANDOC_TIMEOUT" "$SCRIPT_DIR/pandoc" \
      -f html -t gfm+pipe_tables+raw_html \
      --wrap=none \
      --lua-filter=scripts/force-fences.lua \
      --tab-stop=2 \
      --markdown-headings=atx \
      <"$html" \
    | post_process \
    | sed -E "s/$UNDERSCORE_SENTINEL/_/g" >"$output"

  append_missing_attachments "$topic" "$output"
done < <(list_source_topics)

replace_tree "$stage" "$WIKI_BUILD_ROOT" 1
log "Markdown and wiki images are ready in ${WIKI_BUILD_ROOT#$PROJECT_ROOT/}/"

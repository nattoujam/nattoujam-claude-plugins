#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
[ -n "$path" ] || exit 0

# shellcheck source=./lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
doc_guard_skipped "$path" && exit 0
text=$(doc_guard_added_text "$input") || exit 0

state_dir=${CLAUDE_PLUGIN_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks}/doc-review
mkdir -p "$state_dir"

doc_guard_review_style "$path" >/dev/null || exit 0
printf '%s\n' "$path" >> "$state_dir/$session.files"
key=$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)
printf '%s\n' "$text" >> "$state_dir/$session.$key.added"

if [[ $(basename "$path") == README.md && -f $path ]]; then
  lines=$(wc -l < "$path")
  if (( lines > 150 )); then
    printf 'README.md が %d 行あり、上限の 150 行を超えています。readme-policy に従い、節単位で docs/ へ分割してください。\n' "$lines" >&2
    exit 2
  fi
fi
exit 0

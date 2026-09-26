#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""')
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."')
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')

# shellcheck source=./lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

state_dir=$(doc_guard_state_dir)
find "$state_dir" -type f -mtime +7 -delete 2>/dev/null

if [ "$event" = UserPromptSubmit ]; then
  rm -f "$state_dir/$session.baseline" "$state_dir/$session.files" "$state_dir/$session".*.added
fi

dir=$cwd
[ -n "$path" ] && dir=$(dirname "$path")
while [ ! -d "$dir" ] && [ "$dir" != / ]; do
  dir=$(dirname "$dir")
done
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
doc_guard_record_baseline "$session" "$root"
exit 0

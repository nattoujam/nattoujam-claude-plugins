#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""')
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')

# shellcheck source=./lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
state_dir=$(doc_guard_state_dir)

loaded="$state_dir/$session.criteria"

if [ "$event" = PostToolUse ]; then
  case $(printf '%s' "$input" | jq -r '.tool_input.skill // ""') in
    doc-guard:doc-criteria|doc-criteria) : > "$loaded" ;;
  esac
  exit 0
fi

[ -f "$loaded" ] && exit 0
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
[ -n "$path" ] || exit 0
doc_guard_skipped "$path" && exit 0
style=$(doc_guard_review_style "$path") || exit 0

text=$(doc_guard_added_text "$input") || exit 0
printf '%s\n' "$text" | awk -v style="$style" "$DOC_GUARD_AWK_LIB"'
  { t = trim($0) }
  style == "doc" && t != "" { hit = 1 }
  style != "doc" && is_comment($0, style) { hit = 1 }
  END { exit !hit }
' || exit 0

jq -n '{hookSpecificOutput: {
  hookEventName: "PreToolUse",
  permissionDecision: "deny",
  permissionDecisionReason: "コメントや文書を書く前に、Skill ツールで doc-guard:doc-criteria を読み込んでください。読み込んだら、その基準に沿ってこの書き込みをやり直してください。"
}}'

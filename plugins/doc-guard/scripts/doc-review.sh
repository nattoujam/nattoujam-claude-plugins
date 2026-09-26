#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=./lib.sh
. "$here/lib.sh"

state_dir=$(doc_guard_state_dir)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

doc_guard_turn_review_hunks "$session" | awk -v dir="$work" '
  /^\001/ { n++; f = dir "/" n; printf "[%d] %s\n", n, substr($0, 2) >> dir "/items.md"; print substr($0, 2) > f; next }
  n { print >> dir "/items.md"; if ($0 ~ /^\+/) print >> f }
  END { if (n) printf "\n" >> dir "/items.md" }
'
[ -s "$work/items.md" ] || exit 0

hash=$(sha256sum < "$work/items.md" | cut -d' ' -f1)
cache="$state_dir/$session.docreview.$hash"

if [ ! -f "$cache" ]; then
  criteria="$here/../prompts/criteria"
  {
    cat "$here/../prompts/doc-reviewer.md" "$criteria/common.md"
    for f in "$work"/[0-9]*; do
      doc_guard_criteria_kind "$(head -n1 "$f" | sed 's/ (.*)$//')"
    done | sort -u | while IFS= read -r kind; do
      printf '\n'
      cat "$criteria/$kind.md"
    done
  } > "$work/system.md"
  out=$(timeout "${DOC_GUARD_REVIEW_TIMEOUT:-280}" claude -p \
    --model "${DOC_GUARD_REVIEW_MODEL:-sonnet}" \
    --tools "" \
    --settings '{"disableAllHooks": true}' \
    --no-session-persistence \
    --system-prompt-file "$work/system.md" \
    --output-format json < "$work/items.md" 2>/dev/null)
  verdicts=$(printf '%s' "$out" | jq -r '.result // empty' 2>/dev/null | sed -n '/^\[/,/^\]/p')
  if printf '%s' "$verdicts" | jq -e 'type == "array"' >/dev/null 2>&1; then
    printf '%s' "$verdicts" > "$cache"
  else
    verdicts=""
  fi
else
  verdicts=$(cat "$cache")
fi

if [ -z "$verdicts" ]; then
  header="文書・コメントのレビューを実行できませんでした(claude -p の失敗または応答の形式違い)。対象の記述を見直し、不要なものは削除してください。
記述がすべて必要だと考える場合は、自分の判断で残さず、そのまま応答を終えてください。未レビューのままであることはユーザーに直接表示されます。"
  findings=$(grep -a '^\[' "$work/items.md")
else
  header="文書・コメントのレビュー(${DOC_GUARD_REVIEW_MODEL:-sonnet})が次の記述を却下しました。記述を削除するか、却下理由に当たらない形に直してください。
却下が誤りだと考える場合は、自分の判断で残さず、直さないまま応答を終えてください。未解決の却下はユーザーに直接表示されます。"
  findings=$(printf '%s' "$verdicts" | jq -r '.[] | select(.verdict == "reject") | "\(.id)\t\(.category)\t\(.reason)"' |
    while IFS=$'\t' read -r id category reason; do
      [ -f "$work/$id" ] || continue
      printf -- '- %s [%s] %s\n' "$(head -n1 "$work/$id")" "$category" "$reason"
      tail -n +2 "$work/$id" | sed 's/^/    /'
    done)
  [ -n "$findings" ] || exit 0
fi

last="$state_dir/$session.docreview.last"
findings_hash=$(printf '%s' "$findings" | sha256sum | cut -d' ' -f1)

if [[ $active == true && -f $last && $(cat "$last") == "$findings_hash" ]]; then
  if [ -z "$verdicts" ]; then
    summary="doc-guard: 文書・コメントのレビューを実行できないまま応答が終わりました。次の記述は未レビューです。"
  else
    summary="doc-guard: 文書・コメントのレビューで却下された記述が残ったまま応答が終わりました。"
  fi
  jq -n --arg msg "$summary

$findings" '{systemMessage: $msg}'
  exit 0
fi
printf '%s' "$findings_hash" > "$last"

cat >&2 <<MSG
$header

$findings
MSG
exit 2

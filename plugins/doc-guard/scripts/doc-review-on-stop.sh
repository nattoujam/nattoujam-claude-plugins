#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."')

state_dir=${CLAUDE_PLUGIN_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks}/doc-review
files="$state_dir/$session.files"
seen="$state_dir/$session.hash"
[ -f "$files" ] || exit 0
find "$state_dir" -type f -mtime +7 -delete 2>/dev/null

cd "$cwd" 2>/dev/null || exit 0

# shellcheck source=./lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

added=""
digest=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  doc_guard_ignored "$f" && continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    diff=$(git diff HEAD -- "$f" | grep -E '^\+[^+]' | sed 's/^+//' | grep -v '^[[:space:]]*$')
  else
    # git管理外: ファイル全体ではなく、doc-comment-check.sh が記録した
    # このセッションでの追加分だけを見る(触っていない既存内容を誤検知しないため)
    key=$(printf '%s' "$f" | sha256sum | cut -d' ' -f1)
    added_file="$state_dir/$session.$key.added"
    diff=$([ -f "$added_file" ] && grep -v '^[[:space:]]*$' "$added_file")
  fi
  [ -n "$diff" ] || continue
  total=$(printf "%s\n" "$diff" | wc -l)
  added+="- $f ($total 行追加)
"
  # $added を hash すると、行数が同じまま中身が変わった追加を取りこぼす
  digest+="$f
$diff
"
done < <(sort -u "$files")

[ -n "$added" ] || exit 0
hash=$(printf '%s' "$digest" | sha256sum | cut -d' ' -f1)
printf '%s' "$hash" > "$seen.new"

# 差し戻し後の再停止、または既にレビュー済みの追加分なら通す（現在の状態をレビュー済みとして記録）
if [[ $active == true ]] || [[ -f $seen && $(cat "$seen") == "$hash" ]]; then
  mv "$seen.new" "$seen"
  exit 0
fi
mv "$seen.new" "$seen"

cat >&2 <<MSG
このターンで .md に内容を追加しました。コード変更に伴う新しい説明は、本文を書く前に題目の要否をユーザーに聞く方針です。聞いていなければ、追加した段落を消し、題目を 1 行ずつ挙げて要否を聞いてください。
次のどれかなら、そのまま終了して構いません:
  - 事実への追従（パス・名前・コマンドがコードと食い違った箇所の修正）
  - ユーザーが依頼した文書そのもの、またはユーザーが選んだ題目
追加内容が手元にない場合だけ、対象ファイルを読んで確認してください。
検査対象が成果物そのもので繰り返し差し戻される場合は、リポジトリ直下の .doc-guard-ignore にパスや glob を1行ずつ足すようユーザーへ提案してください。

対象ファイル:
$added
MSG
exit 2

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

added=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    diff=$(git diff HEAD -- "$f" | grep -E '^\+[^+]' | sed 's/^+//' | grep -v '^[[:space:]]*$')
  else
    diff=$(grep -v '^[[:space:]]*$' "$f")
  fi
  [ -n "$diff" ] || continue
  total=$(printf "%s\n" "$diff" | wc -l)
  shown=$(printf "%s\n" "$diff" | head -30)
  (( total > 30 )) && shown+="
… 他 $((total - 30)) 行（ファイルを直接読んで確認）"
  added+="=== $f ($total 行追加) ===
$shown

"
done < <(sort -u "$files")

[ -n "$added" ] || exit 0
hash=$(printf '%s' "$added" | sha256sum | cut -d' ' -f1)
printf '%s' "$hash" > "$seen.new"

# 差し戻し後の再停止、または既にレビュー済みの追加分なら通す（現在の状態をレビュー済みとして記録）
if [[ $active == true ]] || [[ -f $seen && $(cat "$seen") == "$hash" ]]; then
  mv "$seen.new" "$seen"
  exit 0
fi
mv "$seen.new" "$seen"

cat >&2 <<MSG
このターンで .md に追加した内容を、終了前に段落ごとに検査してください。基準は「この段落がないと、今後の保守・運用で誰が何を間違えるか」を具体的に答えられるかどうかで、答えられない段落は削除します。
削除対象:
  - コード、--help、設定ファイルを読めば分かる内容
  - 設計判断の理由、採らなかった選択肢。判断にすぎず、仕様が変われば陳腐化する
  - 調査で分かったこと、検証ログ、途中の経緯（回答でユーザーに伝える。残す価値があるものだけ memory へ）
  - README なら readme-policy の節構成に合わないもの（docs/ へ移す）
削除するものがなければ、そのまま終了して構いません。

$added
MSG
exit 2

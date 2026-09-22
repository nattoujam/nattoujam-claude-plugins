#!/usr/bin/env bash
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
[ -n "$path" ] || exit 0

case $path in
  */.claude/*|*/scratchpad/*|/tmp/*|*/memory/*) exit 0 ;;
esac

# shellcheck source=./lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
doc_guard_ignored "$path" && exit 0

case $tool in
  Write) text=$(printf '%s' "$input" | jq -r '.tool_input.content // ""') ;;
  Edit)
    old=$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')
    new=$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')
    # old_string にも存在する行(=触っていない既存行)は対象から外す
    text=$(diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") | sed -n 's/^> //p')
    ;;
  *) exit 0 ;;
esac

state_dir=${CLAUDE_PLUGIN_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks}/doc-review
mkdir -p "$state_dir"

if [[ $path == *.md ]]; then
  # doc-review-on-stop.sh がこのファイルを読む。ここ以外に参照はない
  printf '%s\n' "$path" >> "$state_dir/$session.files"
  # git管理外のファイル向け。git diffが使えない場合の追加分バックアップ(下記参照)
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
fi

ext=${path##*.}
case $ext in
  py|rb|sh|bash|zsh|fish|pl|yaml|yml|toml|mk|r|jl|nix|ex|exs) style=hash ;;
  js|ts|jsx|tsx|mjs|cjs|go|rs|c|h|cpp|hpp|cc|java|kt|swift|scala|dart|php|cs|css|scss) style=slash ;;
  sql|lua|hs) style=dash ;;
  *) [[ $(basename "$path") == Makefile ]] && style=hash || exit 0 ;;
esac

comments=$(printf '%s\n' "$text" | awk -v style="$style" '
  /^[[:space:]]*#!/ { next }
  /^[[:space:]]*(#|\/\/)[[:space:]]*(frozen_string_literal|rubocop|noqa|type:|pylint|pyright|shellcheck|fmt:|eslint|@ts-|prettier|nolint|biome-ignore|yaml-language-server)/ { next }
  /^[[:space:]]*\/\/go:/ { next }
  style == "hash"  && /^[[:space:]]*#/ { print NR": "$0 }
  style == "slash" && /^[[:space:]]*(\/\/|\/\*|\*[[:space:]]|\*\/|\*$)/ { print NR": "$0 }
  style == "dash"  && /^[[:space:]]*--/ { print NR": "$0 }
')
[ -n "$comments" ] || exit 0

n=$(printf '%s\n' "$comments" | wc -l)
cat >&2 <<MSG
$path に追加した内容にコメントが ${n} 行含まれています。1 行ずつ「このコメントがないと、今後の保守・運用で誰が何を間違えるか」を具体的に答え、答えられないものは削除してください。
削除対象:
  - 名前の言い換え、処理の流れ、型や引数の説明（コードを読めば分かる）
  - 設計判断の理由（A と B があって A を選んだ、なぜなら…）。判断にすぎず、仕様が変われば陳腐化する
  - 過去の経緯、修正履歴、移植元の説明、調査で分かったこと（git log と回答の領分）
仕様上の制約や非自明な書き方の理由でも、消して困る人と困り方が具体的に言えなければ同じく削除します。
調査で分かったことは回答でユーザーに伝えるだけにし、残す価値があるものだけ memory に書いてください。

$comments
MSG
exit 2

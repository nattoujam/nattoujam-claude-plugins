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
$path にコメントを ${n} 行追加しました。コメントは書かない方針です。コードから消し、残す価値があると思うものは回答で候補（場所と 1 行の要旨）として挙げてください。
ユーザーが候補から選んだコメント、またはプロジェクトの CLAUDE.md や規約が求めるコメントなら、そのまま続けて構いません。

$comments
MSG
exit 2

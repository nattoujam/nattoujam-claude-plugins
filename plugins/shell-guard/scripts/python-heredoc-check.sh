#!/usr/bin/env bash
# PreToolUse(Bash): 使い捨ての python heredoc を止める。理由コメント付きなら通す。
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

printf '%s\n' "$cmd" | grep -Eq '(^|[;&|(]|\$\()[[:space:]]*python[0-9.]*[[:space:]]+-[[:space:]]*<<' || exit 0
printf '%s\n' "$cmd" | grep -Eq '^[[:space:]]*#[[:space:]]*(why|理由)[:：]' && exit 0

jq -nc --arg r '使い捨て処理での python heredoc は CLAUDE.md で禁止されている。次のどちらかで再実行すること:
1. jq / awk / rg / sed で書き直す(推奨)
2. シェルでは著しく複雑・不安定になる理由を、コマンドの先頭行に「# 理由: …」として1行添える(例: 浮動小数点の集計、多段の状態管理、ネストした構造の変換)' \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'

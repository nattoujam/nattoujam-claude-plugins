#!/usr/bin/env bash

doc_guard_match() {
  local rel=$1 pat=$2
  # shellcheck disable=SC2254
  case $rel in $pat) return 0 ;; esac
  pat=${pat%/}
  pat=${pat%/\*\*}
  [ -n "$pat" ] || return 1
  # shellcheck disable=SC2254
  case $rel in $pat/*) return 0 ;; esac
  return 1
}

doc_guard_ignored() {
  local path=$1 root rel_root rel_cwd pat line pats=()
  root=$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$root" ] || root=$PWD
  rel_root=${path#"$root"/}
  rel_cwd=${path#"$PWD"/}

  if [ -n "${DOC_GUARD_EXCLUDE:-}" ]; then
    IFS=: read -ra pats <<< "$DOC_GUARD_EXCLUDE"
    for pat in "${pats[@]}"; do
      [ -n "$pat" ] || continue
      doc_guard_match "$rel_root" "$pat" && return 0
      doc_guard_match "$rel_cwd" "$pat" && return 0
    done
  fi

  [ -f "$root/.doc-guard-ignore" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [ -n "$line" ] || continue
    [[ $line == \#* ]] && continue
    doc_guard_match "$rel_root" "$line" && return 0
    doc_guard_match "$rel_cwd" "$line" && return 0
  done < "$root/.doc-guard-ignore"
  return 1
}

doc_guard_skipped() {
  case $1 in
    */.claude/*|*/scratchpad/*|/tmp/*|*/memory/*) return 0 ;;
  esac
  doc_guard_ignored "$1"
}

doc_guard_added_text() {
  local input=$1 old new
  case $(printf '%s' "$input" | jq -r '.tool_name // ""') in
    Write) printf '%s' "$input" | jq -r '.tool_input.content // ""' ;;
    Edit)
      old=$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')
      new=$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')
      # old_string にも存在する行(=触っていない既存行)は対象から外す
      diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") | sed -n 's/^> //p'
      ;;
    *) return 1 ;;
  esac
  return 0
}

doc_guard_state_dir() {
  local dir=${CLAUDE_PLUGIN_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks}/doc-review
  mkdir -p "$dir"
  printf '%s' "$dir"
}

doc_guard_is_doc() {
  case $1 in
    *.md|*.markdown|*.rst|*.adoc) return 0 ;;
  esac
  return 1
}

doc_guard_comment_style() {
  local base suffix ext
  base=$(basename "$1")
  for suffix in .example .sample .template .tmpl .dist; do
    base=${base%"$suffix"}
  done
  doc_guard_is_doc "$base" && return 1
  case $base in
    Dockerfile*|Containerfile|Makefile|GNUmakefile|Gemfile|Rakefile|Brewfile|Procfile|.env|.env.*|.gitignore|.dockerignore|.gitattributes|.editorconfig|.tool-versions|.npmrc|.curlrc)
      echo hash; return 0 ;;
  esac
  ext=${base##*.}
  [ "$ext" != "$base" ] || return 1
  case $ext in
    py|pyi) echo "hash docstring" ;;
    rb|sh|bash|zsh|fish|pl|yaml|yml|toml|mk|r|jl|nix|ex|exs|conf|ini|cfg|properties|env|tf|hcl|graphql|gql|ps1|cmake|dockerfile) echo hash ;;
    js|ts|jsx|tsx|mjs|cjs|mts|cts|go|rs|c|h|cpp|hpp|cc|java|kt|kts|swift|scala|dart|php|cs|css|scss|less|groovy|gradle|proto|jsonc|json5|zig) echo slash ;;
    vue|svelte|astro) echo "slash markup" ;;
    html|htm|xhtml|xml|svg) echo markup ;;
    sql|lua|hs|elm) echo dash ;;
    *) return 1 ;;
  esac
}

doc_guard_review_style() {
  if doc_guard_is_doc "$1"; then
    echo doc
  else
    doc_guard_comment_style "$1"
  fi
}

doc_guard_criteria_kind() {
  if ! doc_guard_is_doc "$1"; then
    echo comment
    return
  fi
  case $(basename "$1" | tr '[:upper:]' '[:lower:]') in
    development*|contributing*|hacking*|architecture*|claude.md|agents.md) echo dev-docs ;;
    *) echo readme ;;
  esac
}

DOC_GUARD_AWK_LIB='
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function is_comment(s, style) {
    s = trim(s)
    if (s ~ /^#!/) return 0
    if (s ~ /^(#|\/\/|--|\/\*+|\*|<!--)[ \t]*(frozen_string_literal|rubocop|noqa|type:|pylint|pyright|mypy|shellcheck|fmt:|eslint|@ts-|prettier|nolint|biome-ignore|yaml-language-server|istanbul|c8 |tslint|stylelint|nosec|go:|SPDX-License-Identifier|@license|@preserve|Copyright|\(c\) )/) return 0
    if (index(style, "hash") && s ~ /^#/) return 1
    if (index(style, "docstring") && s ~ /^("""|\047\047\047)/) return 1
    if (index(style, "slash") && s ~ /^(\/\/|\/\*|\*\/|\*[ \t]|\*$)/) return 1
    if (index(style, "dash") && s ~ /^--/) return 1
    if (index(style, "markup") && s ~ /^<!--/) return 1
    return 0
  }
'

doc_guard_snapshot() {
  local root=$1 index tmp rc
  index=$(git -C "$root" rev-parse --git-path index 2>/dev/null) || return 1
  [[ $index == /* ]] || index=$root/$index
  tmp=$(mktemp)
  if [ -f "$index" ]; then
    cp "$index" "$tmp"
  else
    rm -f "$tmp"
  fi
  GIT_INDEX_FILE=$tmp git -C "$root" add -A >/dev/null 2>&1
  GIT_INDEX_FILE=$tmp git -C "$root" write-tree
  rc=$?
  rm -f "$tmp"
  return $rc
}

doc_guard_record_baseline() {
  local session=$1 root=$2 file tree
  file="$(doc_guard_state_dir)/$session.baseline"
  [ -f "$file" ] && awk -F'\t' -v r="$root" '$1 == r { found = 1 } END { exit !found }' "$file" && return 0
  tree=$(doc_guard_snapshot "$root") || return 0
  printf '%s\t%s\n' "$root" "$tree" >> "$file"
}

doc_guard_heading() {
  awk -v n="$1" 'NR >= n { exit } /^#{1,6}[ \t]/ { h = $0 } END { print h }'
}

doc_guard_review_hunks() {
  local root=$1 base=$2 current=$3 work path style start heading line
  work=$(mktemp -d)
  git -C "$root" -c core.quotePath=false diff -U1 --no-color --no-ext-diff --find-renames \
    "$base" "$current" > "$work/diff"
  if [ ! -s "$work/diff" ]; then
    rm -rf "$work"
    return 0
  fi

  awk '/^--- / { next } /^-/ { s = substr($0, 2); gsub(/^[ \t]+|[ \t]+$/, "", s); if (s != "") print s }' \
    "$work/diff" | sort -u > "$work/removed"
  : > "$work/styles"
  while IFS= read -r path; do
    doc_guard_ignored "$root/$path" && continue
    style=$(doc_guard_review_style "$path") || continue
    printf '%s\t%s\n' "$path" "$style" >> "$work/styles"
  done < <(awk '/^\+\+\+ b\// { print substr($0, 7) }' "$work/diff" | sort -u)

  awk -v styles="$work/styles" -v removed="$work/removed" "$DOC_GUARD_AWK_LIB"'
    BEGIN {
      FS = "\n"
      while ((getline l < styles) > 0) { split(l, a, "\t"); st[a[1]] = a[2] }
      while ((getline l < removed) > 0) rm[l] = 1
    }
    function flush() { if (buf != "" && hit) printf "%s", buf; buf = ""; hit = 0 }
    /^diff --git / { flush(); path = ""; next }
    /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
    /^--- / { next }
    /^@@ / {
      flush()
      split($0, h, " ")
      split(h[3], a, ",")
      buf = "\001" path "\t" substr(a[1], 2) "\n"
      next
    }
    path == "" || !(path in st) { next }
    /^\\/ { next }
    /^\+/ {
      s = substr($0, 2)
      t = trim(s)
      if (t != "" && (t in rm)) { buf = buf " " s "\n"; next }
      if (st[path] == "doc") { if (t != "") hit = 1 }
      else if (is_comment(s, st[path])) hit = 1
      buf = buf $0 "\n"
      next
    }
    /^[- ]/ { buf = buf $0 "\n" }
    END { flush() }
  ' "$work/diff" \
  | while IFS= read -r line; do
      if [[ $line == $'\001'* ]]; then
        IFS=$'\t' read -r path start <<< "${line#$'\001'}"
        heading=""
        doc_guard_is_doc "$path" && heading=$(git -C "$root" show "$current:$path" 2>/dev/null | doc_guard_heading "$start")
        printf '\001%s%s\n' "$root/$path" "${heading:+ ($heading)}"
      else
        printf '%s\n' "$line"
      fi
    done
  rm -rf "$work"
}

doc_guard_untracked_hunks() {
  local session=$1 state_dir files path key added kept style
  state_dir=$(doc_guard_state_dir)
  files="$state_dir/$session.files"
  [ -f "$files" ] || return 0
  sort -u "$files" | while IFS= read -r path; do
    [ -f "$path" ] || continue
    git -C "$(dirname "$path")" rev-parse --show-toplevel >/dev/null 2>&1 && continue
    doc_guard_ignored "$path" && continue
    style=$(doc_guard_review_style "$path") || continue
    key=$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)
    added="$state_dir/$session.$key.added"
    [ -f "$added" ] || continue
    kept=$(grep -v '^[[:space:]]*$' "$added" | grep -xF -f - "$path" | sort -u)
    if [ "$style" != doc ]; then
      kept=$(printf '%s\n' "$kept" | awk -v style="$style" "$DOC_GUARD_AWK_LIB"'is_comment($0, style)')
    fi
    [ -n "$kept" ] || continue
    printf '\001%s\n' "$path"
    printf '%s\n' "$kept" | sed 's/^/+/'
  done
}

doc_guard_turn_review_hunks() {
  local session=$1 file root base current
  file="$(doc_guard_state_dir)/$session.baseline"
  if [ -f "$file" ]; then
    while IFS=$'\t' read -r root base; do
      [ -d "$root" ] || continue
      current=$(doc_guard_snapshot "$root") || continue
      doc_guard_review_hunks "$root" "$base" "$current"
    done < "$file"
  fi
  doc_guard_untracked_hunks "$session"
}

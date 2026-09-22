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

#!/usr/bin/env bash
# Reports per-file coverage from an `llvm-cov export -format=text` JSON
# document and fails, listing every offending file, if any file covered by
# $SOURCES_PATTERN falls below the configured minimums.
#
# Usage: check-coverage.sh <label> <sources-pattern> <min-line-pct> <min-branch-pct-or--1-to-skip> -- <llvm-cov export args...>

set -euo pipefail

label="$1"
sources_pattern="$2"
min_line="$3"
min_branch="$4"
shift 4
if [[ "${1:-}" != "--" ]]; then
  echo "check-coverage.sh: expected -- before llvm-cov export arguments" >&2
  exit 2
fi
shift

json="$(xcrun llvm-cov export "$@" -format=text)"

echo "== $label coverage =="
echo "$json" | jq -r --arg pattern "$sources_pattern" '
  .data[0].files[]
  | select(.filename | test($pattern))
  | select(.summary.lines.count > 0)
  | [.filename, .summary.lines.percent, .summary.branches.count, .summary.branches.percent]
  | @tsv
' | while IFS=$'\t' read -r filename line_pct branch_count branch_pct; do
  short="${filename#"$PWD"/}"
  if [[ "$branch_count" == "0" ]]; then
    printf '%-55s lines %6.2f%%   branches n/a\n' "$short" "$line_pct"
  else
    printf '%-55s lines %6.2f%%   branches %6.2f%%\n' "$short" "$line_pct" "$branch_pct"
  fi
done

failures="$(echo "$json" | jq -r --arg pattern "$sources_pattern" --argjson minLine "$min_line" --argjson minBranch "$min_branch" '
  .data[0].files[]
  | select(.filename | test($pattern))
  | select(.summary.lines.count > 0)
  | select(
      (.summary.lines.percent < $minLine)
      or (($minBranch >= 0) and (.summary.branches.count > 0) and (.summary.branches.percent < $minBranch))
    )
  | .filename
')"

if [[ -n "$failures" ]]; then
  echo
  echo "$label coverage below threshold (lines >= ${min_line}%$( [[ "$min_branch" != "-1" ]] && echo ", branches >= ${min_branch}%" )):"
  echo "$failures" | sed "s#$PWD/##"
  exit 1
fi

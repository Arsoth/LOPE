#!/usr/bin/env bash
# Reports per-file coverage from an `llvm-cov export -format=text` JSON
# document and fails, listing every offending file and metric, if any file
# covered by $SOURCES_PATTERN falls below the configured minimums on any
# checked metric (regions, functions, lines, branches).
#
# Usage: check-coverage.sh <label> <sources-pattern> <min-region-pct-or--1> <min-function-pct-or--1> <min-line-pct-or--1> <min-branch-pct-or--1> -- <llvm-cov export args...>
# Pass -1 for any minimum to skip checking that metric entirely (used for
# Branches on the Swift side, since the toolchain does not emit
# branch-region coverage mapping for Swift at all).

set -euo pipefail

label="$1"
sources_pattern="$2"
min_region="$3"
min_function="$4"
min_line="$5"
min_branch="$6"
shift 6
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
  | [.filename, .summary.regions.percent, .summary.functions.percent, .summary.lines.percent, .summary.branches.count, .summary.branches.percent]
  | @tsv
' | while IFS=$'\t' read -r filename region_pct function_pct line_pct branch_count branch_pct; do
  short="${filename#"$PWD"/}"
  if [[ "$branch_count" == "0" ]]; then
    printf '%-55s regions %6.2f%%   functions %6.2f%%   lines %6.2f%%   branches n/a\n' \
      "$short" "$region_pct" "$function_pct" "$line_pct"
  else
    printf '%-55s regions %6.2f%%   functions %6.2f%%   lines %6.2f%%   branches %6.2f%%\n' \
      "$short" "$region_pct" "$function_pct" "$line_pct" "$branch_pct"
  fi
done

failures="$(echo "$json" | jq -r --arg pattern "$sources_pattern" \
  --argjson minRegion "$min_region" --argjson minFunction "$min_function" \
  --argjson minLine "$min_line" --argjson minBranch "$min_branch" '
  def round2: (. * 100 | round) / 100;
  .data[0].files[]
  | select(.filename | test($pattern))
  | select(.summary.lines.count > 0)
  | . as $f
  | (
      (if $minRegion >= 0 and $f.summary.regions.percent < $minRegion
        then "\($f.filename): regions \($f.summary.regions.percent | round2)% < \($minRegion)%" else empty end),
      (if $minFunction >= 0 and $f.summary.functions.percent < $minFunction
        then "\($f.filename): functions \($f.summary.functions.percent | round2)% < \($minFunction)%" else empty end),
      (if $minLine >= 0 and $f.summary.lines.percent < $minLine
        then "\($f.filename): lines \($f.summary.lines.percent | round2)% < \($minLine)%" else empty end),
      (if $minBranch >= 0 and $f.summary.branches.count > 0 and $f.summary.branches.percent < $minBranch
        then "\($f.filename): branches \($f.summary.branches.percent | round2)% < \($minBranch)%" else empty end)
    )
')"

if [[ -n "$failures" ]]; then
  thresholds=""
  [[ "$min_region" != "-1" ]] && thresholds+="regions >= ${min_region}%, "
  [[ "$min_function" != "-1" ]] && thresholds+="functions >= ${min_function}%, "
  [[ "$min_line" != "-1" ]] && thresholds+="lines >= ${min_line}%, "
  [[ "$min_branch" != "-1" ]] && thresholds+="branches >= ${min_branch}%, "
  echo
  echo "$label coverage below threshold (${thresholds%, }):"
  echo "$failures" | sed "s#$PWD/##"
  exit 1
fi

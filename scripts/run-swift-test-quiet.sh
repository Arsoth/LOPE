#!/usr/bin/env bash
# Runs `swift test`, forwarding all arguments, but captures its per-test-case
# and per-suite chatter. A passing run is silent unless `--summary` is given.
# A failing run prints only the lines relevant to the failure (compiler
# errors, failed test cases, and non-zero failure summaries) instead of the
# full pass/fail transcript, since a single failure among hundreds of passing
# tests shouldn't require scrolling past all of them. The full transcript is
# saved alongside the filtered output in case the filter misses something.
# This keeps both ordinary test runs and coverage tables readable while
# preserving swift test's real exit code.
#
# Usage: run-swift-test-quiet.sh [--summary] [swift test arguments...]

set -uo pipefail

summary=0
if [[ "${1:-}" == "--summary" ]]; then
  summary=1
  shift
fi

output="$(mktemp)"
trap 'rm -f "$output"' EXIT

status=0
# This package currently contains XCTest cases only. On Xcode toolchains that
# auto-launch Swift Testing, the empty Swift Testing bundle can be reported as
# a missing test executable after the XCTest bundle has already passed. Keep
# the runner aligned with the package's actual test framework.
swift test --disable-swift-testing "$@" >"$output" 2>&1 || status=$?

if [[ "$status" -ne 0 ]]; then
  # Compiler errors, failed test cases/suites, and non-zero failure summaries.
  # Passing "Test Case ... passed" lines and "0 failures" summaries are noise
  # once we already know the run failed.
  failure_pattern="error:|failed \\(|Test Suite .* failed|Executed [0-9]+ tests?, with [1-9][0-9]* failure|\\*\\* (TEST|BUILD) FAILED \\*\\*"
  filtered="$(grep -E "$failure_pattern" "$output")"
  saved="${TMPDIR:-/tmp}/swift-test-failure-$(date +%Y%m%d-%H%M%S).log"
  cp "$output" "$saved"
  if [[ -n "$filtered" ]]; then
    echo "$filtered"
    echo "Full transcript saved to $saved"
  else
    # Unrecognized failure shape (e.g. a crash) — fall back to the full log
    # rather than silently hiding it.
    cat "$output"
  fi
elif [[ "$summary" -eq 1 ]]; then
  summary_line="$(grep -E "Executed [0-9]+ tests, with 0 failures" "$output" | tail -1)"
  if [[ -n "$summary_line" ]]; then
    echo "Swift tests: passed (${summary_line#*$'\t'})"
  else
    echo "Swift tests: passed"
  fi
fi

exit "$status"

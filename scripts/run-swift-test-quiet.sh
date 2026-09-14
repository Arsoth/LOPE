#!/usr/bin/env bash
# Runs `swift test`, forwarding all arguments, but captures its per-test-case
# and per-suite chatter. A passing run is silent unless `--summary` is given;
# a failing run prints the captured output so the failure is debuggable. This
# keeps both ordinary test runs and coverage tables readable while preserving
# swift test's real exit code.
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
  cat "$output"
elif [[ "$summary" -eq 1 ]]; then
  summary_line="$(grep -E "Executed [0-9]+ tests, with 0 failures" "$output" | tail -1)"
  if [[ -n "$summary_line" ]]; then
    echo "Swift tests: passed (${summary_line#*$'\t'})"
  else
    echo "Swift tests: passed"
  fi
fi

exit "$status"

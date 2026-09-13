#!/usr/bin/env bash
# Runs `swift test`, forwarding all arguments, but drops its per-test-case
# and per-suite "started"/"passed" chatter -- hundreds of lines that bury
# the coverage tables printed after this script runs. Only real failure
# output survives: the "error:" assertion diagnostic (with file:line) and
# any "Test Case '...' failed"/"Test Suite '...' failed" line. On a fully
# passing run this prints nothing at all, so the coverage table that
# follows is the only output. Preserves swift test's real exit code even
# though its output is piped through grep.
#
# Usage: run-swift-test-quiet.sh [swift test arguments...]

set -uo pipefail

output="$(mktemp)"
trap 'rm -f "$output"' EXIT

status=0
swift test "$@" >"$output" 2>&1 || status=$?

grep -E "error:|' failed" "$output"

exit "$status"

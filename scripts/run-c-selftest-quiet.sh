#!/usr/bin/env bash
# Runs the C self-test binary, forwarding all arguments, but keeps its
# console output down to nothing on success. The self-test suite
# deliberately exercises invalid-input/error paths (bad device keys,
# HID++ timeouts, malformed CLI arguments, and so on), and the real CLI
# diagnostics those paths print to stderr are expected, not failures --
# but they bury the coverage table printed after this script runs. On
# failure, prints the full output so the failure is debuggable.
#
# Usage: run-c-selftest-quiet.sh <self-test binary> [arguments...]

set -uo pipefail

output="$(mktemp)"
trap 'rm -f "$output"' EXIT

status=0
"$@" >"$output" 2>&1 || status=$?

if [[ "$status" -ne 0 ]]; then
  cat "$output"
fi

exit "$status"

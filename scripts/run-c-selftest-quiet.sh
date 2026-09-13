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

set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: run-c-selftest-quiet.sh <self-test binary> [arguments...]" >&2
  exit 2
fi

output=""
cleanup() {
  if [[ -n "$output" ]]; then
    rm -f -- "$output"
  fi
}
trap cleanup EXIT

temp_dir="${TMPDIR:-/tmp}"
output="$(mktemp "${temp_dir%/}/lope-c-selftest.XXXXXX" 2>/dev/null)" || {
  fallback_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/.build"
  mkdir -p "$fallback_dir"
  output="$(mktemp "$fallback_dir/lope-c-selftest.XXXXXX")"
}

status=0
"$@" >"$output" 2>&1 || status=$?

if [[ "$status" -ne 0 ]]; then
  cat "$output"
fi

exit "$status"

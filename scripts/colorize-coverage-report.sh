#!/usr/bin/env bash
# Runs an llvm-cov report and colors each percentage cell using the project's
# coverage bands. llvm-cov's built-in colors use fixed thresholds and cannot
# express these bands exactly.
#
# COVERAGE_COLOR=auto (default) colors only when stdout is a terminal.
# COVERAGE_COLOR=always forces ANSI colors; COVERAGE_COLOR=never disables them.

set -uo pipefail

color_mode="${COVERAGE_COLOR:-auto}"
case "$color_mode" in
  auto)
    [[ -t 1 ]] || exec xcrun llvm-cov report "$@"
    ;;
  always)
    ;;
  never)
    exec xcrun llvm-cov report "$@"
    ;;
  *)
    echo "colorize-coverage-report.sh: COVERAGE_COLOR must be auto, always, or never" >&2
    exit 2
    ;;
esac

red=$'\033[31m'
yellow=$'\033[33m'
green=$'\033[32m'
reset=$'\033[0m'

set +e
xcrun llvm-cov report "$@" | awk -v red="$red" -v yellow="$yellow" -v green="$green" -v reset="$reset" '
  {
    line = $0
    colored = ""
    while (match(line, /[0-9]+(\.[0-9]+)?%/)) {
      prefix = substr(line, 1, RSTART - 1)
      token = substr(line, RSTART, RLENGTH)
      percent = substr(token, 1, length(token) - 1) + 0
      if (percent < 90) {
        color = red
      } else if (percent < 99) {
        color = yellow
      } else {
        color = green
      }
      colored = colored prefix color token reset
      line = substr(line, RSTART + RLENGTH)
    }
    print colored line
  }
'
status=${PIPESTATUS[0]}
set -e
exit "$status"

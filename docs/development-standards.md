# Development and formatting standards

This repo is a single macOS app: a C command-line/HID core
(`Sources/C/Core/main.m` plus the independently compiled
modules under `Sources/C`) and a SwiftUI/AppKit GUI under `Sources/Swift`,
packaged together into `outputs/LOPE.app` by the Makefile. These are project
defaults; the Makefile, existing source conventions, and other project docs
override them when they are more specific. For required tooling and one-time
setup, see
[development-setup.md](development-setup.md).

## Working tools

- Search content with `rg`; find files with `fd`.
- Use `jq` for inspecting or transforming the profile JSON under `Profiles/`.
- Use `gh` for GitHub pull requests, issues, reviews, CI, and releases rather
  than scraping GitHub pages or calling its REST API directly when `gh`
  covers the operation.
- Do not use `cat -A`.

## Building and testing

- `./rebuild-signed.sh` is the only command that updates the deliverable at
  `outputs/LOPE.app` (see the Build section in AGENTS.md/CLAUDE.md).
- `make gui` and direct `swiftc` invocations are compile-only checks, useful
  for fast iteration but not a substitute for `./rebuild-signed.sh`.
- `make test` runs `./lope self-test` (C core) and `swift test` (the
  `LOPECoreTests` XCTest target defined in `Package.swift`). Run it after
  touching parsing, model, or protocol code.
- `swift test`/`swift build` are driven by `Package.swift`, which exists
  only to run the Swift unit tests; it does not build or replace the
  shipped app. The app is still built by the Makefile via direct `swiftc`
  invocations, and `Package.swift`'s `LOPECore` target excludes the app
  entry point and SwiftUI view files (the same split the Makefile used for
  its old model-only test binaries); all C sources live outside the Swift
  package target under `Sources/C`.
- Building and testing only invoke local tools (`clang`, `swiftc`, `swift`,
  `codesign`); none of it needs elevated sandbox permissions or network
  access.

## Formatting and quality

- Swift formatting/linting uses Apple's `swift-format` (via `xcrun`), with
  the ruleset pinned in `.swift-format` at the repo root. C formatting uses
  `clang-format`, configured in `.clang-format`. Run `make format` to apply
  both, or `make lint` (alias for `make format-check`) to check without
  writing changes.
- `.clang-format` keeps include sorting disabled so module headers and
  platform headers remain in deliberate, readable groups.
- `make install-hooks` copies `scripts/git-hooks/pre-commit` into
  `.git/hooks/pre-commit`. That hook runs `make format-check`, `make test`,
  and `make coverage-check` before every commit. Each clone needs to run
  `make install-hooks` once; it is not automatic.
- Never bypass commit hooks.
- Work TDD-first and keep solutions simple and non-duplicative: T.D.D. ·
  K.I.S.S. · D.R.Y.

## Testing conventions

- Swift tests are XCTest cases under `Tests/`, run with `swift test` against
  the `LOPECore` library target, mirroring `Sources/Swift/Model/` one file
  at a time (e.g. `DPIModelTests.swift` for `DPIModel.swift`,
  `AppModelWritesTests.swift` for `AppModel+Writes.swift`). Add new test
  methods to the relevant `XCTestCase`, or a new `XCTestCase` file under
  `Tests/` named after the production file it covers — any `.swift` file
  there is picked up automatically by the `LOPECoreTests` target, no
  Makefile changes needed. `AppModelTestFixtures.swift` holds
  `configureFixtureDevice(_:)`, a fixture shared by the several
  `AppModel*Tests.swift` files that need a configured device/profile; add
  further cross-file fixtures there rather than duplicating setup code.
- C self-tests mirror `Sources/C/` the same way, one `test_<module>.c` file
  per production module (e.g. `test_report_rate.c` for `report_rate.c`),
  each exposing a single `int test_<module>(void)` entry point declared in
  `selftest_modules.h`. Each test function is a plain function that
  `fprintf(stderr, ...)` and returns a nonzero status on the first failing
  case, matching the existing C self-test convention; there is no
  XCTest/GoogleTest equivalent wired up for the C side.
  `Sources/C/Testing/selftest.c` is now just the `run_self_test()`
  dispatcher that calls each module's test function in turn and is what
  `./lope self-test` invokes. `Sources/C/Testing/test_doubles.c` holds the
  shared mocking seams (`channel_request_test_double`,
  `discover_devices_for_options_test_double`) and canned fixture builders
  (`build_mock_onboard_sector`, `build_mock_control_sector`,
  `k_mock_get_info_reply`) that more than one module's self-test needs;
  add further cross-module fixtures there rather than duplicating them.
  Add new cases to the relevant `test_<module>.c`, or a new
  `test_<module>.c` file plus a matching declaration in
  `selftest_modules.h` and a call from `run_self_test()`, for new C core
  logic.
- A type named identically to an Apple system type (e.g. `RGBColor`, which
  collides with the legacy QuickDraw `RGBColor` in `ApplicationServices`)
  can become ambiguous in test code once any file in the same target
  imports AppKit/ApplicationServices, even in files that never import them
  directly, because Swift's Clang importer shares one namespace for
  Objective-C/C declarations across a compilation. Qualify the call with
  the module name (`LOPECore.RGBColor(...)`) rather than adding an
  unhelpful type annotation, which does not resolve it.

## Coverage

- Both languages use Clang/LLVM source-based coverage instrumentation
  (`-fprofile-instr-generate -fcoverage-mapping`) so one tool, `llvm-cov`,
  reads both reports. There is no gcov/lcov and no Istanbul/JaCoCo here.
- `make coverage` builds and runs an instrumented C self-test binary and an
  instrumented `swift test` run, then prints an `llvm-cov report` for each.
  `make coverage-c` / `make coverage-swift` run them individually.
- **Branch coverage is only available for the C core.** Clang emits branch
  regions and `make coverage-c` reports them (`--show-branch-summary`). The
  Swift frontend (Swift 6.3 toolchain, checked 2026-09) does not emit
  branch-region coverage mapping at all, so `llvm-cov` always reports 0/0
  branches for Swift files — this is a toolchain limitation, not a bug in
  the test suite. Judge Swift coverage on line/region coverage only; do not
  write or expect a Swift branch-coverage percentage.
- `make coverage-check` enforces per-file minimums (`COVERAGE_MIN_LINE`,
  `COVERAGE_MIN_BRANCH`; default 90 each) via `scripts/check-coverage.sh`,
  which prints every file below the threshold in one run before failing,
  matching per-file-and-aggregate gating intent. `coverage-check-c` checks
  line and branch minimums for the C core; `coverage-check-swift` checks
  the line minimum only for Swift (branch checking is skipped there since
  the toolchain cannot report it). Override thresholds ad hoc with
  `make coverage-check COVERAGE_MIN_LINE=80`.
- `coverage-check-c` and `coverage-c` both exclude `Sources/C/Testing/`
  (`--ignore-filename-regex`/a negative-lookahead source pattern) from the
  report and the threshold check. That directory is test infrastructure —
  the `test_<module>.c` files, `selftest.c`'s dispatcher, and
  `test_doubles.c`'s mocking seams — not production code, so it is scored
  the same way `Tests/` is already excluded from the Swift side. Self-test
  files built from `&&`-chained assertions (`ok = a() && b() && !c(); if
  (!ok) { ...; return 1; }`) structurally cap their own branch coverage
  well under 90%: once every chained condition passes, the early-bail
  branch for each `&&` never executes, and that is a property of the
  assertion style, not a gap in what is tested. Excluding the directory
  avoids grading test code against a metric it can't meaningfully satisfy.
- `make coverage-check` is wired into the pre-commit hook alongside
  `make test` and `make lint`.
- For each uncovered line or path you touch:
  1. Write a test for reachable behavior and relevant edge cases.
  2. There is no per-line exclusion comment (no `LCOV_EXCL_LINE` equivalent
     recognized by `llvm-cov`'s source-based coverage); it only supports
     whole-file exclusion via `--ignore-filename-regex`. If a path is
     genuinely untestable, say so in the PR/commit description and in a
     comment at the site rather than relying on a suppression convention
     that does not exist for this tooling.
  3. Add any newly discovered edge case to the relevant test file.
- Prefer running `make test` for ordinary work; run `make coverage-check`
  before landing changes meant to close a coverage gap, and before release
  candidates.

## Style

- Swift: SwiftUI/AppKit, following the file-splitting convention already in
  use (e.g. `AppModel+Editing.swift`, `AppModel+Writes.swift` extensions on
  a shared model type).
- C: C11 with `-Wall -Wextra -Wpedantic`. Keep each module independently
  compilable, put shared declarations in headers, and keep implementation-
  private helpers `static`.

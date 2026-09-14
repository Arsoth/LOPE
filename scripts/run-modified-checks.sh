#!/usr/bin/env bash
# Runs the focused test and coverage gate for the files changed in the
# current worktree. The pre-commit hook sets MODIFIED_TESTS_STAGED_ONLY=1 so
# this script examines only staged paths; direct invocations include all
# tracked changes since HEAD plus untracked files.
#
# Swift tests are selected by XCTest case. The C self-test binary currently
# has one dispatcher, so any C change runs the complete C self-test suite.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$script_dir"

staged_only="${MODIFIED_TESTS_STAGED_ONLY:-0}"
changed_files() {
  if [[ "$staged_only" == "1" ]]; then
    git diff --cached --name-only --diff-filter=ACMRD
  else
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  fi
}

swift_filters=""
c_coverage_pattern=""
swift_coverage_pattern=""
changed_count=0
run_c_tests=0
run_full_swift=0
run_full_tests=0
run_c_coverage=0
run_swift_coverage=0

add_swift_filter() {
  local filter="$1"
  case "|$swift_filters|" in
    *"|$filter|"*) return ;;
  esac
  if [[ -n "$swift_filters" ]]; then
    swift_filters+="|"
  fi
  swift_filters+="$filter"
}

escape_coverage_path() {
  local path="$1"
  # Source paths only contain ordinary path punctuation plus `.` and `+`.
  path="${path//./\\.}"
  path="${path//+/\\+}"
  printf '%s' "$path"
}

add_c_coverage_file() {
  local escaped
  escaped="$(escape_coverage_path "$1")"
  if [[ -n "$c_coverage_pattern" ]]; then
    c_coverage_pattern+="|"
  fi
  c_coverage_pattern+="${escaped}$"
  run_c_coverage=1
}

add_swift_coverage_file() {
  local escaped
  escaped="$(escape_coverage_path "$1")"
  if [[ -n "$swift_coverage_pattern" ]]; then
    swift_coverage_pattern+="|"
  fi
  swift_coverage_pattern+="${escaped}$"
  run_swift_coverage=1
}

add_swift_model_tests() {
  local basename="$1"
  case "$basename" in
    AppModel+BackupMetadata.swift) add_swift_filter AppModelBackupMetadataTests ;;
    AppModel+BackupRecovery.swift) add_swift_filter AppModelBackupRecoveryTests ;;
    AppModel+Catalog.swift) add_swift_filter AppModelCatalogTests ;;
    AppModel+DeviceDiscovery.swift) add_swift_filter AppModelDeviceDiscoveryTests ;;
    AppModel+EditingButtons.swift) add_swift_filter AppModelEditingButtonsTests ;;
    AppModel+EditingDPI.swift) add_swift_filter AppModelEditingDPITests ;;
    AppModel+EditingKeyboard.swift) add_swift_filter AppModelEditingKeyboardTests ;;
    AppModel+EditingRGB.swift) add_swift_filter AppModelEditingRGBTests ;;
    AppModel+GeneratedProfilesPreferences.swift) add_swift_filter AppModelGeneratedProfilesPreferencesTests ;;
    AppModel+JSONEditableBackups.swift) add_swift_filter AppModelJSONEditableBackupsTests ;;
    AppModel+KnownDeviceReconnect.swift) add_swift_filter AppModelKnownDeviceReconnectTests ;;
    AppModel+LiveDPIPolling.swift) add_swift_filter AppModelLiveDPIPollingTests ;;
    AppModel+Parsing.swift) add_swift_filter AppModelParsingTests ;;
    AppModel+ProfileEditor.swift) add_swift_filter AppModelProfileEditorTests ;;
    AppModel+Refresh.swift)
      add_swift_filter AppModelRefreshTests
      add_swift_filter AppModelRefreshSnapshotTests
      add_swift_filter AppModelRefreshLifecycleTests
      ;;
    AppModel+RefreshLifecycle.swift) add_swift_filter AppModelRefreshLifecycleTests ;;
    AppModel+RefreshSnapshot.swift) add_swift_filter AppModelRefreshSnapshotTests ;;
    AppModel+Writes.swift) add_swift_filter AppModelWritesTests ;;
    AppModel.swift)
      run_full_swift=1
      ;;
    AppModels.swift) add_swift_filter AppModelsTests ;;
    AppSupport.swift) add_swift_filter AppSupportTests ;;
    BackupStorage.swift) add_swift_filter BackupStorageTests ;;
    DeviceClassification.swift) add_swift_filter AppModelsTests ;;
    DPIModel.swift) add_swift_filter DPIModelTests ;;
    MouseProfileCatalog.swift)
      add_swift_filter MouseProfileCatalogTests
      add_swift_filter AppModelCatalogTests
      ;;
    MouseProfileDescriptor.swift)
      add_swift_filter MouseProfileDescriptorTests
      add_swift_filter MouseProfileCatalogTests
      ;;
    PollingRateModel.swift) add_swift_filter PollingRateModelTests ;;
    ProfileOutputParser.swift)
      add_swift_filter ProfileOutputParserTests
      add_swift_filter AppModelParsingTests
      ;;
    ProfileSelection.swift) add_swift_filter ProfileSelectionTests ;;
    ProfileWriteValidation.swift)
      add_swift_filter ProfileWriteValidationTests
      add_swift_filter AppModelWritesTests
      ;;
    RGBModel.swift) add_swift_filter RGBModelTests ;;
    RefreshGuidance.swift)
      add_swift_filter MouseProfileCatalogTests
      add_swift_filter AppModelTests
      ;;
    StatusHistory.swift) add_swift_filter StatusHistoryTests ;;
    Shims/AppModel+BackupRecoveryShim.swift) add_swift_filter AppModelBackupRecoveryTests ;;
    Shims/AppModel+GeneratedProfilesPreferencesShim.swift) add_swift_filter AppModelGeneratedProfilesPreferencesTests ;;
    Shims/AppModel+JSONEditableBackupsShim.swift) add_swift_filter AppModelJSONEditableBackupsTests ;;
    Shims/AppModel+ProfileEditorShim.swift) add_swift_filter AppModelProfileEditorTests ;;
    Shims/AppModel+RefreshShim.swift) add_swift_filter AppModelRefreshTests ;;
    *) run_full_swift=1 ;;
  esac
}

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  changed_count=$((changed_count + 1))

  case "$path" in
    Sources/C/*.c|Sources/C/*.h|Sources/C/*/*.c|Sources/C/*/*.h|Sources/C/Core/main.m)
      run_c_tests=1
      if [[ "$path" == *.c ]]; then
        add_c_coverage_file "$path"
      else
        # Headers can affect several translation units, so use the complete
        # C coverage report when a header or the dispatcher changes.
        run_c_coverage=1
        c_coverage_pattern=""
      fi
      ;;
    Sources/Swift/Model/*.swift)
      add_swift_model_tests "${path##*/}"
      if [[ "${path##*/}" == "AppModel.swift" ]]; then
        run_swift_coverage=1
        swift_coverage_pattern=""
      else
        add_swift_coverage_file "$path"
      fi
      ;;
    Sources/Swift/Tests/*Fixtures.swift|Sources/Swift/Tests/RefreshFakeEngineSupport.swift)
      run_full_swift=1
      ;;
    Sources/Swift/Tests/*Tests.swift)
      test_case="${path##*/}"
      test_case="${test_case%.swift}"
      add_swift_filter "$test_case"
      ;;
    Sources/Swift/Tests/*.swift)
      run_full_swift=1
      ;;
    Sources/Swift/UI/*.swift)
      # UI views have no XCTest target; the signed app rebuild and formatting
      # gate provide the relevant verification for these files.
      ;;
    Sources/Swift/*|Sources/Swift/*/*)
      run_full_swift=1
      ;;
    Profiles/*.json)
      add_swift_filter MouseProfileCatalogTests
      add_swift_filter AppModelCatalogTests
      ;;
    Package.swift|Makefile|scripts/*)
      run_full_tests=1
      ;;
  esac
done < <(changed_files)

if [[ "$changed_count" -eq 0 ]]; then
  echo "modified-test gate: no changed files found; nothing to run"
  exit 0
fi

if [[ "$run_full_tests" -eq 1 ]]; then
  echo "modified-test gate: infrastructure changed; running the full suite"
  make test
  make coverage-check
  exit 0
fi

if [[ "$run_c_tests" -eq 1 ]]; then
  echo "modified-test gate: running the C self-test suite"
  make self-test
fi

if [[ "$run_full_swift" -eq 1 || -n "$swift_filters" ]]; then
  # Swift package tests deliberately exercise the no-bundled-engine path
  # (see the `test` target). The C self-test step above, or a stale build
  # from outside this script, can leave a bundled engine binary behind;
  # remove it so those tests see the environment they expect.
  rm -f lope bin/lope
fi

if [[ "$run_full_swift" -eq 1 ]]; then
  echo "modified-test gate: running the full Swift test suite"
  scripts/run-swift-test-quiet.sh --summary
elif [[ -n "$swift_filters" ]]; then
  echo "modified-test gate: running Swift tests matching: $swift_filters"
  scripts/run-swift-test-quiet.sh --summary --filter "$swift_filters"
fi

if [[ "$run_c_coverage" -eq 1 ]]; then
  if [[ -n "$c_coverage_pattern" ]]; then
    make coverage-check-c COVERAGE_C_SOURCES_PATTERN="$c_coverage_pattern"
  else
    make coverage-check-c
  fi
fi

if [[ "$run_swift_coverage" -eq 1 ]]; then
  if [[ "$run_full_swift" -eq 1 ]]; then
    make coverage-check-swift
  else
    make coverage-check-swift \
      SWIFT_TEST_ARGS="--filter '$swift_filters'" \
      COVERAGE_SWIFT_SOURCES_PATTERN="$swift_coverage_pattern"
  fi
fi

if [[ "$run_c_tests" -eq 0 && "$run_full_swift" -eq 0 && -z "$swift_filters" ]]; then
  echo "modified-test gate: no source or test files require a test run"
fi

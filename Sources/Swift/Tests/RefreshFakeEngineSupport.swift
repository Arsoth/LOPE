// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Shared support for the refresh/live-DPI-polling test files
// (AppModelRefreshTests, AppModelRefreshSnapshotTests,
// AppModelRefreshLifecycleTests, AppModelLiveDPIPollingTests). Those
// production files drive the real `lope` CLI through `EngineRunner`, whose
// entry points take the executable `URL` directly as a parameter rather than
// going through `engineRunnerOverride` (that seam only covers
// `AppModel.runEngine`, consumed by the editing/write paths). A tiny POSIX
// shell script standing in for the engine lets these tests exercise the
// real retry/parsing/state-transition logic without touching hardware.

enum TestTempDirectory {
  static func make(prefix: String = "lope-refresh-test") -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

enum FakeEngine {
  /// Writes an executable shell script to `directory/lope` that answers
  /// "list", "profiles", and "current-dpi" invocations from environment
  /// variables, so each test can control output/exit codes without a
  /// compiled fixture binary. When `LOPE_TEST_ARGS_LOG` is set, every
  /// invocation appends its argument line to that file, letting tests
  /// assert on exact argument construction (device selector, retry counts).
  @discardableResult
  static func write(to directory: URL) -> URL {
    let url = directory.appendingPathComponent("lope")
    // Each command family (LIST/PROFILES/CURRENT_DPI) supports an optional
    // invocation counter (LOPE_TEST_<CMD>_COUNTER, a file path) and
    // LOPE_TEST_<CMD>_FAIL_UNTIL: invocations at or below that count exit
    // with LOPE_TEST_<CMD>_FAIL_OUTPUT/EXIT, later ones fall through to the
    // normal LOPE_TEST_<CMD>_OUTPUT/EXIT. This lets retry-loop tests
    // (runProfileReadWithRetry, runDeviceListWithRetry) exercise a real
    // fail-then-succeed sequence deterministically, without depending on
    // wall-clock timing.
    let script = """
      #!/bin/sh
      if [ -n "$LOPE_TEST_ARGS_LOG" ]; then
        printf '%s\\n' "$*" >> "$LOPE_TEST_ARGS_LOG"
      fi
      args=" $* "
      case "$args" in
        *' list '*) cmd=LIST ;;
        *' current-dpi '*) cmd=CURRENT_DPI ;;
        *' profiles '*) cmd=PROFILES ;;
        *) exit 1 ;;
      esac

      counter_var="LOPE_TEST_${cmd}_COUNTER"
      eval "counter_file=\\$$counter_var"
      count=0
      if [ -n "$counter_file" ]; then
        if [ -f "$counter_file" ]; then count=$(cat "$counter_file"); fi
        count=$((count + 1))
        printf '%s' "$count" > "$counter_file"
      fi

      fail_until_var="LOPE_TEST_${cmd}_FAIL_UNTIL"
      eval "fail_until=\\$$fail_until_var"
      if [ -n "$fail_until" ] && [ "$count" -le "$fail_until" ]; then
        eval "output=\\$LOPE_TEST_${cmd}_FAIL_OUTPUT"
        eval "exit_code=\\$LOPE_TEST_${cmd}_FAIL_EXIT"
        printf '%s' "$output"
        exit "${exit_code:-1}"
      fi

      eval "output=\\$LOPE_TEST_${cmd}_OUTPUT"
      eval "exit_code=\\$LOPE_TEST_${cmd}_EXIT"
      printf '%s' "$output"
      exit "${exit_code:-0}"
      """
    try? FileManager.default.removeItem(at: url)
    try? script.write(to: url, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }
}

enum FakeEngineEnvironment {
  private static let commands = ["LIST", "PROFILES", "CURRENT_DPI"]
  private static let suffixes = [
    "OUTPUT", "EXIT", "COUNTER", "FAIL_UNTIL", "FAIL_OUTPUT", "FAIL_EXIT",
  ]
  private static let allKeys =
    ["LOPE_TEST_ARGS_LOG"]
    + commands.flatMap { command in suffixes.map { "LOPE_TEST_\(command)_\($0)" } }

  static func set(_ key: String, _ value: String) {
    setenv(key, value, 1)
  }

  /// Test bodies call this in a `defer` right after configuring the
  /// scenario's environment variables, so a failure partway through a test
  /// cannot leak fixture output into a later, unrelated test.
  static func clearAll() {
    for key in allKeys {
      unsetenv(key)
    }
  }
}

enum ProcessDirectory {
  /// `AppModel.engine` resolves relative to the process's current working
  /// directory when no bundled resource is found (always true in the test
  /// binary). Swapping the directory only for the synchronous portion of a
  /// refresh call is safe: `engine` is captured into a local `let` before
  /// any `Task { ... }` is created, so restoring the original directory
  /// immediately afterwards does not affect the already-captured URL.
  @discardableResult
  static func withCurrentDirectory<T>(_ path: String, _ operation: () -> T) -> T {
    let original = FileManager.default.currentDirectoryPath
    _ = FileManager.default.changeCurrentDirectoryPath(path)
    defer { _ = FileManager.default.changeCurrentDirectoryPath(original) }
    return operation()
  }
}

@MainActor
func waitUntil(
  timeout: TimeInterval = 3,
  file: StaticString = #filePath,
  line: UInt = #line,
  condition: () -> Bool
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() {
    if Date() >= deadline {
      XCTFail("Timed out waiting for condition", file: file, line: line)
      return
    }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
}

/// A realistic device-list line accepted by `AppModel.parseDeviceChoices`.
/// Note the parser's device-key capture group is hex-and-hyphen only
/// (`[0-9A-Fa-f-]+`), unlike the free-form `deviceKey` strings used
/// elsewhere in fixtures that build `DeviceChoice` values directly (no text
/// parsing involved) -- keep any key threaded through this helper hex-only.
func fakeDeviceListLine(
  id: Int = 1,
  connection: String = "Wired",
  name: String = "G502 X",
  productID: String = "0x0000",
  deviceKey: String = "abc123ef"
) -> String {
  "[\(id)] \(connection)  \(name) (HID++ 4.5, product \(productID), key \(deviceKey))"
}

/// A realistic "profiles" output body accepted by `AppModel.parseProfiles`,
/// `AppModel.selectedProfileNumber(in:)`, and `ProfileOutputParser`.
func fakeProfilesOutput(
  capacity: Int = 3,
  selectedProfile: Int = 2,
  profileID: Int = 2,
  sector: String = "0x0100",
  enabled: Bool = true,
  buttonRaw: String = "80 01 00 02",
  currentDPI: Int = 800
) -> String {
  """
  Profile capacity: \(capacity)
  Selected profile: \(selectedProfile)
  Profile \(profileID) (sector \(sector), enabled=\(enabled ? "yes" : "no"))
  CRC: OK
  format: 0x01
    button 1: Left click [\(buttonRaw)]
  Supported DPI: 100..25600 (step 50)
  DPI sensors: 1
  Current sensor 1 DPI: \(currentDPI)
  DPI stages: 400, 800, 1600 (default 2, shift 1)
  Supported polling rates: 125, 500, 1000
  Current polling rate: 500 Hz

  """
}

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
      if [ "$cmd" = "LIST" ] && [ -z "$output" ]; then
        output='{"contract_version":1,"ok":true,"kind":"device_list","vendor_interface_count":0,"devices":[],"device_count":0}'
      fi
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

/// A realistic device-list response accepted by the GUI-facing JSON decoder.
func fakeDeviceListLine(
  id: Int = 1,
  connection: String = "Wired",
  name: String = "G502 X",
  productID: String = "0x0000",
  deviceKey: String = "abc123ef"
) -> String {
  let numericProductID = UInt32(productID.dropFirst(2), radix: 16) ?? 0
  return
    "{\"contract_version\":1,\"ok\":true,\"kind\":\"device_list\",\"vendor_interface_count\":1,\"devices\":[{\"index\":\(id),\"vendor_id\":1133,\"product_id\":\(numericProductID),\"device_number\":1,\"request_device_number\":1,\"protocol\":4.5,\"name\":\"\(name)\",\"connection\":\"\(connection)\",\"device_key\":\"\(deviceKey)\"}],\"device_count\":1}"
}

func fakeStructuredDeviceListOutput() -> String {
  """
  {"contract_version":1,"ok":true,"kind":"device_list","vendor_interface_count":1,"devices":[{"index":1,"vendor_id":1133,"product_id":0,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"G502 X","connection":"Wired","device_key":"abc123ef"}],"device_count":1}
  """.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fakeStructuredProfilesOutput() -> String {
  """
  {"contract_version":1,"ok":true,"kind":"profiles","device":{"index":1,"vendor_id":1133,"product_id":0,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"G502 X","connection":"Wired","device_key":"abc123ef"},"profile_capacity":3,"headers":[{"number":1,"sector":256,"enabled":false},{"number":2,"sector":512,"enabled":true}],"selected_profile":{"number":2,"sector":512,"enabled":true,"memory":3,"format":1,"macro_format":0,"profile_capacity":3,"button_capacity":5,"sector_count":1,"sector_size":256,"shift_flags":0,"crc_checked":true,"crc_valid":true,"layouts":{"buttons":true,"gshift":true,"dpi":true,"rgb":true},"buttons":[{"number":1,"layer":"normal","raw":[128,1,0,2],"description":"Left click"},{"number":1,"layer":"gShift","raw":[128,2,0,3],"description":"Right click"}],"dpi_stages":[400,800,1600],"dpi_default_stage":2,"dpi_shift_stage":1,"rgb_zones":[{"number":1,"present":true,"mode":1,"color":[255,0,16]}]},"dpi":{"requested":true,"available":true,"sensor_count":1,"supported_values":[400,800,1600],"current_sensor_dpi":800,"error":""},"report_rate":{"requested":true,"available":true,"feature_id":32864,"rates":[{"hertz":125,"wire_value":8},{"hertz":500,"wire_value":2},{"hertz":1000,"wire_value":1}],"current_valid":true,"current_hertz":500,"error":""}}
  """.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fakeStructuredProfilesWithoutSelectionOutput() -> String {
  """
  {"contract_version":1,"ok":true,"kind":"profiles","device":{"index":1,"vendor_id":1133,"product_id":0,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"G502 X","connection":"Wired","device_key":"abc123ef"},"profile_capacity":3,"headers":[],"selected_profile":null,"dpi":null,"report_rate":null}
  """.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fakeStructuredProfilesWithoutDPIOutput() -> String {
  fakeStructuredProfilesOutput().replacingOccurrences(
    of:
      "\"dpi\":{\"requested\":true,\"available\":true,\"sensor_count\":1,\"supported_values\":[400,800,1600],\"current_sensor_dpi\":800,\"error\":\"\"},",
    with: "\"dpi\":null,"
  )
}

func fakeStructuredProfilesWithoutReportedCapacityOutput() -> String {
  var output = fakeStructuredProfilesOutput()
  if let range = output.range(of: "\"profile_capacity\":3,") {
    output.removeSubrange(range)
  }
  return output
}

func fakeStructuredDPIOutput() -> String {
  """
  {"contract_version":1,"ok":true,"kind":"dpi","device":{"index":1,"vendor_id":1133,"product_id":0,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"G502 X","connection":"Wired","device_key":"abc123ef"},"dpi":{"requested":true,"available":true,"sensor_count":1,"supported_values":[400,800,1600],"current_sensor_dpi":800,"error":""},"onboard_profile":null,"onboard_profile_error":""}
  """.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fakeStructuredCurrentDPIOutput(_ value: Int) -> String {
  "{\"contract_version\":1,\"ok\":true,\"kind\":\"current_dpi\",\"device\":null,\"dpi\":{\"requested\":false,\"available\":true,\"sensor_count\":1,\"supported_values\":[],\"current_sensor_dpi\":\(value),\"error\":\"\"}}"
}

func fakeStructuredWriteOutput() -> String {
  """
  {"contract_version":1,"ok":true,"kind":"write","operation":"apply","operation_id":"profile-2-save-test","device":null,"profile":2,"changed":true,"dry_run":false,"completed":true,"planned_sectors":[{"kind":"profile","sector":512,"length":256}],"has_backup":true,"backup_path":"/tmp/profile-2-save-test.logiob","verified_sectors":1}
  """.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fakeStructuredEngineOutput(for arguments: [String]) -> String {
  arguments.contains("profiles") ? fakeStructuredProfilesOutput() : fakeStructuredWriteOutput()
}

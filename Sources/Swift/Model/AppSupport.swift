// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum EngineError: LocalizedError {
  case unavailable
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return L10n.text("The bundled HID++ engine could not be found.")
    case .failed(let message):
      return message.isEmpty ? L10n.text("The HID++ engine failed.") : message
    }
  }
}

enum AppConstants {
  static let displayName = "LOPE"
  static let shortName = "LOPE"
  static let engineName = "lope"
  static let appSupportDirectory = "LOPE"
  static let defaultsPrefix = "LOPE"
  static let lastSelectedDeviceKey = "lastSelectedDevice"
  static let backupExtension = "logiob"
  static let appearancePreferenceKey = "appearancePreference"
}

enum AppearancePreference: String, CaseIterable, Hashable {
  case system
  case light
  case dark

  var label: String {
    switch self {
    case .system: return L10n.text("System")
    case .light: return L10n.text("Light")
    case .dark: return L10n.text("Dark")
    }
  }
}

enum EngineRunner {
  // A refresh can be cancelled after its Task has started, but Process does
  // not stop synchronously with Swift task cancellation. Serialize helper
  // invocations so a stale HID reader cannot hold an interface open while a
  // newly selected device is being queried.
  private static let invocationLock = NSLock()

  /// Wait until a previously launched engine process has released the HID
  /// invocation lock. This keeps an explicit TCC request attributed to the
  /// GUI instead of an in-flight helper process.
  static func waitUntilIdle() async {
    await Task.detached(priority: .utility, operation: waitUntilIdleSynchronously).value
  }

  private static func waitUntilIdleSynchronously() {
    invocationLock.lock()
    invocationLock.unlock()
  }

  struct ProcessResult: Sendable {
    let output: String
    let terminationStatus: Int32
  }

  /// Runs a GUI-facing engine command without interpreting its output. The
  /// caller owns contract validation so structured error envelopes can be
  /// surfaced alongside any stderr diagnostics emitted by the helper.
  static func runStructured(
    executable: URL,
    arguments: [String],
    currentDirectory: URL
  ) throws -> ProcessResult {
    invocationLock.lock()
    defer { invocationLock.unlock() }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    var environment = ProcessInfo.processInfo.environment
    environment["LOGITECH_ONBOARD_DEBUG"] = "0"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(
      output: String(data: data, encoding: .utf8) ?? "",
      terminationStatus: process.terminationStatus
    )
  }

  static func run(executable: URL, arguments: [String], currentDirectory: URL) throws -> String {
    invocationLock.lock()
    defer { invocationLock.unlock() }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    var environment = ProcessInfo.processInfo.environment
    // The engine's HID trace is useful from the CLI, but it is not a
    // user-facing error message. Keep it disabled for GUI invocations so
    // a failed read cannot turn into a wall of transport diagnostics.
    environment["LOGITECH_ONBOARD_DEBUG"] = "0"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw EngineError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return output
  }

  static func runStructuredWithLineProgress(
    executable: URL,
    arguments: [String],
    currentDirectory: URL,
    onLine: @escaping @Sendable (String) -> Void
  ) throws -> ProcessResult {
    invocationLock.lock()
    defer { invocationLock.unlock() }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    var environment = ProcessInfo.processInfo.environment
    environment["LOGITECH_ONBOARD_DEBUG"] = "0"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()

    var outputData = Data()
    var pendingLineData = Data()
    let handle = pipe.fileHandleForReading
    while true {
      let data = handle.availableData
      if data.isEmpty { break }
      outputData.append(data)
      pendingLineData.append(data)
      while let newline = pendingLineData.firstIndex(of: 0x0A) {
        let lineData = pendingLineData[..<newline]
        if let line = String(data: lineData, encoding: .utf8) {
          onLine(line)
        }
        pendingLineData.removeSubrange(...newline)
      }
    }
    if !pendingLineData.isEmpty,
      let line = String(data: pendingLineData, encoding: .utf8)
    {
      onLine(line)
    }

    process.waitUntilExit()
    return ProcessResult(
      output: String(data: outputData, encoding: .utf8) ?? "",
      terminationStatus: process.terminationStatus
    )
  }

  static func runWithLineProgress(
    executable: URL,
    arguments: [String],
    currentDirectory: URL,
    onLine: @escaping @Sendable (String) -> Void
  ) throws -> String {
    let result = try runStructuredWithLineProgress(
      executable: executable,
      arguments: arguments,
      currentDirectory: currentDirectory,
      onLine: onLine
    )
    guard result.terminationStatus == 0 else {
      throw EngineError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return result.output
  }
}

struct RefreshSnapshot: Sendable {
  let devices: [DeviceChoice]
  let selectedDeviceIndex: Int?
  let profileResponse: EngineJSONResponse?
  let profileError: String?
  let dpiText: String?
  let dpiError: String?
  let selectedProfileNumber: Int?
  let errorMessage: String?
  let accessWarning: Bool

  init(
    devices: [DeviceChoice],
    selectedDeviceIndex: Int?,
    profileError: String?,
    dpiText: String?,
    dpiError: String?,
    selectedProfileNumber: Int?,
    errorMessage: String?,
    accessWarning: Bool,
    profileResponse: EngineJSONResponse? = nil
  ) {
    self.devices = devices
    self.selectedDeviceIndex = selectedDeviceIndex
    self.profileResponse = profileResponse
    self.profileError = profileError
    self.dpiText = dpiText
    self.dpiError = dpiError
    self.selectedProfileNumber = selectedProfileNumber
    self.errorMessage = errorMessage
    self.accessWarning = accessWarning
  }
}

struct DeviceEnumerationSnapshot: Sendable {
  let devices: [DeviceChoice]
  let selectedDeviceIndex: Int?
  let accessWarning: Bool
  let errorMessage: String?
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum EngineError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The bundled HID++ engine could not be found."
        case .failed(let message):
            return message.isEmpty ? "The HID++ engine failed." : message
        }
    }
}

enum AppConstants {
    static let displayName = "Logitech Onboard Memory Profile System"
    static let shortName = "LOMPS"
    static let engineName = "lomps"
    static let appSupportDirectory = "LOMPS"
    static let defaultsPrefix = "LOMPS"
    static let backupExtension = "logiob"
}

enum EngineRunner {
    // A refresh can be cancelled after its Task has started, but Process does
    // not stop synchronously with Swift task cancellation. Serialize helper
    // invocations so a stale HID reader cannot hold an interface open while a
    // newly selected device is being queried.
    private static let invocationLock = NSLock()

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
}

struct RefreshSnapshot: Sendable {
    let devices: [DeviceChoice]
    let selectedDeviceIndex: Int?
    let profileText: String?
    let profileError: String?
    let dpiText: String?
    let dpiError: String?
    let selectedProfileNumber: Int?
    let errorMessage: String?
    let accessWarning: Bool
}

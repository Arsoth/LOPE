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
    static let engineName = "logitech-onboard"
    static let appSupportDirectory = "LogitechOnboardProfileManager"
    static let defaultsPrefix = "LogitechOnboardProfileManager"
    static let backupExtension = "logiob"
}

enum EngineRunner {
    static func run(executable: URL, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["LOGITECH_ONBOARD_DEBUG"] = "1"
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

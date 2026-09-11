// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
    func presetLabel(for raw: String) -> String {
        presets.first(where: { normalize($0.raw) == normalize(raw) })?.label ?? "Custom raw output"
    }

    func loadDPI(profileText: String? = nil) {
        dpiDetails = ""
        do {
            let dpiText = try runEngine(["--sensor-only", "dpi"])
            parseDPI([profileText ?? "", dpiText].joined(separator: "\n"))
        } catch {
            dpiDetails = error.localizedDescription
        }
    }

    func runEngine(_ arguments: [String]) throws -> String {
        try runEngine(arguments, selectingDevice: true)
    }

    private func runEngine(_ arguments: [String], selectingDevice: Bool) throws -> String {
        guard let engine else { throw EngineError.unavailable }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = engine
        if selectingDevice, let selected = devices.first(where: { $0.id == selectedDeviceIndex }) {
            let selector = selected.deviceKey.isEmpty
                ? ["--device", String(selectedDeviceIndex)]
                : ["--device-key", selected.deviceKey]
            process.arguments = selector + arguments
        } else {
            process.arguments = arguments
        }
        process.currentDirectoryURL = backupDirectory
        var environment = ProcessInfo.processInfo.environment
        // Keep low-level HID tracing out of the status bar. It remains
        // available when the command-line engine is run directly with
        // LOGITECH_ONBOARD_DEBUG=1.
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

    func backupURL(prefix: String) -> URL {
        // The operation kind is intentionally not part of the public name:
        // all exact binary snapshots use the same mouse-date-time shape.
        _ = prefix
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let filename = "\(selectedMouseFileIdentifier())-\(backupTimestamp())-\(suffix).\(AppConstants.backupExtension)"
        return backupDirectory.appendingPathComponent(filename)
    }

    func normalize(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace }.uppercased()
    }

    nonisolated static func parseDeviceChoices(_ text: String) -> [DeviceChoice] {
        let pattern = try! NSRegularExpression(pattern: #"^\[(\d+)\]\s+(.+?)\s+\(HID\+\+\s+[0-9.]+,\s+product\s+(0x[0-9A-Fa-f]+),\s+key\s+([0-9A-Fa-f-]+)\)$"#)
        var result: [DeviceChoice] = []
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let id = Int(capture(match, in: line, index: 1)) else { continue }
            let descriptor = capture(match, in: line, index: 2)
            let pieces = descriptor.components(separatedBy: "  ").filter { !$0.isEmpty }
            let connection = pieces.first ?? "Logitech HID++"
            let name = pieces.dropFirst().joined(separator: " ").isEmpty
                ? descriptor
                : pieces.dropFirst().joined(separator: " ")
            result.append(DeviceChoice(
                id: id,
                name: name,
                connection: connection,
                productID: capture(match, in: line, index: 3),
                deviceKey: capture(match, in: line, index: 4)
            ))
        }
        return result.sorted { $0.id < $1.id }
    }

    nonisolated static func profileNumbers(in text: String) -> [Int] {
        let pattern = try! NSRegularExpression(pattern: #"^Profile\s+(\d+)\s+\("#)
        var result: [Int] = []
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let number = Int(capture(match, in: line, index: 1)) else { continue }
            result.append(number)
        }
        return result
    }

    nonisolated static func selectedProfileNumber(in text: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: #"^Selected profile:\s+(\d+)\s*$"#)
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = pattern.firstMatch(in: line, range: range),
               let number = Int(capture(match, in: line, index: 1)) {
                return number
            }
        }
        return nil
    }

    func parseProfiles(_ text: String) -> (choices: [ProfileChoice], rowsByProfile: [Int: [ButtonRow]]) {
        let profilePattern = try! NSRegularExpression(pattern: #"^Profile\s+(\d+)\s+\(sector\s+(0x[0-9A-Fa-f]+),\s+enabled=(yes|no)\)"#)
        let buttonPattern = try! NSRegularExpression(pattern: #"^\s*button\s+(\d+):\s*(.*?)\s*\[([0-9A-Fa-f ]+)\]"#)
        var choices: [ProfileChoice] = []
        var rows: [Int: [ButtonRow]] = [:]
        var currentProfile: Int?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let full = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = profilePattern.firstMatch(in: line, range: full),
               let id = Int(capture(match, in: line, index: 1)) {
                let sector = capture(match, in: line, index: 2)
                let enabledText = capture(match, in: line, index: 3)
                currentProfile = id
                if let existing = choices.firstIndex(where: { $0.id == id }) {
                    choices[existing].sector = sector
                    choices[existing].enabled = enabledText == "yes"
                    choices[existing].crcValid = nil
                } else {
                    choices.append(ProfileChoice(
                        id: id, sector: sector, enabled: enabledText == "yes", crcValid: nil
                    ))
                }
                rows[id] = []
                continue
            }
            if let profile = currentProfile,
               let index = choices.firstIndex(where: { $0.id == profile }) {
                switch line.trimmingCharacters(in: .whitespaces) {
                case "CRC: OK":
                    choices[index].crcValid = true
                    continue
                case "CRC: INVALID":
                    choices[index].crcValid = false
                    continue
                default:
                    break
                }
            }
            guard let profile = currentProfile,
                  let match = buttonPattern.firstMatch(in: line, range: full),
                  let number = Int(capture(match, in: line, index: 1)) else { continue }
            let rawBytes = capture(match, in: line, index: 3)
            let raw = normalize(rawBytes)
            rows[profile, default: []].append(ButtonRow(
                id: number,
                label: physicalButtonLabel(number),
                currentRaw: raw,
                draftRaw: raw,
                draftChoice: presets.contains(where: { normalize($0.raw) == raw }) ? raw : "custom"
            ))
        }
        return (choices, rows)
    }

    func parseDPI(_ text: String) {
        let pattern = try! NSRegularExpression(pattern: #"(?:Onboard profile \d+ )?DPI stages:\s*([0-9, ]+)\s*\(default\s+(\d+),\s*shift\s+(\d+)\)"#)
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = pattern.firstMatch(in: line, range: range) {
                let stageText = capture(match, in: line, index: 1)
                let defaultText = capture(match, in: line, index: 2)
                let shiftText = capture(match, in: line, index: 3)
                let values = stageText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if (1...5).contains(values.count) {
                    dpiCount = values.count
                    dpiStages = values + Array(repeating: "", count: 5 - values.count)
                    defaultStage = Int(defaultText) ?? defaultStage
                    shiftStage = Int(shiftText) ?? shiftStage
                    baselineDPICount = dpiCount
                    baselineDPIStages = dpiStages
                    baselineDefaultStage = defaultStage
                    baselineShiftStage = shiftStage
                }
            }
            if line.hasPrefix("Supported DPI:") || line.hasPrefix("Current sensor") {
                dpiDetails = [dpiDetails, line].filter { !$0.isEmpty }.joined(separator: "\n")
            }
            if line.hasPrefix("DPI error:") {
                dpiDetails = [dpiDetails, line].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
    }

    private nonisolated static func capture(_ match: NSTextCheckingResult, in text: String, index: Int) -> String {
        let range = match.range(at: index)
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private func capture(_ match: NSTextCheckingResult, in text: String, index: Int) -> String {
        Self.capture(match, in: text, index: index)
    }

    func rawBytes(_ raw: String) -> [UInt8]? {
        let normalized = normalize(raw)
        guard normalized.count == 8 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(4)
        var index = normalized.startIndex
        for _ in 0..<4 {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

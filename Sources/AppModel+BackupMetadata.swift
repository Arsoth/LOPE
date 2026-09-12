// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

private struct BackupDeviceMetadata {
    let name: String?
    let productID: String?
}

@MainActor
extension AppModel {
    func setShowAllBackups(_ show: Bool) {
        showAllBackups = show
        applyBackupFilter()
    }

    func refreshBackups() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        discoveredBackups = urls
            .filter { [AppConstants.backupExtension, "bin", "json"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      let modifiedAt = values.contentModificationDate,
                      let fileSize = values.fileSize else { return nil }
                let metadata = backupDeviceMetadata(at: url)
                return BackupEntry(
                    url: url,
                    modifiedAt: modifiedAt,
                    size: Int64(fileSize),
                    deviceMatch: backupDeviceMatch(metadata: metadata),
                    deviceName: metadata?.name
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        applyBackupFilter()
    }

    private func applyBackupFilter() {
        backups = showAllBackups
            ? discoveredBackups
            : discoveredBackups.filter { $0.deviceMatch == .selected }
    }

    private func backupDeviceMetadata(at url: URL) -> BackupDeviceMetadata? {
        if url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let editable = try? JSONDecoder().decode(EditableBackup.self, from: data) else {
                return nil
            }
            return BackupDeviceMetadata(
                name: editable.device.name.nilIfEmpty,
                productID: editable.device.productID.nilIfEmpty
            )
        }

        guard let data = try? Data(contentsOf: url), data.count >= 20,
              String(data: data.prefix(8), encoding: .ascii) == "LOGIOB02" else {
            return nil
        }

        let vendorID = UInt16(data[10]) << 8 | UInt16(data[11])
        guard vendorID == 0x046D else { return nil }
        let productID = UInt16(data[12]) << 8 | UInt16(data[13])
        return BackupDeviceMetadata(
            name: backupMouseName(from: url.lastPathComponent),
            productID: String(format: "0x%04X", productID)
        )
    }

    private func backupMouseName(from filename: String) -> String? {
        let pattern = try! NSRegularExpression(
            pattern: #"^(.+)-\d{8}-\d{6}-[0-9a-fA-F]{8}$"#
        )
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
        guard let match = pattern.firstMatch(in: stem, range: range),
              let nameRange = Range(match.range(at: 1), in: stem) else { return nil }
        return String(stem[nameRange]).nilIfEmpty
    }

    private func backupDeviceMatch(metadata: BackupDeviceMetadata?) -> BackupEntry.DeviceMatch {
        guard let selected = devices.first(where: { $0.id == selectedDeviceIndex }) else {
            return .unknown
        }

        guard let metadata else { return .unknown }

        // Backups are associated with a compatible mouse family, not a
        // physical unit. Binary packages provide product metadata and JSON
        // exports provide the display name and product metadata.
        if let metadataProductID = metadata.productID,
           sameProduct(metadataProductID, selected.productID) {
            return .selected
        }
        if let storedName = metadata.name,
           sameMouseFamily(storedName, selected.name) {
            return .selected
        }
        if metadata.productID == nil && metadata.name == nil {
            return .unknown
        }
        return .other
    }

    private func sameProduct(_ lhs: String, _ rhs: String) -> Bool {
        productValue(lhs) != nil && productValue(lhs) == productValue(rhs)
    }

    private func productValue(_ value: String) -> UInt32? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = normalized.lowercased().hasPrefix("0x")
            ? String(normalized.dropFirst(2))
            : normalized
        return UInt32(digits, radix: 16)
    }

    private func sameMouseFamily(_ lhs: String, _ rhs: String) -> Bool {
        let left = sanitizedMouseIdentifier(lhs).lowercased()
        let right = sanitizedMouseIdentifier(rhs).lowercased()
        if left == right { return true }

        // G502 X, G502 X PLUS, and G502 X LIGHTSPEED share the same
        // compatible onboard-memory family even when their display names
        // differ.
        let leftTokens = Set(left.split(separator: "-"))
        let rightTokens = Set(right.split(separator: "-"))
        return leftTokens.contains("g502") && leftTokens.contains("x") &&
            rightTokens.contains("g502") && rightTokens.contains("x")
    }

    func sanitizedMouseIdentifier(_ value: String, fallback: String = "mouse") -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        var result = ""
        var needsSeparator = false
        for scalar in folded.unicodeScalars {
            let asciiAlphaNumeric = (scalar.value >= 48 && scalar.value <= 57) ||
                (scalar.value >= 65 && scalar.value <= 90) ||
                (scalar.value >= 97 && scalar.value <= 122)
            if asciiAlphaNumeric {
                if needsSeparator && !result.isEmpty { result.append("-") }
                result.append(Character(String(scalar)))
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        let bounded = String(trimmed.prefix(32))
        return bounded.isEmpty ? fallback : bounded
    }

    func backupTimestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    func selectedMouseFileIdentifier() -> String {
        let selected = devices.first(where: { $0.id == selectedDeviceIndex })
        return sanitizedMouseIdentifier(selected?.name ?? currentDeviceName)
    }

    func editableJSONExportName() -> String {
        let base = "\(selectedMouseFileIdentifier())-\(backupTimestamp())"
        var candidate = "\(base).json"
        var suffix = 2
        while FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(suffix).json"
            suffix += 1
        }
        return candidate
    }

    func scheduleInitialBackups(for device: DeviceChoice, profileNumbers: [Int]) {
        guard !profileNumbers.isEmpty,
              !hasBinaryBackup(for: device) else { return }
        let key = "\(device.productID.lowercased())|\(device.name.lowercased())"
        guard initialBackupKeys.insert(key).inserted, let executable = engine else { return }

        let directory = backupDirectory
        let mouseIdentifier = sanitizedMouseIdentifier(device.name)
        let backupURLs = profileNumbers.map { _ in
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            let filename = "\(mouseIdentifier)-\(backupTimestamp())-\(suffix).\(AppConstants.backupExtension)"
            return directory.appendingPathComponent(filename)
        }
        let selector = device.deviceKey.isEmpty
            ? ["--device", String(device.id)]
            : ["--device-key", device.deviceKey]

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var saved = 0
                var failed = 0
                for (profileNumber, url) in zip(profileNumbers, backupURLs) {
                    do {
                        _ = try EngineRunner.run(
                            executable: executable,
                            arguments: selector + ["--profile", String(profileNumber), "dump", url.path],
                            currentDirectory: directory
                        )
                        saved += 1
                    } catch {
                        failed += 1
                    }
                }
                return (saved, failed)
            }.value

            guard let self else { return }
            self.initialBackupKeys.remove(key)
            self.refreshBackups()
            guard self.devices.first(where: { $0.id == self.selectedDeviceIndex })?.deviceKey == device.deviceKey else { return }
            if result.0 > 0 {
                let suffix = result.1 == 0 ? "" : " (\(result.1) could not be saved.)"
                self.status = "Created initial backups for \(result.0) onboard profile(s).\(suffix)"
            }
        }
    }

    private func hasBinaryBackup(for device: DeviceChoice) -> Bool {
        guard devices.contains(where: { $0.id == selectedDeviceIndex && $0.deviceKey == device.deviceKey }) else {
            return false
        }
        return discoveredBackups.contains { !$0.isJSON && $0.deviceMatch == .selected }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

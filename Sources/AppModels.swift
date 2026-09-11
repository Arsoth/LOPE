// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct ProfileChoice: Identifiable, Hashable {
    let id: Int
    var sector: String
    var enabled: Bool
    // Header-only discovery intentionally does not read the full profile
    // sector, so CRC status can be unknown until that profile is loaded.
    var crcValid: Bool?

    var title: String {
        "Profile \(id)\(enabled ? "" : " (disabled)")"
    }
}

struct ButtonRow: Identifiable {
    let id: Int
    let label: String
    let currentRaw: String
    var draftRaw: String
    var draftChoice: String
}

struct OutputPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let raw: String
}

struct ModifierChoice: Identifiable, Hashable {
    let id: UInt8
    let label: String
}

struct KeyboardKeyChoice: Identifiable, Hashable {
    let id: UInt8
    let label: String
}

struct BackupEntry: Identifiable {
    let url: URL
    let modifiedAt: Date
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isJSON: Bool { url.pathExtension.lowercased() == "json" }
}

struct DeviceChoice: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let connection: String
    let productID: String
    let deviceKey: String

    var title: String {
        "\(name) — \(connection)"
    }
}

struct EditableBackup: Codable {
    struct Device: Codable {
        var name: String
        var productID: String
    }

    struct ProfileState: Codable {
        var number: Int
        var enabled: Bool
    }

    struct Button: Codable {
        var number: Int
        var physicalControl: String
        var output: String
        var raw: String
    }

    struct DPI: Codable {
        var stages: [Int]
        var defaultStage: Int
        var shiftStage: Int
    }

    struct Profile: Codable {
        var number: Int
        var sector: String?
        var enabled: Bool
        var buttons: [Button]
        var dpi: DPI?
    }

    var formatVersion: Int
    var createdAt: String
    var device: Device
    var profiles: [ProfileState]
    var profile: Profile
    var exactBinaryBackup: String?
}

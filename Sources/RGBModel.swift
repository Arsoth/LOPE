// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// A lossless 8-bit RGB value used at the profile-file boundary. Keeping the
/// representation independent of SwiftUI makes JSON import/export and the
/// parser testable without constructing a view.
struct RGBColor: Codable, Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("0X") {
            value.removeFirst(2)
        } else if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6,
              let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: UInt8((number >> 16) & 0xFF),
            green: UInt8((number >> 8) & 0xFF),
            blue: UInt8(number & 0xFF)
        )
    }

    var hex: String {
        String(format: "0x%02X%02X%02X", red, green, blue)
    }

    var bareHex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

struct RGBZoneState: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    var current: RGBColor
    var draft: RGBColor
}

struct ParsedRGBZone: Hashable, Sendable {
    let index: Int
    let color: RGBColor
}

enum RGBEditorLogic {
    static func settingColor(
        in zones: [RGBZoneState],
        zoneID: Int,
        color: RGBColor,
        allZones: Bool
    ) -> [RGBZoneState] {
        guard zones.contains(where: { $0.id == zoneID }) else { return zones }
        return zones.map { zone in
            guard allZones || zone.id == zoneID else { return zone }
            var updated = zone
            updated.draft = color
            return updated
        }
    }
}

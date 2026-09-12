// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum DeviceClassification {
    static func isMXSeriesMouse(name: String, productID: String) -> Bool {
        let tokens = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tokens.contains("mx") {
            return true
        }

        // MX Master 3S is commonly exposed by macOS as Bluetooth product 0xB034
        // without a useful product name. Keep this narrow so other Logitech
        // Bluetooth model IDs (including the G603's 0xB01C) are not hidden.
        return productID.caseInsensitiveCompare("0xB034") == .orderedSame
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// A data-driven description of a Logitech G mouse's physical controls and
/// onboard-profile transport. The JSON files are deliberately more verbose
/// than the Swift model: fields in `profileIO` are intended to be useful when
/// adding a device whose firmware does not follow the common path.
struct MouseProfileDescriptor: Codable, Hashable, Sendable {
    struct DPIRange: Codable, Hashable, Sendable {
        var minimum: Int
        var maximum: Int

        var capabilities: DPICapabilities {
            DPICapabilities(minimum: minimum, maximum: maximum)
        }
    }

    struct Match: Codable, Hashable, Sendable {
        var nameContains: [String]
        var productIDs: [String]
        var priority: Int
    }

    struct Button: Codable, Hashable, Sendable {
        var number: Int
        var control: String
        var aliases: [String]
        var notes: String?

        var label: String {
            aliases.isEmpty ? control : "\(control) (\(aliases.joined(separator: ", ")))"
        }
    }

    struct ProfileIO: Codable, Hashable, Sendable {
        var supported: Bool
        var capability: String
        var feature: String
        var load: [String: String]
        var save: [String: String]
        var layout: [String: String]
        var notes: [String]

        var canSave: Bool { supported && save["strategy"] != "read-only" }

        init(
            supported: Bool,
            capability: String,
            feature: String,
            load: [String: String],
            save: [String: String],
            layout: [String: String],
            notes: [String]
        ) {
            self.supported = supported
            self.capability = capability
            self.feature = feature
            self.load = load
            self.save = save
            self.layout = layout
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            supported = try values.decodeIfPresent(Bool.self, forKey: .supported) ?? true
            capability = try values.decodeIfPresent(String.self, forKey: .capability) ?? "unknown"
            feature = try values.decodeIfPresent(String.self, forKey: .feature) ?? ""
            load = try values.decodeIfPresent([String: String].self, forKey: .load) ?? [:]
            save = try values.decodeIfPresent([String: String].self, forKey: .save) ?? [:]
            layout = try values.decodeIfPresent([String: String].self, forKey: .layout) ?? [:]
            notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
        }
    }

    var schemaVersion: Int
    var id: String
    var name: String
    var match: Match
    var buttons: [Button]
    // Some onboard profiles expose vertical wheel motion as extra records
    // after the physical button records. Keep these records visible and
    // editable, including when their current output is disabled.
    var scrollWheelButtonLabels: [String: String]?
    // A device may also expose non-programmable controls in its profile
    // record list. Do not present those records as editable buttons.
    var hiddenProfileButtonNumbers: [Int]?
    var dpiRange: DPIRange?
    var refreshGuidance: OnboardProfileRefreshGuidance?
    var profileIO: ProfileIO
    var sources: [String]

    var initialDPICapabilities: DPICapabilities {
        dpiRange?.capabilities ?? DPICapabilities()
    }

    func button(for number: Int) -> Button? {
        buttons.first { $0.number == number }
    }

    func scrollWheelButtonLabel(for number: Int) -> String? {
        scrollWheelButtonLabels?[String(number)]
    }

}

struct MouseProfileCatalog: Sendable {
    static let shared = MouseProfileCatalog()

    let profiles: [MouseProfileDescriptor]

    init() {
        profiles = Self.loadProfiles()
    }

    func matchingProfile(deviceName: String, productID: String) -> MouseProfileDescriptor? {
        let normalizedName = deviceName.lowercased()
        let normalizedProductID = productID.lowercased()

        let candidates = profiles.compactMap { descriptor -> (MouseProfileDescriptor, Int)? in
            let nameHit = descriptor.match.nameContains.contains {
                normalizedName.contains($0.lowercased())
            }
            let productHit = descriptor.match.productIDs.contains {
                normalizedProductID == $0.lowercased()
            }
            guard nameHit || productHit else { return nil }

            // A name match is more reliable than a shared receiver/product
            // ID. Prefer the most specific match, then the descriptor's
            // explicit priority, then the longest matching name token.
            let matchingNameLength = descriptor.match.nameContains
                .filter { normalizedName.contains($0.lowercased()) }
                .map(\.count)
                .max() ?? 0
            let specificity = (nameHit ? 10_000 : 0) +
                descriptor.match.priority * 100 + matchingNameLength
            return (descriptor, specificity)
        }

        return candidates.max { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            return left.0.id > right.0.id
        }?.0
    }

    func profile(deviceName: String, productID: String) -> MouseProfileDescriptor {
        matchingProfile(deviceName: deviceName, productID: productID) ?? Self.genericProfile
    }

    private static func loadProfiles() -> [MouseProfileDescriptor] {
        let fileManager = FileManager.default
        let directories: [URL] = [
            Bundle.main.url(forResource: "MouseProfiles", withExtension: nil),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Profiles", isDirectory: true)
        ].compactMap { $0 }

        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            let descriptors = urls
                .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent != "index.json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { url -> MouseProfileDescriptor? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
                }
            if !descriptors.isEmpty {
                return descriptors
            }
        }

        return [genericProfile]
    }

    static let genericProfile = MouseProfileDescriptor(
        schemaVersion: 1,
        id: "generic",
        name: "Unknown Logitech mouse",
        match: .init(nameContains: [], productIDs: [], priority: 0),
        buttons: [
            .init(number: 1, control: "Primary click", aliases: [], notes: nil),
            .init(number: 2, control: "Secondary click", aliases: [], notes: nil),
            .init(number: 3, control: "Middle click", aliases: [], notes: nil)
        ],
        scrollWheelButtonLabels: nil,
        hiddenProfileButtonNumbers: nil,
        dpiRange: .init(minimum: 100, maximum: 16000),
        refreshGuidance: nil,
        profileIO: .init(
            supported: true,
            capability: "runtime-detected",
            feature: "0x8100",
            load: ["strategy": "runtime-detected"],
            save: ["strategy": "runtime-validated"],
            layout: [:],
            notes: ["The engine must validate the profile layout before writing."]
        ),
        sources: []
    )
}

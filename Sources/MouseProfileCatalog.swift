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

    /// The small, fixed RGB records used by the validated format-4/5 profile
    /// layout. `index` is the zero-based record index in the profile sector;
    /// the user-facing name is supplied by the device descriptor.
    struct RGBProfile: Codable, Hashable, Sendable {
        struct Zone: Codable, Hashable, Sendable {
            var index: Int
            var name: String
        }

        var supported: Bool
        var profileFormats: [Int]
        var baseOffset: Int
        var recordBytes: Int
        var colorOffset: Int
        var zones: [Zone]
        var deviceNameContains: [String]?
        var productIDs: [String]?
        var notes: [String]

        func matches(deviceName: String, productID: String) -> Bool {
            let name = deviceName.lowercased()
            let product = productID.lowercased()
            let nameHit = deviceNameContains?.contains { name.contains($0.lowercased()) } ?? false
            let productHit = productIDs?.contains { product == $0.lowercased() } ?? false
            let hasRestriction = !(deviceNameContains ?? []).isEmpty || !(productIDs ?? []).isEmpty
            return !hasRestriction || nameHit || productHit
        }

        func supports(profileFormat: Int?) -> Bool {
            guard supported else { return false }
            guard let profileFormat else { return true }
            return profileFormats.contains(profileFormat)
        }

        var canEdit: Bool {
            supported && !zones.isEmpty &&
                baseOffset >= 0 && recordBytes >= 4 &&
                (0..<recordBytes).contains(colorOffset) && colorOffset + 3 <= recordBytes
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            supported = try values.decodeIfPresent(Bool.self, forKey: .supported) ?? false
            profileFormats = try values.decodeIfPresent([Int].self, forKey: .profileFormats) ?? []
            baseOffset = try values.decodeIfPresent(Int.self, forKey: .baseOffset) ?? 208
            recordBytes = try values.decodeIfPresent(Int.self, forKey: .recordBytes) ?? 11
            colorOffset = try values.decodeIfPresent(Int.self, forKey: .colorOffset) ?? 1
            zones = try values.decodeIfPresent([Zone].self, forKey: .zones) ?? []
            deviceNameContains = try values.decodeIfPresent([String].self, forKey: .deviceNameContains)
            productIDs = try values.decodeIfPresent([String].self, forKey: .productIDs)
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
    var rgbProfile: RGBProfile?
    var sources: [String]
    // Set on a descriptor LOPE wrote for a device it did not recognize: real
    // button records with placeholder "Button N" names, not a human-confirmed
    // layout. Catalog matching only falls back to one of these when nothing
    // more specific -- built-in or hand-authored -- matches the device.
    var generated: Bool?

    var isGenerated: Bool { generated ?? false }

    var initialDPICapabilities: DPICapabilities {
        dpiRange?.capabilities ?? DPICapabilities()
    }

    func button(for number: Int) -> Button? {
        buttons.first { $0.number == number }
    }

    func scrollWheelButtonLabel(for number: Int) -> String? {
        scrollWheelButtonLabels?[String(number)]
    }

    func rgbCapabilities(deviceName: String, productID: String, profileFormat: Int? = nil) -> RGBProfile? {
        guard let rgbProfile,
              rgbProfile.canEdit,
              rgbProfile.matches(deviceName: deviceName, productID: productID),
              rgbProfile.supports(profileFormat: profileFormat) else { return nil }
        return rgbProfile
    }

}

struct MouseProfileCatalog: Sendable {
    static var shared = MouseProfileCatalog()

    /// Recomputes `shared` after a descriptor is added or changed on disk
    /// (for example, after `AppModel.createGeneratedProfile()` writes a new
    /// file), so the new device is recognized without restarting the app.
    static func reload(customProfilesDirectory: URL? = nil) {
        shared = MouseProfileCatalog(customProfilesDirectory: customProfilesDirectory)
    }

    let profiles: [MouseProfileDescriptor]
    /// The user-accessible folder from which this catalog loads descriptors.
    let customProfilesDirectory: URL
    /// The number of descriptors baked into the app (its bundled resources,
    /// or `Profiles/` in the working directory during development).
    let builtInProfileCount: Int
    /// The number of descriptors the user has dropped into
    /// `customProfilesDirectory`.
    let customProfileCount: Int

    init(customProfilesDirectory: URL? = nil) {
        let customDirectory = customProfilesDirectory ?? Self.defaultCustomProfilesDirectory
        self.customProfilesDirectory = customDirectory
        let builtIn = Self.loadBuiltInProfiles()
        let custom = Self.loadCustomProfiles(in: customDirectory)
        builtInProfileCount = builtIn.count
        customProfileCount = custom.count

        // A custom descriptor whose `id` matches a bundled one replaces it;
        // any other `id` is simply added to the catalog.
        var merged: [String: MouseProfileDescriptor] = [:]
        for descriptor in builtIn { merged[descriptor.id] = descriptor }
        for descriptor in custom { merged[descriptor.id] = descriptor }
        profiles = merged.values.sorted { $0.id < $1.id }
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
            // ID. Among name matches, the longest matching token wins, so a
            // more specific model name (e.g. "G9X") automatically outranks a
            // shorter one it happens to contain (e.g. "G9").
            let matchingNameLength = descriptor.match.nameContains
                .filter { normalizedName.contains($0.lowercased()) }
                .map(\.count)
                .max() ?? 0
            let specificity = (nameHit ? 10_000 : 0) + matchingNameLength
            return (descriptor, specificity)
        }

        // A generated placeholder only stands in for a device when nothing
        // more specific -- built-in or hand-authored -- matches it.
        let confirmed = candidates.filter { !$0.0.isGenerated }
        let pool = confirmed.isEmpty ? candidates : confirmed

        return pool.max { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            return left.0.id > right.0.id
        }?.0
    }

    func profile(deviceName: String, productID: String) -> MouseProfileDescriptor {
        matchingProfile(deviceName: deviceName, productID: productID) ?? Self.genericProfile
    }

    /// The default user-accessible folder for adding or overriding mouse
    /// descriptors. The app-specific configuration root is supplied by
    /// `AppModel` when the user chooses a different location.
    static var defaultCustomProfilesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConstants.appSupportDirectory, isDirectory: true)
            .appendingPathComponent("Custom Profiles", isDirectory: true)
    }

    private static func loadBuiltInProfiles() -> [MouseProfileDescriptor] {
        let fileManager = FileManager.default
        let directories: [URL] = [
            Bundle.main.url(forResource: "MouseProfiles", withExtension: nil),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Profiles", isDirectory: true)
        ].compactMap { $0 }

        for directory in directories {
            let descriptors = Self.descriptors(in: directory, fileManager: fileManager)
            if !descriptors.isEmpty {
                return descriptors
            }
        }

        return [genericProfile]
    }

    private static func loadCustomProfiles(in directory: URL) -> [MouseProfileDescriptor] {
        seedCustomProfilesDirectoryIfNeeded(directory)
        return descriptors(in: directory, fileManager: .default)
    }

    private static func descriptors(in directory: URL, fileManager: FileManager) -> [MouseProfileDescriptor] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            // A leading underscore marks the seeded example so it documents
            // the format without appearing as a selectable device profile.
            .filter {
                $0.pathExtension.lowercased() == "json" &&
                    $0.lastPathComponent != "index.json" &&
                    !$0.lastPathComponent.hasPrefix("_")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> MouseProfileDescriptor? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
            }
    }

    private static func seedCustomProfilesDirectoryIfNeeded(_ directory: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? exampleProfileJSON.write(
            to: directory.appendingPathComponent("_example-mouse.json"),
            atomically: true,
            encoding: .utf8
        )
        try? exampleReadme.write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static let exampleProfileJSON = """
    {
    \t"schemaVersion": 1,
    \t"id": "example-mouse",
    \t"name": "Example Mouse (rename this file to use it)",
    \t"match": {
    \t\t"nameContains": ["Example Mouse"],
    \t\t"productIDs": ["0x0000"]
    \t},
    \t"buttons": [
    \t\t{ "number": 1, "control": "Primary click", "aliases": ["Left"], "notes": null },
    \t\t{ "number": 2, "control": "Secondary click", "aliases": ["Right"], "notes": null },
    \t\t{ "number": 3, "control": "Middle click", "aliases": ["Wheel click"], "notes": null }
    \t],
    \t"dpiRange": { "minimum": 100, "maximum": 16000 },
    \t"profileIO": {
    \t\t"supported": true,
    \t\t"capability": "HID++ 2.0 ONBOARD_PROFILES",
    \t\t"feature": "0x8100",
    \t\t"load": { "command": "profiles", "engineArguments": "--summary-only --with-dpi --profile <number>" },
    \t\t"save": { "strategy": "standard-hidpp20-sector-write" },
    \t\t"layout": {},
    \t\t"notes": ["Copy an existing file from Profiles/ in the app's source for a real starting point."]
    \t},
    \t"sources": []
    }
    """

    private static let exampleReadme = """
    # Custom mouse profiles

    Drop JSON descriptors here to add a mouse the built-in catalog does not \
    know about, or to override a bundled one. A file's `id` decides this: if \
    it matches a bundled descriptor's `id`, this file replaces it; any other \
    `id` is added alongside the built-in profiles. You do not need to \
    register the file anywhere else.

    `_example-mouse.json` shows the expected format. Its leading underscore \
    keeps it from being loaded as a real, selectable profile; copy it to a \
    new file without the underscore, fill in `match`, `buttons`, and the \
    rest, and it will be picked up the next time LOPE starts.

    See `Profiles/README.md` in the LOPE source for the full field reference.
    """

    static let genericProfile = MouseProfileDescriptor(
        schemaVersion: 1,
        id: "generic",
        name: "Unknown Logitech mouse",
        match: .init(nameContains: [], productIDs: []),
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
        rgbProfile: nil,
        sources: []
    )
}

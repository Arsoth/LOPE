// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@main
struct ProfileOutputParserSelfTest {
    static func main() {
        guard AppearancePreference.allCases == [.system, .light, .dark],
              AppearancePreference.light.label == "Light" else {
            fatalError("appearance preference options failed")
        }

        let cases: [(String, Int?)] = [
            ("Onboard profiles for G502 X:\nProfile capacity: 5\nProfile 1 (sector 0x0100, enabled=yes)", 5),
            ("Profile 1 (sector 0x0100, enabled=yes)", nil),
            ("Profile capacity: nope\nProfile capacity: 0\nProfile capacity: 5 trailing", nil),
            ("Profile capacity: 2\r\nProfile 1 (sector 0x0100, enabled=yes)", 2)
        ]

        for (index, testCase) in cases.enumerated() {
            let actual = ProfileOutputParser.onboardProfileCapacity(in: testCase.0)
            guard actual == testCase.1 else {
                fatalError("profile capacity parser case \(index + 1) returned \(String(describing: actual)); expected \(String(describing: testCase.1))")
            }
        }

        guard ProfileOutputParser.scrollWheelOutputLabel("90 10 00 00") == "Scroll down",
              ProfileOutputParser.scrollWheelOutputLabel("90110000") == "Scroll up",
              ProfileOutputParser.isScrollWheelOutput("90 10 00 00"),
              !ProfileOutputParser.isScrollWheelOutput("90010000"),
              !ProfileOutputParser.isScrollWheelOutput("FFFFFFFF") else {
            fatalError("scroll-wheel output recognition failed")
        }

        let wired = DeviceChoice(id: 1, name: "G Pro", connection: "Wired", productID: "0xC085", deviceKey: "wired")
        let receiver = DeviceChoice(id: 2, name: "G604", connection: "LIGHTSPEED", productID: "0x4085", deviceKey: "receiver")
        let bluetooth = DeviceChoice(id: 3, name: "MX Master 3S", connection: "Bluetooth", productID: "0xB034", deviceKey: "bluetooth")
        let withoutAccess = DeviceChoice.addingWiredAccessPrompt(to: [wired, receiver], accessAuthorized: false)
        let withAccess = DeviceChoice.addingWiredAccessPrompt(to: [wired, receiver], accessAuthorized: true)
        guard withoutAccess.last?.isWiredAccessPrompt == true,
              withAccess.count == 2,
              DeviceClassification.isMXSeriesMouse(name: bluetooth.name, productID: bluetooth.productID),
              DeviceClassification.isMXSeriesMouse(name: "MX Anywhere 3", productID: ""),
              !DeviceClassification.isMXSeriesMouse(name: "G603", productID: "0xB01C") else {
            fatalError("wired access prompt or MX classification failed")
        }

        let g604Profile = MouseProfileCatalog.shared.profile(deviceName: "G604", productID: "0x4085")
        guard g604Profile.hiddenProfileButtonNumbers?.contains(16) == true,
              g604Profile.scrollWheelButtonLabel(for: 14) == "Scroll down",
              g604Profile.scrollWheelButtonLabel(for: 15) == "Scroll up",
              g604Profile.refreshGuidance?.sleepDescription.contains("several minutes") == true,
              !MouseProfileCatalog.shared.profiles.isEmpty else {
            fatalError("G604 hidden/non-programmable control metadata failed")
        }

        let g603Profile = MouseProfileCatalog.shared.profile(deviceName: "G603", productID: "0xB01C")
        guard g603Profile.refreshGuidance?.sleepDescription.contains("3 seconds") == true,
              OnboardProfileRefreshPolicy.pollIntervalNanoseconds == 1_000_000_000,
              OnboardProfileRefreshPolicy.maximumPollAttempts == 60 else {
            fatalError("known-device refresh guidance or retry policy failed")
        }

        let g203Profile = MouseProfileCatalog.shared.profile(deviceName: "", productID: "0xC092")
        guard g203Profile.id == "g102-g203", g203Profile.profileIO.canSave else {
            fatalError("G203 LIGHTSYNC product-ID catalog match failed")
        }

        let g600Profile = MouseProfileCatalog.shared.profile(deviceName: "G600 MMO", productID: "0xC24A")
        guard g600Profile.id == "g600",
              !g600Profile.profileIO.supported,
              !g600Profile.profileIO.canSave,
              g600Profile.profileIO.save["strategy"] == "read-only" else {
            fatalError("G600 must remain read-only until all legacy profile features are supported")
        }

        let selectionCases: [(Int?, [Int], Int, Int?)] = [
            (nil, [1], 2, 1),       // multi-profile mouse -> one-profile mouse
            (nil, [1, 2], 1, 1),    // one-profile mouse -> multi-profile mouse
            (2, [1, 2], 1, 2),
            (2, [1], 2, 1)          // stale selected slot is not retained
        ]
        for (index, testCase) in selectionCases.enumerated() {
            let actual = ProfileSelection.resolvedProfileNumber(
                selectedProfileNumber: testCase.0,
                availableProfileIDs: testCase.1,
                preferredProfileNumber: testCase.2
            )
            guard actual == testCase.3 else {
                fatalError("profile selection case \(index + 1) returned \(String(describing: actual)); expected \(String(describing: testCase.3))")
            }
        }

        let rangeCapabilities = DPIOutputParser.parse(
            "DPI sensors: 1\r\nSupported DPI: 400..25600 (step 50)\r\nCurrent sensor 1 DPI: 1600\r\n"
        )
        guard rangeCapabilities.minimum == 400,
              rangeCapabilities.maximum == 25600,
              rangeCapabilities.step == 50,
              rangeCapabilities.sensorCount == 1,
              rangeCapabilities.currentValue == 1600,
              rangeCapabilities.accepts(1600),
              !rangeCapabilities.accepts(1625),
              rangeCapabilities.snappedValue(for: 1573) == 1550 else {
            fatalError("DPI range parsing or snapping failed")
        }

        let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
        guard listCapabilities.supportedValues == [800, 1600, 3200],
              !listCapabilities.accepts(1200),
              listCapabilities.snappedValue(for: 1300) == 1600,
              listCapabilities.snappedValue(for: 1800, lowerBound: 1601) == 3200,
              listCapabilities.snappedValue(for: 1800, upperBound: 1599) == 800 else {
            fatalError("DPI discrete-list parsing or neighbor constraints failed")
        }

        let validStages = ["800", "1600", "3200", "", ""]
        let validMessage = DPIEditorValidation.message(
            stages: validStages,
            count: 3,
            defaultStage: 2,
            shiftStage: 1,
            capabilities: listCapabilities
        )
        guard validMessage == nil else { fatalError("valid DPI stages were rejected") }
        let invalidCases: [([String], Int, String)] = [
            (["800", "", "", "", ""], 2, "Enter a numeric value for DPI stage 2."),
            (["800", "800", "", "", ""], 2, "DPI stages may not overlap."),
            (["800", "1200", "", "", ""], 2, "DPI stage 2 is not supported by this mouse.")
        ]
        for (stages, count, expected) in invalidCases {
            let message = DPIEditorValidation.message(
                stages: stages,
                count: count,
                defaultStage: 1,
                shiftStage: 1,
                capabilities: listCapabilities
            )
            guard message == expected else {
                fatalError("DPI validation returned \(String(describing: message)); expected \(expected)")
            }
        }

        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("lope-backup-storage-\(UUID().uuidString)", isDirectory: true)
        do {
            let g502Directory = BackupStorage.modelDirectory(root: testRoot, mouseIdentifier: "G502 X/PLUS")
            let legacyDirectory = testRoot.appendingPathComponent("legacy", isDirectory: true)
            let hiddenDirectory = testRoot.appendingPathComponent(".hidden", isDirectory: true)
            try fileManager.createDirectory(at: g502Directory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)

            let first = BackupStorage.uniqueBackupURL(
                root: testRoot,
                mouseIdentifier: "G502 X/PLUS",
                prefix: "profile-1-save",
                fileExtension: "logiob",
                timestamp: "20260912-120000"
            )
            guard first.path == testRoot
                    .appendingPathComponent("G502-X-PLUS", isDirectory: true)
                    .appendingPathComponent("G502-X-PLUS-profile-1-save-20260912-120000.logiob")
                    .path,
                  BackupStorage.mouseIdentifier(fromBackupFilename: first.lastPathComponent) == "G502-X-PLUS" else {
                fatalError("model backup directory or filename sanity check failed")
            }

            try Data([0x01]).write(to: first)
            let second = BackupStorage.uniqueBackupURL(
                root: testRoot,
                mouseIdentifier: "G502 X/PLUS",
                prefix: "profile-1-save",
                fileExtension: "logiob",
                timestamp: "20260912-120000"
            )
            guard second.lastPathComponent == "G502-X-PLUS-profile-1-save-20260912-120000-2.logiob" else {
                fatalError("model backup filename collision handling failed")
            }

            let legacy = legacyDirectory.appendingPathComponent("legacy.bin")
            let json = g502Directory.appendingPathComponent("G502-X-PLUS-profile-1-export.json")
            let hidden = hiddenDirectory.appendingPathComponent("hidden.logiob")
            try Data([0x02]).write(to: legacy)
            try Data([0x03]).write(to: json)
            try Data([0x04]).write(to: hidden)
            let discovered = Set(BackupStorage.backupURLs(in: testRoot).map { $0.standardizedFileURL })
            let expectedBackups = Set([first, legacy, json].map { $0.standardizedFileURL })
            guard discovered == expectedBackups,
                  BackupStorage.mouseIdentifier(fromBackupFilename: "profile-1-save-20260912-120000.logiob") == nil,
                  BackupStorage.restoreArguments(for: first) == ["restore", first.path, "--yes"] else {
                fatalError("nested backup discovery or restore path handling failed")
            }

            let expectedDocuments = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            guard BackupStorage.documentsDirectory(fileManager: fileManager) == expectedDocuments else {
                fatalError("JSON panel Documents default failed")
            }
        } catch {
            fatalError("backup storage regression setup failed: \(error)")
        }
        try? fileManager.removeItem(at: testRoot)

        guard let red = RGBColor(hex: "#ff002a"),
              red == RGBColor(red: 255, green: 0, blue: 42),
              red.hex == "0xFF002A",
              RGBColor(hex: "0x123456") == RGBColor(red: 0x12, green: 0x34, blue: 0x56),
              RGBColor(hex: "12345") == nil,
              RGBColor(hex: "0xGG0000") == nil else {
            fatalError("RGB hex conversion or validation failed")
        }

        let parsedRGBLine = ProfileOutputParser.rgbZone(
            from: "  RGB zone 2: A1B2C3 (mode 0x01)"
        )
        guard parsedRGBLine?.index == 1,
              parsedRGBLine?.color == RGBColor(red: 0xA1, green: 0xB2, blue: 0xC3),
              ProfileOutputParser.profileFormat(from: "  format: 0x05, macro format: 0x01") == 5,
              ProfileOutputParser.rgbZone(from: "RGB zone 0: AABBCC (mode 0x01)") == nil else {
            fatalError("RGB profile-output parsing failed")
        }

        let rgbZones = [
            RGBZoneState(id: 0, name: "Primary", current: RGBColor(red: 1, green: 2, blue: 3), draft: RGBColor(red: 1, green: 2, blue: 3)),
            RGBZoneState(id: 1, name: "Logo", current: RGBColor(red: 4, green: 5, blue: 6), draft: RGBColor(red: 4, green: 5, blue: 6))
        ]
        let blue = RGBColor(red: 0, green: 64, blue: 255)
        let oneZone = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 1, color: blue, allZones: false)
        guard oneZone[0].draft == rgbZones[0].draft, oneZone[1].draft == blue else {
            fatalError("per-zone RGB editing changed the wrong zone")
        }
        let allZones = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 0, color: blue, allZones: true)
        guard allZones.allSatisfy({ $0.draft == blue }),
              RGBEditorLogic.settingColor(in: rgbZones, zoneID: 9, color: blue, allZones: true) == rgbZones else {
            fatalError("Shift-click all-zone RGB editing failed")
        }

        let g502 = MouseProfileCatalog.shared.profile(deviceName: "G502 HERO", productID: "0xC08B")
        guard let g502RGB = g502.rgbCapabilities(deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 5),
              g502RGB.zones.map(\.name) == ["Primary", "Logo"],
              g502.rgbCapabilities(deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 7) == nil else {
            fatalError("G502 RGB capability gating failed")
        }
        let unsupported = MouseProfileCatalog.shared.profile(deviceName: "G603 LIGHTSPEED", productID: "0xB01C")
        guard unsupported.rgbCapabilities(deviceName: "G603 LIGHTSPEED", productID: "0xB01C", profileFormat: 5) == nil else {
            fatalError("unsupported device incorrectly advertised RGB")
        }

        print("profile metadata self-test: capacity, selection, DPI, backup-storage, and RGB cases passed")
    }
}

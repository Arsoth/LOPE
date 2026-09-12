// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@main
struct ProfileOutputParserSelfTest {
    static func main() {
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

        let g604Profile = MouseProfileCatalog.shared.profile(deviceName: "G604", productID: "0x4085")
        guard g604Profile.hiddenProfileButtonNumbers?.contains(16) == true,
              g604Profile.scrollWheelButtonLabel(for: 14) == "Scroll down",
              g604Profile.scrollWheelButtonLabel(for: 15) == "Scroll up" else {
            fatalError("G604 hidden/non-programmable control metadata failed")
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
            (["800", "800", "", "", ""], 2, "DPI stages must be strictly increasing."),
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

        print("profile metadata self-test: capacity, selection, and DPI cases passed")
    }
}

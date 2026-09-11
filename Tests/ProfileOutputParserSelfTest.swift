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

        print("profile metadata self-test: capacity and selection cases passed")
    }
}

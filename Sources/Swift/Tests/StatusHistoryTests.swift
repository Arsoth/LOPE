// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class StatusHistoryTests: XCTestCase {
  func testStartsWithConnectionGuidance() {
    let history = StatusHistory()

    XCTAssertEqual(history.events.map(\.message), [StatusHistory.initialMessage])
  }

  func testRecordsNewestEventFirstWithTimestamp() {
    let original = StatusEvent(message: "Original", timestamp: Date(timeIntervalSince1970: 1))
    let recordedAt = Date(timeIntervalSince1970: 2)
    var history = StatusHistory(events: [original])

    history.record("Newest", timestamp: recordedAt)

    XCTAssertEqual(history.events.map(\.message), ["Newest", "Original"])
    XCTAssertEqual(history.events.first?.timestamp, recordedAt)
  }

  func testKeepsOnlyTenMostRecentEvents() {
    var history = StatusHistory(events: [])

    for index in 0..<12 {
      history.record("Event \(index)")
    }

    XCTAssertEqual(history.events.count, StatusHistory.maximumEventCount)
    XCTAssertEqual(history.events.first?.message, "Event 11")
    XCTAssertEqual(history.events.last?.message, "Event 2")
  }

  func testInitializationCapsPreexistingEvents() {
    let events = (0..<12).map { StatusEvent(message: "Event \($0)") }

    let history = StatusHistory(events: events)

    XCTAssertEqual(history.events.map(\.message), (0..<10).map { "Event \($0)" })
  }
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct StatusEvent: Identifiable, Equatable {
  let id: UUID
  let message: String
  let timestamp: Date

  init(id: UUID = UUID(), message: String, timestamp: Date = Date()) {
    self.id = id
    self.message = message
    self.timestamp = timestamp
  }
}

struct StatusHistory {
  static let initialMessage = "Connect a Logitech mouse, then choose Refresh."
  static let maximumEventCount = 10

  private(set) var events: [StatusEvent]

  init(events: [StatusEvent] = [StatusEvent(message: initialMessage)]) {
    self.events = Array(events.prefix(Self.maximumEventCount))
  }

  mutating func record(_ message: String, timestamp: Date = Date()) {
    events.insert(StatusEvent(message: message, timestamp: timestamp), at: 0)
    if events.count > Self.maximumEventCount {
      events.removeLast(events.count - Self.maximumEventCount)
    }
  }
}

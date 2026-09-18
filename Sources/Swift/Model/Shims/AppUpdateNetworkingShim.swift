// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

// URLSession is the live network boundary. Keeping it in this tiny shim lets
// AppUpdateClient remain fully deterministic under XCTest.
enum AppUpdateNetworking {
  static let requestData: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
    request in
    try await URLSession.shared.data(for: request)
  }
}

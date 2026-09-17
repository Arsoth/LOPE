// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

@main
struct LOPEApp {
  private static let appDelegate = LOPEAppDelegate()

  static func main() {
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.run()
  }
}

private final class LOPEAppDelegate: NSObject, NSApplicationDelegate {
  private var mainWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let hostingController = NSHostingController(rootView: ContentView())
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = AppConstants.displayName
    window.isReleasedWhenClosed = false
    window.center()
    mainWindow = window

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

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
    configureMainMenu()

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
    addCenteredTitlebarTitle(to: window)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let applicationMenuItem = NSMenuItem()
    let applicationMenu = NSMenu(title: AppConstants.displayName)

    mainMenu.addItem(applicationMenuItem)
    applicationMenuItem.submenu = applicationMenu

    applicationMenu.addItem(
      withTitle: "About \(AppConstants.displayName)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    applicationMenu.addItem(NSMenuItem.separator())

    let hideItem = applicationMenu.addItem(
      withTitle: "Hide \(AppConstants.displayName)",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    hideItem.keyEquivalentModifierMask = [.command]

    let quitItem = applicationMenu.addItem(
      withTitle: "Quit \(AppConstants.displayName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.keyEquivalentModifierMask = [.command]

    NSApp.mainMenu = mainMenu
  }

  private func addCenteredTitlebarTitle(to window: NSWindow) {
    guard let closeButton = window.standardWindowButton(.closeButton) else { return }
    let title = window.title
    window.title = ""

    var titlebarView = closeButton.superview
    while let currentView = titlebarView,
      let superview = currentView.superview
    {
      titlebarView = superview
      if superview.bounds.width >= window.frame.width - 1 {
        break
      }
    }

    guard let titlebarView else { return }

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.alignment = .center
    titleLabel.setAccessibilityLabel(title)
    titleLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    titlebarView.addSubview(titleLabel, positioned: .above, relativeTo: nil)

    let titleSize = NSSize(width: 160, height: 22)
    titleLabel.frame = NSRect(
      x: (titlebarView.bounds.width - titleSize.width) / 2,
      y: (titlebarView.bounds.height - titleSize.height) / 2,
      width: titleSize.width,
      height: titleSize.height
    )
  }
}

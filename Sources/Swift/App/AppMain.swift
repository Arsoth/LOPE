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
  private var aboutWindow: NSWindow?

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

    let aboutItem = applicationMenu.addItem(
      withTitle: "About \(AppConstants.displayName)",
      action: #selector(showAboutPanel(_:)),
      keyEquivalent: ""
    )
    aboutItem.target = self
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

  @objc private func showAboutPanel(_ sender: Any?) {
    if let aboutWindow {
      aboutWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "About \(AppConstants.displayName)"
    window.isReleasedWhenClosed = false

    let contentView = NSView()
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    let nameLabel = NSTextField(labelWithString: AppConstants.displayName)
    nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)

    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Unknown"
    let versionLabel = NSTextField(labelWithString: "Version \(version)")

    let copyrightStack = NSStackView()
    copyrightStack.alignment = .centerY
    copyrightStack.spacing = 4

    let copyright =
      Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright")
      as? String ?? "Copyright © 2026"
    let copyrightLabel = NSTextField(labelWithString: copyright)
    let companyLink = NSButton(
      title: "Cotyledon Labs",
      target: self,
      action: #selector(openCompanyWebsite(_:))
    )
    companyLink.isBordered = false
    companyLink.attributedTitle = NSAttributedString(
      string: "Cotyledon Labs",
      attributes: [
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    )
    companyLink.toolTip = "https://cotyledonlabs.com"
    companyLink.setAccessibilityLabel("Cotyledon Labs")

    copyrightStack.addArrangedSubview(copyrightLabel)
    copyrightStack.addArrangedSubview(companyLink)
    stackView.addArrangedSubview(nameLabel)
    stackView.addArrangedSubview(versionLabel)
    stackView.addArrangedSubview(copyrightStack)
    contentView.addSubview(stackView)
    window.contentView = contentView

    NSLayoutConstraint.activate([
      stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      stackView.leadingAnchor.constraint(
        greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
      stackView.trailingAnchor.constraint(
        lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
    ])

    aboutWindow = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openCompanyWebsite(_ sender: Any?) {
    guard let url = URL(string: "https://cotyledonlabs.com") else { return }
    NSWorkspace.shared.open(url)
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

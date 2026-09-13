// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import PackageDescription

// This manifest exists only to run the Swift unit tests through
// `swift test`. The shipped app is still built by the Makefile via direct
// `swiftc` invocations (see `make gui` / `make app` / `./rebuild-signed.sh`);
// nothing here changes that path.
let package = Package(
  name: "LOPE",
  platforms: [.macOS(.v13)],
  targets: [
    .target(
      name: "LOPECore",
      path: "Sources",
      exclude: [
        "AppMain.swift",
        "ContentView.swift",
        "ContentViewControls.swift",
        "ContentViewSections.swift",
        "ProfileEditorPane.swift",
        "logitech_onboard.m",
        "logitech_onboard_backup.inc",
        "logitech_onboard_commands_backup_bind.inc",
        "logitech_onboard_commands_mutate.inc",
        "logitech_onboard_commands_read.inc",
        "logitech_onboard_g600.inc",
        "logitech_onboard_hid_discovery.inc",
        "logitech_onboard_hid_transport.inc",
        "logitech_onboard_profile_io.inc",
        "logitech_onboard_profile_rendering.inc",
        "logitech_onboard_report_rate.inc",
        "logitech_onboard_selftest.inc",
        "logitech_onboard_types.inc",
        "logitech_onboard_watch_cli.inc",
      ]
    ),
    .testTarget(
      name: "LOPECoreTests",
      dependencies: ["LOPECore"],
      path: "Tests"
    ),
  ]
)

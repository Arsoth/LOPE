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
      path: "Sources/Swift",
      exclude: [
        "App",
        "UI",
        "Tests",
      ]
    ),
    .testTarget(
      name: "LOPECoreTests",
      dependencies: ["LOPECore"],
      path: "Sources/Swift/Tests"
    ),
  ]
)

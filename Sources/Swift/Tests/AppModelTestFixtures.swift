// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@testable import LOPECore

// Shared fixture for AppModel-level tests spread across AppModelTests,
// AppModelEditingTests, AppModelWritesTests, and AppModelParsingTests:
// configures a G502 X with profile 2 selected and a single primary-click
// button, matching the device/profile combination those tests validate
// against.
@MainActor
func configureFixtureDevice(_ model: AppModel) {
  model.devices = [
    DeviceChoice(
      id: 1,
      name: "G502 X",
      connection: "Wired",
      productID: "0x0000",
      deviceKey: "test-device"
    )
  ]
  model.selectedDeviceIndex = 1
  model.currentDeviceName = "G502 X / X LIGHTSPEED / X PLUS"
  model.profileNumber = 2
  model.profiles = [
    ProfileChoice(
      id: 2,
      sector: "0x0100",
      enabled: true,
      crcValid: true
    )
  ]
  model.baselineProfileEnabled = [2: true]
  model.buttons = [
    ButtonRow(
      id: 1,
      label: "G1 · Primary click (Left)",
      currentRaw: "80010002",
      draftRaw: "80010002",
      draftChoice: "80010002",
      layer: .normal
    )
  ]
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelRefreshTests: XCTestCase {
  func testSleepingDeviceTransitionKeepsUnderlyingProfileSurface() {
    let sleepingModel = AppModel(startInitialRefresh: false)
    sleepingModel.devices = [
      DeviceChoice(
        id: 1,
        name: "G603",
        connection: "Wireless",
        productID: "0xB01C",
        deviceKey: "sleeping-device"
      )
    ]
    sleepingModel.selectedDeviceIndex = 1
    sleepingModel.currentDeviceName = "G603"
    sleepingModel.buttons = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click",
        currentRaw: "80010001",
        draftRaw: "80010001",
        draftChoice: "80010001",
        layer: .normal
      )
    ]
    sleepingModel.profiles = [
      ProfileChoice(
        id: 1,
        sector: "0x0100",
        enabled: true,
        crcValid: nil
      )
    ]
    sleepingModel.applyRefreshSnapshot(
      RefreshSnapshot(
        devices: sleepingModel.devices,
        selectedDeviceIndex: 1,
        profileText: nil,
        profileError: "sleeping",
        dpiText: nil,
        dpiError: nil,
        selectedProfileNumber: nil,
        errorMessage: nil,
        accessWarning: false
      ))
    XCTAssertTrue(sleepingModel.waitingForKnownDevice)
    XCTAssertFalse(sleepingModel.buttons.isEmpty)
    XCTAssertFalse(sleepingModel.profiles.isEmpty)
    sleepingModel.knownDevicePollTask?.cancel()
  }
}

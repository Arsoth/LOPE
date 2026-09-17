// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelParsingTests: XCTestCase {
  func testNormalAndGShiftProfileOutputLayersParseSeparately() {
    let layeredModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(layeredModel)
    let layeredText = """
      Profile 2 (sector 0x0100, enabled=yes)
        button 1: Left click [80010001]
        G-Shift button 1: Right click [80010002]
      """
    let parsedLayers = layeredModel.parseProfiles(layeredText)
    XCTAssertEqual(parsedLayers.rowsByProfile[2]?.first?.layer, .normal)
    XCTAssertEqual(parsedLayers.gShiftRowsByProfile[2]?.first?.layer, .gShift)
  }

  func testPresetLabelResolvesKnownAndUnknownRawOutputs() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertEqual(model.presetLabel(for: "80010001"), "Left click")
    XCTAssertEqual(model.presetLabel(for: "80 01 00 01"), "Left click")
    XCTAssertEqual(model.presetLabel(for: "DEADBEEF"), "Custom raw output")
  }

  func testLoadDPICatchesEngineFailureAndRecordsErrorMessage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in
      throw EngineError.failed("Sensor read timed out.")
    }
    model.loadDPI()
    XCTAssertEqual(model.dpiCapabilities.errorMessage, "Sensor read timed out.")
    XCTAssertEqual(model.dpiDetails, "Sensor read timed out.")
  }

  func testLoadDPIReportsMissingStructuredCapabilities() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in
      #"{"contract_version":1,"ok":true,"kind":"dpi","dpi":null}"#
    }

    model.loadDPI()

    XCTAssertEqual(
      model.dpiDetails, "The HID++ engine returned no DPI capabilities.")
    XCTAssertEqual(
      model.dpiCapabilities.errorMessage,
      "The HID++ engine returned no DPI capabilities.")
  }

  func testRunEngineJSONDecodesAnOverriddenStructuredResponse() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in fakeStructuredDPIOutput() }

    let result = try model.runEngineJSON(["dpi"], expectedKind: "dpi")

    XCTAssertEqual(result.response.kind, "dpi")
    XCTAssertEqual(result.response.dpi?.currentSensorDPI, 800)
  }

  func testRunEngineJSONWithoutOverrideUsesDeviceKeySelector() throws {
    let output = fakeStructuredDPIOutput()
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' '\(output)'
        """
    ) { model in
      let result = try model.runEngineJSON(["dpi"], expectedKind: "dpi")

      XCTAssertEqual(result.response.kind, "dpi")
      XCTAssertEqual(result.response.dpi?.currentSensorDPI, 800)
    }
  }

  func testRunEngineJSONWithoutDeviceKeyUsesNumericSelector() throws {
    let output = fakeStructuredDPIOutput()
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' '\(output)'
        """
    ) { model in
      model.devices = [
        DeviceChoice(
          id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "")
      ]
      let result = try model.runEngineJSON(["dpi"], expectedKind: "dpi")

      XCTAssertEqual(result.response.kind, "dpi")
    }
  }

  func testRunEngineJSONWithoutSelectedDeviceOmitsSelector() throws {
    let output = fakeStructuredDPIOutput()
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' '\(output)'
        """
    ) { model in
      model.selectedDeviceIndex = 999
      let result = try model.runEngineJSON(["dpi"], expectedKind: "dpi")

      XCTAssertEqual(result.response.kind, "dpi")
    }
  }

  func testRunEngineJSONReportsStructuredProcessFailure() throws {
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' '{"contract_version":1,"ok":false,"kind":"dpi","error":{"code":"read","message":"sensor unavailable"}}'
        exit 1
        """
    ) { model in
      XCTAssertThrowsError(try model.runEngineJSON(["dpi"], expectedKind: "dpi")) { error in
        XCTAssertTrue(error.localizedDescription.contains("sensor unavailable"))
      }
    }
  }

  func testRunEngineJSONReportsMalformedProcessFailureAndMalformedSuccess() throws {
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' 'malformed output'
        exit 7
        """
    ) { model in
      XCTAssertThrowsError(try model.runEngineJSON(["dpi"], expectedKind: "dpi")) { error in
        XCTAssertTrue(error.localizedDescription.contains("malformed output"))
      }
    }

    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '%s\\n' 'malformed output'
        exit 0
        """
    ) { model in
      XCTAssertThrowsError(try model.runEngineJSON(["dpi"], expectedKind: "dpi")) { error in
        XCTAssertTrue(error.localizedDescription.contains("invalid structured output"))
      }
    }
  }

  func testStructuredProfileProjectionBuildsEditorRowsAndRGB() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let response = try EngineJSON.decode(fakeStructuredProfilesOutput()).response

    let parsed = model.parseProfiles(response)

    XCTAssertEqual(parsed.choices.map(\.id), [1, 2])
    XCTAssertEqual(parsed.choices[1].sector, "0x0200")
    XCTAssertEqual(parsed.rowsByProfile[2]?.first?.currentRaw, "80010002")
    XCTAssertEqual(parsed.gShiftRowsByProfile[2]?.first?.layer, .gShift)
    XCTAssertEqual(parsed.rgbByProfile[2]?.first?.color, RGBColor(red: 255, green: 0, blue: 16))
    XCTAssertEqual(parsed.profileFormatsByProfile[2], 1)
  }

  func testStructuredProfileProjectionAddsSelectedProfileWhenHeaderIsMissing() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let output = fakeStructuredProfilesOutput().replacingOccurrences(
      of:
        #""headers":[{"number":1,"sector":256,"enabled":false},{"number":2,"sector":512,"enabled":true}]"#,
      with: #""headers":[] "#.trimmingCharacters(in: .whitespaces)
    )
    let response = try EngineJSON.decode(output).response

    let parsed = model.parseProfiles(response)

    XCTAssertEqual(parsed.choices.map(\.id), [2])
    XCTAssertEqual(parsed.choices.first?.crcValid, true)
  }

  func testStructuredProfileProjectionUsesScrollAndGenericButtonLabels() throws {
    let model = AppModel(startInitialRefresh: false)
    model.devices = [
      DeviceChoice(
        id: 1, name: "G604", connection: "Wireless", productID: "0x4085", deviceKey: "g604-test")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G604"
    let output = fakeStructuredProfilesOutput().replacingOccurrences(
      of:
        #""buttons":[{"number":1,"layer":"normal","raw":[128,1,0,2],"description":"Left click"},{"number":1,"layer":"gShift","raw":[128,2,0,3],"description":"Right click"}],"dpi_stages""#,
      with:
        #""buttons":[{"number":20,"layer":"normal","raw":[144,16,0,0],"description":"Scroll down"},{"number":21,"layer":"normal","raw":[18,52,86,120],"description":"Mystery"}],"dpi_stages""#
    )
    let response = try EngineJSON.decode(output).response

    let parsed = model.parseProfiles(response)

    XCTAssertEqual(parsed.rowsByProfile[2]?.first(where: { $0.id == 20 })?.label, "Scroll down")
    XCTAssertEqual(parsed.rowsByProfile[2]?.first(where: { $0.id == 21 })?.label, "Button 21")
  }

  func testApplyStructuredDPIProjectsStagesAndCapabilities() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let response = try EngineJSON.decode(fakeStructuredProfilesOutput()).response
    let dpi = try XCTUnwrap(response.dpi)

    model.applyStructuredDPI(dpi, profile: response.selectedProfile)

    XCTAssertEqual(model.dpiStages, ["400", "800", "1600", "", ""])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertEqual(model.dpiCapabilities.supportedValues, [400, 800, 1600])
    XCTAssertTrue(model.dpiDetails.contains("DPI sensors: 1"))
  }

  func testApplyStructuredDPIPreservesCatalogRangeWhenResponseHasNoValues() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800], minimum: 400, maximum: 800)
    let dpi = EngineJSONDPI(
      requested: true,
      available: false,
      sensorCount: 0,
      supportedValues: [],
      currentSensorDPI: 0,
      error: "DPI unavailable"
    )

    model.applyStructuredDPI(dpi)

    XCTAssertEqual(model.dpiCapabilities.supportedValues, [400, 800])
    XCTAssertNil(model.dpiCapabilities.currentValue)
    XCTAssertEqual(model.dpiCapabilities.errorMessage, "DPI unavailable")
    XCTAssertTrue(model.dpiDetails.contains("DPI unavailable"))
  }

  func testParsePollingRateUpdatesDraftAndBaseline() {
    let model = AppModel(startInitialRefresh: false)

    model.parsePollingRate(
      "Supported polling rates: 125, 500, 1000 Hz\nCurrent polling rate: 500 Hz")

    XCTAssertEqual(model.pollingRateCapabilities.supportedRates, [125, 500, 1000])
    XCTAssertEqual(model.pollingRateDraft, 500)
    XCTAssertEqual(model.baselinePollingRate, 500)
  }

  func testRunEngineWithoutOverrideAndNoBundledEngineThrowsUnavailable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertNil(model.engineRunnerOverride)
    XCTAssertNil(
      model.engine, "test environment unexpectedly found a bundled/relative lope engine binary")
    XCTAssertThrowsError(try model.runEngine(["--sensor-only", "dpi"])) { error in
      XCTAssertEqual(error.localizedDescription, "The bundled HID++ engine could not be found.")
    }
  }

  /// Points `AppModel.engine` at a throwaway shell script standing in for
  /// the real `lope` binary (by briefly relocating the process's current
  /// directory to a sandbox containing `bin/lope`, one of the two relative
  /// candidates `engine` checks), so the real `Process`-spawning path in
  /// `runEngine(_:selectingDevice:)` can be exercised without touching real
  /// HID hardware. All `AppModel` instances in this suite use
  /// `startInitialRefresh: false`, so nothing else is relying on the
  /// current directory while it is temporarily changed.
  private func withSandboxedEngine(
    scriptBody: String,
    perform: (AppModel) throws -> Void
  ) throws {
    let originalDirectory = FileManager.default.currentDirectoryPath
    defer { _ = FileManager.default.changeCurrentDirectoryPath(originalDirectory) }

    let sandbox = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-engine-spawn-test-" + UUID().uuidString, isDirectory: true)
    let binDirectory = sandbox.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sandbox) }
    let scriptURL = binDirectory.appendingPathComponent(AppConstants.engineName)
    try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(sandbox.path))

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertNotNil(model.engine, "sandboxed bin/\(AppConstants.engineName) was not found")
    try perform(model)
  }

  func testRunEngineWithoutOverrideSpawnsRelativeEngineBinaryAndCapturesOutput() throws {
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        echo "arguments: $@"
        exit 0
        """
    ) { model in
      let output = try model.runEngine(["--sensor-only", "dpi"])
      XCTAssertTrue(output.contains("--device-key test-device"))
      XCTAssertTrue(output.contains("--sensor-only dpi"))
    }
  }

  func testRunEngineWithoutOverrideThrowsWhenSpawnedEngineExitsNonZero() throws {
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        echo "boom: simulated engine failure"
        exit 1
        """
    ) { model in
      XCTAssertThrowsError(try model.runEngine(["profiles"])) { error in
        XCTAssertTrue(error.localizedDescription.contains("boom: simulated engine failure"))
      }
    }
  }

  func testBackupURLDelegatesToUniqueBackupURL() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-backupurl-test-" + UUID().uuidString, isDirectory: true)
    model.configurationDirectory = tempDirectory
    let url = model.backupURL(prefix: "profile-2-test")
    XCTAssertEqual(url.pathExtension, AppConstants.backupExtension)
    XCTAssertTrue(url.lastPathComponent.contains("profile-2-test"))
    XCTAssertEqual(url.deletingLastPathComponent(), model.mouseBackupDirectory())
  }

  func testParseDeviceChoicesParsesConnectionNameProductAndKeyAndSorts() {
    let text = """
      [5] Wireless  G502 X LIGHTSPEED (HID++ 4.5, product 0x407F, key ab12cd34-56ef)
      [2] G100S (HID++ 2.0, product 0xC24E, key 11-22-33)
      not a device line
      """
    let devices = AppModel.parseDeviceChoices(text)
    XCTAssertEqual(devices.map(\.id), [2, 5])
    XCTAssertEqual(devices[1].connection, "Wireless")
    XCTAssertEqual(devices[1].name, "G502 X LIGHTSPEED")
    XCTAssertEqual(devices[1].productID, "0x407F")
    XCTAssertEqual(devices[1].deviceKey, "ab12cd34-56ef")
    XCTAssertEqual(devices[0].connection, "G100S")
    XCTAssertEqual(devices[0].name, "G100S")
  }

  func testParseDeviceChoicesRemovesGenericWirelessGamingMouseSuffix() {
    let text =
      "[1] Wireless  G604 Wireless Gaming Mouse (HID++ 4.5, product 0x4085, key ab604)"

    XCTAssertEqual(AppModel.parseDeviceChoices(text).first?.name, "G604")
  }

  func testParseDeviceChoicesCanonicalizesBaseG502MarketingName() {
    let text =
      "[1] Wired  Tunable RGB Gaming Mouse G502 (HID++ 4.5, product 0xC332, key abc502)"

    let device = AppModel.parseDeviceChoices(text).first
    XCTAssertEqual(device?.name, "G502")
    XCTAssertEqual(device?.title, "G502 Proteus Spectrum — Wired")
  }

  func testReportedDeviceNamePrefersSpecificPairedModelOverGenericLabel() {
    let text = """
      Onboard profiles for Paired Logitech Mouse - Lightspeed:
      Device: G604
      Selected profile: 1
      """

    XCTAssertEqual(AppModel.reportedDeviceName(in: text), "G604")
  }

  func testProfileNumbersExtractsProfileHeaderIDs() {
    let text = """
      Profile 1 (sector 0x0100, enabled=yes)
      Profile 3 (sector 0x0300, enabled=no)
      not a profile line
      """
    XCTAssertEqual(AppModel.profileNumbers(in: text), [1, 3])
  }

  func testSelectedProfileNumberParsesOrReturnsNil() {
    XCTAssertEqual(AppModel.selectedProfileNumber(in: "Selected profile: 4"), 4)
    XCTAssertNil(AppModel.selectedProfileNumber(in: "No selection line here"))
  }

  func testOnboardProfileCapacityDelegatesToProfileOutputParser() {
    XCTAssertEqual(AppModel.onboardProfileCapacity(in: "Profile capacity: 5"), 5)
    XCTAssertNil(AppModel.onboardProfileCapacity(in: "no capacity here"))
  }

  func testParseProfilesUpdatesExistingHeaderCRCFormatAndRGBAndSkipsHiddenButtons() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.devices = [
      DeviceChoice(
        id: 1, name: "G604", connection: "Wireless", productID: "0x4085", deviceKey: "g604-test")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G604"
    let text = """
      Profile 5 (sector 0x0100, enabled=yes)
        CRC: OK
        button 1: Primary click [80010001]
      Profile 5 (sector 0x0200, enabled=no)
        format: 0x4
        RGB zone 1: FF00FF (mode 0x01)
        CRC: INVALID
        button 1: Primary click [80010001]
        button 16: Hidden [FFFFFFFF]
        button 20: Scroll Down Output [90100000]
        button 21: Mystery [12345678]
      """
    let parsed = model.parseProfiles(text)
    XCTAssertEqual(parsed.choices.count, 1)
    guard let profile = parsed.choices.first else {
      XCTFail("expected one parsed profile")
      return
    }
    XCTAssertEqual(profile.sector, "0x0200")
    XCTAssertFalse(profile.enabled)
    XCTAssertEqual(profile.crcValid, false)
    XCTAssertEqual(parsed.profileFormatsByProfile[5], 4)
    XCTAssertEqual(parsed.rgbByProfile[5]?.first?.index, 0)
    XCTAssertEqual(parsed.rgbByProfile[5]?.first?.color, RGBColor(hex: "FF00FF"))
    let normalRows = parsed.rowsByProfile[5] ?? []
    XCTAssertFalse(
      normalRows.contains(where: { $0.id == 16 }), "hidden button 16 should be excluded")
    XCTAssertEqual(normalRows.first(where: { $0.id == 20 })?.label, "Scroll down")
    XCTAssertEqual(normalRows.first(where: { $0.id == 21 })?.label, "Button 21")
  }

  func testParseDPIPreservesCatalogRangeWhenProfileReadLacksCapabilities() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800], minimum: 400, maximum: 800)
    model.parseDPI("No DPI information present in this profile dump.")
    XCTAssertEqual(model.dpiCapabilities.supportedValues, [400, 800])
    XCTAssertNil(model.dpiCapabilities.errorMessage)
  }

  func testParseDPIParsesOnboardStagesLine() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.parseDPI("Onboard profile 2 DPI stages: 400, 800, 1200 (default 2, shift 1)")
    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertEqual(model.baselineDPICount, 3)
    XCTAssertEqual(model.baselineDPIStages, ["400", "800", "1200", "", ""])
  }

  func testParseDPIKeepsPreviousStageIndexesWhenReportedIndexOverflowsInt() {
    // The regex constrains default/shift to `\d+`, so `Int(...)` can only
    // fail on overflow (not on malformed non-digit text) -- exercised here
    // with an absurdly long digit run standing in for garbled firmware
    // output.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.defaultStage = 2
    model.shiftStage = 1
    model.parseDPI(
      "Onboard profile 2 DPI stages: 400, 800, 1200 (default 99999999999999999999, shift 99999999999999999999)"
    )
    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testLoadDPIDecodesTheStructuredResponse() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in fakeStructuredDPIOutput() }
    model.loadDPI()
    XCTAssertEqual(model.dpiCapabilities.currentValue, 800)
    XCTAssertEqual(model.dpiCapabilities.supportedValues, [400, 800, 1600])
  }

  func testRunEngineWithoutOverrideFallsBackToEmptyStringWhenOutputIsNotValidUTF8() throws {
    try withSandboxedEngine(
      scriptBody: """
        #!/bin/sh
        printf '\\xff\\xfe'
        exit 0
        """
    ) { model in
      let output = try model.runEngine(["--sensor-only", "dpi"])
      XCTAssertEqual(output, "")
    }
  }
}

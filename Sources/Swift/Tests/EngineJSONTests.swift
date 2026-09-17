// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class EngineJSONTests: XCTestCase {
  func testDecodesDeviceProfileDPIReportRateAndWriteFields() throws {
    let profileResult = try EngineJSON.validate(
      EngineJSON.decode(fakeStructuredProfilesOutput()), expectedKind: "profiles")
    let response = profileResult.response

    XCTAssertEqual(response.contractVersion, 1)
    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.kind, "profiles")
    XCTAssertEqual(response.device?.deviceChoice.name, "G502 X")
    XCTAssertNil(response.devices)
    XCTAssertEqual(response.profileCapacity, 3)
    XCTAssertEqual(response.headers?.count, 2)
    XCTAssertEqual(response.selectedProfile?.buttons.count, 2)
    XCTAssertEqual(response.selectedProfile?.layouts.gShift, true)
    XCTAssertEqual(response.selectedProfile?.rgbZones.first?.color, [255, 0, 16])

    let devices = EngineJSON.deviceChoices(from: response)
    XCTAssertTrue(devices.isEmpty)
    XCTAssertEqual(EngineJSON.profileChoices(from: response).map(\.id), [1, 2])
    XCTAssertEqual(EngineJSON.profileChoices(from: response)[1].crcValid, true)

    let dpi = try XCTUnwrap(response.dpi)
    XCTAssertEqual(dpi.capabilities.supportedValues, [400, 800, 1600])
    XCTAssertEqual(dpi.capabilities.currentValue, 800)
    XCTAssertEqual(dpi.capabilities.sensorCount, 1)

    let reportRate = try XCTUnwrap(response.reportRate)
    XCTAssertEqual(reportRate.capabilities.supportedRates, [125, 500, 1000])
    XCTAssertEqual(reportRate.capabilities.currentRate, 500)
    XCTAssertEqual(reportRate.rates.first?.wireValue, 8)

    let write = try EngineJSON.validate(
      EngineJSON.decode(fakeStructuredWriteOutput()), expectedKind: "write"
    ).response
    XCTAssertEqual(write.operation, "apply")
    XCTAssertEqual(write.operationID, "profile-2-save-test")
    XCTAssertEqual(write.completed, true)
    XCTAssertEqual(write.plannedSectors?.first?.length, 256)
    XCTAssertEqual(write.hasBackup, true)
    XCTAssertEqual(write.backupPath, "/tmp/profile-2-save-test.logiob")
    XCTAssertEqual(write.verifiedSectors, 1)
  }

  func testDecodesDeviceListAndNormalizesProductID() throws {
    let result = try EngineJSON.validate(
      EngineJSON.decode(fakeStructuredDeviceListOutput()), expectedKind: "device_list")
    XCTAssertEqual(result.response.vendorInterfaceCount, 1)
    XCTAssertEqual(result.response.deviceCount, 1)
    let devices = EngineJSON.deviceChoices(from: result.response)
    XCTAssertEqual(devices.count, 1)
    XCTAssertEqual(devices[0].id, 1)
    XCTAssertEqual(devices[0].productID, "0x0000")
    XCTAssertEqual(devices[0].deviceKey, "abc123ef")
  }

  func testDecodeSeparatesDiagnosticsFromTheJSONEnvelope() throws {
    let output = "macOS denied HID access to one interface\n\(fakeStructuredDeviceListOutput())\n"
    let result = try EngineJSON.validate(
      EngineJSON.decode(output), expectedKind: "device_list")
    XCTAssertEqual(result.diagnostics, "macOS denied HID access to one interface")
  }

  func testRejectsInvalidOutputContractVersionAndKind() throws {
    XCTAssertThrowsError(try EngineJSON.decode("not JSON")) { error in
      XCTAssertEqual(
        error.localizedDescription, "The HID++ engine returned invalid structured output.")
    }

    let versioned = fakeStructuredDeviceListOutput().replacingOccurrences(
      of: "\"contract_version\":1", with: "\"contract_version\":99")
    XCTAssertThrowsError(try EngineJSON.validate(EngineJSON.decode(versioned))) { error in
      XCTAssertTrue(error.localizedDescription.contains("contract version 99"))
    }

    let result = try EngineJSON.decode(fakeStructuredDeviceListOutput())
    XCTAssertThrowsError(try EngineJSON.validate(result, expectedKind: "profiles")) { error in
      XCTAssertTrue(error.localizedDescription.contains("device_list"))
    }
  }

  func testSurfacesStructuredErrorAndDiagnostics() throws {
    let output =
      "Save operation save-1 failed after 0 sector(s) were verified.\n"
      + "  /tmp/save-1.logiob\n"
      + "{\"contract_version\":1,\"ok\":false,\"error\":{\"code\":\"operation\",\"message\":\"apply failed\"}}\n"
    XCTAssertThrowsError(try EngineJSON.validate(EngineJSON.decode(output))) { error in
      XCTAssertTrue(error.localizedDescription.contains("apply failed"))
      XCTAssertTrue(error.localizedDescription.contains("/tmp/save-1.logiob"))
    }
  }

  func testUsesGenericMessageForStructuredErrorWithoutPayloadOrDiagnostics() throws {
    let output = "{\"contract_version\":1,\"ok\":false,\"kind\":\"dpi\"}"

    XCTAssertThrowsError(try EngineJSON.validate(EngineJSON.decode(output))) { error in
      XCTAssertEqual(error.localizedDescription, "The HID++ engine failed.")
    }
  }

  func testMapsUnavailableDPIAndReportRateCapabilities() throws {
    let dpiOutput = fakeStructuredDPIOutput()
      .replacingOccurrences(of: "\"sensor_count\":1", with: "\"sensor_count\":0")
      .replacingOccurrences(
        of: "\"supported_values\":[400,800,1600]", with: "\"supported_values\":[]"
      )
      .replacingOccurrences(of: "\"current_sensor_dpi\":800", with: "\"current_sensor_dpi\":0")
      .replacingOccurrences(
        of: "\"error\":\"\"", with: "\"error\":\"DPI unavailable\"", options: [.backwards])
    let dpi = try XCTUnwrap(EngineJSON.decode(dpiOutput).response.dpi)
    XCTAssertNil(dpi.capabilities.sensorCount)
    XCTAssertNil(dpi.capabilities.currentValue)
    XCTAssertEqual(dpi.capabilities.errorMessage, "DPI unavailable")

    let reportOutput = """
      {"contract_version":1,"ok":true,"kind":"profiles","report_rate":{"requested":true,"available":false,"feature_id":0,"rates":[],"current_valid":false,"current_hertz":0,"error":"Polling rate unavailable"}}
      """.trimmingCharacters(in: .whitespacesAndNewlines)
    let reportRate = try XCTUnwrap(EngineJSON.decode(reportOutput).response.reportRate)
    XCTAssertTrue(reportRate.capabilities.supportedRates.isEmpty)
    XCTAssertNil(reportRate.capabilities.currentRate)
    XCTAssertEqual(reportRate.capabilities.errorMessage, "Polling rate unavailable")
  }

  func testProfileChoiceOmitsCRCWhenSelectedProfileWasNotChecked() throws {
    let output = fakeStructuredProfilesOutput().replacingOccurrences(
      of: "\"crc_checked\":true,\"crc_valid\":true",
      with: "\"crc_checked\":false,\"crc_valid\":false")
    let response = try EngineJSON.decode(output).response

    XCTAssertNil(EngineJSON.profileChoices(from: response)[1].crcValid)
  }

  func testEmptyOptionalCollectionsRemainSafe() throws {
    let output =
      "{\"contract_version\":1,\"ok\":true,\"kind\":\"device_list\",\"devices\":[],\"device_count\":0}"
    let response = try EngineJSON.validate(EngineJSON.decode(output)).response
    XCTAssertTrue(EngineJSON.deviceChoices(from: response).isEmpty)
    XCTAssertTrue(EngineJSON.profileChoices(from: response).isEmpty)
    XCTAssertNil(response.dpi)
  }
}

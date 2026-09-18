// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct EngineJSONError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}

struct EngineJSONErrorPayload: Decodable, Sendable {
  let code: String
  let message: String
}

struct EngineJSONDevice: Decodable, Sendable {
  let index: Int
  let vendorID: Int
  let productID: Int
  let deviceNumber: Int
  let requestDeviceNumber: Int
  let protocolVersion: Double
  let name: String
  let connection: String
  let deviceKey: String

  enum CodingKeys: String, CodingKey {
    case index
    case vendorID = "vendor_id"
    case productID = "product_id"
    case deviceNumber = "device_number"
    case requestDeviceNumber = "request_device_number"
    case protocolVersion = "protocol"
    case name
    case connection
    case deviceKey = "device_key"
  }

  var deviceChoice: DeviceChoice {
    DeviceChoice(
      id: index,
      name: DeviceChoice.normalizedReportedName(name),
      connection: connection,
      productID: String(format: "0x%04X", productID),
      deviceKey: deviceKey
    )
  }
}

struct EngineJSONProfileHeader: Decodable, Sendable {
  let number: Int
  let sector: Int
  let enabled: Bool
}

struct EngineJSONLayouts: Decodable, Sendable {
  let buttons: Bool
  let gShift: Bool
  let dpi: Bool
  let rgb: Bool

  enum CodingKeys: String, CodingKey {
    case buttons
    case gShift = "gshift"
    case dpi
    case rgb
  }
}

struct EngineJSONButton: Decodable, Sendable {
  let number: Int
  let layer: String
  let raw: [Int]
  let description: String
}

struct EngineJSONRGBZone: Decodable, Sendable {
  let number: Int
  let present: Bool
  let mode: Int
  let color: [Int]
}

struct EngineJSONProfile: Decodable, Sendable {
  let number: Int
  let sector: Int
  let enabled: Bool
  let memory: Int
  let format: Int
  let macroFormat: Int
  let profileCapacity: Int
  let buttonCapacity: Int
  let sectorCount: Int
  let sectorSize: Int
  let shiftFlags: Int
  let crcChecked: Bool
  let crcValid: Bool
  let layouts: EngineJSONLayouts
  let buttons: [EngineJSONButton]
  let dpiStages: [Int]
  let dpiDefaultStage: Int
  let dpiShiftStage: Int
  let rgbZones: [EngineJSONRGBZone]

  enum CodingKeys: String, CodingKey {
    case number
    case sector
    case enabled
    case memory
    case format
    case macroFormat = "macro_format"
    case profileCapacity = "profile_capacity"
    case buttonCapacity = "button_capacity"
    case sectorCount = "sector_count"
    case sectorSize = "sector_size"
    case shiftFlags = "shift_flags"
    case crcChecked = "crc_checked"
    case crcValid = "crc_valid"
    case layouts
    case buttons
    case dpiStages = "dpi_stages"
    case dpiDefaultStage = "dpi_default_stage"
    case dpiShiftStage = "dpi_shift_stage"
    case rgbZones = "rgb_zones"
  }
}

struct EngineJSONDPI: Decodable, Sendable {
  let requested: Bool
  let available: Bool
  let sensorCount: Int
  let supportedValues: [Int]
  let currentSensorDPI: Int
  let error: String

  enum CodingKeys: String, CodingKey {
    case requested
    case available
    case sensorCount = "sensor_count"
    case supportedValues = "supported_values"
    case currentSensorDPI = "current_sensor_dpi"
    case error
  }

  var capabilities: DPICapabilities {
    DPICapabilities(
      supportedValues: supportedValues,
      sensorCount: sensorCount > 0 ? sensorCount : nil,
      currentValue: currentSensorDPI > 0 ? currentSensorDPI : nil,
      errorMessage: error.isEmpty ? nil : error
    )
  }
}

struct EngineJSONReportRateEntry: Decodable, Sendable {
  let hertz: Int
  let wireValue: Int

  enum CodingKeys: String, CodingKey {
    case hertz
    case wireValue = "wire_value"
  }
}

struct EngineJSONReportRate: Decodable, Sendable {
  let requested: Bool
  let available: Bool
  let featureID: Int
  let rates: [EngineJSONReportRateEntry]
  let currentValid: Bool
  let currentHertz: Int
  let error: String

  enum CodingKeys: String, CodingKey {
    case requested
    case available
    case featureID = "feature_id"
    case rates
    case currentValid = "current_valid"
    case currentHertz = "current_hertz"
    case error
  }

  var capabilities: PollingRateCapabilities {
    PollingRateCapabilities(
      supportedRates: rates.map(\.hertz),
      currentRate: currentValid && currentHertz > 0 ? currentHertz : nil,
      errorMessage: error.isEmpty ? nil : error
    )
  }
}

struct EngineJSONPlannedSector: Decodable, Sendable {
  let kind: String
  let sector: Int
  let length: Int
}

struct EngineJSONResponse: Decodable, Sendable {
  let contractVersion: Int
  let ok: Bool
  let kind: String?
  let error: EngineJSONErrorPayload?
  let vendorInterfaceCount: Int?
  let devices: [EngineJSONDevice]?
  let deviceCount: Int?
  let device: EngineJSONDevice?
  let profileCapacity: Int?
  let headers: [EngineJSONProfileHeader]?
  let selectedProfile: EngineJSONProfile?
  let dpi: EngineJSONDPI?
  let reportRate: EngineJSONReportRate?
  let onboardProfile: EngineJSONProfile?
  let onboardProfileError: String?
  let operation: String?
  let operationID: String?
  let profile: Int?
  let changed: Bool?
  let dryRun: Bool?
  let completed: Bool?
  let plannedSectors: [EngineJSONPlannedSector]?
  let hasBackup: Bool?
  let backupPath: String?
  let verifiedSectors: Int?

  enum CodingKeys: String, CodingKey {
    case contractVersion = "contract_version"
    case ok
    case kind
    case error
    case vendorInterfaceCount = "vendor_interface_count"
    case devices
    case deviceCount = "device_count"
    case device
    case profileCapacity = "profile_capacity"
    case headers
    case selectedProfile = "selected_profile"
    case dpi
    case reportRate = "report_rate"
    case onboardProfile = "onboard_profile"
    case onboardProfileError = "onboard_profile_error"
    case operation
    case operationID = "operation_id"
    case profile
    case changed
    case dryRun = "dry_run"
    case completed
    case plannedSectors = "planned_sectors"
    case hasBackup = "has_backup"
    case backupPath = "backup_path"
    case verifiedSectors = "verified_sectors"
  }
}

struct EngineJSONCommandResult: Sendable {
  let response: EngineJSONResponse
  let diagnostics: String
}

enum EngineJSON {
  static let contractVersion = 1

  static func decode(_ output: String) throws -> EngineJSONCommandResult {
    let lines = output.components(separatedBy: .newlines)
    let decoder = JSONDecoder()

    for (index, line) in lines.enumerated() {
      let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard candidate.first == "{", let data = candidate.data(using: .utf8) else { continue }
      guard let response = try? decoder.decode(EngineJSONResponse.self, from: data) else {
        continue
      }
      let diagnostics = lines.enumerated()
        .filter { $0.offset != index }
        .map(\.element)
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return EngineJSONCommandResult(response: response, diagnostics: diagnostics)
    }

    throw EngineJSONError(message: "The HID++ engine returned invalid structured output.")
  }

  static func validate(
    _ result: EngineJSONCommandResult,
    expectedKind: String? = nil
  ) throws -> EngineJSONCommandResult {
    guard result.response.contractVersion == contractVersion else {
      throw EngineJSONError(
        message:
          "Unsupported HID++ engine contract version \(result.response.contractVersion). This app supports version \(contractVersion)."
      )
    }
    guard result.response.ok else {
      let message = result.response.error?.message ?? "The HID++ engine failed."
      let detail = result.diagnostics.isEmpty ? message : "\(message)\n\(result.diagnostics)"
      throw EngineError.failed(detail)
    }
    if let expectedKind, result.response.kind != expectedKind {
      throw EngineJSONError(
        message:
          "The HID++ engine returned \(result.response.kind ?? "an unknown result") instead of \(expectedKind)."
      )
    }
    return result
  }

  static func profileChoices(from response: EngineJSONResponse) -> [ProfileChoice] {
    guard let headers = response.headers else { return [] }
    return headers.sorted { $0.number < $1.number }.map { header in
      let crcValid =
        response.selectedProfile?.number == header.number
        ? response.selectedProfile.map { $0.crcChecked ? $0.crcValid : nil } ?? nil
        : nil
      return ProfileChoice(
        id: header.number,
        sector: String(format: "0x%04X", header.sector),
        enabled: header.enabled,
        crcValid: crcValid
      )
    }
  }

  static func deviceChoices(from response: EngineJSONResponse) -> [DeviceChoice] {
    (response.devices ?? []).map(\.deviceChoice).sorted { $0.id < $1.id }
  }
}

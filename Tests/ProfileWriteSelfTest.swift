// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@main
@MainActor
struct ProfileWriteSelfTest {
    static func main() {
        guard ProfileWriteValidation.isPrimaryClick(raw: "80010001"),
              ProfileWriteValidation.isPrimaryClick(raw: "80 01 00 01"),
              ProfileWriteValidation.isPrimaryClick(raw: "80010001".lowercased()),
              !ProfileWriteValidation.isPrimaryClick(raw: "FFFFFFFF"),
              !ProfileWriteValidation.isPrimaryClick(raw: "80010002") else {
            fatalError("primary-click raw-record recognition failed")
        }

        let invalidMessage = ProfileWriteValidation.missingPrimaryClickMessage(
            profileNumber: 2,
            profileName: "G502 X",
            buttonRaws: ["80010002", "FFFFFFFF"]
        )
        guard invalidMessage == "Profile 2 on G502 X has no primary click assigned. Choose “Left click” for one of its buttons, then save again." else {
            fatalError("primary-click validation message was not actionable or profile-specific")
        }
        let inaccessibleGShiftMessage = ProfileWriteValidation.inaccessibleGShiftPrimaryClickMessage(
            profileNumber: 2,
            profileName: "G502 X",
            normalButtonRaws: ["80010002", "FFFFFFFF"],
            gShiftButtonRaws: ["80010001"]
        )
        guard inaccessibleGShiftMessage == "Profile 2 on G502 X has primary click assigned only on the G-Shift layer, but no Normal-layer button activates G-Shift. Assign G-Shift to a Normal button or add a primary click to the Normal layer, then save again." else {
            fatalError("inaccessible G-Shift primary-click warning was not actionable")
        }
        guard ProfileWriteValidation.inaccessibleGShiftPrimaryClickMessage(
            profileNumber: 2,
            profileName: "G502 X",
            normalButtonRaws: ["900B0000"],
            gShiftButtonRaws: ["80010001"]
        ) == nil else {
            fatalError("bound G-Shift button was incorrectly treated as inaccessible")
        }

        let presetModel = AppModel(startInitialRefresh: false)
        configure(presetModel)
        guard presetModel.primaryClickValidationMessage ==
            "Profile 2 on G502 X has no primary click assigned. Choose “Left click” for one of its buttons, then save again." else {
            fatalError("primary-click validation did not prefer the runtime mouse name")
        }
        guard let leftClick = presetModel.presets.first(where: { $0.label == "Left click" }) else {
            fatalError("Left click preset is missing")
        }
        presetModel.selectOutput(buttonIndex: 0, choice: leftClick.raw)
        guard presetModel.buttons[0].draftRaw == ProfileWriteValidation.primaryClickRaw else {
            fatalError("preset primary-click assignment was not normalized")
        }

        let rawModel = AppModel(startInitialRefresh: false)
        configure(rawModel)
        rawModel.setRaw(buttonIndex: 0, raw: "80 01 00 01")
        guard rawModel.buttons[0].draftRaw == ProfileWriteValidation.primaryClickRaw else {
            fatalError("raw primary-click assignment was not normalized")
        }

        let importedModel = AppModel(startInitialRefresh: false)
        configure(importedModel)
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "lope-profile-write-self-test-" + String(ProcessInfo.processInfo.processIdentifier) + ".json"
        )
        let imported = EditableBackup(
            formatVersion: 1,
            createdAt: "2026-01-01T00:00:00Z",
            device: EditableBackup.Device(name: "G502 X", productID: "0x0000"),
            profiles: [EditableBackup.ProfileState(number: 2, enabled: true)],
            profile: EditableBackup.Profile(
                number: 2,
                sector: "0x0100",
                enabled: true,
                buttons: [EditableBackup.Button(
                    number: 1,
                    physicalControl: "G1 · Primary click",
                    output: "Left click",
                    raw: "FFFFFFFF",
                    layer: ButtonLayer.normal.rawValue
                )],
                dpi: nil
            ),
            exactBinaryBackup: nil
        )
        do {
            let data = try JSONEncoder().encode(imported)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            fatalError("could not create imported JSON fixture: \(error)")
        }
        importedModel.loadEditableBackup(jsonURL)
        guard importedModel.buttons[0].draftRaw == ProfileWriteValidation.primaryClickRaw else {
            fatalError("imported JSON primary-click output was not resolved")
        }

        let dpiDragModel = AppModel(startInitialRefresh: false)
        configure(dpiDragModel)
        dpiDragModel.dpiCapabilities = DPICapabilities(
            supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
            minimum: 400,
            maximum: 4000
        )
        dpiDragModel.dpiCount = 3
        dpiDragModel.dpiStages = ["400", "1200", "2400", "", ""]
        dpiDragModel.defaultStage = 2
        dpiDragModel.shiftStage = 1

        let firstDragIndex = dpiDragModel.moveDPIStageDuringDrag(index: 1, value: 1600)
        guard firstDragIndex == 1,
              dpiDragModel.dpiStages.prefix(3).map({ Int($0) }) == [400, 1600, 2400] else {
            fatalError("continuous DPI drag update did not track the snapped value")
        }

        let crossedForwardIndex = dpiDragModel.moveDPIStageDuringDrag(index: firstDragIndex, value: 3200)
        guard crossedForwardIndex == 2,
              dpiDragModel.dpiStages.prefix(3).map({ Int($0) }) == [400, 2400, 3200],
              dpiDragModel.defaultStage == 3,
              dpiDragModel.shiftStage == 1 else {
            fatalError("DPI stage crossing did not preserve order or default/shift assignment")
        }

        let crossedBackwardIndex = dpiDragModel.moveDPIStageDuringDrag(index: crossedForwardIndex, value: 800)
        guard crossedBackwardIndex == 1,
              dpiDragModel.dpiStages.prefix(3).map({ Int($0) }) == [400, 800, 2400],
              dpiDragModel.defaultStage == 2 else {
            fatalError("reverse DPI stage crossing did not keep the dragged stage active")
        }

        dpiDragModel.dpiStages = ["400", "800", "800", "", ""]
        dpiDragModel.finishDPIStageDrag()
        let finishedDPIValues = dpiDragModel.dpiStages.prefix(3).compactMap(Int.init)
        guard finishedDPIValues == [400, 800, 1200],
              zip(finishedDPIValues, finishedDPIValues.dropFirst()).allSatisfy({ $0 < $1 }) else {
            fatalError("DPI drag completion did not repair strict stage ordering")
        }

        let rejectedButtonsModel = AppModel(startInitialRefresh: false)
        configure(rejectedButtonsModel)
        var rejectedButtonCalls = [[String]]()
        rejectedButtonsModel.engineRunnerOverride = { arguments in
            rejectedButtonCalls.append(arguments)
            return ""
        }
        rejectedButtonsModel.buttons[0].draftRaw = "FFFFFFFF"
        rejectedButtonsModel.applyButtons()
        guard rejectedButtonCalls.isEmpty,
              rejectedButtonsModel.status.contains("Profile 2"),
              rejectedButtonsModel.status.contains("Left click") else {
            fatalError("button-only save did not reject before invoking the write engine")
        }

        let rejectedDPIModel = AppModel(startInitialRefresh: false)
        configure(rejectedDPIModel)
        rejectedDPIModel.dpiCount = 1
        rejectedDPIModel.dpiStages = ["800", "", "", "", ""]
        rejectedDPIModel.baselineDPICount = 5
        rejectedDPIModel.baselineDPIStages = ["", "", "", "", ""]
        var rejectedDPICalls = [[String]]()
        rejectedDPIModel.engineRunnerOverride = { arguments in
            rejectedDPICalls.append(arguments)
            return ""
        }
        rejectedDPIModel.applyDPI()
        guard rejectedDPICalls.isEmpty else {
            fatalError("DPI-only save did not reject before invoking the write engine")
        }

        let rejectedCombinedModel = AppModel(startInitialRefresh: false)
        configure(rejectedCombinedModel)
        rejectedCombinedModel.buttons[0].draftRaw = "FFFFFFFF"
        rejectedCombinedModel.profiles[0].enabled = false
        rejectedCombinedModel.baselineProfileEnabled = [2: true]
        var rejectedCombinedCalls = [[String]]()
        rejectedCombinedModel.engineRunnerOverride = { arguments in
            rejectedCombinedCalls.append(arguments)
            return ""
        }
        rejectedCombinedModel.applyAll()
        guard rejectedCombinedCalls.isEmpty else {
            fatalError("combined save did not reject before invoking the write engine")
        }

        let validModel = AppModel(startInitialRefresh: false)
        configure(validModel)
        validModel.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
        var validCalls = [[String]]()
        validModel.engineRunnerOverride = { arguments in
            validCalls.append(arguments)
            return "Verified sector 0x0100"
        }
        validModel.applyButtons()
        guard validCalls.contains(where: { $0.contains("apply") }) else {
            fatalError("valid primary-click assignment did not invoke the write engine")
        }

        let layeredModel = AppModel(startInitialRefresh: false)
        configure(layeredModel)
        let layeredText = """
        Profile 2 (sector 0x0100, enabled=yes)
          button 1: Left click [80010001]
          G-Shift button 1: Right click [80010002]
        """
        let parsedLayers = layeredModel.parseProfiles(layeredText)
        guard parsedLayers.rowsByProfile[2]?.first?.layer == .normal,
              parsedLayers.gShiftRowsByProfile[2]?.first?.layer == .gShift else {
            fatalError("normal/G-Shift profile-output layers were not parsed separately")
        }
        let normalRows = layeredModel.buttons
        let gShiftRows = [ButtonRow(
            id: 1,
            label: "G1 · Primary click (Left)",
            currentRaw: "80010002",
            draftRaw: "80010002",
            draftChoice: "80010002",
            layer: .gShift
        )]
        layeredModel.setButtonRows(normal: normalRows, gShift: gShiftRows)
        layeredModel.setRaw(layer: .normal, buttonIndex: 0, raw: ProfileWriteValidation.primaryClickRaw)
        layeredModel.selectButtonLayer(.gShift)
        layeredModel.setRaw(buttonIndex: 0, raw: "80010004")
        layeredModel.selectButtonLayer(.normal)
        guard layeredModel.gShiftButtonRows[0].draftRaw == "80010004",
              layeredModel.buttons[0].draftRaw == ProfileWriteValidation.primaryClickRaw else {
            fatalError("G-Shift edits were not retained across layer switching")
        }
        var layeredCalls = [[String]]()
        layeredModel.engineRunnerOverride = { arguments in
            layeredCalls.append(arguments)
            return "Verified sector 0x0100"
        }
        layeredModel.applyButtons()
        guard layeredCalls.contains(where: { $0.contains("gshift:1:80010004") }) else {
            fatalError("G-Shift button edits were not forwarded to the write engine")
        }

        try? FileManager.default.removeItem(at: jsonURL)
        print("profile write self-test: primary-click validation and save guards passed")
    }

    private static func configure(_ model: AppModel) {
        model.devices = [DeviceChoice(
            id: 1,
            name: "G502 X",
            connection: "Wired",
            productID: "0x0000",
            deviceKey: "test-device"
        )]
        model.selectedDeviceIndex = 1
        model.currentDeviceName = "G502 X / X LIGHTSPEED / X PLUS"
        model.profileNumber = 2
        model.profiles = [ProfileChoice(
            id: 2,
            sector: "0x0100",
            enabled: true,
            crcValid: true
        )]
        model.baselineProfileEnabled = [2: true]
        model.buttons = [ButtonRow(
            id: 1,
            label: "G1 · Primary click (Left)",
            currentRaw: "80010002",
            draftRaw: "80010002",
            draftChoice: "80010002",
            layer: .normal
        )]
    }
}

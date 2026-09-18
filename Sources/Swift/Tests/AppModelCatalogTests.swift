// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Covers AppModel+Catalog.swift: the stock button-to-raw-output mapping used
// while a profile is still loading, the keyboard key catalog, and the output
// preset list. `stockRawAssignment` is private, so it is exercised only
// through `loadingButtonRows()`, using real catalog descriptors under
// `Profiles/` wherever their button wording already covers a branch, and one
// synthetic descriptor (reloaded into `MouseProfileCatalog.shared` for the
// duration of a single test) for the handful of branches — the numeric
// fallback `switch` and the "scroll down"/"scroll up" keywords — that no
// shipped descriptor's button text currently reaches.
@MainActor
final class AppModelCatalogTests: XCTestCase {
  private func rawsByLabel(_ model: AppModel) -> [String: String] {
    Dictionary(uniqueKeysWithValues: model.loadingButtonRows().map { ($0.label, $0.currentRaw) })
  }

  func testLoadingButtonRowsMapsG502XPhysicalControls() {
    let model = AppModel(startInitialRefresh: false)
    model.currentDeviceName = "G502 X"
    let rows = model.loadingButtonRows()
    let raws = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.currentRaw) })

    XCTAssertEqual(raws[1], "80010001", "primary click")
    XCTAssertEqual(raws[2], "80010002", "secondary click")
    XCTAssertEqual(raws[3], "80010004", "middle click")
    XCTAssertEqual(raws[4], "80010008", "back")
    XCTAssertEqual(raws[5], "90070000", "DPI Shift / sniper button")
    XCTAssertEqual(raws[6], "80010010", "forward")
    XCTAssertEqual(raws[7], "90010000", "wheel tilt left / scroll left")
    XCTAssertEqual(raws[8], "90020000", "wheel tilt right / scroll right")
    XCTAssertEqual(raws[9], "900A0000", "profile button")
    XCTAssertEqual(raws[10], "90030000", "DPI up")
    XCTAssertEqual(raws[11], "90040000", "DPI down")

    // Every mapped raw here is a known preset, so the draft choice should be
    // the raw value itself rather than falling back to "keystroke".
    for row in rows {
      XCTAssertEqual(row.draftChoice, row.currentRaw, "button \(row.id) fell back to keystroke")
    }
  }

  func testLoadingButtonRowsMapsGShiftAndModeSwitch() {
    let model = AppModel(startInitialRefresh: false)
    model.currentDeviceName = "G600 MMO"
    let raws = Dictionary(
      uniqueKeysWithValues: model.loadingButtonRows().map { ($0.id, $0.currentRaw) })

    XCTAssertEqual(raws[6], "900B0000", "G-Shift layer button")
    XCTAssertEqual(raws[8], "900A0000", "mode switch / profile cycle")
  }

  func testLoadingButtonRowsMapsDPIButtonKeyword() {
    let model = AppModel(startInitialRefresh: false)
    // G203's catalog entry only matches by product ID (see
    // MouseProfileCatalogTests.testG203ProductIDCatalogMatch), and has a
    // button whose control text is literally "DPI button".
    model.devices = [
      DeviceChoice(id: 1, name: "", connection: "Wired", productID: "0xC092", deviceKey: "g203")
    ]
    model.selectedDeviceIndex = 1
    let dpiButtonRow = model.loadingButtonRows().first {
      $0.label.lowercased().contains("dpi button")
    }
    XCTAssertEqual(dpiButtonRow?.currentRaw, "90050000")
  }

  func testLoadingButtonRowsFallsBackToNumericDefaultsWithoutKeywordMatch() {
    let model = AppModel(startInitialRefresh: false)
    // pro-2's G4/G5 side buttons carry no recognizable keyword in their
    // control/alias text, so stockRawAssignment falls through to the plain
    // switch on the physical button number.
    model.currentDeviceName = "PRO 2 LIGHTSPEED"
    let raws = Dictionary(
      uniqueKeysWithValues: model.loadingButtonRows().map { ($0.id, $0.currentRaw) })
    XCTAssertEqual(raws[4], "80010008", "button 4 falls back to the Back preset")
    XCTAssertEqual(raws[5], "80010010", "button 5 falls back to the Forward preset")
  }

  /// Exercises the branches no shipped `Profiles/*.json` descriptor reaches:
  /// the numeric switch's cases 1–3, its final `default` (unrecognized text
  /// on a button number outside 1–5), and the "scroll down"/"scroll up"
  /// keywords (which only ever appear in `scrollWheelButtonLabels`, not in a
  /// button's own control/alias text, in every real descriptor). Reloads
  /// `MouseProfileCatalog.shared` with one throwaway descriptor for the
  /// duration of this test only, then restores the default catalog.
  func testLoadingButtonRowsFallsBackForSyntheticUnrecognizedButtons() throws {
    defer { MouseProfileCatalog.reload(customProfilesDirectory: nil) }

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-catalog-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let descriptor = MouseProfileDescriptor(
      schemaVersion: 1,
      id: "test-fallback-mouse",
      name: "Test Fallback Mouse",
      match: .init(nameContains: ["Test Fallback Mouse"], productIDs: []),
      buttons: [
        .init(number: 1, control: "Mystery A", aliases: [], notes: nil),
        .init(number: 2, control: "Mystery B", aliases: [], notes: nil),
        .init(number: 3, control: "Mystery C", aliases: [], notes: nil),
        .init(number: 12, control: "Mystery D", aliases: [], notes: nil),
        .init(number: 20, control: "Scroll Down", aliases: [], notes: nil),
        .init(number: 21, control: "Scroll Up", aliases: [], notes: nil),
      ],
      scrollWheelButtonLabels: nil,
      hiddenProfileButtonNumbers: nil,
      dpiRange: nil,
      refreshGuidance: nil,
      profileIO: MouseProfileCatalog.genericProfile.profileIO,
      rgbProfile: nil,
      sources: []
    )
    let data = try JSONEncoder().encode(descriptor)
    try data.write(to: tempDirectory.appendingPathComponent("test-fallback-mouse.json"))

    // AppModel's own init reloads the shared catalog from its (default)
    // configuration directory, so the temporary catalog must be installed
    // after construction or it is immediately overwritten.
    let model = AppModel(startInitialRefresh: false)
    MouseProfileCatalog.reload(customProfilesDirectory: tempDirectory)
    model.currentDeviceName = "Test Fallback Mouse"
    let raws = Dictionary(
      uniqueKeysWithValues: model.loadingButtonRows().map { ($0.id, $0.currentRaw) })

    XCTAssertEqual(raws[1], "80010001", "switch case 1")
    XCTAssertEqual(raws[2], "80010002", "switch case 2")
    XCTAssertEqual(raws[3], "80010004", "switch case 3")
    XCTAssertEqual(raws[12], "FFFFFFFF", "unrecognized button outside 1...5 falls to the default")
    XCTAssertEqual(raws[20], "90100000", "scroll down keyword")
    XCTAssertEqual(raws[21], "90110000", "scroll up keyword")
  }

  func testModifierChoicesAreFixedSet() {
    let model = AppModel(startInitialRefresh: false)
    XCTAssertEqual(model.modifierChoices.map(\.label), ["Ctrl", "Shift", "Alt", "Command"])
    XCTAssertEqual(model.modifierChoices.map(\.id), [0x01, 0x02, 0x04, 0x08])
  }

  func testKeyboardKeysIncludeLettersAndAppendedRanges() {
    let model = AppModel(startInitialRefresh: false)
    let keys = model.keyboardKeys
    XCTAssertTrue(keys.contains { $0.id == 0x04 && $0.label == "A" })
    XCTAssertTrue(keys.contains { $0.id == 0x1D && $0.label == "Z" })
    // Appended digit row: 0x1E...0x26 -> "1"..."9", 0x27 -> "0".
    XCTAssertTrue(keys.contains { $0.id == 0x1E && $0.label == "1" })
    XCTAssertTrue(keys.contains { $0.id == 0x27 && $0.label == "0" })
    // Appended function-key ranges.
    XCTAssertTrue(keys.contains { $0.id == 0x3A && $0.label == "F1" })
    XCTAssertTrue(keys.contains { $0.id == 0x45 && $0.label == "F12" })
    XCTAssertTrue(keys.contains { $0.id == 0x68 && $0.label == "F13" })
    XCTAssertTrue(keys.contains { $0.id == 0x73 && $0.label == "F24" })
    XCTAssertTrue(keys.contains { $0.id == 0xE2 && $0.label == "Left Alt" })
    XCTAssertTrue(keys.contains { $0.id == 0xE7 && $0.label == "Right GUI" })
  }

  func testExtendedKeyboardKeyClassification() {
    let model = AppModel(startInitialRefresh: false)
    let printScreen = KeyboardKeyChoice(id: 0x46, label: "Print Screen")
    let letterA = KeyboardKeyChoice(id: 0x04, label: "A")
    XCTAssertTrue(model.isExtendedKeyboardKey(printScreen))
    XCTAssertTrue(model.isNonStandardKeyboardKey(printScreen))
    XCTAssertFalse(model.isExtendedKeyboardKey(letterA))
    XCTAssertTrue(model.extendedKeyboardKeys.contains(printScreen))
    XCTAssertFalse(model.extendedKeyboardKeys.contains(letterA))

    let leftAlt = KeyboardKeyChoice(id: 0xE2, label: "Left Alt")
    XCTAssertTrue(model.isExtendedKeyboardKey(leftAlt))
    XCTAssertEqual(model.keyboardKeyGroup(for: leftAlt), .modifier)
    XCTAssertTrue(model.extendedKeyboardKeys.contains(leftAlt))
  }

  func testKeyboardOutputKeysRespectsShowNonStandardKeyboardKeysFlag() {
    let model = AppModel(startInitialRefresh: false)
    model.showNonStandardKeyboardKeys = false
    XCTAssertTrue(model.keyboardOutputKeys.isEmpty)
    model.showNonStandardKeyboardKeys = true
    XCTAssertFalse(model.keyboardOutputKeys.isEmpty)
    XCTAssertEqual(model.keyboardOutputKeys, model.extendedKeyboardKeys)
    XCTAssertFalse(model.keyboardOutputKeys.contains { $0.id == 0x04 && $0.label == "A" })
  }

  func testKeyboardKeyLayoutGroupsFollowFullSizePhysicalOrder() {
    let model = AppModel(startInitialRefresh: false)
    let groups = model.keyboardKeyLayoutGroups

    XCTAssertEqual(
      groups.map(\.label),
      ["Main typing block", "Navigation and arrow cluster", "Numpad"])

    let navigationLabels = groups.first { $0.group == .navigation }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      navigationLabels,
      [
        "Print Screen", "Scroll Lock", "Pause", "Insert", "Home", "Page Up", "Delete", "End",
        "Page Down", "Up Arrow", "Left Arrow", "Down Arrow", "Right Arrow", "Locking Scroll Lock",
      ])

    let numpadLabels = groups.first { $0.group == .numpad }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      numpadLabels,
      [
        "Num Lock", "Keypad /", "Keypad *", "Keypad -", "Keypad 7 / Home",
        "Keypad 8 / Up Arrow", "Keypad 9 / Page Up", "Keypad +", "Keypad 4 / Left Arrow",
        "Keypad 5", "Keypad 6 / Right Arrow", "Keypad 1 / End", "Keypad 2 / Down Arrow",
        "Keypad 3 / Page Down", "Keypad Enter", "Keypad 0 / Insert", "Keypad . / Delete",
        "Keypad =", "Locking Num Lock", "Keypad Comma", "Keypad Equal Sign",
      ])

    let mainTypingLabels = groups.first { $0.group == .mainTyping }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      mainTypingLabels.prefix(14),
      [
        "Escape", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "`",
      ])
    XCTAssertEqual(
      mainTypingLabels.suffix(5),
      ["Space", "Non-US \\", "Application", "Power", "Locking Caps Lock"])
  }

  func testExtendedKeyboardKeyPickerGroupsKeepPhysicalStandardKeysTogether() {
    let model = AppModel(startInitialRefresh: false)
    let groups = model.extendedKeyboardKeyLayoutGroups

    XCTAssertEqual(
      groups.map(\.label),
      ["Main typing block", "Navigation and arrow cluster", "Numpad"])
    XCTAssertEqual(
      groups[0].keys.map(\.label),
      ["Non-US \\", "Application", "Power", "Locking Caps Lock"])
    XCTAssertEqual(
      groups[1].keys.map(\.label),
      [
        "Print Screen", "Scroll Lock", "Pause", "Insert", "Home", "Page Up", "Delete", "End",
        "Page Down", "Up Arrow", "Left Arrow", "Down Arrow", "Right Arrow", "Locking Scroll Lock",
      ])
    XCTAssertEqual(
      groups[2].keys.map(\.label),
      [
        "Num Lock", "Keypad /", "Keypad *", "Keypad -", "Keypad 7 / Home",
        "Keypad 8 / Up Arrow", "Keypad 9 / Page Up", "Keypad +", "Keypad 4 / Left Arrow",
        "Keypad 5", "Keypad 6 / Right Arrow", "Keypad 1 / End", "Keypad 2 / Down Arrow",
        "Keypad 3 / Page Down", "Keypad Enter", "Keypad 0 / Insert", "Keypad . / Delete",
        "Keypad =", "Locking Num Lock", "Keypad Comma", "Keypad Equal Sign",
      ])
  }

  func testExtendedKeyboardKeyGroupsAreCategoryOrdered() {
    let model = AppModel(startInitialRefresh: false)
    let groups = model.extendedKeyboardKeyGroups

    XCTAssertEqual(
      groups.map(\.label),
      [
        "Standard full-size keyboard keys",
        "Modifier keys",
        "F13 and later keys",
        "Media keys",
        "Other unusual keys",
      ])
    XCTAssertEqual(model.extendedKeyboardKeys, groups.flatMap(\.keys))

    let standardLabels = groups.first { $0.group == .standard }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      standardLabels,
      model.extendedKeyboardKeyLayoutGroups.flatMap(\.keys).map(\.label))

    for group in groups where group.group != .standard {
      XCTAssertEqual(
        group.keys,
        group.keys.sorted {
          let leftLabel = $0.label.lowercased()
          let rightLabel = $1.label.lowercased()
          return leftLabel == rightLabel ? $0.id < $1.id : leftLabel < rightLabel
        },
        "\(group.label) is not alphabetized"
      )
    }

    let mediaLabels = groups.first { $0.group == .media }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      mediaLabels,
      [
        "Eject", "Fast Forward", "Mute", "Pause", "Play", "Record", "Rewind",
        "Scan Next Track", "Scan Previous Track", "Stop", "Volume Down", "Volume Up",
      ])

    let modifierLabels = groups.first { $0.group == .modifier }?.keys.map(\.label) ?? []
    XCTAssertEqual(
      modifierLabels,
      [
        "Left Alt", "Left Control", "Left GUI", "Left Shift",
        "Right Alt", "Right Control", "Right GUI", "Right Shift",
      ])
  }

  func testKeyboardKeyGroupChoiceExposesStableIdentityAndLabel() {
    let key = KeyboardKeyChoice(id: 0x04, label: "A")
    let choices = KeyboardKeyGroup.allCases.map {
      KeyboardKeyGroupChoice(group: $0, keys: [key])
    }

    XCTAssertEqual(choices.map(\.id), KeyboardKeyGroup.allCases)
    XCTAssertEqual(choices.map(\.label), KeyboardKeyGroup.allCases.map(\.rawValue))
    XCTAssertEqual(choices.map(\.keys), Array(repeating: [key], count: choices.count))
  }

  func testKeyboardKeyLayoutGroupChoiceExposesStableIdentityAndLabel() {
    let key = KeyboardKeyChoice(id: 0x04, label: "A")
    let choices = KeyboardKeyLayoutGroup.allCases.map {
      KeyboardKeyLayoutGroupChoice(group: $0, keys: [key])
    }

    XCTAssertEqual(choices.map(\.id), KeyboardKeyLayoutGroup.allCases)
    XCTAssertEqual(choices.map(\.label), KeyboardKeyLayoutGroup.allCases.map(\.rawValue))
    XCTAssertEqual(choices.map(\.keys), Array(repeating: [key], count: choices.count))
  }

  func testExpandedKeyboardCatalogIncludesSupportedMediaKeys() {
    let model = AppModel(startInitialRefresh: false)
    let media = model.keyboardKeys.filter { $0.id == 0xB0 || $0.id == 0xB5 }

    XCTAssertEqual(media.map(\.label), ["Play", "Scan Next Track"])
    XCTAssertTrue(media.allSatisfy(model.isExtendedKeyboardKey))
  }

  func testPresetsContainsEveryKnownRawOutput() {
    let model = AppModel(startInitialRefresh: false)
    let rawValues = Set(model.presets.map(\.raw))
    XCTAssertTrue(rawValues.isSuperset(of: ["FFFFFFFF", "80010001", "900A0000", "900B0000"]))
    XCTAssertEqual(model.presets.count, Set(model.presets.map(\.id)).count, "preset ids are unique")
  }
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Mirrors AppModel+EditingButtons.swift. AppModelEditingTests.swift already
// covers selectOutput's happy-path preset normalization and the G-Shift
// layer-switching flow through the active-layer branch of
// setRaw(layer:buttonIndex:raw:); these tests fill in the remaining
// out-of-bounds guards, the keystroke-choice branch, profile-enable
// bookkeeping, and the non-active-layer branches of setRaw(layer:).
@MainActor
final class AppModelEditingButtonsTests: XCTestCase {
  func testSetPresetDelegatesToSetRaw() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setPreset(buttonIndex: 0, raw: "80 01 00 04")

    XCTAssertEqual(model.buttons[0].draftRaw, "80010004")
    XCTAssertEqual(model.buttons[0].draftChoice, "80010004")
  }

  func testSelectOutputIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let before = model.buttons

    model.selectOutput(buttonIndex: 5, choice: "keystroke")

    XCTAssertEqual(model.buttons.map(\.draftRaw), before.map(\.draftRaw))
  }

  func testSelectOutputKeystrokeInitializesChordWhenNotAlreadyRecording() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertFalse(model.isKeyboardRecord(buttonIndex: 0))

    model.selectOutput(buttonIndex: 0, choice: "keystroke")

    XCTAssertEqual(model.buttons[0].draftChoice, "keystroke")
    XCTAssertEqual(model.buttons[0].draftRaw, "80020000")
  }

  func testSelectOutputKeystrokePreservesExistingChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x02, key: 0x04)
    XCTAssertTrue(model.isKeyboardRecord(buttonIndex: 0))

    model.selectOutput(buttonIndex: 0, choice: "keystroke")

    XCTAssertEqual(model.buttons[0].draftChoice, "keystroke")
    XCTAssertEqual(model.buttons[0].draftRaw, "80020204")
  }

  func testSelectOutputPresetChoiceDelegatesToSetPreset() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.selectOutput(buttonIndex: 0, choice: "80010008")

    XCTAssertEqual(model.buttons[0].draftRaw, "80010008")
    XCTAssertEqual(model.buttons[0].draftChoice, "80010008")
  }

  func testProfileEnabledReflectsKnownAndUnknownProfiles() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    XCTAssertTrue(model.profileEnabled(2))
    XCTAssertFalse(model.profileEnabled(999))
  }

  func testSetProfileEnabledIgnoresUnknownProfileID() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let statusBefore = model.status

    model.setProfileEnabled(profileID: 999, enabled: false)

    XCTAssertEqual(model.status, statusBefore)
  }

  func testSetProfileEnabledRefusesToDisableLastEnabledProfile() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setProfileEnabled(profileID: 2, enabled: false)

    XCTAssertTrue(model.profiles[0].enabled)
    XCTAssertEqual(model.status, "At least one onboard profile must remain enabled.")
  }

  func testSetProfileEnabledAllowsDisablingWhenAnotherProfileStaysEnabled() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.profiles.append(ProfileChoice(id: 3, sector: "0x0200", enabled: true, crcValid: true))

    model.setProfileEnabled(profileID: 2, enabled: false)

    XCTAssertFalse(model.profiles[0].enabled)
    XCTAssertEqual(model.status, "Profile 2 will be disabled when you save to the mouse.")

    model.setProfileEnabled(profileID: 2, enabled: true)
    XCTAssertTrue(model.profiles[0].enabled)
    XCTAssertEqual(model.status, "Profile 2 will be enabled when you save to the mouse.")
  }

  func testSetRawIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let before = model.buttons

    model.setRaw(buttonIndex: 7, raw: "80010001")

    XCTAssertEqual(model.buttons.map(\.draftRaw), before.map(\.draftRaw))
  }

  func testSetRawRecordsKeyInputDraftForKeyboardChordWithNonZeroKey() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setRaw(buttonIndex: 0, raw: "80020004")

    XCTAssertEqual(model.keyInputDrafts[0], "A")
  }

  func testSetRawClearsKeyInputDraftForKeyboardChordWithZeroKey() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80020004")
    XCTAssertNotNil(model.keyInputDrafts[0])

    model.setRaw(buttonIndex: 0, raw: "80020000")

    XCTAssertNil(model.keyInputDrafts[0])
  }

  func testSetRawClearsKeyInputDraftWhenSwitchingAwayFromKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80020004")
    XCTAssertNotNil(model.keyInputDrafts[0])

    model.setRaw(buttonIndex: 0, raw: "FFFFFFFF")

    XCTAssertNil(model.keyInputDrafts[0])
  }

  func testSetRawWithExplicitLayerMatchingActiveLayerDelegatesDirectly() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setRaw(layer: .normal, buttonIndex: 0, raw: "80010004")

    XCTAssertEqual(model.buttons[0].draftRaw, "80010004")
  }

  func testSetRawWithExplicitNormalLayerWhileGShiftActiveUpdatesStoredRowsOnly() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let normalRows = model.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .gShift
      )
    ]
    model.setButtonRows(normal: normalRows, gShift: gShiftRows)
    model.selectButtonLayer(.gShift)

    model.setRaw(layer: .normal, buttonIndex: 0, raw: "80010010")

    XCTAssertEqual(model.normalButtonRows[0].draftRaw, "80010010")
    XCTAssertEqual(model.normalButtonRows[0].draftChoice, "80010010")
    // The active (G-Shift) layer is untouched by the .normal-layer write.
    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
  }

  func testSetRawWithExplicitGShiftLayerWhileNormalActiveUpdatesStoredRowsOnly() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let normalRows = model.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .gShift
      )
    ]
    model.setButtonRows(normal: normalRows, gShift: gShiftRows)

    model.setRaw(layer: .gShift, buttonIndex: 0, raw: "keystroke-not-a-preset")

    XCTAssertEqual(model.gShiftButtonRows[0].draftRaw, "KEYSTROKE-NOT-A-PRESET")
    XCTAssertEqual(model.gShiftButtonRows[0].draftChoice, "keystroke")
    // The active (normal) layer is untouched.
    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
  }

  func testSetRawWithExplicitNormalLayerIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let normalRows = model.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .gShift
      )
    ]
    model.setButtonRows(normal: normalRows, gShift: gShiftRows)
    model.selectButtonLayer(.gShift)

    model.setRaw(layer: .normal, buttonIndex: 99, raw: "80010010")

    XCTAssertEqual(model.normalButtonRows.map(\.draftRaw), normalRows.map(\.draftRaw))
  }

  func testSetRawWithExplicitGShiftLayerIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let normalRows = model.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .gShift
      )
    ]
    model.setButtonRows(normal: normalRows, gShift: gShiftRows)

    model.setRaw(layer: .gShift, buttonIndex: 99, raw: "80010010")

    XCTAssertEqual(model.gShiftButtonRows.map(\.draftRaw), gShiftRows.map(\.draftRaw))
  }
}

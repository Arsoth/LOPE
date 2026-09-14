// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import XCTest

@testable import LOPECore

// Mirrors AppModel+EditingKeyboard.swift, which had no dedicated coverage
// before this file.
@MainActor
final class AppModelEditingKeyboardTests: XCTestCase {
  private func keyEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = []
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifierFlags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )!
  }

  // MARK: isKeyboardRecord / keyboardBytes

  func testIsKeyboardRecordIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    XCTAssertFalse(model.isKeyboardRecord(buttonIndex: 5))
  }

  func testIsKeyboardRecordFalseForNonKeyboardRaw() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80010001")

    XCTAssertFalse(model.isKeyboardRecord(buttonIndex: 0))
  }

  // MARK: isModifierEnabled / setModifier

  func testIsModifierEnabledFalseWhenNotAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80010001")

    XCTAssertFalse(model.isModifierEnabled(buttonIndex: 0, bit: 0x01))
  }

  func testIsModifierEnabledReflectsSetBits() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x03, key: 0x04)

    XCTAssertTrue(model.isModifierEnabled(buttonIndex: 0, bit: 0x01))
    XCTAssertTrue(model.isModifierEnabled(buttonIndex: 0, bit: 0x02))
    XCTAssertFalse(model.isModifierEnabled(buttonIndex: 0, bit: 0x04))
  }

  func testSetModifierIsNoOpWhenNotAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80010001")

    model.setModifier(buttonIndex: 0, bit: 0x01, enabled: true)

    XCTAssertEqual(model.buttons[0].draftRaw, "80010001")
  }

  func testSetModifierEnablesAndDisablesBit() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x00, key: 0x04)

    model.setModifier(buttonIndex: 0, bit: 0x02, enabled: true)
    XCTAssertTrue(model.isModifierEnabled(buttonIndex: 0, bit: 0x02))

    model.setModifier(buttonIndex: 0, bit: 0x02, enabled: false)
    XCTAssertFalse(model.isModifierEnabled(buttonIndex: 0, bit: 0x02))
  }

  // MARK: keyboardKey / keyboardKeyText / keyboardChordText

  func testKeyboardKeyDefaultsToZeroWithoutAChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80010001")

    XCTAssertEqual(model.keyboardKey(buttonIndex: 0), 0)
  }

  func testKeyboardKeyTextPrefersInFlightDraftOverStoredChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)
    model.keyInputDrafts[0] = "Recording…"

    XCTAssertEqual(model.keyboardKeyText(buttonIndex: 0), "Recording…")
  }

  func testKeyboardKeyTextFallsBackToStoredChordLabel() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // setRaw(buttonIndex:raw:) eagerly caches an in-flight keyInputDrafts
    // entry for keyboard chords, so routing the chord through
    // setKeyboardChord would exercise the draft branch, not the fallback.
    // Writing the row directly (as the G-Shift layer does before it is
    // ever made active) and then switching to it — which clears
    // keyInputDrafts — reproduces a stored chord with no in-flight draft.
    let normalRows = model.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80020004",
        draftRaw: "80020004",
        draftChoice: "keystroke",
        layer: .gShift
      )
    ]
    model.setButtonRows(normal: normalRows, gShift: gShiftRows)
    model.selectButtonLayer(.gShift)
    XCTAssertNil(model.keyInputDrafts[0])

    XCTAssertEqual(model.keyboardKeyText(buttonIndex: 0), "A")
  }

  func testKeyboardChordTextEmptyWithoutAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setRaw(buttonIndex: 0, raw: "80010001")

    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "")
  }

  func testKeyboardChordTextEmptyWhenKeyIsZero() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x0F, key: 0)

    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "")
  }

  func testKeyboardChordTextJoinsActiveModifiersAndKey() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x01 | 0x02 | 0x08, key: 0x04)

    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "Ctrl+Shift+Cmd+A")
  }

  func testKeyboardChordTextWithoutModifiersIsJustTheKey() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "A")
  }

  // MARK: keyboardKeyChoice / specialKeyChoice

  func testKeyboardKeyChoiceIsZeroWhenNonStandardKeysAreHidden() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = false
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x49)

    XCTAssertEqual(model.keyboardKeyChoice(buttonIndex: 0), 0)
  }

  func testKeyboardKeyChoiceMatchesExtendedKeyWhenNonStandardKeysAreShown() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x49)

    XCTAssertEqual(model.keyboardKeyChoice(buttonIndex: 0), 0x49)
  }

  func testCapturedExtendedKeyRemainsTheRecordedChoice() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.beginKeyboardRecording(buttonIndex: 0)

    model.recordKeyboardEvent(buttonIndex: 0, keyCode: 0x49, modifier: 0x02)

    XCTAssertEqual(model.keyboardKeyChoice(buttonIndex: 0), 0)
    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "Shift+Insert")
    XCTAssertTrue(model.extendedKeyboardKeys.contains { $0.id == 0x49 })
  }

  func testDirectExtendedKeyChoiceStillUsesExtendedChoiceControls() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.keyboardKeyChoice(buttonIndex: 0), 0x49)
    XCTAssertEqual(model.keyboardChordText(buttonIndex: 0), "Insert")
  }

  func testSpecialKeyChoiceIsZeroForOrdinaryKeyEvenWhenShown() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    XCTAssertEqual(model.specialKeyChoice(buttonIndex: 0), 0)
  }

  func testSpecialKeyChoiceMatchesExtendedKeyWhenShown() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x49)

    XCTAssertEqual(model.specialKeyChoice(buttonIndex: 0), 0x49)
  }

  // MARK: setKeyboardKeyChoice

  func testSetKeyboardKeyChoiceIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let before = model.buttons[0].draftRaw

    model.setKeyboardKeyChoice(buttonIndex: 9, key: 0x04)

    XCTAssertEqual(model.buttons[0].draftRaw, before)
  }

  func testSetKeyboardKeyChoiceZeroResetsChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x02, key: 0x04)

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020000")
  }

  func testSetKeyboardKeyChoiceIgnoresValueOutsideByteRange() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 999)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")
  }

  func testSetKeyboardKeyChoiceIgnoresUsageNotInCatalog() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    // 0x01 is a valid byte but is not one of the catalog's key usages.
    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x01)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")
  }

  func testSetKeyboardKeyChoiceBlocksNonStandardKeyWhenSettingIsOff() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = false

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
    XCTAssertTrue(model.status.contains("Enable non-standard keyboard keys"))
  }

  func testSetKeyboardKeyChoiceAllowsNonStandardKeyWhenSettingIsOnAndPreservesModifier() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x02, key: 0x04)

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020249")
  }

  func testSetKeyboardKeyChoiceDefaultsModifierToZeroWhenButtonIsNotAlreadyAKeyboardChord() {
    // The fixture button's draftRaw ("80010002") is a primary-click record,
    // not a keyboard chord, so keyboardBytes(_:) returns nil here and the
    // modifier falls back to 0 instead of being read from existing bytes.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x04)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")
  }

  // MARK: beginKeyboardRecording / cancelKeyboardRecording / recordKeyboardEvent

  func testBeginKeyboardRecordingIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.beginKeyboardRecording(buttonIndex: 9)

    XCTAssertNil(model.recordingKeyboardButtonID)
  }

  func testBeginKeyboardRecordingSetsTargetAndStatus() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.beginKeyboardRecording(buttonIndex: 0)

    XCTAssertEqual(model.recordingKeyboardButtonID, model.buttons[0].id)
    XCTAssertEqual(model.status, "Press one keyboard key to record it.")
  }

  func testCancelKeyboardRecordingClearsTargetAndSetsStatus() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.beginKeyboardRecording(buttonIndex: 0)

    model.cancelKeyboardRecording()

    XCTAssertNil(model.recordingKeyboardButtonID)
    XCTAssertEqual(model.status, "Keyboard recording canceled.")
  }

  func testRecordKeyboardEventIgnoresOutOfBoundsIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.recordKeyboardEvent(buttonIndex: 9, keyCode: 0x04, modifier: 0)

    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
  }

  func testRecordKeyboardEventIgnoresEventWhenNotTheActiveRecordingTarget() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // recordingKeyboardButtonID is nil (no recording in progress).

    model.recordKeyboardEvent(buttonIndex: 0, keyCode: 0x04, modifier: 0)

    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
  }

  func testRecordKeyboardEventReportsUnsupportedKeyCode() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.beginKeyboardRecording(buttonIndex: 0)

    model.recordKeyboardEvent(buttonIndex: 0, keyCode: 0xFF, modifier: 0)

    XCTAssertEqual(model.status, "That keyboard input is not supported by the HID++ key table.")
    XCTAssertNotNil(model.recordingKeyboardButtonID)
  }

  func testRecordKeyboardEventCommitsChordAndEndsRecording() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.beginKeyboardRecording(buttonIndex: 0)

    model.recordKeyboardEvent(buttonIndex: 0, keyCode: 0x04, modifier: 0x02)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020204")
    XCTAssertNil(model.recordingKeyboardButtonID)
    XCTAssertEqual(model.status, "Recorded A.")
  }

  // MARK: keyboardUsage(forMacKeyCode:) / keyboardUsage(for:)

  func testKeyboardUsageForMacKeyCodeKnownAndUnknown() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    XCTAssertEqual(model.keyboardUsage(forMacKeyCode: 0), 0x04)
    XCTAssertNil(model.keyboardUsage(forMacKeyCode: 9_999))
  }

  func testKeyboardUsageForEventRecognizesExtendedFunctionKeyScalars() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let f21 = String(Unicode.Scalar(0xF718)!)

    let event = keyEvent(keyCode: 111, characters: f21)

    XCTAssertEqual(model.keyboardUsage(for: event), 0x70)
  }

  func testKeyboardUsageForEventMapsFnReturnToInsert() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let event = keyEvent(keyCode: 36, characters: "\r", modifierFlags: .function)

    XCTAssertEqual(model.keyboardUsage(for: event), 0x49)
  }

  func testKeyboardUsageForEventFallsBackToMacKeyCodeTable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let event = keyEvent(keyCode: 0, characters: "a")

    XCTAssertEqual(model.keyboardUsage(for: event), 0x04)
  }

  // MARK: functionKeyChoice / setFunctionKey

  func testFunctionKeyChoiceCoversLowAndHighRangesAndDefault() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x3A)
    XCTAssertEqual(model.functionKeyChoice(buttonIndex: 0), 1)

    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x45)
    XCTAssertEqual(model.functionKeyChoice(buttonIndex: 0), 12)

    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x68)
    XCTAssertEqual(model.functionKeyChoice(buttonIndex: 0), 13)

    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x73)
    XCTAssertEqual(model.functionKeyChoice(buttonIndex: 0), 24)

    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)
    XCTAssertEqual(model.functionKeyChoice(buttonIndex: 0), 0)
  }

  func testSetFunctionKeyIgnoresOutOfRangeNumber() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    model.setFunctionKey(buttonIndex: 0, number: 0)
    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")

    model.setFunctionKey(buttonIndex: 0, number: 25)
    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")
  }

  func testSetFunctionKeySetsLowAndHighFunctionKeysPreservingModifier() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x01, key: 0x04)

    model.setFunctionKey(buttonIndex: 0, number: 1)
    XCTAssertEqual(model.buttons[0].draftRaw, "8002013A")

    model.setFunctionKey(buttonIndex: 0, number: 13)
    XCTAssertEqual(model.buttons[0].draftRaw, "80020168")
  }

  func testSetFunctionKeyDefaultsModifierToZeroWhenButtonIsNotAlreadyAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setFunctionKey(buttonIndex: 0, number: 1)

    XCTAssertEqual(model.buttons[0].draftRaw, "8002003A")
  }

  // MARK: setSpecialKey / setKeyboardKey

  func testSetSpecialKeyIgnoresNonPositiveKey() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0, key: 0x04)

    model.setSpecialKey(buttonIndex: 0, key: 0)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020004")
  }

  func testSetSpecialKeySetsClampedKeyPreservingModifier() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x08, key: 0x04)

    model.setSpecialKey(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020849")
  }

  func testSetSpecialKeyDefaultsModifierToZeroWhenButtonIsNotAlreadyAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setSpecialKey(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.buttons[0].draftRaw, "80020049")
  }

  func testSetKeyboardKeySetsClampedKeyPreservingModifier() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setKeyboardChord(buttonIndex: 0, modifier: 0x04, key: 0x04)

    model.setKeyboardKey(buttonIndex: 0, key: 999)

    XCTAssertEqual(model.buttons[0].draftRaw, "800204FF")
  }

  func testSetKeyboardKeyDefaultsModifierToZeroWhenButtonIsNotAlreadyAKeyboardChord() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setKeyboardKey(buttonIndex: 0, key: 999)

    XCTAssertEqual(model.buttons[0].draftRaw, "800200FF")
  }

  // MARK: keyboardKeyLabel

  func testKeyboardKeyLabelHandlesZeroKnownAndUnknownCodes() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    XCTAssertEqual(model.keyboardKeyLabel(0), "")
    XCTAssertEqual(model.keyboardKeyLabel(0x04), "A")
    XCTAssertEqual(model.keyboardKeyLabel(0xFF), "0xFF")
  }
}

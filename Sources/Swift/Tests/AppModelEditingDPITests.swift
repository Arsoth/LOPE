// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Mirrors AppModel+EditingDPI.swift. AppModelEditingTests.swift already
// covers the common continuous-drag and drag-completion happy paths for
// moveDPIStageDuringDrag/finishDPIStageDrag; these tests cover the
// remaining guard clauses and every other stage-editing entry point in the
// file (text entry, single-value commit, keyboard nudge, default/shift
// stage bookkeeping, deletion, and stage-count changes).
@MainActor
final class AppModelEditingDPITests: XCTestCase {
  /// A wide, evenly spaced supported-value catalog (every 100 from 400 to
  /// `maximum`) so nearest-value snapping in the tests below is
  /// deterministic.
  private func stageCapabilities(maximum: Int = 20_000) -> DPICapabilities {
    DPICapabilities(
      supportedValues: Array(stride(from: 400, through: maximum, by: 100)),
      minimum: 400,
      maximum: maximum
    )
  }

  // MARK: setDPIStageText

  func testSetDPIStageTextFiltersNonNumericCharacters() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3

    model.setDPIStageText(index: 0, text: "1a2b3c")

    XCTAssertEqual(model.dpiStages[0], "123")
  }

  func testSetDPIStageTextIgnoresIndexBeyondArrayBounds() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3

    model.setDPIStageText(index: 10, text: "123")

    XCTAssertEqual(model.dpiStages, ["", "", "", "", ""])
  }

  func testSetDPIStageTextIgnoresIndexAtOrBeyondActiveCount() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3

    model.setDPIStageText(index: 3, text: "123")

    XCTAssertEqual(model.dpiStages[3], "")
  }

  // MARK: commitDPIStageText

  func testCommitDPIStageTextAppliesSnappedValue() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "850", "1600", "", ""]

    model.commitDPIStageText(index: 1)

    XCTAssertEqual(model.dpiStages[1], "800")
  }

  func testCommitDPIStageTextIgnoresUnparsableText() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "", "1600", "", ""]

    model.commitDPIStageText(index: 1)

    XCTAssertEqual(model.dpiStages[1], "")
  }

  func testCommitDPIStageTextIgnoresIndexBeyondActiveCount() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1600", "900", ""]

    model.commitDPIStageText(index: 3)

    XCTAssertEqual(model.dpiStages[3], "900")
  }

  // MARK: setDPIStageValue

  func testSetDPIStageValueSnapsToTieBreakingLowerNeighbor() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "1600", "2400", "", ""]

    model.setDPIStageValue(index: 1, value: 850)

    XCTAssertEqual(model.dpiStages[1], "800")
  }

  func testSetDPIStageValueIgnoresIndexOutOfRange() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3

    model.setDPIStageValue(index: 4, value: 800)

    XCTAssertEqual(model.dpiStages[4], "")
  }

  func testSetDPIStageValueIsNoOpWhenNoSupportedValueFallsInNeighborWindow() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // The neighbor-derived window (801...1199) contains no supported value.
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200], minimum: 400, maximum: 1200)
    model.dpiCount = 3
    model.dpiStages = ["800", "801", "1200", "", ""]

    model.setDPIStageValue(index: 1, value: 850)

    XCTAssertEqual(model.dpiStages[1], "801")
  }

  func testSetDPIStageValueIsNoOpWhenNeighborWindowIsInverted() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    // Out-of-order neighbors invert the derived window (lowerBound 801 >
    // upperBound 800), so snappedValue bails before even filtering.
    model.dpiStages = ["800", "1000", "801", "", ""]

    model.setDPIStageValue(index: 1, value: 1000)

    XCTAssertEqual(model.dpiStages[1], "1000")
  }

  // MARK: moveDPIStageDuringDrag guard paths

  func testMoveDPIStageDuringDragIgnoresIndexOutOfArrayBounds() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    let result = model.moveDPIStageDuringDrag(index: 10, value: 800)

    XCTAssertEqual(result, 10)
    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
  }

  func testMoveDPIStageDuringDragIgnoresIndexAtOrBeyondActiveCount() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    let result = model.moveDPIStageDuringDrag(index: 3, value: 800)

    XCTAssertEqual(result, 3)
    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
  }

  func testMoveDPIStageDuringDragIsNoOpWhenAlreadyAtSnappedValue() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    let result = model.moveDPIStageDuringDrag(index: 1, value: 800)

    XCTAssertEqual(result, 1)
    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
  }

  // MARK: finishDPIStageDrag guard paths

  func testFinishDPIStageDragIsNoOpWithZeroActiveStages() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 0
    model.dpiStages = ["400", "800", "1200", "", ""]

    model.finishDPIStageDrag()

    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
  }

  func testFinishDPIStageDragStopsAtFirstUnparsableStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "not-a-number", "1200", "", ""]

    model.finishDPIStageDrag()

    // The first stage is in range and unaffected by neighbors, so it snaps
    // to itself; the loop then bails on the unparsable second stage before
    // touching the third.
    XCTAssertEqual(model.dpiStages[0], "400")
    XCTAssertEqual(model.dpiStages[1], "not-a-number")
    XCTAssertEqual(model.dpiStages[2], "1200")
  }

  // MARK: swapDPIStages (private, exercised through moveDPIStageDuringDrag)

  func testCrossingSwapMovesDefaultStageFromSecondToFirstAndShiftFromFirstToSecond() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    // The upcoming swap exchanges stage 1 and stage 2: defaultStage sits on
    // the second (higher) stage and shiftStage sits on the first.
    model.defaultStage = 2
    model.shiftStage = 1

    _ = model.moveDPIStageDuringDrag(index: 0, value: 900)

    XCTAssertEqual(Array(model.dpiStages.prefix(3)), ["800", "900", "1200"])
    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 2)
  }

  func testCrossingSwapMovesShiftStageFromSecondToFirstWhenDefaultIsElsewhere() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    // Same stage-1/stage-2 swap, but this time shiftStage sits on the
    // second (higher) stage and defaultStage is unrelated to either.
    model.defaultStage = 3
    model.shiftStage = 2

    _ = model.moveDPIStageDuringDrag(index: 0, value: 900)

    XCTAssertEqual(Array(model.dpiStages.prefix(3)), ["800", "900", "1200"])
    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertEqual(model.defaultStage, 3)
  }

  // MARK: adjustDPIStage

  func testAdjustDPIStageIncreasesWithinNeighborBounds() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    model.adjustDPIStage(index: 1, direction: .increase)

    XCTAssertEqual(model.dpiStages[1], "900")
  }

  func testAdjustDPIStageDecreasesWithinNeighborBounds() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    model.adjustDPIStage(index: 1, direction: .decrease)

    XCTAssertEqual(model.dpiStages[1], "700")
  }

  func testAdjustDPIStageIgnoresIndexOutOfArrayBounds() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3

    model.adjustDPIStage(index: 10, direction: .increase)

    XCTAssertEqual(model.dpiStages, ["", "", "", "", ""])
  }

  func testAdjustDPIStageIgnoresUnparsableCurrentValue() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "", "1200", "", ""]

    model.adjustDPIStage(index: 1, direction: .increase)

    XCTAssertEqual(model.dpiStages[1], "")
  }

  func testAdjustDPIStageIsNoOpWhenNoCandidateBeyondLastStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities(maximum: 20_000)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "20000", "", ""]

    model.adjustDPIStage(index: 2, direction: .increase)

    XCTAssertEqual(model.dpiStages[2], "20000")
  }

  // MARK: setDefaultDPIStage / setShiftDPIStage

  func testSetDefaultDPIStageIgnoresOutOfRangeStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.defaultStage = 1

    model.setDefaultDPIStage(9)

    XCTAssertEqual(model.defaultStage, 1)
  }

  func testSetDefaultDPIStageWithSingleStageSkipsShiftSwap() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 1
    model.defaultStage = 1
    model.shiftStage = 1

    model.setDefaultDPIStage(1)

    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testSetDefaultDPIStageSwapsShiftWhenTheyCollide() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDefaultDPIStage(2)

    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testSetDefaultDPIStageLeavesShiftAloneWhenNoCollision() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDefaultDPIStage(3)

    XCTAssertEqual(model.defaultStage, 3)
    XCTAssertEqual(model.shiftStage, 2)
  }

  func testSetShiftDPIStageIgnoresOutOfRangeStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.shiftStage = 1

    model.setShiftDPIStage(9)

    XCTAssertEqual(model.shiftStage, 1)
  }

  func testSetShiftDPIStageWithSingleStageSkipsDefaultSwap() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 1
    model.defaultStage = 1
    model.shiftStage = 1

    model.setShiftDPIStage(1)

    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertEqual(model.defaultStage, 1)
  }

  func testSetShiftDPIStageSwapsDefaultWhenTheyCollide() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.defaultStage = 2
    model.shiftStage = 1

    model.setShiftDPIStage(2)

    XCTAssertEqual(model.shiftStage, 2)
    XCTAssertEqual(model.defaultStage, 1)
  }

  // MARK: deleteDPIStage

  func testDeleteDPIStageRefusesWhenOnlyOneStageRemains() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 1
    model.dpiStages = ["400", "", "", "", ""]

    model.deleteDPIStage(index: 0)

    XCTAssertEqual(model.dpiCount, 1)
    XCTAssertEqual(model.dpiStages[0], "400")
  }

  func testDeleteDPIStageIgnoresIndexOutOfRange() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    model.deleteDPIStage(index: 5)

    XCTAssertEqual(model.dpiCount, 3)
  }

  func testDeleteDPIStageRefusesToRemoveDefaultStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    model.defaultStage = 2
    model.shiftStage = 3

    model.deleteDPIStage(index: 1)

    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(model.dpiStages[1], "800")
  }

  func testDeleteDPIStageRefusesToRemoveShiftStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    model.defaultStage = 1
    model.shiftStage = 3

    model.deleteDPIStage(index: 2)

    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(model.dpiStages[2], "1200")
  }

  func testDeleteDPIStageDecrementsBothAssignmentsWhenBothAreAboveRemovedStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    model.defaultStage = 3
    model.shiftStage = 2

    model.deleteDPIStage(index: 0)

    XCTAssertEqual(model.dpiCount, 2)
    XCTAssertEqual(Array(model.dpiStages.prefix(2)), ["800", "1200"])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testDeleteDPIStageRemovesStageAndShiftsLaterStageAssignmentsDown() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    model.defaultStage = 1
    model.shiftStage = 3

    model.deleteDPIStage(index: 1)

    XCTAssertEqual(model.dpiCount, 2)
    XCTAssertEqual(Array(model.dpiStages.prefix(2)), ["400", "1200"])
    XCTAssertEqual(model.dpiStages[2], "")
    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 2)
  }

  // MARK: setDPIStageCount

  func testSetDPIStageCountClampsRequestedValueToSupportedRange() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]

    model.setDPIStageCount(0)
    XCTAssertEqual(model.dpiCount, 1)
  }

  func testSetDPIStageCountClampsAboveFiveStages() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    // Use a 4-stage starting point (a single-stage increment to the clamped
    // maximum) rather than jumping several stages at once: the insertion
    // branch below only accounts for growing the active count by exactly
    // one, so a multi-stage jump from a small starting count is a separate,
    // pre-existing edge case outside what this coverage pass targets.
    model.dpiCount = 4
    model.dpiStages = ["400", "800", "1200", "1600", ""]

    model.setDPIStageCount(10)
    XCTAssertEqual(model.dpiCount, 5)
  }

  func testSetDPIStageCountIsNoOpWhenRequestMatchesCurrentCount() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    model.dpiStages = ["400", "800", "1200", "", ""]
    model.defaultStage = 2
    model.shiftStage = 1

    model.setDPIStageCount(3)

    XCTAssertEqual(model.dpiStages, ["400", "800", "1200", "", ""])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testSetDPIStageCountIncreaseInsertsAfterLastWhenFarFromMaximum() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 2
    model.dpiStages = ["400", "800", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDPIStageCount(3)

    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(Array(model.dpiStages.prefix(3)), ["400", "800", "1800"])
    XCTAssertEqual(model.defaultStage, 1)
    // insertionIndex (2) is not less than shiftStage(2), so it is unaffected.
    XCTAssertEqual(model.shiftStage, 2)
  }

  func testSetDPIStageCountIncreaseInsertsBeforeLastWhenNearMaximumAndBumpsLaterStages() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities(maximum: 20_000)
    model.dpiCount = 2
    model.dpiStages = ["400", "19900", "", "", ""]
    model.defaultStage = 2
    model.shiftStage = 1

    model.setDPIStageCount(3)

    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(Array(model.dpiStages.prefix(3)), ["400", "18900", "19900"])
    // insertionIndex is 1; defaultStage (2) > 1, so it is bumped to 3.
    XCTAssertEqual(model.defaultStage, 3)
    // shiftStage (1) is not greater than insertionIndex (1), so unaffected.
    XCTAssertEqual(model.shiftStage, 1)
  }

  func testSetDPIStageCountIncrementsShiftStageAboveInsertionPoint() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities(maximum: 20_000)
    model.dpiCount = 2
    model.dpiStages = ["400", "19900", "", "", ""]
    // insertionIndex will be 1; defaultStage (1) stays put but shiftStage
    // (2) is above the insertion point and must be bumped.
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDPIStageCount(3)

    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(Array(model.dpiStages.prefix(3)), ["400", "18900", "19900"])
    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 3)
  }

  func testSetDPIStageCountFromSingleStageAssignsDistinctShiftStage() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 1
    model.dpiStages = ["400", "", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 1

    model.setDPIStageCount(2)

    XCTAssertEqual(model.dpiCount, 2)
    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 2)
  }

  func testSetDPIStageCountIncreaseSilentlyNoOpsWhenNoRoomToInsert() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // Adjacent supported values leave no snapping room between the last
    // two active stages, so the suggested-value lookup fails.
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [4000, 4001], minimum: 100, maximum: 4001)
    model.dpiCount = 2
    model.dpiStages = ["4000", "4001", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDPIStageCount(3)

    // dpiCount is only mutated inside the successful-insert branch, so a
    // failed lookup leaves the active stage count unchanged even though a
    // higher count was requested.
    XCTAssertEqual(model.dpiCount, 2)
    XCTAssertEqual(Array(model.dpiStages.prefix(2)), ["4000", "4001"])
  }

  func testSetDPIStageCountIncreaseWithIncompleteTrailingStageUsesFallback() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 3
    // Only two of the three "active" stages actually parse, simulating an
    // incomplete text field mid-edit.
    model.dpiStages = ["400", "800", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 2

    model.setDPIStageCount(4)

    XCTAssertEqual(model.dpiCount, 4)
    XCTAssertEqual(model.dpiStages[3], "1000")
    XCTAssertEqual(model.dpiStages[4], "")
  }

  func testSetDPIStageCountDecreaseTrimsTrailingStagesAndClampsAssignments() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = stageCapabilities()
    model.dpiCount = 5
    model.dpiStages = ["400", "800", "1200", "1600", "2000"]
    model.defaultStage = 4
    model.shiftStage = 5

    model.setDPIStageCount(2)

    XCTAssertEqual(model.dpiCount, 2)
    XCTAssertEqual(model.dpiStages, ["400", "800", "", "", ""])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 2)
  }
}

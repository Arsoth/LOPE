# LOPE todo list

This list turns the product notes into implementation tasks and records what is
known about feasibility from the current code and HID++ protocol. Priority is
ordered as `P0` (correctness/safety), `P1` (high-value UX), and `P2` (polish).

## P0 — safe writes and backup behavior

### [ ] 1. Make a save operation batch its changes

**Feasibility: Medium-high, with an important limitation.** The UI already has
one `Save to mouse` action, but `AppModel+Writes.swift:applyAll()` currently
loops over button changes and invokes the engine separately for each one. Each
invocation reads, backs up, and writes a sector. The HID++ onboard-profiles
protocol only commits one sector at a time, so changes in the selected profile
can be combined into one sector write, but a selected-profile sector and the
profile-control sector cannot be made physically atomic together.

**Implementation tasks:**

- [ ] Add a batch/apply command or equivalent engine API that loads the
      selected profile sector once, applies all button and DPI mutations in memory,
      recalculates CRC once, writes once, and performs one complete read-back.
- [ ] Apply profile enable/disable changes as a separate control-sector batch
      when needed. Keep the UI as one save action and report the number of sectors
      written rather than implying a transaction across sectors.
- [ ] Preflight every requested mutation before the first write: supported
      layout, valid raw records, DPI values, profile-state invariant, CRC, and
      device/profile selection.
- [ ] Define partial-failure behavior. If a later sector write fails, show
      exactly which sector succeeded and offer restore from the backups created for
      this save operation.
- [ ] Add engine/model tests proving that multiple button changes produce one
      profile-sector write and that unchanged sectors are not touched.

**Done when:** one Save action creates a single operation record, makes all
required exact backups before any mutation, writes each affected sector at most
once, verifies each write, and clearly reports any unavoidable multi-sector
partial state.

### [ ] 2. Create exact binary backups once, before the first write

**Feasibility: High after the batch design above.** The current backup package
format already stores the complete sector and enough device information for
restore. The missing piece is moving backup creation out of each per-button
command and into a preflight phase, deduplicated by sector.

**Implementation tasks:**

- [ ] Identify the unique affected sectors for a save operation.
- [ ] Read and save each complete sector before any write, using one operation
      timestamp/ID in the filenames.
- [ ] Do not create a second backup for another edit that targets the same
      sector in the same Save operation.
- [ ] Keep the existing restore safety checks: matching device/product and
      profile format/sector size, valid target sector, and verified read-back.
- [ ] Add failure-path tests for backup creation, first-sector write failure,
      and later-sector write failure.

**Done when:** every affected sector has an exact, restorable binary snapshot
before the first write; no JSON sidecar is required for this safety guarantee.

## P1 — backup and profile UX

### [ ] 3. Make backups mouse-specific and filter them to the active mouse

**Feasibility: High for model-level filtering; medium for old/imported files.**
`DeviceChoice` already has a display name, product ID, and device key. Binary
backup headers currently preserve vendor/product/device-number metadata, while
editable JSON contains the device name and product ID. `BackupEntry` currently
just lists every `.bin`, custom backup extension, and `.json` in the directory.

**Implementation tasks:**

- [ ] Add a sanitized mouse identifier to new binary backup names, preferably
      using the display name, for example `G502-X-20260911-021500.bin`.
- [ ] Keep names filesystem-safe and bounded; avoid relying on the display name
      as the only identity when two devices share a model name.
- [ ] Add backup metadata parsing/indexing so the list can compare a backup to
      the selected device. Use embedded binary metadata where available and JSON
      metadata for import files; define a visible “unknown device” state for legacy
      files that cannot be matched safely.
- [ ] Filter the Backups tab to the selected mouse by default and offer an
      explicit “show all mice” option for recovery/import workflows.
- [ ] Refresh the filtered list when the selected device changes.
- [ ] Add tests for two mice, same-model mice, malformed metadata, and legacy
      filenames.

**Done when:** new backups identify their target mouse, changing the active
mouse changes the visible list, and an unmatched backup is never presented as
belonging to the active mouse without an explicit warning.

### [ ] 4. Stop generating JSON backup sidecars; use JSON only for import/export

**Feasibility: High.** `AppModel+Writes.swift` currently calls
`makeEditableBackup()` and writes a `.json` beside every binary backup. JSON
import/export is already implemented separately, so this is primarily a
lifecycle and UI cleanup.

**Implementation tasks:**

- [ ] Remove sidecar JSON creation from button, DPI, profile-state, batch, and
      manual binary-backup paths.
- [ ] Keep `Import JSON…` and `Export JSON…` as explicit profile workflows.
- [ ] Change the export default name from `profileN.json` to a sanitized
      `mouse-date-time.json` name, using a stable timestamp format and avoiding
      collisions where practical.
- [ ] Decide how existing sidecar JSON files appear: retain them as importable
      files with an “Editable JSON” label, but do not call them backups or create
      new ones.
- [ ] Update the Backups help text and list filtering so exact binary backups
      and editable JSON imports are not conflated.

**Done when:** a mouse write creates only the exact binary backup(s), while an
explicit JSON export creates a file named for the mouse and date/time.

## P1 — profile and button discovery

### [ ] 5. Expose onboard profile capacity in the loaded UI

**Feasibility: High.** The native engine already reads `ProfileInfo.profile_count`
from HID++ feature `0x8100`, and prints profile/header information. The Swift
model parses the actual profile headers into `profiles`, but does not retain the
reported capacity separately. Capacity and currently discovered headers should
be represented as different values.

**Implementation tasks:**

- [ ] Emit a stable machine-readable line such as `Profile capacity: N` in the
      engine output used by the GUI, or add a dedicated metadata command/result.
- [ ] Parse and store `onboardProfileCapacity` in `AppModel`; fall back to the
      number of readable headers if older engine output does not include it.
- [ ] Show it during/after load, for example `Onboard profiles (2 of 5
supported)` or `Profile 1 of 1`, and make the distinction between capacity and
      readable slots clear.
- [ ] Keep the UI honest for devices that report unavailable or inconsistent
      profile metadata.
- [ ] Add parser tests for capacity, missing capacity, and malformed values.

**Done when:** the user can see the mouse’s reported onboard profile capacity
as soon as profile loading completes, without mistaking it for the number of
currently readable/available profile headers.

### [ ] 6. Hide redundant profile selectors for one-profile mice

**Feasibility: High and low risk.** The app already knows the number of
discovered profile headers. The top-level profile `Picker` in `ContentView`
should be conditional on `profiles.count > 1`; the editor must continue to
load profile 1 normally.

**Implementation tasks:**

- [ ] Hide the top header profile picker when only one profile is available.
- [ ] Hide or simplify profile-cycle/enable controls when there is only one
      profile, while preserving the invariant that the sole profile cannot be
      disabled.
- [ ] Use the capacity label from item 5 where it gives useful context without
      reintroducing a selector.
- [ ] Test switching from a multi-profile mouse to a one-profile mouse and back
      without leaving a stale profile number or stale edits.

**Done when:** one-profile devices have no redundant profile selector, and
multi-profile devices retain the current picker and profile-state controls.

## P2 — button highlighting coverage

### [ ] 7. Detect and highlight all standard mouse buttons when possible

**Feasibility: Medium.** `AppModel+ButtonHighlight.swift` currently listens for
`.leftMouseDown`, `.rightMouseDown`, and `.otherMouseDown`, then maps
`event.buttonNumber + 1` to a profile button. `.otherMouseDown` may already
cover additional standard buttons, so the first task is to measure the actual
events rather than assume the current three-button behavior is the whole limit.
Some Logitech controls (DPI, profile, G-Shift, and vendor-specific buttons) may
not generate ordinary macOS mouse-button events at all. A lower-level HID event
path would require more permission handling and may still not reveal the
firmware’s logical profile-record number.

**Implementation tasks:**

- [ ] Add a temporary/diagnostic event log for event type, `buttonNumber`, and
      device context; test primary, secondary, middle, side, extra, tilt, and
      vendor-mapped controls across representative mice.
- [ ] Expand the standard-button mapping if AppKit already reports the event;
      keep highlighting limited to buttons that can be mapped unambiguously to the
      loaded profile rows.
- [ ] If AppKit cannot observe a required button, evaluate a CGEvent/HID-level
      monitor behind the existing Input Monitoring permission flow. Do not make
      this a prerequisite for editing, and do not claim coverage that the OS or
      firmware does not provide.
- [ ] Add a visible “not observable”/“mapping not confirmed” state rather than
      highlighting the wrong row.
- [ ] Remove the diagnostic logging before release and add regression coverage
      for buttons 1–8 and unsupported vendor controls.

**Done when:** every standard button that macOS exposes is mapped and
highlighted correctly; unsupported or ambiguous controls are reported clearly
and never mapped by guesswork.

## P2 — DPI editor visualization

### [ ] 8. Replace the plain DPI stage row with a multi-handle DPI bar

**Feasibility: Medium-high for visualization; medium for drag editing.** The
current editor already supports one to five stages, stage text fields, and
default/DPI-shift selectors. The protocol stores one to five strictly
increasing 16-bit stage values plus one-based default and shift indexes, with
unused slots cleared. A visual bar is therefore compatible, but “enable a
handle” must map to the contiguous `dpiCount` representation and drag values
must respect the mouse’s supported DPI values.

**Implementation tasks:**

- [ ] Parse supported DPI values/ranges into typed model data instead of keeping
      them only in the display string `dpiDetails`.
- [ ] Design a SwiftUI bar with one handle per active stage, a clear add/remove
      or enabled-stage affordance, and a text field for exact DPI entry.
- [ ] Snap dragged handles to supported values where the device reports a
      discrete list or step; otherwise use the supported min/max and validate the
      result before saving.
- [ ] Preserve strict ordering, one-to-five active stages, valid default/shift
      indexes, and the existing `0xFFFF` unused-stage behavior.
- [ ] Distinguish the default and DPI-shift stages visually with stable shapes
      or badges, while handling the case where both refer to the same stage.
- [ ] Retain accessible text/picker controls as an alternative to drag-only
      interaction and test keyboard editing, invalid input, duplicate values, and
      stage removal.

**Done when:** the bar is a clearer visualization and a reliable editor, every
drag/text change produces the same validated protocol representation as the
current controls, and the user can identify default and DPI-shift stages at a
glance.

## Suggested delivery order

1. Batch/preflight writes and exact backups (items 1–2).
2. Remove JSON sidecars and improve backup naming/filtering (items 3–4).
3. Add profile capacity metadata and one-profile UI behavior (items 5–6).
4. Instrument and expand button highlighting (item 7).
5. Build the DPI bar after the typed DPI capability model exists (item 8).

## Relevant current files

- `Sources/AppModel+Writes.swift` — save, backup, import, and export flows.
- `Sources/AppModel+ButtonHighlight.swift` — mouse event monitoring.
- `Sources/ContentView.swift` — profile selector, backup UI, and DPI editor.
- `Sources/LogitechOnboardProfileManagerApp.swift` — published state and
  change detection.
- `Sources/AppModel+Parsing.swift` — engine output parsing and backup naming.
- `Sources/logitech_onboard_commands_mutate.inc` and
  `Sources/logitech_onboard_profile_io.inc` — sector mutation/write behavior.
- `docs/PROTOCOL.md` — current HID++ and onboard-sector constraints.

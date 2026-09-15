# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 3: Add a retry action to the mouse-asleep dialog

- [ ] Add a `Retry` button to the mouse-asleep dialog that restarts the 60-second retry clock when the mouse times out after 60 seconds.

**Done when:** After a 60-second timeout, the dialog shows `Retry`; activating it restarts the retry countdown/system and allows the retry flow to continue.

### 4: Enforce valid G-shift primary-click bindings

- [ ] Require a G-shift key on the normal layer when primary click is bound on a G-shift layer, unless primary click is also bound on both layers.

**Done when:** The profile editor prevents or flags the invalid binding and allows the documented exception when primary click is bound on both layers.

### 5: Keep G-shift key bindings synchronized across layers

- [ ] Ensure a configured G-shift key is bound to the same physical key on both layers.

**Done when:** Setting a G-shift binding always produces matching bindings on the normal and G-shift layers.

### 6: Edit profile editor aliases

- [ ] Add profile editor support for editing aliases in addition to primary button names.

**Done when:** Alias fields can be edited alongside primary button names and the changes persist in the profile.

### 7: Preserve profile editor contents across tab changes

- [ ] Prevent changing tabs from resetting the profile editor contents.

**Done when:** Unsaved profile editor values remain intact after switching tabs and returning to the editor.

### 8: Improve RGB color controls

- [ ] Make the color box open an in-app RGB wheel and brightness slider, arranged in a row instead of a column.

**Done when:** Clicking a color box opens the RGB controls in-app, with the wheel and brightness slider displayed side by side.

### 9: Arrange color mode controls according to scope

- [ ] Show per-region color-mode buttons in a row to the right of the related color, or per-mouse buttons in a row below the color.

**Done when:** Color-mode controls use the right-of-color layout for per-region modes and the below-color layout for per-mouse modes.

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API. Does keeping the lope engine separate allow for easier multi platform work later?

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

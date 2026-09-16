# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 1: Improve color wheel drag responsiveness

- [ ] Make dragging the color wheel selector responsive, investigating whether it shares the same lag as the DPI slider.

**Done when:** Color wheel dragging responds smoothly without noticeable lag, and any shared cause with the DPI slider is addressed or documented.

### 2: Show a hand pointer over the color wheel selector

- [ ] Use a hand pointer when hovering over the draggable color wheel selector dot.

**Done when:** The pointer changes to a hand over the selector dot and remains the normal pointer elsewhere in the color control.

### 3: Add hex color input without a persistent hex display

- [ ] Allow entering a standard hex color value while removing the hex value display from the main color-control UI.

**Done when:** A valid standard hex value can be entered and applied, invalid input is handled clearly, and the main UI no longer shows a persistent hex display.

### 4: Persist color settings in exported backup JSON

- [ ] Ensure color settings are included in exported backup JSON files.

**Done when:** Exported backup JSON contains all relevant color settings and importing a backup restores them correctly.

### 5: Show connection-type symbols before device names

- [ ] Show a USB, wireless, or Bluetooth symbol before each device name instead of specifying the connection by name at the end of the device list entry.

**Done when:** Each device entry displays the correct connection-type symbol before its name, and the trailing connection-name text is removed.

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API. Does keeping the lope engine separate allow for easier multi platform work later?

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

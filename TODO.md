# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

1. [x] Add language support by replacing hard-coded labels with JSON-based input bundled into the app, including UI labels and mouse button labels. Initially support `en-us.json`, select the OS language by default, and fall back to English when that language is unavailable.

   **Done when:** All user-facing UI and mouse button labels are loaded from the bundled localization data, the OS language is selected when supported, and English is used as the fallback.

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API. Does keeping the lope engine separate allow for easier multi platform work later?

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

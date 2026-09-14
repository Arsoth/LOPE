# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- area beside status drawer button shows a text select cursor even when nothing is there
- why is `Recon Mouse - Wireless` showing
- Switching from Light to system breaks the UI for a little while, fades in color wise later. this is a regression. Light to dark and dark to light work fine.
- put the light theme and dark theme dropdown selectors horizontally, and make them longer.
- settings cards should be full width (like mouse profiles)
- put the key categories in a 2x2 grid

# LOPE todo list

# Ignore below item(s):

### 4: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 1: Permission-aware wired-mouse access

- [x] Selecting a wired mouse that is visible but unavailable because of missing HID permissions opens the permission request window, using the wake window's styling and behavior.
- [x] The permission request window is not shown automatically in other situations.
- [x] The settings pane shows the current permission state and provides an action to open the relevant macOS privacy settings.

**Done when:** A permission-blocked wired mouse selection presents the shared permission request UI; unrelated app startup and refresh paths do not auto-present it; the settings pane accurately reflects permission state and its action opens the relevant System Settings page; focused tests, formatting, and coverage checks pass. The prescribed signed rebuild was attempted twice but stopped during `codesign`, so `outputs/LOPE.app` is not a verified signed deliverable.

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

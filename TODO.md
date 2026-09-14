# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- Selecting a wired mouse that is unavailable due to permissions should pop up the request permissions window (which should be styled/function same as the wake window). In fact that should probably be the only time the permissions window auto appears - assuming we are always able to see a wired mouse exists, just not access the HID without permissions. Add a permissions checker/notification in the settings pane that lets you open system preferences from it as well.

# LOPE todo list

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- make the C tests report total quantity of tests passed/failed, not just a rolled up yes/no. this will require a refactor of testing.
- try and push all testing to 95% or better, focus on anything <92% for that.
- a "Retry" button should appear in the mouse asleep dialog that restarts the 60s clock/retry system if the mouse times out after 60s.

# LOPE todo list

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

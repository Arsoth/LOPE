# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 1: Evaluate an in-process engine API after the C boundaries are clean

- [x] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API. Does keeping the lope engine separate allow for easier multi platform work later?

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

# Ignore below item(s):

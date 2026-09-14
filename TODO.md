# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- Organize the keyboard keys better in the full size, arrows go together, numpad keys, etc.

# LOPE todo list

### 0: Define JSON-driven themes

- [ ] Define theme JSON files using hex colors for the header, footer, recent-events header, button and checkbox active/inactive states, main background, primary and secondary text, drag handles and their shapes, cards, the DPI bar and DPI background, plus other app colors; support light-mode and dark-mode themes.

**Done when:** The theme format documents and controls all app-wide color and drag-handle surfaces, and the bundled light and dark themes load with valid hex color values.

### 1: Add a custom themes directory

- [ ] Add a custom themes directory in the configuration directory that is automatically loaded, can be opened and moved like the backups directory, and is pre-populated with an underscore-named empty theme; recreate that theme if it is removed or renamed.

**Done when:** The directory is created and discovered automatically, users can manage it through the same workflow as backups, and the required underscore-named empty theme is restored on the next check when missing.

### 2: Add light-mode and dark-mode theme selection

- [ ] Let users choose separate light-mode and dark-mode themes, with a system setting determining which selected theme is active; default both selections to the included themes.
- [ ] Keep the current system/light/dark picker, add light/dark selectors below to choose theme

**Done when:** Settings expose independent light and dark theme choices, system appearance selects the corresponding theme, and the included themes are used by default.

### 3: Filter non-standard keyboard keys by category

- [ ] Make the “Show non standard Keyboard keys” setting expose checkboxes for the four key categories in its settings card, with only “Standard Full size Keyboard” selected by default; keep keys available in the visual picker even when their category checkbox is disabled, while omitting disabled categories from the list.

**Done when:** The four category filters control only the length of the displayed key list, the standard full-size category is enabled initially, and disabling a category never prevents a key from that category from appearing when selected in the visual picker.

# Ignore below item(s):

### 4: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

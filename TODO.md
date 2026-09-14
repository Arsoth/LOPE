# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 1: Remove the stray text-selection cursor

- [ ] Remove the text-select cursor from the area beside the status drawer button when that area is empty.

**Done when:** The pointer uses the normal cursor over the empty area beside the status drawer button.

### 2: Investigate the unexpected Recon Mouse entry

- [ ] Determine why `Recon Mouse - Wireless` appears intermittently and fix the underlying device-list behavior. I do not own that mouse, and it is only used in tests. Was this due to having the C backend missing?

**Done when:** The device picker only shows `Recon Mouse - Wireless` when the corresponding device is actually present and eligible to display.

### 3: Fix the Light-to-System theme transition

- [ ] Fix the regression where switching from Light to System leaves the UI visually delayed before the colors fade in.

**Done when:** Light-to-System updates cleanly and promptly, matching the already-working Light-to-Dark and Dark-to-Light transitions.

### 4: Arrange theme selectors horizontally

- [ ] Place the light-theme and dark-theme dropdown selectors side by side and make them longer.

**Done when:** Both selectors appear in one horizontal row with increased usable width and remain usable at supported window sizes.

### 5: Make settings cards full width

- [ ] Make the settings cards span the full available width, like the mouse profile cards.

**Done when:** Settings cards align to the same full-width layout behavior as mouse profile cards.

### 6: Arrange key categories in a 2x2 grid

- [ ] Replace the vertical key-category stack with a 2x2 grid.

**Done when:** The key categories display in two columns and two rows without overlap or clipped content.

### 7: Move the Themes button into Appearance

- [ ] Move the Themes button into the Appearance section instead of keeping it in its own card.

**Done when:** The Themes button is available within Appearance and no standalone Themes card remains.

### 8: Add a theme-folder refresh button

- [ ] Add a refresh button that reloads themes from the themes folder.

**Done when:** Activating refresh rereads the themes folder and updates the available themes in the UI.

### 9: Manage system themes with hash validation

- [ ] Automatically build and load Light and Dark as hash-validated system themes in the themes folder, replacing the need for an empty theme. If a system theme is modified, restore the system version and rename the modified copy.

**Done when:** The canonical Light and Dark system themes are present, validated, restored when modified, and modified copies are preserved under renamed files.

### 10: Load themes from JSON when switching or refreshing

- [ ] Make theme switching and theme-folder refreshing load theme data from the themes JSON so color changes do not require rebuilding the app during development.

**Done when:** Both actions reflect the current themes JSON contents without an application rebuild.

### 11: Hide the unauthorized wired device during its popup

- [ ] Hide the unauthorized wired device from the device picker while the wired-device popup is active.

**Done when:** The unauthorized wired device is absent from the picker for the full duration of the popup and returns afterward when appropriate.

### 12: Simplify the wake-wireless-mouse popup

- [ ] Remove the refresh button and loading spinner from the wake wireless mouse popup.

**Done when:** The popup no longer displays either control and its remaining content still presents correctly.

# Ignore below item(s):

### NIL: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

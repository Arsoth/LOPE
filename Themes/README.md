# LOPE themes

Themes are JSON files with a schema version, an appearance (`light` or
`dark`), a complete color palette, and the shape/color definitions for the
DPI drag handles. Colors use `#RRGGBB` or `#RRGGBBAA` hex values. The bundled
`light.json` and `dark.json` files are the reference format.

The app loads bundled themes from this directory and overlays valid JSON
themes from the selected configuration directory's `Custom Themes` folder.
The first load creates canonical, hash-validated `light.json` and `dark.json`
system themes in that custom folder. If either system file is changed, LOPE
preserves the changed file as `Custom Light (Modified)-<hash>.json` or
`Custom Dark (Modified)-<hash>.json` and restores the canonical system JSON.
System theme IDs are reserved and cannot be overridden by custom JSON. The
preserved copy remains loaded and selectable with a unique catalog ID such as
`custom-light-modified-<hash>`, a name such as `Custom Light (Modified)`, and
the modified colors and drag handles.

Copy a system theme or another complete theme to a new filename, give it a new
ID, and fill in every required field to create a custom theme.

## Format

```json
{
  "schemaVersion": 1,
  "id": "my-theme",
  "name": "My Theme",
  "appearance": "dark",
  "colors": {
    "header": "#1E1E1E",
    "footer": "#1E1E1E",
    "recentEventsHeader": "#1E1E1E",
    "buttonActive": "#0A84FF",
    "buttonInactive": "#FFFFFF",
    "checkboxActive": "#0A84FF",
    "checkboxInactive": "#FFFFFF80",
    "mainBackground": "#1E1E1E",
    "primaryText": "#FFFFFF",
    "secondaryText": "#FFFFFF80",
    "tertiaryText": "#FFFFFF66",
    "card": "#FFFFFF0B",
    "cardBorder": "#FFFFFF0E",
    "controlBackground": "#2C2C2E",
    "controlBorder": "#FFFFFF26",
    "dpiBar": "#6B7380",
    "dpiBackground": "#FFFFFF14",
    "accent": "#0A84FF",
    "success": "#30D158",
    "warning": "#FF9F0A",
    "error": "#FF453A",
    "separator": "#FFFFFF26",
    "shadow": "#0000003D",
    "hover": "#FFFFFF0D",
    "selected": "#0A84FF33",
    "disabled": "#FFFFFF80"
  },
    "dragHandles": {
    "defaultStage": { "color": "#E83D40", "outline": "#E83D40", "textColor": "#000000", "shape": "circle" },
    "shiftStage": { "color": "#3385F0", "outline": "#3385F0", "textColor": "#000000", "shape": "pentagon" },
    "otherStage": {
      "color": "#F2B326",
      "outline": "#F2B326",
      "textColor": "#000000",
      "shape": "roundedRectangle"
    }
  }
}
```

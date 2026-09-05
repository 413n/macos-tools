# NAF Tools

macOS menu-bar app. SwiftUI inside an AppKit `NSStatusItem` + `NSPopover`. No Dock icon (`LSUIElement`).

## UI style — Control Center modules

Mimic **macOS Control Center**. Stay on SwiftUI + AppKit. Do not add a third-party widget kit (MacControlCenterUI, web component libraries, etc.).

### Shell

- Panel background: `.regularMaterial`. Follow system light/dark. Do not force `colorScheme` or `NSAppearance.darkAqua`.
- Width ~300pt. Padding 14. 2-column grid, 10pt gutters.
- Home is a **grid of squares**. Each tile: icon, short name, status. No extra copy.
- Tap a tile → detail (where the tool is used). Gear (top right) → Settings. Chevron → home. Closing the popover resets to home.

### Modules

- Corner radius 16, inner padding 12 (`Radius.tile` / `tilePadding`).
- **Off / informational:** `Color.primary.opacity(0.08)` fill, `.primary` content.
- **On:** fill the whole tile with the module color, white content.
- Keyboard: `Color.orange`
- Scroll: `Color.accentColor`
- Lid Sleep: `Color.purple`
- Awake: `Color.brown`
- This Mac: always informational (never an On fill). Show **CPU and RAM** on the tile.
- Status on toggle tiles is `On` / `Off` (keyboard lock On = locked). Awake shows remaining time when a duration is set.
- Press: `scale(0.96)`, 150ms, `cubic-bezier(0.2, 0, 0, 1)`.
- Icons: outline when off, fill when on; cross-fade (scale 0.25→1, opacity, blur 4→0).

### Chrome and details

- Back/settings: 28pt **circles**, same off-fill, system icons. No custom drop shadows.
- Type: system SF Pro. Titles semibold 12–15. Secondary labels `.secondary`. Tabular numbers on stats.
- Details/settings: grouped wells `Color.primary.opacity(0.06)`, radius 16.
- Controls: native `Toggle` + `.switch` + `.small`. Not custom rocker switches. Not checkboxes.
- Tokens live in `Sources/Theme.swift` (`Radius`, `Motion`, `ModuleColor`). Reuse them.

### Don’t

- Workshop/copper palettes, serif wordmarks, tinted card borders for depth, or forced dark popovers.
- Extra description text on home tiles.

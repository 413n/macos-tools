# Yeobun

macOS menu-bar app by N6 Studio. SwiftUI inside an AppKit `NSStatusItem` + `NSPopover`. No Dock icon (`LSUIElement`).

Agents should drive tools with the `yeobun` CLI (`yeobun --help`, `--json`), not by clicking the popover. GUI rules below apply only to the panel.

## UI style — Control Center modules

Mimic **macOS Control Center**. Stay on SwiftUI + AppKit. Do not add a third-party widget kit (MacControlCenterUI, web component libraries, etc.).

### Shell

- Panel background: `.regularMaterial`. Follow system light/dark. Do not force `colorScheme` or `NSAppearance.darkAqua`.
- Width ~300pt. Padding 18. 2-column grid, 10pt gutters.
- Home is a **grid of squares** split into **Tools** and **Stats** tabs. The selected tab is persisted. Each tile: icon in a circle, short name, status. No extra copy.
- Tap the icon circle → toggle the tool with current options. Tap the rest of the tile → detail. Gear (top right) → Settings. Pencil (left of gear) → edit home (hide, show, drag to reorder). Checkmark → done. Chevron → home. Closing the popover resets to home (the last tab stays).

### Modules

- Corner radius 16, inner padding 12 (`Radius.tile` / `tilePadding`).
- **Off / informational:** `Color.primary.opacity(0.08)` fill, `.primary` content.
- **On:** fill the whole tile with the module color, white content. The icon circle is a white 22% disk.
- Keyboard: `Color.orange`
- Scroll: `Color.accentColor`
- Lid Sleep: `Color.purple`
- Awake: `Color.brown`
- This Mac: always informational (never an On fill). Show **CPU and RAM** on the tile.
- Battery, Network, Storage: always informational. Battery warns when charge is low; Storage warns when the disk is full.
- Status on toggle tiles is `On` / `Off` (keyboard lock On = locked). Awake shows remaining time when a duration is set.
- Hover: brighten the tile fill (`offFillHover`, or a white wash when On). Icon circles brighten and scale to `1.06`. Press: `scale(0.96)`, 150ms, `cubic-bezier(0.2, 0, 0, 1)`.
- Icons: outline when off, fill when on; cross-fade (scale 0.25→1, opacity, blur 4→0). Sit in a 30pt circle (`Radius.glyph`). Off disk `primary.opacity(0.14)`; on disk white 22% over the module fill.

### Chrome and details

- Back/settings: 28pt **circles**, same off-fill, system icons. No custom drop shadows.
- Type: system SF Pro. Titles semibold 12–15. Secondary labels `.secondary`. Tabular numbers on stats.
- Details/settings: grouped wells `Color.primary.opacity(0.06)`, radius 16.
- Controls: native `Toggle` + `.switch` + `.small`. Not custom rocker switches. Not checkboxes.
- Tokens live in `Sources/App/Theme.swift` (`Radius`, `Motion`, `ModuleColor`). Reuse them.

### Don’t

- Workshop/copper palettes, serif wordmarks, tinted card borders for depth, or forced dark popovers.
- Extra description text on home tiles.

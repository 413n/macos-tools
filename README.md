# NAF Tools

A macOS menu-bar workbench for a few small input utilities. It lives in the
status bar, launches at login by default, and does not show a Dock icon.

## Tools

### Keyboard lock

Disables the MacBook's **built-in keyboard** while leaving the trackpad, any
external keyboard, Touch ID, and the power button working.

This is the same `hidutil` UserKeyMapping approach as
[`~/Code/keyboard-lock`](../keyboard-lock): every HID keyboard usage on the
internal keyboard is remapped to "no event" for the current boot. A reboot or
logout always restores the keys, so you cannot lock yourself out.

Optional auto-unlock after 5–60 minutes is a dead-man's switch for wiping the
keyboard down. Sleep/wake can drop the mapping; the app re-applies it if the
lock was still on.

### Scroll reverse

macOS has one system-wide Natural Scrolling switch. When this tool is on, **mouse
wheel** (and Magic Mouse) scrolling is reversed so a mouse feels classic while
the trackpad stays natural.

Requires **Accessibility** permission (System Settings → Privacy & Security →
Accessibility). The panel will prompt if it is missing.

### Lid sleep

Keeps the Mac awake on **battery** when the lid is closed — the same `pmset`
calls as the `lid-sleep-off` / `lid-sleep-on` functions in `~/.zshrc`:

```sh
sudo pmset -b sleep 0
sudo pmset -b disablesleep 1
```

Turning the tile Off restores battery sleep to 60 minutes and `disablesleep 0`.

The first toggle asks for an administrator password once. That installs a
narrow `/etc/sudoers.d/naf-tools-lid-sleep` rule so later On/Off switches do
not prompt. The flag is system-wide for battery power and stays until you turn
it off; quitting the app does not restore sleep. A closed MacBook with nowhere
to dump heat can get hot — switch it off when you are done.

## Persistence

Each tool remembers the last On/Off you chose. Opening the app again restores
that choice:

- **Keyboard lock** is re-applied for the rest of this boot. A reboot always
  unlocks the keys (so you cannot lock yourself out). Auto-unlock, if set, keeps
  running after Quit.
- **Scroll reverse** is an event tap in this process, so it is started again
  from the saved per-mouse switches.
- **Lid sleep** lives in `pmset`. The tile reads the real setting on launch.

Settings → **Check status** reads each tool from the Mac and restores anything
that dropped (sleep can clear a keyboard mapping; Accessibility can disable the
scroll tap).

## Install

```sh
./build.sh
open ~/Applications/NAF\ Tools.app
```

Look for the N logo in the menu bar. Click it to open the panel. Drag the icon
leftward in the menu bar if macOS tucks it behind the extra-items chevron.

The first build is ad-hoc signed. If Gatekeeper blocks it, right-click the app
→ Open.

## Notes

- Keyboard lock needs no extra permission.
- Scroll reverse needs Accessibility because it installs a session event tap.
- Lid sleep asks for an administrator password once, then toggles without prompting.
- Open at login can be turned off from the panel.
- Opening the panel shows this Mac's live CPU and memory (sampled only while
  the menu is open).

# Layout Planner

A widget for planning base layouts in game. Draw buildings and lines on the map, save layouts to slots, load and place them again later, and render them as map marker lines so your team can see them.

## Usage

- Click "Enable Layout Draw", then use the **left mouse button** to place buildings of the selected size (Small, Square, Big, Large or Chunk). Hold **Alt** to fill an area, or **Ctrl+Alt** to trace its outline instead.
- Use the **right mouse button** to draw lines; hold **Alt** to remove the lines you cross.
- **Ctrl+Z** / **Ctrl+A** undo / redo.
- **W A S D** shift the whole layout (when "Shift Layout" is enabled).
- Save a layout to a slot with a "Save" button, and load it with the matching "Load" button. Before placing a loaded layout, press **R** to rotate it or **I** to invert it. Hold **Alt** while placing to merge it with the current layout instead of replacing it.
- "Render" draws the layout as map marker lines. Turn off "Auto Erase Map Marks" (Settings → Interface) so they stay; the "Auto Erase Reminder" button tells your team about it in chat.
- Hover "DON'T PANIC!" in the widget's window for the in-game help.

## Settings and saved layouts

The default settings ship with the widget as `layout-planner-config-default.txt`. Don't edit it: the widget saves your settings and window position to `[...]\Beyond-All-Reason\data\LuaUI\Config\layout-planner\layout-planner-config.txt`, which overrides the default when it exists.

Saved layouts go to the same folder as `layout_<slot>.txt`.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\layout-planner` folder and enable the "Layout Planner" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\layout-planner" -Target "$PWD\src\layout-planner"
```

```bash
# Linux
ln -s "$PWD/src/layout-planner" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/layout-planner"
```

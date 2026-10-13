# Build Orders

A widget that takes control of constructors to make sure specific "priority" buildings get built exactly where you place them. If something on the "eraseable" list is in the way, nearby construction turrets reclaim it first. It's disabled while spectating.

## How it works

- Enable it with the "Enable Build Order" checkbox in the widget's window, then place a priority building as usual (drag to place a line or, with Alt, a rectangle).
- Hold **Space** while placing to split the placements between all selected constructors that can build it. The others guard them.
- Hold **Shift** to add more of the same building to an existing build order.
- Press **N** to skip the current building of the selected constructors.
- If the build spot is blocked by eraseable units, construction turrets in range reclaim them. With no turrets in range it stalls. Placements blocked by anything else are skipped.
- With Repeat mode on, a priority building destroyed before it is finished is placed again at the same spot.
- Works with [Holo Place](../holo-place): the constructors move on to the next building once the current one reaches the Holo Place threshold.

Some notes:

- A unit can be both priority and eraseable, so Build Orders can reclaim other priority buildings too.
- Construction turrets are both priority and eraseable by default, but a turret can't erase turrets of the same or a higher tier.
- A constructor can't reclaim itself.

## Custom lists

The default lists and settings ship with the widget as `build-orders-priority-default.txt`, `build-orders-eraseable-default.txt` and `build-orders-config-default.txt`. Don't edit these: override them in `[...]\Beyond-All-Reason\data\LuaUI\Config\build-orders\` instead. When an override exists, the widget uses it instead of the default:

- `build-orders-priority.txt` / `build-orders-eraseable.txt` - unit def names, one per line or comma-separated; lines starting with `#` are comments. Click "Open Config" in the widget's window and use "Create Custom Priority File" / "Create Custom Eraseable File" to start from a copy of the defaults.
- `build-orders-config.txt` - the settings from the config panel and the window position. The widget writes this file itself every time it saves.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\build-orders` folder and enable the "Build Orders" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\build-orders" -Target "$PWD\src\build-orders"
```

```bash
# Linux
ln -s "$PWD/src/build-orders" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/build-orders"
```

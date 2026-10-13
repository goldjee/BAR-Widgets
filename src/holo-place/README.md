# Holo Place

A widget that lets builders move on to their next queued building while nearby nano turrets finish the current one. When a selected builder starts a building, the best nano turret in range is told to assist it. The builder then skips ahead once the build reaches the threshold for the current mode.

To pick the nano turret, the widget prefers ones that are closer, idle, and have shorter queues. It only uses turrets that are on a Fight command and aren't waiting.

## Modes

Click the "Holo" button in the order menu to cycle through the modes:

- **Holo off** - disabled
- **Holo Smart** - picks the threshold from the nano/builder speed ratio (20-50%) (default)
- **Holo 90 / 60 / 30** - skip ahead at 90%, 60% or 30% build progress
- **Holo Ins** - skip ahead as soon as the nano starts assisting

Press `Ctrl+Shift+'` to toggle the selected builders between off and the last active mode. The `holo_place` action can be bound to a hotkey; it applies the current mode to the selected builders.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\holo-place` folder and enable the "Holo Place" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\holo-place" -Target "$PWD\src\holo-place"
```

```bash
# Linux
ln -s "$PWD/src/holo-place" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/holo-place"
```

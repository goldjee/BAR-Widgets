# Reclaim Selected

A widget that adds a "Reclaim Selected" button to the order menu. Pressing it makes every nano turret in range reclaim the selected units. By default the turrets are shuffled and spread across the selected units, so large selections are reclaimed in parallel.

Also available as actions for hotkey binding: `reclaim_selected` (every nearby turret reclaims each selected unit in turn) and `reclaim_selected_shuffle` (the same as the button).

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\reclaim-selected` folder and enable the "Reclaim Selected" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\reclaim-selected" -Target "$PWD\src\reclaim-selected"
```

```bash
# Linux
ln -s "$PWD/src/reclaim-selected" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/reclaim-selected"
```

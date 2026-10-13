# Raptor Grid Draw (Full Metal Plate)

A widget that draws evenly divided build zones for 12 players on the Full Metal Plate map, using map marker lines. The lines are drawn once at game start, a few at a time to stay under the engine's marker spam limit. The widget then removes itself.

It only runs in Raptors or Scavengers games on "Full Metal Plate 1.7", and not while spectating.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\raptor-fmp-grid-draw` folder and enable the "Raptor Grid Draw 12 players (Full Metal Plate)" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\raptor-fmp-grid-draw" -Target "$PWD\src\raptor-fmp-grid-draw"
```

```bash
# Linux
ln -s "$PWD/src/raptor-fmp-grid-draw" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/raptor-fmp-grid-draw"
```

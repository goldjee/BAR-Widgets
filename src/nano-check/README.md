# Construction Turrets Range Check

A widget that stops construction turrets from being assigned to targets out of their reach. When you give selected turrets a repair, guard, reclaim or attack order, it checks their queues shortly afterwards. Any order whose target is out of build range is removed, and turrets left with nothing in range are stopped.

Works with every stationary builder, including Legion and T3 construction turrets. It's disabled while spectating.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\nano-check` folder and enable the "Construction Turrets Range Check" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\nano-check" -Target "$PWD\src\nano-check"
```

```bash
# Linux
ln -s "$PWD/src/nano-check" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/nano-check"
```

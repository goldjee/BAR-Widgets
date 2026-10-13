# Raptor Notifications

A widget that provides notifications for raptor-related events. It alerts players in team chat pointing out crucial timings in the game.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\raptor-notifications` folder and enable the "Raptor Notifications" widget from the in-game settings menu.

Alternatively, clone this repository and symlink the folder, so `git pull` keeps it up to date (see the [main README](../../README.md#install-with-git-and-a-symlink)). From the repository root:

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\raptor-notifications" -Target "$PWD\src\raptor-notifications"
```

```bash
# Linux
ln -s "$PWD/src/raptor-notifications" "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/raptor-notifications"
```

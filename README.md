# BAR-Widgets
A collection of tweaks for Beyond All Reason RTS

## How to install
Select a widget from `./src` and download its folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\` folder. You can also automate the download/update process with a batch script. The example can be found at the root of this repository.

Widgets used to be published under `./dist`. If your update script downloads from there, point it at `./src` instead.

### Install with git and a symlink

Clone the repository anywhere and link the widget folders into BAR, so a `git pull` updates them. The commands assume the default install location; adjust the path if yours differs. Most widgets go into `LuaUI/Widgets`, but `raptor-panel` goes into `LuaUI/RmlWidgets` (each widget's README has the exact command).

Windows (PowerShell). A junction doesn't need admin rights, unlike a symlink:

```powershell
git clone https://github.com/goldjee/BAR-Widgets.git
cd BAR-Widgets
$widgets = "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets"
New-Item -ItemType Junction -Path "$widgets\nano-check" -Target "$PWD\src\nano-check"
```

Linux:

```bash
git clone https://github.com/goldjee/BAR-Widgets.git
cd BAR-Widgets
widgets="$HOME/.local/state/Beyond All Reason/LuaUI/Widgets"
ln -s "$PWD/src/nano-check" "$widgets/nano-check"
```

Repeat the last line for each widget you want. To remove a widget, delete the link (not the folder it points to): `Remove-Item "$widgets\nano-check"` on Windows, `rm "$widgets/nano-check"` on Linux.

If you have downloaded the widget while the game was already running, type `/luaui reload` in the in-game chat to reload all widgets. Then, open the settings menu and enable the widget in "Custom" tab.

echo off
rem BAR Widgets update

set base_path=path_to_your_BAR_installation\Beyond-All-Reason\data\LuaUI\Widgets

rem Harmony Library
set widget_dir=harmony

set file_name=harmony.lua
set download_url=https://raw.githubusercontent.com/goldjee/BAR-Widgets/refs/heads/main/harmony/harmony.lua
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%widget_dir%\%file_name%'"

set file_name=harmony-raptor.lua
set download_url=https://raw.githubusercontent.com/goldjee/BAR-Widgets/refs/heads/main/harmony/harmony-raptor.lua
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%widget_dir%\%file_name%'"

rem Raptor Panel
set widget_dir=raptor-panel

set file_name=raptor-panel.lua
set download_url=https://raw.githubusercontent.com/goldjee/BAR-Widgets/refs/heads/main/raptor-panel/raptor-panel.lua
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%widget_dir%\%file_name%'"

set file_name=raptor-panel.rcss
set download_url=https://raw.githubusercontent.com/goldjee/BAR-Widgets/refs/heads/main/raptor-panel/raptor-panel.rcss
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%widget_dir%\%file_name%'"

set file_name=raptor-panel.rml
set download_url=https://raw.githubusercontent.com/goldjee/BAR-Widgets/refs/heads/main/raptor-panel/raptor-panel.rml
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%widget_dir%\%file_name%'"

echo Update finished
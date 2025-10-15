echo off
rem BAR Widgets update

set base_path=path_to_your_BAR_installation\Beyond-All-Reason\data\LuaUI\Widgets

rem Change the following two lines to match the file you want to download
set file_name=file_to_download.lua
set download_url=url_of_the_raw_file_from_github.lua
powershell -Command "Invoke-WebRequest -Uri '%download_url%' -OutFile '%base_path%\%file_name%'"

echo Update finished
-- Harmony - Shared utility library for BAR widgets
-- Usage: local harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')

local harmony = {}

-- Returns current game time in seconds
function harmony.getTime()
	return Spring.GetGameSeconds()
end

return harmony
-- Harmony - Shared utility library for BAR widgets
-- Usage: local harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')

local harmony = {}

-- Player name cache
local cachedPlayerNames = {}

-- Returns current game time in seconds
function harmony.getTime()
	return Spring.GetGameSeconds()
end

-- Returns player or AI name for a given team ID (with caching)
function harmony.getPlayerName(teamID)
	-- Return cached name if available
	if cachedPlayerNames[teamID] then
		return cachedPlayerNames[teamID]
	end

	local playerName = ''
	local playerList = Spring.GetPlayerList(teamID)

	if playerList and #playerList > 0 then
		if #playerList == 1 then
			playerName = select(1, Spring.GetPlayerInfo(playerList[1]))
		else
			-- Multiple players on same team
			local names = {}
			for _, player in ipairs(playerList) do
				if player then
					local name = select(1, Spring.GetPlayerInfo(player))
					if name then
						names[#names + 1] = name
					end
				end
			end
			playerName = table.concat(names, ' & ')
		end
	else
		-- Try AI name
		_, playerName = Spring.GetAIInfo(teamID)
	end

	-- Cache the name
	if playerName and playerName ~= '' then
		cachedPlayerNames[teamID] = playerName
	end

	return playerName or ''
end

return harmony
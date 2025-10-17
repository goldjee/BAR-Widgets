-- Raptor Harmony - Shared utility library for raptor game mode widgets
-- Usage: local RaptorHarmony = VFS.Include('LuaUI/Widgets/raptor-harmony/harmony-raptor.lua')

local harmonyRaptor = {}

local harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')

local gameInfo = {}
local rules = {
	'raptorDifficulty',
	'raptorGracePeriod',
	'scavBossAnger',
	'raptorQueenAnger',
	'RaptorQueenAngerGain_Aggression',
	'RaptorQueenAngerGain_Base',
	'RaptorQueenAngerGain_Eco',
	'raptorQueenHealth',
	'raptorQueensKilled',
	'raptorQueenTime',
	'raptorTechAnger',
}
local nilDefaultRules = {
	['raptorQueensKilled'] = true,
}

-- Returns true if current game mode is Raptors
function harmonyRaptor.isRaptors()
	return Spring.Utilities.Gametype.IsRaptors()
end

-- Returns true if player is spectating or watching a replay
function harmonyRaptor.isSpectating()
	return Spring.GetSpectatingState() or Spring.IsReplay()
end

local function updateRules()
	for i = 1, #rules do
		local rule = rules[i]
		gameInfo[rule] = Spring.GetGameRulesParam(rule) or (nilDefaultRules[rule] and nil or 0)
	end
end

-- Updates and returns table containing all raptor game rules
function harmonyRaptor.getGameInfo()
	updateRules()
	return gameInfo
end

-- Returns current game stage: "grace", "main", or "boss"
function harmonyRaptor.getRaptorStage()
	local stage = "grace"
	if harmony.getTime() > gameInfo.raptorGracePeriod then
		if (gameInfo.raptorQueenAnger < 100) then
			stage = "main"
		else
			stage = "boss"
		end
	end
	return stage
end

-- Returns time remaining in grace period (in seconds)
function harmonyRaptor.getGraceElapsedTime()
    return (((harmony.getTime() - gameInfo.raptorGracePeriod) * -1) - 0.5)
end

-- Returns queen hatch progress as percentage (0-100)
function harmonyRaptor.getQueenHatchProgress()
    return math.min(100, math.floor(0.5 + gameInfo.raptorQueenAnger))
end

-- ========================================
-- Mini Boss Detection Functions
-- ========================================

-- Mini boss data tables
local miniBossNames = {
	raptor_miniq_a = "Queenling Prima",
	raptor_miniq_b = "Queenling Secunda",
	raptor_miniq_c = "Queenling Tertia",
	raptor_mama_ba = "Matrona",
	raptor_mama_fi = "Pyro Matrona",
	raptor_mama_el = "Paralyzing Matrona",
	raptor_mama_ac = "Acid Matrona",
	raptor_consort = "Raptor Consort",
	raptor_doombringer = "Doombringer",
}

local miniBossDescriptions = {
	raptor_miniq_a = "Majestic and bold, ruler of the hunt.",
	raptor_miniq_b = "Swift and sharp, a noble among raptors.",
	raptor_miniq_c = "Refined tastes. Likes her prey rare.",
	raptor_mama_ba = "Claws charged with vengeance.",
	raptor_mama_fi = "A firestorm of maternal wrath.",
	raptor_mama_el = "Crackling with rage, ready to strike.",
	raptor_mama_ac = "Acid-fueled, melting everything in sight.",
	raptor_consort = "Sneaky powerful little terror.",
	raptor_doombringer = "Your time is up. The Queens called for backup.",
}

-- Returns table with all mini boss definitions
function harmonyRaptor.getMiniBossInfo()
	return {
		names = miniBossNames,
		descriptions = miniBossDescriptions
	}
end

-- Returns display name for a mini boss unit (or nil if not a mini boss)
function harmonyRaptor.getMiniBossName(unitDefName)
	return miniBossNames[unitDefName]
end

-- Returns description for a mini boss unit (or nil if not a mini boss)
function harmonyRaptor.getMiniBossDescription(unitDefName)
	return miniBossDescriptions[unitDefName]
end

-- Returns true if the given unit def name is a mini boss
function harmonyRaptor.isMiniBoss(unitDefName)
	return miniBossNames[unitDefName] ~= nil
end

-- Returns true if the given unit def name is a Queenling
function harmonyRaptor.isQueenling(unitDefName)
	return unitDefName and (unitDefName:find("raptor_miniq_") ~= nil)
end

-- ========================================
-- Grace Period Utilities
-- ========================================

-- Returns time remaining in grace period (in seconds), or 0 if grace period has ended
function harmonyRaptor.getGraceTimeRemaining()
	local remaining = gameInfo.raptorGracePeriod - harmony.getTime()
	return math.max(0, remaining)
end

-- Formats time in seconds to human-readable format ("12 minutes", "5m 30s", "45 seconds")
function harmonyRaptor.formatGraceTime(seconds)
	if seconds <= 0 then
		return "0 seconds"
	end

	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)

	if minutes > 0 and secs > 0 then
		return minutes .. "m " .. secs .. "s"
	elseif minutes > 0 then
		return minutes .. " minute" .. (minutes > 1 and "s" or "")
	else
		return secs .. " seconds"
	end
end

-- Returns true if currently in grace period
function harmonyRaptor.isInGracePeriod()
	return harmonyRaptor.getRaptorStage() == "grace"
end

-- ========================================
-- Tech Anger & Threat Detection
-- ========================================

-- Returns current tech anger level (0-100+)
function harmonyRaptor.getTechAnger()
	return gameInfo.raptorTechAnger or 0
end

-- Returns nuke warning level: "none", "warning", or "critical"
-- Based on tech anger thresholds used in gui_raptor_nuke_warning.lua
function harmonyRaptor.getNukeWarningLevel()
	local techAnger = harmonyRaptor.getTechAnger()
	local isScavengers = Spring.Utilities.Gametype.IsScavengers()

	if techAnger < (isScavengers and 50 or 65) then
		return "none"
	elseif techAnger < (isScavengers and 85 or 90) then
		return "warning"
	else
		return "critical"
	end
end

-- Returns true if nuke warning should be displayed (based on nuke warning widget logic)
-- Checks: no anti-nuke, tech anger in warning range, sufficient energy storage
function harmonyRaptor.shouldShowNukeWarning(hasAntiNuke, teamID)
	if hasAntiNuke then
		return false
	end

	local warningLevel = harmonyRaptor.getNukeWarningLevel()
	if warningLevel ~= "warning" then
		return false
	end

	-- Check if team has enough energy storage to be at risk
	if teamID then
		local _, _, _, energyStorage = Spring.GetTeamResources(teamID, 'energy')
		if energyStorage and energyStorage < 1000 then
			return false
		end

		local unitCount = Spring.GetTeamUnitCount(teamID)
		if unitCount and unitCount <= 3 then
			return false
		end
	end

	return true
end

-- ========================================
-- Queen/Boss Information
-- ========================================

-- Returns estimated time until queen spawns (in seconds), or 0 if already spawned
function harmonyRaptor.getQueenETA()
	if harmonyRaptor.getRaptorStage() ~= "main" then
		return 0
	end

	local currentAnger = gameInfo.raptorQueenAnger or 0
	local gainRate = harmonyRaptor.getAngerGainRate()

	if gainRate <= 0 then
		return 999999  -- Infinite time if no anger gain
	end

	local angerRemaining = 100 - currentAnger
	return angerRemaining / gainRate
end

-- Returns number of queens/bosses configured for this match
function harmonyRaptor.getBossCount()
	local modOptions = Spring.GetModOptions()
	return modOptions.raptor_queen_count or 1
end

-- Returns current queen health percentage (0-100), or 0 if queen not spawned
function harmonyRaptor.getQueenHealth()
	if harmonyRaptor.getRaptorStage() ~= "boss" then
		return 0
	end
	return gameInfo.raptorQueenHealth or 0
end

-- Returns number of queens killed, or nil if not tracked
function harmonyRaptor.getQueensKilled()
	return gameInfo.raptorQueensKilled
end

-- ========================================
-- Team & Player Utilities
-- ========================================

-- Returns the Raptors/Gaia team ID
function harmonyRaptor.getRaptorsTeamID()
	-- Check all teams for Raptors LuaAI
	local teamIDs = Spring.GetTeamList()
	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local teamLuaAI = Spring.GetTeamLuaAI(teamID)
		if teamLuaAI and teamLuaAI:find('Raptors') then
			return teamID
		end
	end

	-- Fallback to Gaia team
	return Spring.GetGaiaTeamID()
end

-- Returns true if the given unit belongs to the Raptors team
function harmonyRaptor.isRaptorUnit(unitID)
	if not unitID then
		return false
	end

	local unitTeam = Spring.GetUnitTeam(unitID)
	if not unitTeam then
		return false
	end

	return unitTeam == harmonyRaptor.getRaptorsTeamID()
end

-- Returns list of player team IDs (excluding Raptors/Scavengers/Gaia)
function harmonyRaptor.getPlayerTeams()
	local teamIDs = Spring.GetTeamList()
	local playerTeams = {}
	local raptorsTeam = harmonyRaptor.getRaptorsTeamID()

	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local teamLuaAI = Spring.GetTeamLuaAI(teamID)

		-- Exclude Raptors, Scavengers, and teams with no players
		if teamID ~= raptorsTeam then
			if not teamLuaAI or (not teamLuaAI:find('Raptors') and not teamLuaAI:find('Scavengers')) then
				playerTeams[#playerTeams + 1] = teamID
			end
		end
	end

	return playerTeams
end

-- ========================================
-- Anger Breakdown Functions
-- ========================================

-- Returns total anger gain rate per second
function harmonyRaptor.getAngerGainRate()
	local base = gameInfo.RaptorQueenAngerGain_Base or 0
	local eco = gameInfo.RaptorQueenAngerGain_Eco or 0
	local aggression = gameInfo.RaptorQueenAngerGain_Aggression or 0
	return base + eco + aggression
end

-- Returns table with anger gain components
function harmonyRaptor.getAngerComponents()
	return {
		base = gameInfo.RaptorQueenAngerGain_Base or 0,
		eco = gameInfo.RaptorQueenAngerGain_Eco or 0,
		aggression = gameInfo.RaptorQueenAngerGain_Aggression or 0,
		total = harmonyRaptor.getAngerGainRate()
	}
end

return harmonyRaptor
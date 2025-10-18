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
	updateRules()
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
	updateRules()
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
	updateRules()
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

-- Returns boss/queen information including resistances, player damages, and health status
-- Returns a table with guaranteed structure (empty arrays if no boss data available):
-- {
--   resistances = {{name, percent, damage}, ...},
--   playerDamages = {{name, damage, relative}, ...},
--   healths = {{id, health, maxHealth, percentage}, ...}
-- }
function harmonyRaptor.getBossInfo()
	local result = {
		resistances = {},
		playerDamages = {},
		healths = {}
	}

	local bossInfoRaw = Spring.GetGameRulesParam('pveBossInfo')
	if not bossInfoRaw then
		return result
	end

	-- Safely decode JSON with error handling
	local success, decoded = pcall(Json.decode, bossInfoRaw)
	if not success or not decoded then
		Spring.Echo("Harmony Raptor: Failed to decode boss info JSON")
		return result
	end

	bossInfoRaw = decoded

	-- Process resistances
	for defID, resistance in pairs(bossInfoRaw.resistances or {}) do
		if resistance.percent >= 0.1 then
			local name = UnitDefs[tonumber(defID)].translatedHumanName
			table.insert(result.resistances, {
				name = name,
				percent = resistance.percent,
				damage = resistance.damage
			})
		end
	end
	table.sort(result.resistances, function(a, b) return a.damage > b.damage end)

	-- Process player damages
	local totalDamage = 0
	for _, damage in pairs(bossInfoRaw.playerDamages or {}) do
		totalDamage = totalDamage + damage
	end

	for teamID, damage in pairs(bossInfoRaw.playerDamages or {}) do
		local name = harmony.getPlayerName(teamID)
		table.insert(result.playerDamages, {
			name = name,
			damage = damage,
			relative = damage / math.max(totalDamage, 1)
		})
	end
	table.sort(result.playerDamages, function(a, b) return a.damage > b.damage end)

	-- Process boss healths
	for queenID, status in pairs(bossInfoRaw.statuses or {}) do
		if not status.isDead and status.health > 0 then
			table.insert(result.healths, {
				id = tonumber(queenID),
				health = status.health,
				maxHealth = status.maxHealth,
				percentage = (status.health / status.maxHealth) * 100
			})
		end
	end
	table.sort(result.healths, function(a, b) return a.percentage < b.percentage end)

	return result
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

-- ========================================
-- Eco Value Calculation (Raptor Targeting)
-- ========================================

-- Check if unit is an object (not counted for eco value)
local isObject = {}
for udefID, def in ipairs(UnitDefs) do
	if def.modCategories['object'] or def.customParams.objectify then
		isObject[udefID] = true
	end
end

-- Calculate eco attraction value for a unit definition
local function calculateEcoValueForDef(unitDef)
	if (unitDef.canMove and not (unitDef.customParams and unitDef.customParams.iscommander)) or isObject[unitDef.name] then
		return 0
	end

	local ecoValue = 1
	if unitDef.energyMake then
		ecoValue = ecoValue + unitDef.energyMake
	end
	if unitDef.energyUpkeep and unitDef.energyUpkeep < 0 then
		ecoValue = ecoValue - unitDef.energyUpkeep
	end
	if unitDef.windGenerator then
		ecoValue = ecoValue + unitDef.windGenerator * 0.75
	end
	if unitDef.tidalGenerator then
		ecoValue = ecoValue + unitDef.tidalGenerator * 15
	end
	if unitDef.extractsMetal and unitDef.extractsMetal > 0 then
		ecoValue = ecoValue + 200
	end

	if unitDef.customParams then
		if unitDef.customParams.energyconv_capacity then
			ecoValue = ecoValue + tonumber(unitDef.customParams.energyconv_capacity) / 2
		end
		if unitDef.customParams.decoyfor == 'armfus' then
			ecoValue = ecoValue + 1000
		end
		if unitDef.customParams.techlevel and tonumber(unitDef.customParams.techlevel) > 1 then
			ecoValue = ecoValue * tonumber(unitDef.customParams.techlevel) * 2
		end
		if unitDef.customParams.unitgroup == 'antinuke' or unitDef.customParams.unitgroup == 'nuke' then
			ecoValue = 1000
		end
	end

	return ecoValue
end

-- Cached eco values by unitDefID
local defIDsEcoValues = nil

-- Initialize eco value cache (call once at startup)
function harmonyRaptor.initEcoValueCache()
	if defIDsEcoValues then
		return defIDsEcoValues
	end

	defIDsEcoValues = {}
	for unitDefID, unitDef in pairs(UnitDefs) do
		local ecoValue = calculateEcoValueForDef(unitDef) or 0
		if ecoValue > 0 then
			defIDsEcoValues[unitDefID] = ecoValue
		end
	end
	return defIDsEcoValues
end

-- Returns eco value for a unit def ID (uses cache)
function harmonyRaptor.getUnitEcoValue(unitDefID)
	if not defIDsEcoValues then
		harmonyRaptor.initEcoValueCache()
	end
	return defIDsEcoValues[unitDefID] or 0
end

-- Update player eco values when units are created/destroyed
-- playerEcoTable: table of {teamID = ecoValue}
-- unitDefID: the unit def ID
-- teamID: the team owning the unit
-- isAdd: true to add, false to subtract
function harmonyRaptor.updatePlayerEcoValues(playerEcoTable, unitDefID, teamID, isAdd)
	if not playerEcoTable[teamID] then
		return
	end

	local ecoValue = harmonyRaptor.getUnitEcoValue(unitDefID)
	if ecoValue > 0 then
		if isAdd then
			playerEcoTable[teamID] = playerEcoTable[teamID] + ecoValue
		else
			playerEcoTable[teamID] = playerEcoTable[teamID] - ecoValue
		end
	end
end

return harmonyRaptor
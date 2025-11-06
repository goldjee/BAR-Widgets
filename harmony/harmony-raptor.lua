-- Raptor Harmony - Shared utility library for raptor game mode widgets
-- Usage: local RaptorHarmony = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')

local hr = {}

-- Definitions
-- ========================================

local harmony = require("harmony")

-- Table containing all the information about the game
local gameInfo = {}
local nilDefaultRules = {
	["raptorQueensKilled"] = true,
}

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

-- Main game info functions
-- ========================================

-- Helper to get game rule from the engine
local function getGameRule(key)
	return Spring.GetGameRulesParam(key) or (nilDefaultRules[key] and nil or 0)
end

-- Updates the gameInfo table with the latest game rules parameters
function hr.updateGameInfo()
	-- Main settings
	gameInfo.difficulty = getGameRule("raptorDifficulty")
	gameInfo.gracePeriod = getGameRule("raptorGracePeriod")
	gameInfo.anger = getGameRule("raptorQueenAnger")
	gameInfo.angerTech = getGameRule("raptorTechAnger")
	gameInfo.angerGainAggression = getGameRule("RaptorQueenAngerGain_Aggression")
	gameInfo.angerGainBase = getGameRule("RaptorQueenAngerGain_Base")
	gameInfo.angerGainEco = getGameRule("RaptorQueenAngerGain_Eco")
	gameInfo.queenHealth = getGameRule("raptorQueenHealth")
	gameInfo.queenCountKilled = getGameRule("raptorQueensKilled")
	gameInfo.queenTime = getGameRule("raptorQueenTime")

	local modOptions = Spring.GetModOptions()

	-- Queen count
	gameInfo.queenCount = modOptions.raptor_queen_count or 1

	-- Current raptor stage: "grace", "main", or "boss"
	local stage = nil
	if gameInfo.gracePeriod and gameInfo.anger then
		stage = "grace"
		if harmony.getTime() > gameInfo.gracePeriod then
			if gameInfo.anger < 100 then
				stage = "main"
			else
				stage = "boss"
			end
		end
	end
	gameInfo.stage = stage

	-- Time remaining in grace period (in seconds), or 0 if grace period has ended
	local gracePeriodRemaining = nil
	if gameInfo.gracePeriod then
		gracePeriodRemaining = gameInfo.gracePeriod - harmony.getTime()
		gameInfo.gracePeriodRemaining = math.max(0, gracePeriodRemaining)
	end

	-- Queen hatch progress as a percentage (0-100)
	if gameInfo.anger then
		gameInfo.queenHatchProgress = math.min(100, math.floor(0.5 + gameInfo.anger))
	end

	-- Nuke threat level: "none", "warning", or "critical"
	local nukeThreatLevel = nil
	if gameInfo.angerTech then
		if gameInfo.angerTech < 65 then
			nukeThreatLevel = "none"
		elseif gameInfo.angerTech < 90 then
			nukeThreatLevel = "warning"
		else
			nukeThreatLevel = "critical"
		end
	end
	gameInfo.nukeThreatLevel = nukeThreatLevel
end

-- Returns gameInfo table
function hr.getGameInfo()
	return gameInfo
end

-- Utility functions
-- ========================================

-- Stages of the game and timings
-- ----------------------------------------

-- Returns estimated time until queen spawns (in seconds), or nil if already spawned
function hr.getQueenETA()
	local stage = gameInfo.stage
	if not gameInfo.anger or not stage or stage ~= "main" then
		return nil
	end

	local currentAnger = gameInfo.anger
	local gainRate = gameInfo.angerGainBase + gameInfo.angerGainAggression + gameInfo.angerGainEco

	if gainRate <= 0 then
		return 999999 -- Infinite time if no anger gain
	end

	local angerRemaining = 100 - currentAnger
	return angerRemaining / gainRate
end

-- Unit utilities
-- ----------------------------------------

-- Returns true if the given unit def name is a mini boss
function hr.isMiniBoss(unitDefName)
	return miniBossNames[unitDefName] ~= nil
end

-- Returns true if the given unit def name is a Queenling
function hr.isQueenling(unitDefName)
	return unitDefName and (unitDefName:find("raptor_miniq_") ~= nil)
end

-- Returns boss/queen information including resistances, player damages, and health status
-- Returns a table with guaranteed structure (empty arrays if no boss data available):
-- {
--   resistances = {{name, percent, damage}, ...},
--   playerDamages = {{name, damage, relative}, ...},
--   healths = {{id, health, maxHealth, percentage}, ...}
-- }
function hr.getBossInfo()
	local result = {
		resistances = {},
		playerDamages = {},
		healths = {},
	}

	local bossInfoRaw = Spring.GetGameRulesParam("pveBossInfo")
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
				damage = resistance.damage,
			})
		end
	end
	table.sort(result.resistances, function(a, b)
		return a.damage > b.damage
	end)

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
			relative = damage / math.max(totalDamage, 1),
		})
	end
	table.sort(result.playerDamages, function(a, b)
		return a.damage > b.damage
	end)

	-- Process boss healths
	for queenID, status in pairs(bossInfoRaw.statuses or {}) do
		if not status.isDead and status.health > 0 then
			table.insert(result.healths, {
				id = tonumber(queenID),
				health = status.health,
				maxHealth = status.maxHealth,
				percentage = (status.health / status.maxHealth) * 100,
			})
		end
	end
	table.sort(result.healths, function(a, b)
		return a.percentage < b.percentage
	end)

	return result
end

-- Team & Player Utilities
-- ========================================

-- Returns the Raptors/Gaia team ID
function hr.getRaptorsTeamID()
	-- Check all teams for Raptors LuaAI
	local teamIDs = Spring.GetTeamList()
	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local teamLuaAI = Spring.GetTeamLuaAI(teamID)
		if teamLuaAI and teamLuaAI:find("Raptors") then
			return teamID
		end
	end

	-- Fallback to Gaia team
	return Spring.GetGaiaTeamID()
end

-- Returns true if the given unit belongs to the Raptors team
function hr.isRaptorUnit(unitID)
	if not unitID then
		return false
	end

	local unitTeam = Spring.GetUnitTeam(unitID)
	if not unitTeam then
		return false
	end

	return unitTeam == hr.getRaptorsTeamID()
end

-- Returns list of player team IDs (excluding Raptors/Scavengers/Gaia)
function hr.getPlayerTeams()
	local teamIDs = Spring.GetTeamList()
	local playerTeams = {}
	local raptorsTeam = hr.getRaptorsTeamID()

	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local teamLuaAI = Spring.GetTeamLuaAI(teamID)

		-- Exclude Raptors, Scavengers, and teams with no players
		if teamID ~= raptorsTeam then
			if not teamLuaAI or (not teamLuaAI:find("Raptors") and not teamLuaAI:find("Scavengers")) then
				playerTeams[#playerTeams + 1] = teamID
			end
		end
	end

	return playerTeams
end

-- Eco Value Calculation (Raptor Targeting)
-- ========================================

-- Check if unit is an object (not counted for eco value)
local isObject = {}
for udefID, def in ipairs(UnitDefs) do
	if def.modCategories["object"] or def.customParams.objectify then
		isObject[udefID] = true
	end
end

-- Calculate eco attraction value for a unit definition
local function calculateEcoValueForDef(unitDef)
	if
		(unitDef.canMove and not (unitDef.customParams and unitDef.customParams.iscommander)) or isObject[unitDef.name]
	then
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
		if unitDef.customParams.decoyfor == "armfus" then
			ecoValue = ecoValue + 1000
		end
		if unitDef.customParams.techlevel and tonumber(unitDef.customParams.techlevel) > 1 then
			ecoValue = ecoValue * tonumber(unitDef.customParams.techlevel) * 2
		end
		if unitDef.customParams.unitgroup == "antinuke" or unitDef.customParams.unitgroup == "nuke" then
			ecoValue = 1000
		end
	end

	return ecoValue
end

-- Cached eco values by unitDefID
local defIDsEcoValues = nil

-- Initialize eco value cache (call once at startup)
function hr.initEcoValueCache()
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
function hr.getUnitEcoValue(unitDefID)
	if not defIDsEcoValues then
		hr.initEcoValueCache()
	end
	return defIDsEcoValues[unitDefID] or 0
end

-- Update player eco values when units are created/destroyed
-- playerEcoTable: table of {teamID = ecoValue}
-- unitDefID: the unit def ID
-- teamID: the team owning the unit
-- isAdd: true to add, false to subtract
function hr.updatePlayerEcoValues(playerEcoTable, unitDefID, teamID, isAdd)
	if not playerEcoTable[teamID] then
		return
	end

	local ecoValue = hr.getUnitEcoValue(unitDefID)
	if ecoValue > 0 then
		if isAdd then
			playerEcoTable[teamID] = playerEcoTable[teamID] + ecoValue
		else
			playerEcoTable[teamID] = playerEcoTable[teamID] - ecoValue
		end
	end
end

return hr

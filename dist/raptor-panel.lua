-- luapack bundle v0.1.1 (auto-generated)
local __B_LOADED = {}
local __B_MODULES = {}

local function __B_REQUIRE(name)
  if __B_LOADED[name] ~= nil then
    return __B_LOADED[name] == true and nil or __B_LOADED[name]
  end
  local loader = __B_MODULES[name]
  if loader then
    local res = loader(__B_REQ_TO_PASS)
    __B_LOADED[name] = (res == nil) and true or res
    return res
  end
  error('module not found: ' .. name)
end

__B_REQ_TO_PASS = __B_REQUIRE

-- module: harmony  (from ../harmony/harmony.lua)
__B_MODULES['harmony'] = function(require)
-- Harmony - Shared utility library for BAR widgets
-- Usage: local harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')

local harmony = {}

-- Player name cache
local cachedPlayerNames = {}

-- Returns current game time in seconds
function harmony.getTime()
	return Spring.GetGameSeconds()
end

-- Returns true if player is spectating or watching a replay
function harmony.isSpectating()
	return Spring.GetSpectatingState() or Spring.IsReplay()
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
end

-- module: harmony-raptor  (from ../harmony/harmony-raptor.lua)
__B_MODULES['harmony-raptor'] = function(require)
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
end

-- module: raptor-panel-rcss  (from raptor-panel-rcss.lua)
__B_MODULES['raptor-panel-rcss'] = function(require)
return [[
/* ========================================
   1. BASE STYLES (HTML Elements)
   ======================================== */

body {
    font-family: "Exo 2";
    font-size: 16dp;
}

div {
    display: block;
}

p {
    display: block;
    font-size: 16dp;
}

h1 {
    display: block;
    font-size: 18dp;
}

h2 {
    display: block;
    font-size: 16dp;
}

/* Table elements */
table {
    width: 100%;
    box-sizing: border-box;
    display: table;
    font-size: 14dp;
}

tr {
    box-sizing: border-box;
    display: table-row;
}

td {
    box-sizing: border-box;
    display: table-cell;
}

col {
    box-sizing: border-box;
    display: table-column;
}

colgroup {
    display: table-column-group;
}

thead, tbody, tfoot {
    display: table-row-group;
}

thead tr td {
    text-align: left;
    padding: 4dp 0dp;
    color: #B3B3B3;
    border-bottom: 1dp #ffffff40;
}

tbody tr td {
    padding: 4dp 0dp;
}


/* ========================================
   2. UTILITIES (Single-Purpose Classes)
   ======================================== */

/* Typography utilities */
.font-bold {
    font-weight: 700;
}

.text-sm {
    font-size: 14dp;
}

.text-xl {
    font-size: 18dp;
}

/* Color utilities */
.text-dark {
    color: #4a4a4a;
}

.text-dim {
    color: #B3B3B3;
}

.bg-primary {
    background-color: #FDC04C;
}

/* Semantic color utilities */
.bad {
    color: #FF4D4D;
}

.good {
    color: #4DFF4D;
}

.warning {
    color: #FFCC4D;
}

.neutral {
    color: #CCCCFF;
}


/* ========================================
   3. LAYOUT (Page Structure)
   ======================================== */

#raptor-panel-widget {
    /* positional properties */
    position: absolute;
    top: 120dp;
    right: 10dp;
    /* dimensional properties */
    width: 300dp;
    /* height: 400dp; */
    background: #060606ba;
}

#widget-container {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
}


/* ========================================
   4. COMPONENTS (Reusable UI Parts)
   ======================================== */

/* Debug Controls Component */
.debug-controls {
    position: absolute;
    top: -15dp;
    right: -5dp;
    display: flex;
    gap: 3dp;
    z-index: 10;
}

.debug-btn {
    height: 20dp;
    padding: 0 4dp;
    cursor: pointer;
    text-align: center;
    line-height: 18dp;
    transition: all 0.1s;
}

.debug-btn:hover {
    transform: scale(1.1);
}

.debug-btn:active {
    transform: scale(0.95);
}

/* Header Component */
#widget-header {
    display: flex;
    flex-direction: row;
    justify-content: space-between;

    background-color: #4a4a4aba;
    text-align: center;
    text-transform: uppercase;
    color: white;
    padding: 4dp 8dp;
}

/* Status Panel Component */
#status {
    background-color: #282828ba;
    padding: 8dp 8dp;
}

#status div {
    display: flex;
    flex-direction: column;
    gap: 4dp;
}

/* Tabs Component */
#tab-list {
    display: flex;
    flex-direction: row;
    justify-content: space-between;

    background-color: #333;
}

.tab {
    width: 33.33%;
    cursor: pointer;
    text-align: center;
    text-transform: uppercase;
    padding: 4dp 8dp;
}

.tab:hover {
    color: #ebebeb;
}

/* Tab Content Container */
.tab-content-section {
    padding: 4dp 8dp;
}

/* Tab Panel Component */
.tab-panel h2 {
    margin-bottom: 8dp;
    color: #FFCC4D;
}

/* Progress Bar Component */
.progress-bar {
    width: 100%;
    background-color: #333333;
    height: 6dp;
    border-radius: 6dp;
    position: relative;
    overflow: hidden;
}

.progress-fill {
    background-color: #CCCCCC;  /* Default gray, overridden by color variants */
    height: 100%;
    position: absolute;
    left: 0;
    top: 0;
    transition: width 0.3s;
}

/* Progress bar color variants */
.progress-fill.bad {
    background-color: #FF4D4D;
}

.progress-fill.warning {
    background-color: #FFCC4D;
}

.progress-fill.good {
    background-color: #4DFF4D;
}

.progress-fill.neutral {
    background-color: #CCCCFF;
}

.progress-cell {
    padding-right: 4dp;
}

.progress-cell .progress-bar {
    top: 5dp;
}

/* Boss Health Grid Component */
.boss-health-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 8dp;
    margin-bottom: 12dp;
}

.boss-health-item {
    font-size: 14dp;
    font-weight: bold;
}


/* ========================================
   5. STATE MODIFIERS (Dynamic States)
   ======================================== */

/* Active state for tabs */
.is-active {
    background-color: #4d4d804d;
}

/* Player highlight state */
.is-highlighted {
    background-color: #4D4D804D;
}

/* Threat level states */
.is-threat-high td {
    color: #FF4D4D;
}

.is-threat-medium td {
    color: #FFCC4D;
}

.is-threat-low td {
    color: #4DFF4D;
}

/* Threat level progress bar colors */
.is-threat-high .progress-fill {
    background-color: #FF4D4D;
}

.is-threat-medium .progress-fill {
    background-color: #FFCC4D;
}

.is-threat-low .progress-fill {
    background-color: #4DFF4D;
}
]]
end

-- module: raptor-panel-rml  (from raptor-panel-rml.lua)
__B_MODULES['raptor-panel-rml'] = function(require)
return [[
<rml>
<head>
    <title>raptor-panel Widget</title>

    <!-- Stylesheet -->
    <link rel="stylesheet" href="raptor-panel.rcss" type="text/rcss" />
</head>
<body id="raptor-panel-widget">
    <div id="widget-container" data-model="raptor-panel_model">
        <!-- Small floating debug buttons -->
        <div class="debug-controls" data-if="isDev == true">
            <button class="debug-btn text-dark text-sm font-bold bg-primary" onclick="widget:Reload()" title="Reload Widget">reload</button>
            <button class="debug-btn text-dark text-sm font-bold bg-primary" onclick="widget:ToggleDebugger()" title="Toggle Debugger">debug</button>
        </div>

        <div id="widget-header">
            <p>Raptor Panel</p>
            <p class="neutral">{{difficulty}}</p>
        </div>

        <div id="status">
            <!-- Grace Period Stage -->
            <div data-if="stage == 'grace'">
                <h1>Stage: <span class="good">Grace</span></h1>
                <p>Remaining time: {{gracePeriodRemaining}}</p>
            </div>

            <!-- Main Phase - Queen Anger -->
            <div data-if="stage == 'main'" class="main-phase">
                <h1>Stage: <span class="warning">Hatching</span></h1>
                <p>{{queenCount}} queens, Hatch: {{queenHatchProgress}}%, ETA: {{queenETA}}</p>
                <p class="text-sm text-dim">Rate: +{{angerGainTotal}}/s</p>
                <!-- <p class="text-sm text-dim">Base: {{angerGainBase}}  Eco: {{angerGainEco}}  Aggro: {{angerGainAggression}}</p> -->
                <p>Evolution: {{angerTech}}%</p>
            </div>

            <!-- Boss Phase - Queen Active -->
            <div data-if="stage == 'boss'" class="boss-phase">
                <h1>Stage: <span class="bad">Bosses</span></h1>
                <p>Total health: {{queenHealth}}%<span data-if="queenCountKilled > 0 && queenCount > 1">, Killed: {{queenCountKilled}}/{{queenCount}}</span></p>
                <!-- Progress bar for queen health -->
                <div class="progress-bar">
                    <div class="progress-fill bad" data-style-width="queenHealth + '%'"></div>
                </div>
                <p>Evolution: {{angerTech}}%</p>
            </div>
        </div>

        <div id="tab-list">
            <button class="tab"
                    data-class-is-active="activeTab == 'economy'"
                    onclick="widget:SetTab('economy')">Economy</button>
            <button class="tab"
                    data-class-is-active="activeTab == 'damage'"
                    onclick="widget:SetTab('damage')">Damage</button>
            <button class="tab"
                    data-class-is-active="activeTab == 'queens'"
                    onclick="widget:SetTab('queens')">Queens</button>
        </div>

        <div id="tab-content">
            <!-- Economy Tab -->
            <div id="tab-content-economy" data-if="activeTab == 'economy'" class="tab-panel">
                <div class="tab-content-section">
                    <h2>Player Eco Attractions</h2>

                    <!-- Empty state -->
                    <p data-if="playerEcoDataLength == 0" class="text-dim">No economy data yet</p>

                    <!-- Data table -->
                    <table data-if="playerEcoDataLength > 0">
                        <colgroup>
                            <col style="width: 45%"/>
                            <col style="width: 15%"/>
                            <col style="width: 15%"/>
                            <col style="width: 25%"/>
                        </colgroup>
                        <thead>
                            <tr>
                                <td>Player</td>
                                <td>Mult</td>
                                <td>Share</td>
                                <td></td>
                            </tr>
                        </thead>
                        <tbody>
                            <tr data-for="player : ecoData"
                                data-class-is-highlighted="player.isMe"
                                data-class-is-threat-high="player.threatLevel == 'high'"
                                data-class-is-threat-medium="player.threatLevel == 'medium'"
                                data-class-is-threat-low="player.threatLevel == 'low'">
                                <td>{{player.isMe ? '> ' : '  '}}{{player.name}}</td>
                                <td>{{player.multiplierFormatted}}X</td>
                                <td>{{player.percentageFormatted}}%</td>
                                <td class="progress-cell">
                                    <div class="progress-bar">
                                        <div class="progress-fill" data-style-width="player.percentage + '%'"></div>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Damage Tab -->
            <div id="tab-content-damage" data-if="activeTab == 'damage'" class="tab-panel">
                <div class="tab-content-section">
                    <h2>Player Damage to Queens</h2>

                    <!-- Empty state -->
                    <p data-if="bossData.playerDamagesLength == 0" class="text-dim">No data yet</p>

                    <!-- Leaderboard table -->
                    <table data-if="bossData.playerDamagesLength > 0">
                        <colgroup>
                            <col style="width: 15%"/>
                            <col style="width: 50%"/>
                            <col style="width: 20%"/>
                            <col style="width: 15%"/>
                        </colgroup>
                        <thead>
                            <tr>
                                <td>Rank</td>
                                <td>Player</td>
                                <td>Dmg</td>
                                <td>Rel</td>
                            </tr>
                        </thead>
                        <tbody>
                            <tr data-for="dmg, i : bossData.playerDamages">
                                <td>{{i < 3 ? '#' + (i+1) : '#' + (i+1)}}</td>
                                <td>{{dmg.name}}</td>
                                <td class="neutral">{{dmg.damageFormatted}}</td>
                                <td class="neutral">{{dmg.relative}}X</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Queens Tab -->
            <div id="tab-content-queens" data-if="activeTab == 'queens'" class="tab-panel">
                <div class="tab-content-section">
                    <h2>Queen Health Status</h2>

                    <!-- Empty state -->
                    <p data-if="bossData.healthsLength == 0 && bossData.resistancesLength == 0" class="text-dim">No data yet</p>

                    <!-- Boss health percentages (horizontal flow) -->
                    <div data-if="bossData.healthsLength > 0" class="boss-health-grid">
                        <span data-for="hp : bossData.healths"
                                class="boss-health-item"
                                data-style-color="hp.colorHex">
                            {{hp.percentage}}%
                        </span>
                    </div>
                </div>

                <!-- Resistances section -->
                <div class="tab-content-section">
                    <h2>Resistances (top 5 by damage)</h2>

                    <!-- Empty state -->
                    <p data-if="bossData.resistancesLength == 0" class="text-dim">No data yet</p>

                    <table data-if="bossData.resistancesLength > 0">
                        <colgroup>
                            <col style="width: 60%"/>
                            <col style="width: 20%"/>
                            <col style="width: 20%"/>
                        </colgroup>
                        <thead>
                            <tr>
                                <td>Unit</td>
                                <td>Resist</td>
                                <td>Dmg</td>
                            </tr>
                        </thead>
                        <tbody>
                            <tr data-for="res, i : bossData.resistances" data-if="i < 5">
                                <td>{{res.name}}</td>
                                <td class="bad">{{res.percent * 100}}%</td>
                                <td class="text-dim">{{res.damageFormatted}}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <!-- <div class="content mt-4 flex flex-col gap-6">
            <p class="text-white">{{message}}</p>
            <p class="text-gray-600">Time: {{currentTime}}</p>
        </div> -->
    </div>
</body>
</rml>
]]
end

-- root module: __root
__B_MODULES['__root'] = function(require)
if not RmlUi then
	return
end

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Raptor Panel",
		desc = "Shows raptor and player statistics in a compact interface",
		author = "Insider",
		date = "16.10.2025",
		layer = 0,
		enabled = true,
		version = 3,
	}
end

local RCSS_CHUNK = require("raptor-panel-rcss")
local RML_CHUNK = require("raptor-panel-rml")

local Harmony = require("harmony")
local HarmonyRaptor = require("harmony-raptor")

local modOptions = Spring.GetModOptions()

-- Constants
local WIDGET_NAME = "raptor-panel"
local MODEL_NAME = "raptor-panel_model"
local RML_PATH = "LuaUI/Widgets/raptor-panel.rml"
local RCSS_PATH = "LuaUI/Widgets/raptor-panel.rcss"

-- Widget state
local document
local dm_handle

-- Game data
local teamIDs = {}
local raptorsTeamID
local playerEcoAttractionsRaw = {}

-- Configuration
local CONFIG = {
	THREAT_HIGH = 1.7,
	THREAT_MED = 1.2,
}

-- Boss colors for health bars (used for queen health visualization)
local bossColors = {
	{ 0.709, 0.537, 0.000 }, -- yellow
	{ 0.796, 0.294, 0.086 }, -- orange
	{ 0.862, 0.196, 0.184 }, -- red
	{ 0.827, 0.211, 0.509 }, -- magenta
	{ 0.423, 0.443, 0.768 }, -- violet
	{ 0.149, 0.545, 0.823 }, -- blue
	{ 0.164, 0.631, 0.596 }, -- cyan
	{ 0.521, 0.600, 0.000 }, -- green
}

-- Helper to convert RGB to hex color string for RmlUI
local function rgbToHex(r, g, b)
	return string.format("#%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Complete data model structure (all fields must be defined at creation time)
local init_model = {
	-- UI state
	isDev = false, -- enables development controls
	debugMode = false,
	activeTab = "economy",

	-- Length counters for RmlUI data bindings
	playerEcoDataLength = 0,

	-- Game info
	difficulty = "unknown",
	stage = "grace",
	gracePeriodRemaining = 0,
	graceTimeFormatted = "",
	queenHatchProgress = 0,
	angerTech = 0,
	queenETA = "",
	angerGainBase = 0,
	angerGainEco = 0,
	angerGainAggression = 0,
	angerGainTotal = "0.00",
	queenCount = 0,
	queenHealth = 0,
	queenCountKilled = 0,

	ecoData = {},

	-- Boss data structure
	bossData = {
		playerDamages = {},
		playerDamagesLength = 0,
		healths = {},
		healthsLength = 0,
		resistances = {},
		resistancesLength = 0,
	},
}

-- Utility Functions
local function log(msg)
	-- Spring.SendCommands("say a: " .. msg)
	Spring.Echo(WIDGET_NAME .. ": " .. msg)
end

-- Helper to check if file contents and chunk are the same.
--
---@param chunk string
---@param path string
---@return boolean tmp false if not else true
local function checkFile(chunk, path)
	local file = io.open(path, "r")
	if not file then
		return false
	end

	local fileChunk = file:read("*a")
	file:close()

	if chunk ~= fileChunk then
		return false
	end

	return true
end

-- Helper to overwrite file contents with the given chunk.
--
---@param chunk string
---@param path string
local function overwriteFile(chunk, path)
	local file = io.open(path, "w")

	if not file then
		log(string.format("unable to save file %s", path))
		return
	end

	if not file:write(chunk) then
		log(string.format("failed to write to file %s", path))
		file:close()
		return
	end

	file:close()
end

local function formatNumber(num)
	-- Nil-safe: return "0" if num is nil or not a number
	if not num or type(num) ~= "number" then
		return "0"
	end

	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	else
		return tostring(math.floor(num))
	end
end

local function formatTime(seconds)
	-- Nil-safe: return "0 seconds" if seconds is nil or not a number
	if not seconds or type(seconds) ~= "number" or seconds <= 0 then
		return "0 s"
	end

	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)

	if minutes > 0 and secs > 0 then
		return minutes .. "m " .. secs .. "s"
	elseif minutes > 0 then
		return minutes .. " m" .. (minutes > 1 and "s" or "")
	else
		return secs .. " s"
	end
end

local function updateGameInfo()
	if not dm_handle then
		return
	end

	HarmonyRaptor.updateGameInfo() -- Fetch fresh data from engine
	local info = HarmonyRaptor.getGameInfo()
	if not info then
		-- Keep existing values, don't crash
		return
	end

	-- Copy fields with fallbacks to prevent nil crashes
	dm_handle.difficulty = modOptions.raptor_difficulty
	dm_handle.stage = info.stage
	dm_handle.gracePeriodRemaining = formatTime(info.gracePeriodRemaining)
	dm_handle.queenHatchProgress = info.queenHatchProgress
	dm_handle.angerTech = info.angerTech
	dm_handle.angerGainBase = info.angerGainBase
	dm_handle.angerGainEco = info.angerGainEco
	dm_handle.angerGainAggression = info.angerGainAggression
	dm_handle.angerGainTotal = info.angerGainBase + info.angerGainEco + info.angerGainAggression
	dm_handle.queenHealth = info.queenHealth
	dm_handle.queenCount = info.queenCount
	dm_handle.queenCountKilled = info.queenCountKilled
	dm_handle.queenETA = formatTime(HarmonyRaptor.getQueenETA())

	-- Calculate economy data
	local myTeamId = Spring.GetMyTeamID()
	local playerEcoData = {}
	local sum = 0

	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local playerName = Harmony.getPlayerName(teamID)

		if playerName and playerName ~= "" and not (playerName:find("Raptors") or playerName:find("Scavengers")) then
			local ecoValue = playerEcoAttractionsRaw[teamID] or 0
			ecoValue = math.max(0, ecoValue)
			sum = sum + ecoValue

			table.insert(playerEcoData, {
				name = playerName,
				value = ecoValue,
				teamID = teamID,
				isMe = (myTeamId == teamID),
			})
		end
	end

	-- Calculate percentages and multipliers
	if sum > 0 then
		for _, data in ipairs(playerEcoData) do
			data.percentage = (data.value / sum) * 100
			data.multiplier = (#playerEcoData * data.value) / sum

			-- Add threat level based on multiplier thresholds
			if data.multiplier > CONFIG.THREAT_HIGH then
				data.threatLevel = "high"
			elseif data.multiplier > CONFIG.THREAT_MED then
				data.threatLevel = "medium"
			else
				data.threatLevel = "low"
			end

			-- Add formatted values for display
			data.multiplierFormatted = string.format("%.1f", data.multiplier)
			data.percentageFormatted = string.format("%.0f", data.percentage)
		end
	else
		-- Set defaults when no eco value exists yet
		for _, data in ipairs(playerEcoData) do
			data.percentage = 0
			data.multiplier = 0
			data.threatLevel = "low"
			data.multiplierFormatted = "0.0"
			data.percentageFormatted = "0"
		end
	end

	-- Sort by value descending
	table.sort(playerEcoData, function(a, b)
		return a.value > b.value
	end)

	-- Update data model
	dm_handle.ecoData = playerEcoData
	dm_handle.playerEcoDataLength = #playerEcoData

	-- Calculate boss data
	local bossInfo = HarmonyRaptor.getBossInfo()

	-- Always initialize empty arrays (even when no boss data exists yet)
	local playerDamages = {}
	local healths = {}
	local resistances = {}

	-- Only populate arrays if boss data is available
	if bossInfo then
		-- Process player damages with formatted values
		local totalDamage = 0

		-- Calculate total damage first
		for _, dmg in ipairs(bossInfo.playerDamages) do
			totalDamage = totalDamage + dmg.damage
		end

		-- Process each player's damage
		for _, dmg in ipairs(bossInfo.playerDamages) do
			local relativeValue = totalDamage > 0 and (dmg.damage / totalDamage) or 0
			table.insert(playerDamages, {
				name = dmg.name,
				damage = dmg.damage,
				damageFormatted = formatNumber(dmg.damage),
				relative = string.format("%.1f", dmg.relative or relativeValue),
			})
		end

		-- Process queen health percentages with colors
		for i, health in ipairs(bossInfo.healths) do
			local color = bossColors[((i - 1) % #bossColors) + 1]
			table.insert(healths, {
				id = health.id,
				health = health.health,
				maxHealth = health.maxHealth,
				percentage = string.format("%.0f", health.percentage),
				colorHex = rgbToHex(color[1], color[2], color[3]),
			})
		end

		-- Process resistances with formatted values
		for _, res in ipairs(bossInfo.resistances) do
			table.insert(resistances, {
				name = res.name,
				percent = res.percent,
				damage = res.damage,
				damageFormatted = formatNumber(res.damage),
			})
		end
	end

	-- Update entire bossData object to trigger RmlUI reactivity
	-- (updating nested properties individually doesn't notify RmlUI of changes)
	dm_handle.bossData = {
		playerDamages = playerDamages,
		playerDamagesLength = #playerDamages,
		healths = healths,
		healthsLength = #healths,
		resistances = resistances,
		resistancesLength = #resistances,
	}
end

function widget:Initialize()
	-- log(WIDGET_NAME .. ": Initializing widget...")

	-- Get the shared RML context
	widget.rmlContext = RmlUi.GetContext("shared")
	if not widget.rmlContext then
		log("ERROR - Failed to get RML context")
		return false
	end

	-- Create and bind the data model
	dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, init_model)
	if not dm_handle then
		log("ERROR - Failed to create data model")
		return false
	end

	-- log("Data model created successfully")

	-- Initialize team data
	raptorsTeamID = HarmonyRaptor.getRaptorsTeamID()
	local playerTeams = HarmonyRaptor.getPlayerTeams()

	teamIDs = Spring.GetTeamList()

	for i = 1, #playerTeams do
		playerEcoAttractionsRaw[playerTeams[i]] = 0
	end

	-- Initialize eco value cache
	HarmonyRaptor.initEcoValueCache()

	-- Register existing units
	local allUnits = Spring.GetAllUnits()
	for i = 1, #allUnits do
		local unitID = allUnits[i]
		local unitDefID = Spring.GetUnitDefID(unitID)
		local unitTeamID = Spring.GetUnitTeam(unitID)
		if unitTeamID ~= raptorsTeamID then
			HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
		end
	end

	-- Populate data
	updateGameInfo()

	-- Write .rml and .rcss if needed
	if not checkFile(RML_CHUNK, RML_PATH) then
		log(string.format("Writing .rml: %s", RML_PATH))
		overwriteFile(RML_CHUNK, RML_PATH)
	end

	if not checkFile(RCSS_CHUNK, RCSS_PATH) then
		log(string.format("Writing .rcss: %s", RCSS_PATH))
		overwriteFile(RCSS_CHUNK, RCSS_PATH)
	end

	-- Load the RML document
	document = widget.rmlContext:LoadDocument(RML_PATH, widget)
	if not document then
		log("ERROR - Failed to load document: " .. RML_PATH)
		widget:Shutdown()
		return false
	end

	-- Apply styles and show the document
	document:ReloadStyleSheet()
	document:Show()

	-- log(WIDGET_NAME .. ": Widget initialized successfully")

	return true
end

function widget:Shutdown()
	-- log(WIDGET_NAME .. ": Shutting down widget...")

	-- Clean up data model
	if widget.rmlContext and dm_handle then
		widget.rmlContext:RemoveDataModel(MODEL_NAME)
		dm_handle = nil
	end

	-- Close document
	if document then
		document:Close()
		document = nil
	end

	widget.rmlContext = nil
	-- log(WIDGET_NAME .. ": Shutdown complete")
end

function widget:GameFrame(n)
	if n % 30 == 0 then
		updateGameInfo()
	end
end

-- Widget functions callable from RML
function widget:Reload()
	-- log(WIDGET_NAME .. ": Reloading widget...")
	widget:Shutdown()
	widget:Initialize()
end

function widget:ToggleDebugger()
	if dm_handle then
		dm_handle.debugMode = not dm_handle.debugMode

		if dm_handle.debugMode then
			RmlUi.SetDebugContext("shared")
			-- log(WIDGET_NAME .. ": RmlUi debugger enabled")
		else
			RmlUi.SetDebugContext(nil)
			-- log(WIDGET_NAME .. ": RmlUi debugger disabled")
		end
	end
end

function widget:SetTab(tabName)
	if not (tabName == "economy" or tabName == "damage" or tabName == "queens") then
		return
	end

	if dm_handle then
		dm_handle.activeTab = tabName
	end
end

function widget:UnitCreated(unitID, unitDefID, unitTeamID)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, true)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, oldTeam, false)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, false)
end
end

return __B_REQUIRE('__root')

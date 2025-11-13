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

-- module: harmony
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

    local playerName = ""
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
            playerName = table.concat(names, " & ")
        end
    else
        -- Try AI name
        _, playerName = Spring.GetAIInfo(teamID)
    end

    -- Cache the name
    if playerName and playerName ~= "" then
        cachedPlayerNames[teamID] = playerName
    end

    return playerName or ""
end

return harmony
end

-- module: harmony-raptor
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
            if
                not teamLuaAI
                or (not teamLuaAI:find("Raptors") and not teamLuaAI:find("Scavengers"))
            then
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
        (unitDef.canMove and not (unitDef.customParams and unitDef.customParams.iscommander))
        or isObject[unitDef.name]
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
        if
            unitDef.customParams.unitgroup == "antinuke"
            or unitDef.customParams.unitgroup == "nuke"
        then
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

local Harmony = require("harmony")
local HarmonyRaptor = require("harmony-raptor")

local modOptions = Spring.GetModOptions()

-- Constants
local WIDGET_NAME = "raptor-panel"
local MODEL_NAME = "raptor-panel_model"
local RML_PATH = "LuaUI/Widgets/raptor-panel/raptor-panel.rml"
local RCSS_PATH = "LuaUI/Widgets/raptor-panel/raptor-panel.rcss"

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
    return string.format(
        "#%02x%02x%02x",
        math.floor(r * 255),
        math.floor(g * 255),
        math.floor(b * 255)
    )
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

        if
            playerName
            and playerName ~= ""
            and not (playerName:find("Raptors") or playerName:find("Scavengers"))
        then
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
            HarmonyRaptor.updatePlayerEcoValues(
                playerEcoAttractionsRaw,
                unitDefID,
                unitTeamID,
                true
            )
        end
    end

    -- Populate data
    updateGameInfo()

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

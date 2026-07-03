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

-- Main game info functions
-- ========================================

-- Helper to get game rule from the engine
local function getGameRule(key)
    return Spring.GetGameRulesParam(key) or (nilDefaultRules[key] and nil or 0)
end

-- Updates the gameInfo table with the latest game rules parameters
function hr.updateGameInfo()
    -- Main settings
    gameInfo.gracePeriod = getGameRule("raptorGracePeriod")
    gameInfo.anger = getGameRule("raptorQueenAnger")
    gameInfo.angerTech = getGameRule("raptorTechAnger")
    gameInfo.angerGainAggression = getGameRule("RaptorQueenAngerGain_Aggression")
    gameInfo.angerGainBase = getGameRule("RaptorQueenAngerGain_Base")
    gameInfo.angerGainEco = getGameRule("RaptorQueenAngerGain_Eco")
    gameInfo.queenHealth = getGameRule("raptorQueenHealth")
    gameInfo.queenCountKilled = getGameRule("raptorQueensKilled")
    gameInfo.queenTime = getGameRule("raptorQueenTime")

    -- Queen stagger (base game PR #7825): depleting the stagger bar paralyzes
    -- queens and halves their resistances for the stagger duration
    gameInfo.queenStaggerPercentage = getGameRule("raptorQueenStaggerPercentage")
    local staggerActive = Spring.GetGameRulesParam("raptorQueenStaggerActive")
    gameInfo.queenStaggerActive = staggerActive == true or staggerActive == 1

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
        return nil -- Infinite time if no anger gain
    end

    local angerRemaining = 100 - currentAnger
    return angerRemaining / gainRate
end

-- Returns the multiplier applied to player damage against queens, based on
-- total queen health. Mirrors the base game's raptor_spawner_defense.lua
-- ("bosses get stronger the less health they have"):
-- >50%: x2, >25%: x1, >10%: x0.75, >5%: x0.5, <=5%: x0.25
function hr.getQueenDamageMultiplier()
    local hp = gameInfo.queenHealth
    if gameInfo.stage ~= "boss" or not hp then
        return 1
    end

    if hp > 50 then
        return 2
    elseif hp > 25 then
        return 1
    elseif hp > 10 then
        return 0.75
    elseif hp > 5 then
        return 0.5
    else
        return 0.25
    end
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
        local def = UnitDefs[tonumber(defID)]
        if def and resistance.percent >= 0.1 then
            table.insert(result.resistances, {
                name = def.translatedHumanName,
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

-- Returns true if the current game is a Raptors game
function hr.isRaptors()
    return Spring.Utilities.Gametype.IsRaptors()
end

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

-- Threat level thresholds, expressed as eco multiplier relative to the average player
local THREAT_HIGH = 1.7
local THREAT_MED = 1.2

-- Calculate eco attraction value for a unit definition
local function calculateEcoValueForDef(unitDef)
    local isObject = unitDef.modCategories["object"]
        or (unitDef.customParams and unitDef.customParams.objectify)
    if
        (unitDef.canMove and not (unitDef.customParams and unitDef.customParams.iscommander))
        or isObject
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

-- Computes per-player eco threat from a raw eco attraction table.
-- playerEcoAttractionsRaw: table of {teamID = rawEcoValue}
-- Returns a list (sorted by value descending) of:
--   { name, value, teamID, percentage, multiplier, threatLevel }
-- where threatLevel is "high", "medium", or "low" based on the eco multiplier
-- relative to the average player.
function hr.getPlayerEcoThreat(playerEcoAttractionsRaw)
    local playerEcoData = {}
    local sum = 0

    for _, teamID in ipairs(hr.getPlayerTeams()) do
        local playerName = harmony.getPlayerName(teamID)
        if playerName and playerName ~= "" then
            local value = math.max(0, playerEcoAttractionsRaw[teamID] or 0)
            sum = sum + value
            table.insert(playerEcoData, {
                name = playerName,
                value = value,
                teamID = teamID,
            })
        end
    end

    for _, data in ipairs(playerEcoData) do
        if sum > 0 then
            data.percentage = (data.value / sum) * 100
            data.multiplier = (#playerEcoData * data.value) / sum
        else
            data.percentage = 0
            data.multiplier = 0
        end

        if data.multiplier > THREAT_HIGH then
            data.threatLevel = "high"
        elseif data.multiplier > THREAT_MED then
            data.threatLevel = "medium"
        else
            data.threatLevel = "low"
        end
    end

    -- Sort by value descending
    table.sort(playerEcoData, function(a, b)
        return a.value > b.value
    end)

    return playerEcoData
end

return hr
end

-- root module: __root
__B_MODULES['__root'] = function(require)
local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Raptor Timing Notifications",
        desc = "Shows timing reminders for NuttyB Raptor spawns and aggro",
        author = "Insider",
        date = "27.09.2025",
        layer = 0,
        enabled = true,
        version = 3,
    }
end

local Harmony = require("harmony")
local HarmonyRaptor = require("harmony-raptor")

local isDebug = false
local notificationSound = "LuaUI/Widgets/raptor-notifications/alert.mp3"

-- Notification messages
local gameStartNotification = "Focus on building your base and economy during the grace period."
local firstWaveNotification =
    "First wave of Raptors will spawn soon. You should start working on defences."
local queenHatchNotification60 =
    "Queen hatch at 60%. Consider strengthening your defences and building LRPCs."
local queenHatchNotification80 = "Queen hatch at 80%. Consider walling off your base."
local queenHatchNotification100 = "Queen hatched. Brace for impact!"

-- Notification flags
local gameStartNotified = false
local firstWaveNotified = false
local queenHatchNotified60 = false
local queenHatchNotified80 = false
local queenHatchNotified100 = false

local function notify(msg)
    Spring.PlaySoundFile(notificationSound, 1.0, "ui")
    if isDebug then
        Spring.Echo("Raptor Notification: " .. msg)
    end
    -- Intentionally broadcasts to ally chat so the whole team sees the reminder;
    -- teammates running this widget too will produce duplicate messages.
    Spring.SendCommands("say a: " .. msg)
end

function widget:Initialize()
    if not HarmonyRaptor.isRaptors() or (not isDebug and Harmony.isSpectating()) then
        widgetHandler:RemoveWidget()
        return
    end

    HarmonyRaptor.updateGameInfo()
end

function widget:GameFrame(n)
    if n % 30 == 17 then
        HarmonyRaptor.updateGameInfo()
        local gameInfo = HarmonyRaptor.getGameInfo()
        local stage = gameInfo.stage
        local gracePeriodRemaining = gameInfo.gracePeriodRemaining
        local queenHatchProgress = gameInfo.queenHatchProgress

        if stage == "grace" then
            if not gameStartNotified then
                notify(gameStartNotification)
                gameStartNotified = true
            -- elseif staggers this from the game-start notification when the
            -- grace period is shorter than 6 minutes
            elseif gracePeriodRemaining <= 6 * 60 and not firstWaveNotified then
                notify(firstWaveNotification)
                firstWaveNotified = true
            end
        elseif stage == "main" then
            if queenHatchProgress >= 60 and not queenHatchNotified60 then
                notify(queenHatchNotification60)
                queenHatchNotified60 = true
            end
            if queenHatchProgress >= 80 and not queenHatchNotified80 then
                notify(queenHatchNotification80)
                queenHatchNotified80 = true
            end
        elseif stage == "boss" and not queenHatchNotified100 then
            notify(queenHatchNotification100)
            queenHatchNotified100 = true
        end
    end
end
end

return __B_REQUIRE('__root')

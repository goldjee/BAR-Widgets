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
        version = 4,
    }
end

local Harmony = require("harmony")
local HarmonyRaptor = require("harmony-raptor")

local modOptions = Spring.GetModOptions()

-- Constants
local WIDGET_NAME = "raptor-panel"
local MODEL_NAME = "raptor-panel_model"
local RML_PATH = "LuaUI/RmlWidgets/raptor-panel/raptor-panel.rml"
local RCSS_PATH = "LuaUI/RmlWidgets/raptor-panel/raptor-panel.rcss"

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

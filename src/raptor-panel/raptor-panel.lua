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

-- Constants
-- ========================================

local WIDGET_NAME = "raptor-panel"
local MODEL_NAME = "raptor-panel_model"
local RML_PATH = "LuaUI/RmlWidgets/raptor-panel/raptor-panel.rml"
local TABS = { economy = true, damage = true, queens = true }

-- Eco threat thresholds, as eco multiplier relative to the average player
local THREAT_HIGH = 1.7
local THREAT_MED = 1.2

-- Queen health bar colors, cycled per queen
local BOSS_COLORS = {
    "#b58900", -- yellow
    "#cb4b16", -- orange
    "#dc322f", -- red
    "#d33682", -- magenta
    "#6c71c4", -- violet
    "#268bd2", -- blue
    "#2aa198", -- cyan
    "#859900", -- green
}

local modOptions = Spring.GetModOptions()

-- Data model (RmlUi needs every field defined at creation time)
local initModel = {
    -- UI state
    isDev = false, -- enables development controls
    activeTab = "economy",

    -- Status
    difficulty = modOptions.raptor_difficulty or "unknown",
    queenCount = tonumber(modOptions.raptor_queen_count) or 1,
    stage = "grace",
    gracePeriodRemaining = "",
    queenHatchProgress = 0,
    queenETA = "",
    angerGainTotal = "",
    angerTech = 0,
    queenHealth = 0,
    queenCountKilled = 0,
    queenStaggerActive = false,
    queenStaggerPercentage = 0,
    queenDamageMultiplier = "",

    -- Economy tab
    ecoData = {},
    playerEcoDataLength = 0,

    -- Damage and queens tabs
    bossData = {
        playerDamages = {},
        playerDamagesLength = 0,
        healths = {},
        healthsLength = 0,
        resistances = {},
        resistancesLength = 0,
    },
}

-- Widget state
-- ========================================

local rmlContext
local document
local dataModel
local debuggerOn = false
local playerEcoValues = {} -- {teamID = eco attraction}, player teams only
local playerNames = {} -- {teamID = name} cache

-- Helpers
-- ========================================

local function log(msg)
    Spring.Echo(WIDGET_NAME .. ": " .. msg)
end

local function formatNumber(num)
    if type(num) ~= "number" then
        return "0"
    end
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(math.floor(num))
end

local function formatTime(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then
        return "0s"
    end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    if minutes > 0 then
        return minutes .. "m " .. secs .. "s"
    end
    return secs .. "s"
end

-- Formats a 0-1 fraction as a whole percent number, e.g. 0.256 -> "26"
local function formatPercent(fraction)
    return string.format("%.0f", fraction * 100)
end

-- Sorts list in place by list[i][key], descending unless ascending is true
local function sortBy(list, key, ascending)
    table.sort(list, function(a, b)
        if ascending then
            return a[key] < b[key]
        end
        return a[key] > b[key]
    end)
end

local function getRule(key)
    return Spring.GetGameRulesParam(key) or 0
end

-- Returns the player names of a team joined with " & ", or the AI name
local function getPlayerName(teamID)
    if playerNames[teamID] then
        return playerNames[teamID]
    end

    local names = {}
    for _, playerID in ipairs(Spring.GetPlayerList(teamID) or {}) do
        local name = Spring.GetPlayerInfo(playerID)
        if name then
            table.insert(names, name)
        end
    end

    local name = #names > 0 and table.concat(names, " & ")
        or select(2, Spring.GetAIInfo(teamID))
        or ""
    if name ~= "" then
        playerNames[teamID] = name
    end
    return name
end

-- Status
-- ========================================

-- Multiplier applied to player damage against queens, based on total queen
-- health. Mirrors the base game's raptor_spawner_defense.lua ("bosses get
-- stronger the less health they have")
local function getQueenDamageMultiplier(queenHealth)
    if queenHealth > 50 then
        return 2
    elseif queenHealth > 25 then
        return 1
    elseif queenHealth > 10 then
        return 0.75
    elseif queenHealth > 5 then
        return 0.5
    end
    return 0.25
end

-- Updates the status fields; returns the queen damage multiplier and stagger
-- state, which the resistance math in updateBoss() needs
local function updateStatus()
    local graceRemaining = getRule("raptorGracePeriod") - Spring.GetGameSeconds()
    local anger = getRule("raptorQueenAnger")
    local angerGain = getRule("RaptorQueenAngerGain_Base")
        + getRule("RaptorQueenAngerGain_Aggression")
        + getRule("RaptorQueenAngerGain_Eco")
    local queenHealth = getRule("raptorQueenHealth")
    local stage = (graceRemaining >= 0 and "grace") or (anger < 100 and "main") or "boss"
    local damageMultiplier = stage == "boss" and getQueenDamageMultiplier(queenHealth) or 1

    -- Queen stagger (base game PR #7825): depleting the stagger bar paralyzes
    -- queens and halves their resistances for the stagger duration
    local staggerRule = Spring.GetGameRulesParam("raptorQueenStaggerActive")
    local staggerActive = staggerRule == true or staggerRule == 1

    dataModel.stage = stage
    dataModel.gracePeriodRemaining = formatTime(graceRemaining)
    dataModel.queenHatchProgress = math.min(100, math.floor(anger + 0.5))
    -- zero anger gain means the queens never hatch
    dataModel.queenETA = angerGain > 0 and formatTime((100 - anger) / angerGain) or "∞"
    dataModel.angerGainTotal = string.format("%.2f", angerGain)
    dataModel.angerTech = getRule("raptorTechAnger")
    dataModel.queenHealth = queenHealth
    dataModel.queenCountKilled = getRule("raptorQueensKilled")
    dataModel.queenStaggerActive = staggerActive
    dataModel.queenStaggerPercentage = getRule("raptorQueenStaggerPercentage")
    dataModel.queenDamageMultiplier = string.format("%.2g", damageMultiplier)

    return damageMultiplier, staggerActive
end

-- Economy
-- ========================================

-- Raptor targeting attraction of a unit def; mobile units (except
-- commanders) and objects attract nothing
local function getEcoValue(unitDef)
    local cp = unitDef.customParams
    if
        (unitDef.canMove and not cp.iscommander)
        or unitDef.modCategories.object
        or cp.objectify
    then
        return 0
    end

    local value = 1
        + (unitDef.energyMake or 0)
        + (unitDef.windGenerator or 0) * 0.75
        + (unitDef.tidalGenerator or 0) * 15
    if (unitDef.energyUpkeep or 0) < 0 then
        value = value - unitDef.energyUpkeep
    end
    if (unitDef.extractsMetal or 0) > 0 then
        value = value + 200
    end
    if cp.energyconv_capacity then
        value = value + tonumber(cp.energyconv_capacity) / 2
    end
    if cp.decoyfor == "armfus" then
        value = value + 1000
    end
    local techLevel = tonumber(cp.techlevel) or 1
    if techLevel > 1 then
        value = value * techLevel * 2
    end
    if cp.unitgroup == "antinuke" or cp.unitgroup == "nuke" then
        value = 1000
    end
    return value
end

local ecoValueByDefID = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    ecoValueByDefID[unitDefID] = getEcoValue(unitDef)
end

-- Adds sign * the unit's eco value to its team; untracked teams are ignored
local function addEcoValue(unitDefID, unitTeam, sign)
    if playerEcoValues[unitTeam] then
        playerEcoValues[unitTeam] = playerEcoValues[unitTeam] + sign * ecoValueByDefID[unitDefID]
    end
end

local function updateEco()
    local myTeamID = Spring.GetMyTeamID()
    local rows = {}
    local sum = 0

    for teamID, value in pairs(playerEcoValues) do
        local name = getPlayerName(teamID)
        if name ~= "" then
            value = math.max(0, value)
            sum = sum + value
            table.insert(rows, { name = name, value = value, isMe = teamID == myTeamID })
        end
    end

    for _, row in ipairs(rows) do
        local share = sum > 0 and row.value / sum or 0
        local multiplier = share * #rows
        row.percentage = share * 100
        row.percentageFormatted = formatPercent(share)
        row.multiplierFormatted = string.format("%.1f", multiplier)
        if multiplier > THREAT_HIGH then
            row.threatLevel = "high"
        elseif multiplier > THREAT_MED then
            row.threatLevel = "medium"
        else
            row.threatLevel = "low"
        end
    end
    sortBy(rows, "value")

    dataModel.ecoData = rows
    dataModel.playerEcoDataLength = #rows
end

-- Bosses
-- ========================================

local function updateBoss(damageMultiplier, staggerActive)
    local bossInfo = {}
    local raw = Spring.GetGameRulesParam("pveBossInfo")
    if raw then
        local ok, decoded = pcall(Json.decode, raw)
        if ok and decoded then
            bossInfo = decoded
        else
            log("failed to decode boss info JSON")
        end
    end

    -- The game applies the health-phase multiplier BEFORE resistance:
    -- applied = raw * phaseMult * (1 - resist [* 0.5 while staggered]),
    -- so effective resistance differs from the raw percent (e.g. 95% resist
    -- at the x0.25 phase means 98.75% of raw damage is mitigated)
    local staggerFactor = staggerActive and 0.5 or 1
    local resistances = {}
    for defID, resistance in pairs(bossInfo.resistances or {}) do
        local def = UnitDefs[tonumber(defID)]
        if def and resistance.percent >= 0.1 then
            local effective = 1 - (1 - resistance.percent * staggerFactor) * damageMultiplier
            table.insert(resistances, {
                name = def.translatedHumanName,
                damage = resistance.damage,
                damageFormatted = formatNumber(resistance.damage),
                percentFormatted = formatPercent(resistance.percent),
                -- negative = queens currently take extra damage from this weapon
                effectiveFormatted = formatPercent(effective),
            })
        end
    end
    sortBy(resistances, "damage")

    local damages = bossInfo.playerDamages or {}
    local totalDamage = 0
    for _, damage in pairs(damages) do
        totalDamage = totalDamage + damage
    end
    local playerDamages = {}
    for teamID, damage in pairs(damages) do
        table.insert(playerDamages, {
            name = getPlayerName(tonumber(teamID)),
            damage = damage,
            damageFormatted = formatNumber(damage),
            relative = string.format("%.1f", damage / math.max(totalDamage, 1)),
        })
    end
    sortBy(playerDamages, "damage")

    local healths = {}
    for _, status in pairs(bossInfo.statuses or {}) do
        if not status.isDead and status.health > 0 then
            table.insert(healths, { fraction = status.health / status.maxHealth })
        end
    end
    sortBy(healths, "fraction", true)
    for i, health in ipairs(healths) do
        health.percentage = formatPercent(health.fraction)
        health.colorHex = BOSS_COLORS[(i - 1) % #BOSS_COLORS + 1]
    end

    -- Replace the whole object: RmlUi isn't notified of nested field changes
    dataModel.bossData = {
        playerDamages = playerDamages,
        playerDamagesLength = #playerDamages,
        healths = healths,
        healthsLength = #healths,
        resistances = resistances,
        resistancesLength = #resistances,
    }
end

local function update()
    local damageMultiplier, staggerActive = updateStatus()
    updateEco()
    updateBoss(damageMultiplier, staggerActive)
end

-- Widget callins
-- ========================================

local function fail(msg)
    log("ERROR - " .. msg)
    widgetHandler:RemoveWidget()
end

function widget:Initialize()
    if not BAR.Utilities.Gametype.IsRaptors() then
        widgetHandler:RemoveWidget()
        return
    end

    rmlContext = RmlUi.GetContext("shared")
    if not rmlContext then
        return fail("failed to get RML context")
    end

    dataModel = rmlContext:OpenDataModel(MODEL_NAME, initModel)
    if not dataModel then
        return fail("failed to create data model")
    end

    -- Track player teams only (no Gaia, Raptors or Scavengers)
    playerEcoValues = {}
    local gaiaTeamID = Spring.GetGaiaTeamID()
    for _, teamID in ipairs(Spring.GetTeamList()) do
        local luaAI = Spring.GetTeamLuaAI(teamID) or ""
        if teamID ~= gaiaTeamID and not luaAI:find("Raptors") and not luaAI:find("Scavengers") then
            playerEcoValues[teamID] = 0
        end
    end
    for _, unitID in ipairs(Spring.GetAllUnits()) do
        widget:UnitCreated(unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
    end

    update()

    document = rmlContext:LoadDocument(RML_PATH, widget)
    if not document then
        return fail("failed to load document: " .. RML_PATH)
    end
    document:ReloadStyleSheet()
    document:Show()
end

function widget:Shutdown()
    if dataModel then
        rmlContext:RemoveDataModel(MODEL_NAME)
        dataModel = nil
    end
    if document then
        document:Close()
        document = nil
    end
    rmlContext = nil
end

function widget:GameFrame(n)
    if n % 30 == 0 then
        update()
    end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
    addEcoValue(unitDefID, unitTeam, 1)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
    addEcoValue(unitDefID, unitTeam, 1)
    addEcoValue(unitDefID, oldTeam, -1)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    addEcoValue(unitDefID, unitTeam, -1)
end

-- Called from RML
-- ========================================

function widget:Reload()
    widget:Shutdown()
    widget:Initialize()
end

function widget:ToggleDebugger()
    debuggerOn = not debuggerOn
    RmlUi.SetDebugContext(debuggerOn and "shared" or nil)
end

function widget:SetTab(tabName)
    if TABS[tabName] then
        dataModel.activeTab = tabName
    end
end

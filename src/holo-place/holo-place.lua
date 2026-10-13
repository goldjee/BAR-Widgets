local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Holo Place",
        desc = "Starts the next building once a nano turret assists the current one (smart auto mode picks the best nano)",
        author = "augustin, manshanko, then enchanced by Pyrem, fixed by Insider",
        date = "13.10.2026",
        layer = 2,
        enabled = true,
        handler = true,
        version = 2,
    }
end

-- Constants
-- ========================================

local UPDATE_INTERVAL = 3 -- frames between builder updates
local KEY_TOGGLE = string.byte("'") -- CTRL+SHIFT+' toggles off / last mode
local ASSIST_TIMEOUT = 30 -- updates to wait for the nano to start assisting

local MODE_OFF = 0
local MODE_SMART = 1

-- Indexed by mode: off, smart, 90, 60, 30, instant
local MODE_LABELS = { "Holo off", "Holo Smart", "Holo 90", "Holo 60", "Holo 30", "Holo Ins" }

-- Build progress at which the builder moves on; smart mode recalculates it per building
local HOLO_THRESHOLDS = {
    [MODE_SMART] = 0.3,
    [2] = 0.9,
    [3] = 0.6,
    [4] = 0.3,
    [5] = 0,
}

local CMD_HOLO_PLACE = 28341
local CMD_HOLO_PLACE_DESCRIPTION = {
    id = CMD_HOLO_PLACE,
    type = CMDTYPE.ICON_MODE,
    name = "Holo Place",
    action = "holo_place",
    -- params[1] is the current mode, the rest are the mode label keys
    params = {
        MODE_SMART,
        "holo_place_off",
        "holo_place_smart",
        "holo_place_90",
        "holo_place_60",
        "holo_place_30",
        "holo_place_ins",
    },
}

-- The order menu labels mode buttons with commands.<params[mode + 2]>
-- and their tooltip with commands.<action>_tooltip
for i, label in ipairs(MODE_LABELS) do
    BAR.I18N.set("en.commands." .. CMD_HOLO_PLACE_DESCRIPTION.params[i + 1], label)
end
BAR.I18N.set("en.commands.holo_place_tooltip", "Start next building if assisted (Smart auto mode)")

-- Constructors (by build speed) and construction turrets (by build range)
local BUILDER_DEFS = {}
local NANO_DEFS = {}
local MAX_DISTANCE = 0
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.isFactory then
        if #unitDef.buildOptions > 0 then
            BUILDER_DEFS[unitDefID] = unitDef.buildSpeed
        end
        if not unitDef.canMove then
            NANO_DEFS[unitDefID] = unitDef.buildDistance
            MAX_DISTANCE = math.max(MAX_DISTANCE, unitDef.buildDistance)
        end
    end
end

-- State
-- ========================================

local myTeamID = 0
local lastActiveMode = MODE_SMART

-- {unitID = {mode, threshold, monitoring, nanoID, buildingID, tick, cmdTag}}
local placers = {}

-- Helpers
-- ========================================

local function log(msg)
    Spring.Echo("Holo Place: " .. msg)
end

local function getCurrentMode()
    return CMD_HOLO_PLACE_DESCRIPTION.params[1]
end

local function setPlacerMode(unitID, mode)
    if mode == MODE_OFF then
        placers[unitID] = nil
        return
    end
    local placer = placers[unitID] or {}
    placer.mode = mode
    placer.threshold = HOLO_THRESHOLDS[mode]
    placer.monitoring = false
    placers[unitID] = placer
end

-- Applies the current mode to the selected builders
local function applyModeToSelection()
    for _, unitID in ipairs(Spring.GetSelectedUnits()) do
        if BUILDER_DEFS[Spring.GetUnitDefID(unitID)] then
            setPlacerMode(unitID, getCurrentMode())
        end
    end
end

local function resetBuilder(builder)
    builder.nanoID = false
    builder.buildingID = false
    builder.monitoring = false
    builder.tick = nil
    builder.cmdTag = nil
end

-- The faster the nano compared to the builder, the earlier the builder can move on
local function calculateSmartThreshold(builderID, nanoID)
    local builderSpeed = BUILDER_DEFS[Spring.GetUnitDefID(builderID)] or 1
    local nanoSpeed = BUILDER_DEFS[Spring.GetUnitDefID(nanoID)] or 1
    local speedRatio = nanoSpeed / builderSpeed
    if speedRatio > 3 then
        return 0.2
    elseif speedRatio > 1.5 then
        return 0.3
    end
    return 0.5
end

-- Construction turrets (other than targetID) that can reach targetID
local function nanosNearUnit(targetID)
    local x, _, z = Spring.GetUnitPosition(targetID)
    if not x then
        return {}
    end

    local nanos = {}
    for _, unitID in ipairs(Spring.GetUnitsInCylinder(x, z, MAX_DISTANCE, -2)) do
        local buildDistance = NANO_DEFS[Spring.GetUnitDefID(unitID)]
        if
            buildDistance
            and unitID ~= targetID
            and buildDistance > Spring.GetUnitSeparation(targetID, unitID, true)
        then
            nanos[#nanos + 1] = unitID
        end
    end
    return nanos
end

-- Prefers close, idle nanos with short queues
local function selectBestNano(targetID, nanos)
    local bestNano = nil
    local bestScore = -1
    for _, nanoID in ipairs(nanos) do
        if Spring.ValidUnitID(nanoID) then
            local distance = Spring.GetUnitSeparation(targetID, nanoID, true)
            local score = math.max(0, 1000 - distance)
                + (Spring.GetUnitIsBuilding(nanoID) and 0 or 500)
                + math.max(0, 100 - Spring.GetUnitCommandCount(nanoID) * 10)
            if score > bestScore then
                bestScore = score
                bestNano = nanoID
            end
        end
    end
    return bestNano
end

local function hasWaitCommand(unitID)
    if not Spring.ValidUnitID(unitID) then
        return false
    end
    for _, cmd in ipairs(Spring.GetUnitCommands(unitID, 20)) do
        if cmd.id == CMD.WAIT then
            return true
        end
    end
    return false
end

-- Builder update
-- ========================================

-- Builder started a new building: hand it to an idle fighting nano and track it
local function assignNano(unitID, builder, targetID)
    local nanoID = selectBestNano(targetID, nanosNearUnit(targetID))
    if not nanoID then
        return
    end

    local cmds = Spring.GetUnitCommands(nanoID, 2)
    local isFighting = (cmds[1] and cmds[1].id == CMD.FIGHT)
        or (cmds[2] and cmds[2].id == CMD.FIGHT)
    if
        not isFighting
        or hasWaitCommand(nanoID)
        or hasWaitCommand(unitID)
        or Spring.GetUnitIsBuilding(nanoID)
    then
        return
    end

    local _, _, cmdTag = Spring.GetUnitCurrentCommand(unitID)
    builder.nanoID = nanoID
    builder.buildingID = targetID
    builder.cmdTag = cmdTag
    builder.tick = 0
    builder.monitoring = true
    -- Re-read the threshold per building, so mode changes take effect
    if builder.mode == MODE_SMART then
        builder.threshold = calculateSmartThreshold(unitID, nanoID)
    else
        builder.threshold = HOLO_THRESHOLDS[builder.mode] or 0.6
    end

    Spring.GiveOrderToUnit(nanoID, CMD.REPAIR, targetID, 0)
end

-- Once the nano is assisting and the building passed the threshold,
-- drop the build command so the builder moves on to the next one
local function watchNanoAssist(unitID, builder)
    if not Spring.ValidUnitID(builder.nanoID) then
        resetBuilder(builder)
        return
    end

    local nanoTarget = Spring.GetUnitIsBuilding(builder.nanoID)
    local nanoCmdCount = Spring.GetUnitCommands(builder.nanoID, 0)
    if nanoTarget == builder.buildingID and nanoCmdCount == 1 then
        local health, _, _, _, buildProgress = Spring.GetUnitHealth(builder.buildingID)
        if not health then
            resetBuilder(builder)
        elseif (buildProgress or 0) >= (builder.threshold or 0.6) then
            -- Stop tracking this building but keep monitoring the builder
            builder.nanoID = false
            builder.buildingID = false
            builder.tick = nil
            Spring.GiveOrderToUnit(unitID, CMD.REMOVE, builder.cmdTag, 0)
        end
    elseif builder.tick and builder.tick > ASSIST_TIMEOUT then
        resetBuilder(builder)
    else
        builder.tick = (builder.tick or 0) + 1
    end
end

local function updateBuilder(unitID, builder)
    local targetID = Spring.GetUnitIsBuilding(unitID)
    if not builder.monitoring then
        if not targetID then
            return
        end
        builder.monitoring = true
    end

    if builder.nanoID and targetID == builder.buildingID then
        watchNanoAssist(unitID, builder)
    elseif targetID and targetID ~= builder.buildingID then
        assignNano(unitID, builder, targetID)
    elseif not targetID then
        resetBuilder(builder)
    end
end

-- Widget callins
-- ========================================

function widget:Initialize()
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget()
        return
    end
    myTeamID = Spring.GetMyTeamID()
    widgetHandler.actionHandler:AddAction(self, "holo_place", applyModeToSelection, nil, "Insert")
end

function widget:Shutdown()
    widgetHandler.actionHandler:RemoveAction(self, "holo_place", "Insert")
end

-- Shows the button for builders; new builders start in smart mode unless the button is off
function widget:CommandsChanged()
    local foundMode = MODE_SMART
    local hasBuilders = false
    for _, unitID in ipairs(Spring.GetSelectedUnits()) do
        if BUILDER_DEFS[Spring.GetUnitDefID(unitID)] then
            hasBuilders = true
            local placer = placers[unitID]
            if placer and placer.mode then
                foundMode = placer.mode
                break
            elseif getCurrentMode() ~= MODE_OFF then
                setPlacerMode(unitID, MODE_SMART)
                foundMode = MODE_SMART
            else
                foundMode = MODE_OFF
            end
        end
    end

    CMD_HOLO_PLACE_DESCRIPTION.params[1] = foundMode
    if hasBuilders then
        local cmds = widgetHandler.customCommands
        cmds[#cmds + 1] = CMD_HOLO_PLACE_DESCRIPTION
    end
end

function widget:CommandNotify(cmdID)
    if cmdID == CMD_HOLO_PLACE then
        local mode = (getCurrentMode() + 1) % #MODE_LABELS
        CMD_HOLO_PLACE_DESCRIPTION.params[1] = mode
        if mode ~= MODE_OFF then
            lastActiveMode = mode
        end
        applyModeToSelection()
        return true -- the engine would cycle the mode too
    end
end

function widget:KeyPress(key, mods, isRepeat)
    if key ~= KEY_TOGGLE or not mods.ctrl or not mods.shift or isRepeat then
        return false
    end

    local mode = getCurrentMode()
    if mode == MODE_OFF then
        mode = lastActiveMode
    else
        lastActiveMode = mode
        mode = MODE_OFF
    end
    CMD_HOLO_PLACE_DESCRIPTION.params[1] = mode
    applyModeToSelection()

    log(BAR.I18N("commands." .. CMD_HOLO_PLACE_DESCRIPTION.params[mode + 2]))
    return true
end

function widget:UnitCmdDone(unitID, _, unitTeam, cmdID)
    if unitTeam == myTeamID and cmdID < 0 and placers[unitID] then
        resetBuilder(placers[unitID])
    end
end

-- No team check: teammates may finish a building our builder is tracking
function widget:UnitFinished(unitID)
    for _, builder in pairs(placers) do
        if builder.buildingID == unitID then
            resetBuilder(builder)
        end
    end
end

local function forgetUnit(_, unitID)
    placers[unitID] = nil
end

widget.UnitDestroyed = forgetUnit
widget.UnitTaken = forgetUnit

function widget:GameFrame(frame)
    if frame % UPDATE_INTERVAL ~= 0 then
        return
    end
    for unitID, builder in pairs(placers) do
        updateBuilder(unitID, builder)
    end
end

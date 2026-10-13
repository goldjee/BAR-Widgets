local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Construction Turrets Range Check",
        desc = "Stops construction turrets from being assigned to constructions out of reach.",
        author = "Nehroz, Insider",
        date = "13.10.2026",
        license = "GPL v3",
        layer = 0,
        enabled = true,
        version = 2,
    }
end

-- Constants
-- ========================================

-- DELAY is the number of frames between a given command and getting processed;
-- Should be bigger than `COMMAND_LIMIT / expected number of nanos`. Default is 15.
-- NOTE: There is no "overflow" protection. Setting DELAY too low will cause stacks to fill up constantly.
local DELAY = 15
-- Maximum number of commands to be processed in a single frame; Game sim blocking if too many commands per frame.
-- Default is 20. But modern hardware could handle more. 20 is sufficient for any game case.
local COMMAND_LIMIT = 20

-- Construction turrets: every stationary, non-factory builder
local TURRET_DEFS = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
        TURRET_DEFS[unitDefID] = true
    end
end

-- State
-- ========================================

local frameCounter = 0
local isListening = false
local isProcessed = true
local currentTurrets = {}
local commandBudget = 0
local toBeCleared = {} -- turrets to stop
local newOrders = {} -- {unitID, cmdArray} to reissue
local radiusByDefID = {} -- {unitDefID = model radius} cache

-- Helpers
-- ========================================

-- 2D distance: nanos build in cylinders, not spheres
local function calculateDistance2D(x1, y1, x2, y2)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function getUnitRadius(unitID)
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return 0
    end
    local radius = radiusByDefID[unitDefID]
    if not radius then
        local dimensions = Spring.GetUnitDefDimensions(unitDefID)
        radius = dimensions and dimensions.radius or 0
        radiusByDefID[unitDefID] = radius
    end
    return radius
end

local function isValidCommandID(commandID)
    return commandID == CMD.REPAIR
        or commandID == CMD.GUARD
        or commandID == CMD.RECLAIM
        or commandID == CMD.ATTACK
end

-- Range check
-- ========================================

local function checkTurretRange(unitID)
    local x, _, z = Spring.GetUnitPosition(unitID)
    local buildDistance = Spring.GetUnitEffectiveBuildRange(unitID, nil) -- Same as UnitDef.buildDistance; Not ambiguous
    local isChanged = false
    local isFirstCmd = true
    local cmds = Spring.GetUnitCommands(unitID, -1)
    local newCmds = {}
    for i = #cmds, 1, -1 do
        local cmd = cmds[i]
        if isValidCommandID(cmd.id) then
            local targetID = cmd.params[1]
            local tx, _, tz = Spring.GetUnitPosition(targetID)
            if tx == nil then
                break
            end
            local distance = calculateDistance2D(x, z, tx, tz)
            local radius = getUnitRadius(targetID)
            if distance < buildDistance + radius then -- BP uses buildDistance + radius (spherical shape of model)
                cmd.options.shift = not isFirstCmd
                isFirstCmd = false
                table.insert(newCmds, { cmd.id, cmd.params, cmd.options }) -- building cmdArr
            else
                isChanged = true
            end
        end
    end
    if isChanged then
        if #newCmds > 0 then
            table.insert(newOrders, { unitID, newCmds }) -- schedule for new order
        else
            table.insert(toBeCleared, unitID) -- schedule for clear
        end
    end
end

-- Applies all stop orders to units in the `toBeCleared` stack.
local function applyStopOrders()
    if #toBeCleared > 0 then
        Spring.GiveOrderToUnitArray(toBeCleared, CMD.STOP, {}, {})
        commandBudget = commandBudget - #toBeCleared
        toBeCleared = {}
    end
end

-- Processes new orders that have been scheduled for execution in the `newOrders` stack.
local function processNewOrders()
    if #newOrders > 0 and #toBeCleared == 0 then
        for i = #newOrders, 1, -1 do
            if commandBudget <= 0 then
                break
            end
            Spring.GiveOrderArrayToUnit(newOrders[i][1], newOrders[i][2])
            table.remove(newOrders, i) -- pop
            commandBudget = commandBudget - 1
        end
    end
end

-- Processes the turret range check after a certain number of frames (controlled by `DELAY`).
-- It iterates over the current list of turrets and checks their range to ensure they are not assigned
-- to constructions out of reach.
-- If any changes are detected, it schedules new orders or/and clears existing ones.
local function processTurretRange()
    if frameCounter >= DELAY then
        frameCounter = 0
        for _, turret in ipairs(currentTurrets) do
            checkTurretRange(turret)
        end
        isProcessed = true
    end
end

-- Handles the flow control. If no command is scheduled, it disables the listener for the gameframe loop,
-- else it keeps calling the `processTurretRange` function, in case anything changed during re-ordering.
local function handleFlowControl()
    if #toBeCleared == 0 and #newOrders == 0 then
        if isProcessed then
            isListening = false
        else
            processTurretRange()
        end
    end
end

-- Widget callins
-- ========================================

function widget:Initialize()
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget()
    end
end

function widget:GameFrame()
    if isListening then -- only while a selected turret has pending work
        frameCounter = frameCounter + 1
        commandBudget = COMMAND_LIMIT

        applyStopOrders()
        processNewOrders()
        handleFlowControl()
    end
end

-- Grabs any turret in selection and stores it in the list
function widget:SelectionChanged(selectedUnits)
    if isProcessed then -- remove old when processing is done, else append.
        currentTurrets = {}
    end
    for _, unitID in ipairs(selectedUnits) do
        if TURRET_DEFS[Spring.GetUnitDefID(unitID)] then
            table.insert(currentTurrets, unitID)
        end
    end
end

-- Starts listening when a tracked turret receives a command
function widget:UnitCommand(unitID)
    for _, turret in ipairs(currentTurrets) do
        if unitID == turret then
            isListening = true
            frameCounter = 0
            isProcessed = false
            break
        end
    end
end

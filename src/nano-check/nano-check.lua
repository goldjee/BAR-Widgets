--[[
### VERSIONS ###
1.0 - initial release, basic
1.1 - added more command types (reclaim, attack)
1.2 - added support for queued commands to be flag_processed
1.3 - fixed a range deviation caused by the game adding model radius
1.4a - optimization, added LRU cache to reduce the number of calls to the engine
1.4b - optimization, changed the flag_listening method to await a command instead of polling x'th frame
1.4c - optimization, added a command limit to prevent the engine from ignoring commands
1.4d - optimization, replaced loop with GiveOrderToUnitArray, renaiming and adding comments
1.4e - changed distance calculation from 3D to 2D
1.4f - removed a Spring.Echo() that was left from debugging.
1.4g - refactored the code, added more comments, better readability.
1.5 - fixed edge case that allows to skip the script the execution of the script by switching selection.
2 - all stationary builders (incl. Legion and T3 turrets), per-unitdef radius cache, sandbox ready.
]]

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

-- Settings
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

local counter = 0
local flag_listening = false
local flag_processed = true
local current_towers = {}
local command_budget = 0
local to_be_cleared = {} -- stack of uIDs to be cleared
local new_orders = {} -- stack of {uid = {cmdArr},...} to be processed
local radius_by_def = {} -- model radius cache, so we don't have to ask the engine every time

-- Helpers
-- ========================================

-- 2D distance: nanos build in cylinders, not spheres
local function calculateDistance2D(x1, y1, x2, y2)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function getUnitRadius(uID)
    local unitDefID = Spring.GetUnitDefID(uID)
    if not unitDefID then
        return 0
    end
    local radius = radius_by_def[unitDefID]
    if not radius then
        local dimensions = Spring.GetUnitDefDimensions(unitDefID)
        radius = dimensions and dimensions.radius or 0
        radius_by_def[unitDefID] = radius
    end
    return radius
end

local function isValidCommandID(commandID)
    return commandID == CMD.REPAIR
        or commandID == CMD.GUARD
        or commandID == CMD.RECLAIM
        or commandID == CMD.ATTACK
end

-- Main functions
-- ========================================

local function checkTurretRange(uID)
    local x, _, z = Spring.GetUnitPosition(uID)
    local build_distance = Spring.GetUnitEffectiveBuildRange(uID, nil) -- Same as UnitDef.buildDistance; Not ambiguous
    local is_changed = false
    local is_first_cmd = true
    local cmds = Spring.GetUnitCommands(uID, -1)
    local new_cmds = {}
    for i = #cmds, 1, -1 do
        local cmd = cmds[i]
        if isValidCommandID(cmd.id) then
            local tuID = cmd.params[1]
            local tx, _, tz = Spring.GetUnitPosition(tuID)
            if tx == nil then
                break
            end
            local distance = calculateDistance2D(x, z, tx, tz)
            local radius = getUnitRadius(tuID)
            if distance < build_distance + radius then -- BP uses build_distance + radius (sphereical shape of model)
                cmd.options.shift = not is_first_cmd
                is_first_cmd = false
                table.insert(new_cmds, { cmd.id, cmd.params, cmd.options }) -- building cmdArr
            else
                is_changed = true
            end
        end
    end
    if is_changed then
        if #new_cmds > 0 then
            table.insert(new_orders, { uID, new_cmds }) -- schedule for new order
        else
            table.insert(to_be_cleared, uID) -- schedule for clear
        end
    end
end

-- Applies all stop orders to units in the `to_be_cleared` stack.
local function applyStopOrders()
    if #to_be_cleared > 0 then
        Spring.GiveOrderToUnitArray(to_be_cleared, CMD.STOP, {}, {})
        command_budget = command_budget - #to_be_cleared
        to_be_cleared = {}
    end
end

-- Processes new orders that have been scheduled for execution in the `new_orders` stack.
local function processNewOrders()
    if #new_orders > 0 and #to_be_cleared == 0 then
        for i = #new_orders, 1, -1 do
            if command_budget <= 0 then
                break
            end
            Spring.GiveOrderArrayToUnit(new_orders[i][1], new_orders[i][2])
            table.remove(new_orders, i) -- pop
            command_budget = command_budget - 1
        end
    end
end

-- Processes the turret range check after a certain number of frames (controlled by `DELAY`).
-- It iterates over the current list of nano turrets and checks their range to ensure they are not assigned
-- to constructions out of reach.
-- If any changes are detected, it schedules new orders or/and clears existing ones.
local function processTurretRange()
    if counter >= DELAY then
        counter = 0
        for _, tower in ipairs(current_towers) do
            checkTurretRange(tower)
        end
        flag_processed = true
    end
end

-- Handles the flow control. If no command is scheduled, it disables the listener for the gameframe loop,
-- else it keeps calling the `processTurretRange` function, in case anything changed during re-ordering.
local function handleFlowControl()
    if #to_be_cleared == 0 and #new_orders == 0 then
        if flag_processed then
            flag_listening = false
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
    if flag_listening then -- only as long as turret is selection and one post-frame after selection drop.
        counter = counter + 1
        command_budget = COMMAND_LIMIT

        applyStopOrders()
        processNewOrders()
        handleFlowControl()
    end
end

-- Grabs any nano in selection and stores it in the list
function widget:SelectionChanged(selectedUnits)
    if flag_processed then -- remove old when processing is done, else append.
        current_towers = {}
    end
    for _, unitID in ipairs(selectedUnits) do
        if TURRET_DEFS[Spring.GetUnitDefID(unitID)] then
            table.insert(current_towers, unitID)
        end
    end
end

-- Listener to when nano receives a command
function widget:UnitCommand(uID)
    for _, nano in ipairs(current_towers) do
        if uID == nano then
            flag_listening = true
            counter = 0
            flag_processed = false
            break
        end
    end
end

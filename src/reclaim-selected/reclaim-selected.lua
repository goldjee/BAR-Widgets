local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name    = "Reclaim Selected",
        desc    = "Reclaim selected units with nearby nano turrets",
        author  = "manshanko, Insider",
        date    = "2026-10-13",
        layer   = 2,
        enabled = false,
        version = 2,
        handler = true,
    }
end

local CONFIG = {
    -- change default action on button press to shuffle
    shuffle = true,
}

local i18n = BAR.I18N
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local UnitDefs = UnitDefs
local CMD_RECLAIM = CMD.RECLAIM
local CMD_INSERT = CMD.INSERT
local CMD_OPT_SHIFT = CMD.OPT_SHIFT

local CMD_RECLAIM_SELECTED = 28329
local CMD_RECLAIM_SELECTED_DESCRIPTION = {
    id = CMD_RECLAIM_SELECTED,
    type = CMDTYPE.ICON,
    name = "Reclaim Selected",
    cursor = nil,
    action = "reclaim_selected",
}

-- The order menu labels buttons with commands.<action> and commands.<action>_tooltip
i18n.set("en.commands." .. CMD_RECLAIM_SELECTED_DESCRIPTION.action, "Reclaim Selected")
i18n.set("en.commands." .. CMD_RECLAIM_SELECTED_DESCRIPTION.action .. "_tooltip", "Reclaim selected units")

local NANO_DEFS = {}
local MAX_DISTANCE = 0

for unit_def_id, unit_def in pairs(UnitDefs) do
    if unit_def.isBuilder and not unit_def.canMove and not unit_def.isFactory then
        NANO_DEFS[unit_def_id] = unit_def.buildDistance
        if unit_def.buildDistance > MAX_DISTANCE then
            MAX_DISTANCE = unit_def.buildDistance
        end
    end
end

local ALT = {"alt"}
local CMD_CACHE = { 0, CMD_RECLAIM, CMD_OPT_SHIFT, 0 }

local function ntNearUnit(target_unit_id)
    local pos = {GetUnitPosition(target_unit_id)}
    local units_near = GetUnitsInCylinder(pos[1], pos[3], MAX_DISTANCE, -2)
    local unit_ids = {}
    for _, id in ipairs(units_near) do
        local dist = NANO_DEFS[GetUnitDefID(id)]
        if dist ~= nil and target_unit_id ~= id then
            if dist > GetUnitSeparation(target_unit_id, id, true) then
                unit_ids[#unit_ids + 1] = id
            end
        end
    end

    return unit_ids
end

local function signalReclaim(target_unit_id)
    local unit_ids = ntNearUnit(target_unit_id)

    CMD_CACHE[4] = target_unit_id
    GiveOrderToUnitArray(unit_ids, CMD_INSERT, CMD_CACHE, ALT)
end

local TASKS = nil
--=============================================================================
-- OPTIMIZED SHUFFLE HANDLER
-- This version preserves the original's correct logic while making the
-- initial setup phase asynchronous to prevent lag on large selections.
--=============================================================================
local function signalReclaimShuffleOptimized(target_unit_ids)
    if TASKS then return end -- Don't start a new task if one is already running

    TASKS = coroutine.wrap(function()
        -- 1. ASYNCHRONOUS SETUP PHASE
        local tasks = {}
        for i=1, #target_unit_ids do
            local unit_ids = ntNearUnit(target_unit_ids[i])
            table.shuffle(unit_ids)

            -- Only create a task if reclaimers were actually found for this target
            if #unit_ids > 0 then
                tasks[#tasks + 1] = {
                    num_units = #unit_ids,
                    unit_ids = unit_ids,
                    target_unit_id = target_unit_ids[i],
                }
            end

            --[[
            OPTIMIZATION: This is the critical change.
            By yielding periodically during the setup loop, we prevent the game
            from freezing when a very large number of units are selected. The work
            of finding and shuffling reclaimers is now spread across multiple frames.
            --]]
            if i % 15 == 0 then
                coroutine.yield()
            end
        end

        -- 2. EXECUTION PHASE (Logically Unchanged)
        -- This part of the original code was already well-designed and asynchronous.
        local work = 0
        local executed = 0
        local num_tasks = #tasks
        local split = num_tasks
        while num_tasks > 0 do
            for i, group in pairs(tasks) do
                local grp_unit_ids = group.unit_ids
                local num_units = group.num_units
                local take = math.ceil(math.min(math.max(4, num_units / split), num_units))
                group.num_units = group.num_units - take

                local unit_ids_batch = {}
                for j=1, take do
                    unit_ids_batch[j] = grp_unit_ids[num_units - j + 1]
                end

                if group.num_units <= 0 then
                    tasks[i] = nil
                    num_tasks = num_tasks - 1
                end

                CMD_CACHE[4] = group.target_unit_id
                GiveOrderToUnitArray(unit_ids_batch, CMD_INSERT, CMD_CACHE, ALT)

                work = work + take
                if work > 30 then
                    executed = executed + work
                    work = 0
                    if executed >= 1000 then
                        num_tasks = 0
                        break
                    else
                        coroutine.yield()
                    end
                end
            end
        end

        TASKS = nil
    end)

    TASKS()
end

local function handleReclaimSelected()
    local unit_ids = GetSelectedUnits()

    for _, unit_id in ipairs(unit_ids) do
        signalReclaim(unit_id)
    end
end

local function handleReclaimSelectedShuffleOptimized()
    signalReclaimShuffleOptimized(GetSelectedUnits())
end

function widget:CommandsChanged()
    local unit_ids = GetSelectedUnits()
    if #unit_ids > 0 then
        local cmds = widgetHandler.customCommands
        cmds[#cmds + 1] = CMD_RECLAIM_SELECTED_DESCRIPTION
    end
end

function widget:CommandNotify(cmd_id)
    if cmd_id == CMD_RECLAIM_SELECTED then
        if CONFIG.shuffle then
            -- Use the fully optimized handler
            handleReclaimSelectedShuffleOptimized()
        else
            handleReclaimSelected()
        end
    end
end

function widget:GameFrame(n)
    if TASKS and n % 3 == 0 then
        TASKS()
    end
end

function widget:Initialize()
    -- NOTE: Action handlers are kept for potential hotkey binding, etc.
    widgetHandler.actionHandler:AddAction(self, "reclaim_selected", handleReclaimSelected, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "reclaim_selected_shuffle", handleReclaimSelectedShuffleOptimized, nil, "p")
end

function widget:Shutdown()
    widgetHandler.actionHandler:RemoveAction(self, "reclaim_selected", "p")
    widgetHandler.actionHandler:RemoveAction(self, "reclaim_selected_shuffle", "p")
end

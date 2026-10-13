local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Reclaim Selected",
        desc = "Reclaim selected units with nearby nano turrets",
        author = "manshanko, Insider",
        date = "13.10.2026",
        layer = 2,
        enabled = false,
        handler = true,
        version = 2,
    }
end

-- Constants
-- ========================================

-- The order button shuffles which turrets take which target; false reclaims in plain order
local SHUFFLE = true

local CMD_RECLAIM_SELECTED = 28329
local CMD_RECLAIM_SELECTED_DESCRIPTION = {
    id = CMD_RECLAIM_SELECTED,
    type = CMDTYPE.ICON,
    name = "Reclaim Selected",
    action = "reclaim_selected",
}

-- The order menu labels buttons with commands.<action> and commands.<action>_tooltip
BAR.I18N.set("en.commands.reclaim_selected", "Reclaim Selected")
BAR.I18N.set("en.commands.reclaim_selected_tooltip", "Reclaim selected units")

-- Construction turrets and their build range: every stationary, non-factory builder
local NANO_DEFS = {}
local MAX_DISTANCE = 0
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
        NANO_DEFS[unitDefID] = unitDef.buildDistance
        MAX_DISTANCE = math.max(MAX_DISTANCE, unitDef.buildDistance)
    end
end

-- Inserted at the front of the queue, so turrets reclaim first and resume afterwards
local INSERT_OPTIONS = { "alt" }
local RECLAIM_PARAMS = { 0, CMD.RECLAIM, CMD.OPT_SHIFT, 0 } -- [4] = target, set per order

-- Shuffled reclaim, spread over frames so large selections don't freeze the game
local SETUP_TARGETS_PER_FRAME = 15
local ORDERS_PER_FRAME = 30
local MAX_ORDERS = 1000

-- State
-- ========================================

local shuffleTask = nil -- coroutine of the running shuffled reclaim

-- Helpers
-- ========================================

-- Own turrets (other than targetID) that can reach targetID
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

local function giveReclaim(nanos, targetID)
    RECLAIM_PARAMS[4] = targetID
    Spring.GiveOrderToUnitArray(nanos, CMD.INSERT, RECLAIM_PARAMS, INSERT_OPTIONS)
end

-- Reclaim
-- ========================================

local function reclaimSelected()
    for _, targetID in ipairs(Spring.GetSelectedUnits()) do
        giveReclaim(nanosNearUnit(targetID), targetID)
    end
end

-- Hands each target's turrets out in rounds across all targets, so every target gets
-- reclaimed in parallel instead of the first one hogging every turret
local function reclaimSelectedShuffled()
    if shuffleTask then
        return
    end
    local targetIDs = Spring.GetSelectedUnits()

    shuffleTask = coroutine.wrap(function()
        local tasks = {}
        for i, targetID in ipairs(targetIDs) do
            local nanos = nanosNearUnit(targetID)
            table.shuffle(nanos)
            if #nanos > 0 then
                tasks[#tasks + 1] = { nanos = nanos, remaining = #nanos, targetID = targetID }
            end
            if i % SETUP_TARGETS_PER_FRAME == 0 then
                coroutine.yield()
            end
        end

        local work = 0
        local executed = 0
        local taskCount = #tasks
        local split = taskCount
        while taskCount > 0 do
            for i, task in pairs(tasks) do
                local remaining = task.remaining
                local take = math.ceil(math.min(math.max(4, remaining / split), remaining))
                task.remaining = remaining - take

                local batch = {}
                for j = 1, take do
                    batch[j] = task.nanos[remaining - j + 1]
                end
                if task.remaining <= 0 then
                    tasks[i] = nil
                    taskCount = taskCount - 1
                end
                giveReclaim(batch, task.targetID)

                work = work + take
                if work > ORDERS_PER_FRAME then
                    executed = executed + work
                    work = 0
                    if executed >= MAX_ORDERS then
                        taskCount = 0
                        break
                    end
                    coroutine.yield()
                end
            end
        end

        shuffleTask = nil
    end)

    shuffleTask()
end

-- Widget callins
-- ========================================

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "reclaim_selected", reclaimSelected, nil, "p")
    widgetHandler.actionHandler:AddAction(
        self,
        "reclaim_selected_shuffle",
        reclaimSelectedShuffled,
        nil,
        "p"
    )
end

function widget:Shutdown()
    widgetHandler.actionHandler:RemoveAction(self, "reclaim_selected", "p")
    widgetHandler.actionHandler:RemoveAction(self, "reclaim_selected_shuffle", "p")
end

function widget:CommandsChanged()
    if #Spring.GetSelectedUnits() > 0 then
        local cmds = widgetHandler.customCommands
        cmds[#cmds + 1] = CMD_RECLAIM_SELECTED_DESCRIPTION
    end
end

function widget:CommandNotify(cmdID)
    if cmdID == CMD_RECLAIM_SELECTED then
        if SHUFFLE then
            reclaimSelectedShuffled()
        else
            reclaimSelected()
        end
    end
end

function widget:GameFrame(n)
    if shuffleTask and n % 3 == 0 then
        shuffleTask()
    end
end

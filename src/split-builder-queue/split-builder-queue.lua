local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Split Builder Queue",
        desc = [[
Smart queue copying & division for constructors

CTRL+ALT+Q = Self-organize: merge the queues of all selected builders and split them evenly.
Each builder gets its share first, then the rest as backup.
CTRL+ALT+W = Frontline: like CTRL+ALT+Q, but hands out the nearest tasks first, in 4 waves.
Both modes send the builders back to their starting positions afterwards.

Guard a constructor while holding:
ALT = copy its full queue
CTRL+ALT = take an even, sequential share of its queue
CTRL = take a share first, then the rest of the queue as backup
CTRL+SHIFT = copy its full queue, starting at a random position
]],
        author = "uBdead (v1), Pyrem (v2), Insider (v3)",
        date = "14.10.2026",
        license = "GPL v3 or later",
        layer = 0,
        enabled = true,
        version = 3,
    }
end

-- Constants
-- ========================================

local KEY_Q = string.byte("q")
local KEY_W = string.byte("w")

local FRONTLINE_CHUNK_COUNT = 4
local BUILDERS_PER_FRAME = 3 -- self-organize spreads its orders over frames to prevent lag
-- ponytail: Recoil silently drops order packets over 8 KB (~350 build orders); 200 leaves headroom
local ORDERS_PER_PACKET = 200

-- First entry of every order list, so all orders after it can be shift-queued
local STOP_ORDER = { CMD.STOP, {}, 0 }

-- Mobile constructors and nano turrets
local BUILDER_DEFS = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.isFactory then
        BUILDER_DEFS[unitDefID] = true
    end
end

-- State
-- ========================================

-- Guard batch: UnitCommand fires once per selected unit
local processingBatch = false
local currentUnitIndex = 0
local totalUnitsInBatch = 0
local splitByBuildOrders = false -- the batch was handed to Build Orders

local selfOrganizeTask = nil -- coroutine of the running self-organize

-- Helpers
-- ========================================

local function log(msg)
    Spring.Echo("Split Builder Queue: " .. msg)
end

-- Appends a shift-queued copy of cmd to an order list
local function queueOrder(orders, cmd)
    local options = {}
    for k, v in pairs(cmd.options or {}) do
        options[k] = v
    end
    options.shift = true
    table.insert(orders, { cmd.id, cmd.params, options })
end

-- Sends an order list as a few packets instead of one network message per order
local function sendOrders(unitID, orders)
    for i = 1, #orders, ORDERS_PER_PACKET do
        local last = math.min(i + ORDERS_PER_PACKET - 1, #orders)
        Spring.GiveOrderArrayToUnit(unitID, { unpack(orders, i, last) })
    end
end

-- Range [startIdx, endIdx] of the index-th of `parts` even shares of `total` items;
-- earlier shares take the remainder. Empty (startIdx > endIdx) when parts > total.
local function shareRange(total, parts, index)
    local perPart = math.floor(total / parts)
    local remainder = total % parts
    local startIdx = (index - 1) * perPart + 1 + math.min(index - 1, remainder)
    local endIdx = startIdx + perPart - 1 + (index <= remainder and 1 or 0)
    return startIdx, math.min(endIdx, total)
end

-- Appends commands[startIdx..endIdx], then optionally all the other commands as backup
local function addShare(orders, commands, startIdx, endIdx, withBackup)
    for i = startIdx, endIdx do
        queueOrder(orders, commands[i])
    end
    if withBackup then
        for i, cmd in ipairs(commands) do
            if i < startIdx or i > endIdx then
                queueOrder(orders, cmd)
            end
        end
    end
end

local function queueReturnHome(data)
    local pos = data.position
    table.insert(data.orders, { CMD.MOVE, { pos.x, pos.y, pos.z }, { shift = true } })
end

local function getGroupCenter(builderData)
    local x, z = 0, 0
    for _, data in ipairs(builderData) do
        x = x + data.position.x
        z = z + data.position.z
    end
    return x / #builderData, z / #builderData
end

-- Sorts commands nearest-first from (x, z); commands without a position go last
local function sortByDistance(commands, x, z)
    for _, cmd in ipairs(commands) do
        local cmdX, cmdZ = cmd.params[1], cmd.params[3]
        cmd.distanceSquared = cmdX and cmdZ and (cmdX - x) ^ 2 + (cmdZ - z) ^ 2 or math.huge
    end
    table.sort(commands, function(a, b)
        return a.distanceSquared < b.distanceSquared
    end)
end

-- Self-organize
-- ========================================

-- Merges the build commands of all builders, dropping duplicates at the same spot
local function collectSelfOrganizeData(builders)
    local builderData = {}
    local seenCommands = {}
    local mergedCommands = {}
    local buildCommands = 0

    for _, unitID in ipairs(builders) do
        local x, y, z = Spring.GetUnitPosition(unitID)
        if x then
            local commands = Spring.GetUnitCommands(unitID, -1) or {}
            table.insert(builderData, {
                unitID = unitID,
                position = { x = x, y = y, z = z },
                orders = { STOP_ORDER },
                assigned = {}, -- commands handed out in frontline waves
            })

            -- Non-build commands are skipped; a fresh return-home move is added later
            for _, cmd in ipairs(commands) do
                if cmd.id < 0 and cmd.params then
                    buildCommands = buildCommands + 1
                    local cmdX = math.floor((cmd.params[1] or 0) / 8 + 0.5) * 8
                    local cmdZ = math.floor((cmd.params[3] or 0) / 8 + 0.5) * 8
                    local key = cmd.id .. "," .. cmdX .. "," .. cmdZ
                    if not seenCommands[key] then
                        seenCommands[key] = true
                        table.insert(mergedCommands, cmd)
                    end
                end
            end
        end
    end

    return builderData, mergedCommands, buildCommands
end

-- Each builder gets an even share of the merged queue in order, then the rest as backup
local function distributeBalanced(builderData, mergedCommands)
    for i, data in ipairs(builderData) do
        local startIdx, endIdx = shareRange(#mergedCommands, #builderData, i)
        addShare(data.orders, mergedCommands, startIdx, endIdx, true)
        queueReturnHome(data)
        sendOrders(data.unitID, data.orders)

        if i % BUILDERS_PER_FRAME == 0 then
            coroutine.yield()
        end
    end
end

-- Hands a chunk of commands to the builders nearest to it, an even share each
local function assignFrontlineChunk(builderData, chunkCommands)
    local centerX, centerZ = 0, 0
    for _, cmd in ipairs(chunkCommands) do
        centerX = centerX + (cmd.params[1] or 0)
        centerZ = centerZ + (cmd.params[3] or 0)
    end
    centerX = centerX / #chunkCommands
    centerZ = centerZ / #chunkCommands

    local nearest = {}
    for _, data in ipairs(builderData) do
        local distance = (centerX - data.position.x) ^ 2 + (centerZ - data.position.z) ^ 2
        table.insert(nearest, { data = data, distance = distance })
    end
    table.sort(nearest, function(a, b)
        return a.distance < b.distance
    end)

    for i, entry in ipairs(nearest) do
        local data = entry.data
        local startIdx, endIdx = shareRange(#chunkCommands, #nearest, i)
        for j = startIdx, endIdx do
            queueOrder(data.orders, chunkCommands[j])
            data.assigned[chunkCommands[j]] = true
        end
    end
end

-- Splits the queue nearest-first into waves handed to the nearest builders,
-- then gives everyone the rest of the queue as backup
local function distributeFrontline(builderData, mergedCommands)
    sortByDistance(mergedCommands, getGroupCenter(builderData))

    local chunkCount = math.min(FRONTLINE_CHUNK_COUNT, #mergedCommands)
    for chunk = 1, chunkCount do
        local startIdx, endIdx = shareRange(#mergedCommands, chunkCount, chunk)
        assignFrontlineChunk(builderData, { unpack(mergedCommands, startIdx, endIdx) })
    end

    for i, data in ipairs(builderData) do
        -- Queuing a build that's already queued cancels it, so skip the builder's own wave orders
        for _, cmd in ipairs(mergedCommands) do
            if not data.assigned[cmd] then
                queueOrder(data.orders, cmd)
            end
        end
        queueReturnHome(data)
        sendOrders(data.unitID, data.orders)
        if i % BUILDERS_PER_FRAME == 0 then
            coroutine.yield()
        end
    end
end

-- Runs the self-organize task, if any, until its next yield
local function resumeSelfOrganize()
    local task = selfOrganizeTask
    if not task then
        return
    end
    local ok, err = pcall(task)
    if not ok then
        log("ERROR - " .. tostring(err))
        selfOrganizeTask = nil
    end
end

local function startSelfOrganize(mode)
    if selfOrganizeTask then
        log("already processing, please wait")
        return
    end

    local builders = {}
    for _, unitID in ipairs(Spring.GetSelectedUnits()) do
        if BUILDER_DEFS[Spring.GetUnitDefID(unitID)] then
            table.insert(builders, unitID)
        end
    end
    if #builders < 2 then
        log("select at least 2 builders")
        return
    end

    -- Build Orders keeps its jobs to itself; it re-splits them between the builders without
    -- queues of their own, the rest split their queues below
    local taken = WG.buildOrders and WG.buildOrders.split(builders)
    if taken then
        for i = #builders, 1, -1 do
            if taken[builders[i]] then
                table.remove(builders, i)
            end
        end
        if #builders < 2 then
            return
        end
    end

    selfOrganizeTask = coroutine.wrap(function()
        local builderData, mergedCommands, buildCommands = collectSelfOrganizeData(builders)
        coroutine.yield()

        if #builderData == 0 then
            log("no valid builders found")
        elseif #mergedCommands == 0 then
            log("selected builders have no build commands")
        else
            if mode == "frontline" then
                distributeFrontline(builderData, mergedCommands)
            else
                distributeBalanced(builderData, mergedCommands)
            end
            log(
                string.format(
                    "%s: %d commands (%d duplicates removed) split across %d builders",
                    mode,
                    #mergedCommands,
                    buildCommands - #mergedCommands,
                    #builderData
                )
            )
        end

        selfOrganizeTask = nil
    end)
    resumeSelfOrganize()
end

-- Widget callins
-- ========================================

function widget:Initialize()
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget()
    end
end

function widget:KeyPress(key, mods)
    if mods.ctrl and mods.alt then
        if key == KEY_Q then
            startSelfOrganize("balanced")
        elseif key == KEY_W then
            startSelfOrganize("frontline")
        end
    end
    return false
end

function widget:MousePress()
    -- A new click starts a new guard batch
    processingBatch = false
    currentUnitIndex = 0
    totalUnitsInBatch = 0
    splitByBuildOrders = false

    return false -- don't eat the event
end

-- Guard with modifiers: copy or split the guarded constructor's queue (fires per unit).
-- The keys come with the command, so Build Orders' shift-only helper guards never trigger it.
function widget:UnitCommand(unitID, unitDefID, _, cmdID, cmdParams, cmdOpts)
    local ctrlHeld = cmdOpts.ctrl
    local altHeld = cmdOpts.alt
    if not (ctrlHeld or altHeld) or cmdID ~= CMD.GUARD or not BUILDER_DEFS[unitDefID] then
        return false
    end

    local targetID = cmdParams[1]
    if
        not targetID
        or not Spring.ValidUnitID(targetID)
        or not BUILDER_DEFS[Spring.GetUnitDefID(targetID)]
    then
        return false
    end

    -- Build Orders keeps its jobs to itself: on the first guard of the batch, it re-splits the
    -- target's build order between the target and the guards instead
    if not processingBatch and WG.buildOrders then
        local units = Spring.GetSelectedUnits()
        if not Spring.IsUnitSelected(targetID) then
            table.insert(units, 1, targetID) -- first, so its build order is the one re-split
        end
        splitByBuildOrders = WG.buildOrders.split(units) ~= nil
    end
    if splitByBuildOrders then
        processingBatch = true
        return true
    end

    local commands = Spring.GetUnitCommands(targetID, -1)
    if not commands or #commands == 0 then
        return false
    end

    -- First unit of the batch: count the selected constructors (excluding the target)
    if not processingBatch then
        processingBatch = true
        currentUnitIndex = 0

        local selectedBuilders = 0
        for _, selectedID in ipairs(Spring.GetSelectedUnits()) do
            if BUILDER_DEFS[Spring.GetUnitDefID(selectedID)] and selectedID ~= targetID then
                selectedBuilders = selectedBuilders + 1
            end
        end
        if selectedBuilders == 0 then
            return false
        end

        -- The target keeps working on its queue too, so it counts as builder #1
        totalUnitsInBatch = 1 + selectedBuilders
    end

    currentUnitIndex = currentUnitIndex + 1
    local orders = { STOP_ORDER }

    if ctrlHeld and cmdOpts.shift and not altHeld then
        -- CTRL+SHIFT: full queue, rotated to start at a random position
        local startPos = math.random(1, #commands)
        for n = 0, #commands - 1 do
            queueOrder(orders, commands[(startPos - 1 + n) % #commands + 1])
        end
    elseif altHeld and not ctrlHeld then
        -- ALT: full queue in order
        addShare(orders, commands, 1, #commands, false)
    else
        -- CTRL+ALT: this builder's share only; CTRL: its share, then the rest as backup
        local startIdx, endIdx = shareRange(#commands, totalUnitsInBatch, currentUnitIndex + 1)
        addShare(orders, commands, startIdx, endIdx, not altHeld)
    end

    sendOrders(unitID, orders)
    return true
end

function widget:TextCommand(command)
    if command == "copyqueue" or command == "cq" then
        Spring.Echo("Split Builder Queue commands:")
        Spring.Echo(
            "  - CTRL+ALT+Q: Self-Organize (merge all selected builder queues, return home after)"
        )
        Spring.Echo(
            "  - CTRL+ALT+W: Frontline chunking (4 waves, nearest-first, return home after)"
        )
        Spring.Echo("  - ALT+Guard: Copy in order (full queue)")
        Spring.Echo("  - CTRL+ALT+Guard: Divide sequentially (portion only)")
        Spring.Echo("  - CTRL+Guard: Hybrid (portion, then the rest as backup)")
        Spring.Echo("  - CTRL+SHIFT+Guard: Full queue from a random start")
        return true
    end
    return false
end

function widget:GameFrame(n)
    -- Resume the self-organize task every 2 frames to spread the work
    if n % 2 == 0 then
        resumeSelfOrganize()
    end
end

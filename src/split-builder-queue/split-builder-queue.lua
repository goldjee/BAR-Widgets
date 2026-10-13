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
        date = "Jan 2025",
        license = "GPL v3 or later",
        layer = 0,
        enabled = true,
        version = 3,
    }
end

-- Constants
-- ========================================

local CMD_GUARD = CMD.GUARD
local CMD_STOP = CMD.STOP
local CMD_MOVE = CMD.MOVE

-- SDL keycodes for letters are their lowercase ASCII codes
local KEY_Q = string.byte("q")
local KEY_W = string.byte("w")

local SELF_ORGANIZE_PRESERVE_QUEUE_ORDER = true -- keep merged commands sequential (matches CTRL+Guard feel)
local FRONTLINE_CHUNK_COUNT = 4
local FRONTLINE_ADD_BACKUP = true

-- Mobile constructors and nano turrets
local builderDefs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.isFactory then
        builderDefs[unitDefID] = true
    end
end

-- State
-- ========================================

-- Modifier keys captured on mouse press, before the guard command is issued
local ctrlHeldOnPress = false
local altHeldOnPress = false
local shiftHeldOnPress = false

-- Guard batch: UnitCommand fires once per selected unit
local processingBatch = false
local currentUnitIndex = 0
local totalUnitsInBatch = 0

-- Async self-organize task (spreads the work over frames to prevent lag)
local selfOrganizeTask = nil

-- Helpers
-- ========================================

-- Gives a copy of cmd to unitID; queued after the previous order unless it's the first one
local function giveCommand(unitID, cmd, queued)
    if not queued then
        Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, cmd.options or 0)
        return
    end
    local options = {}
    for k, v in pairs(cmd.options or {}) do
        options[k] = v
    end
    options.shift = true
    Spring.GiveOrderToUnit(unitID, cmd.id, cmd.params, options)
end

local function queueReturnHome(data)
    local pos = data.position
    Spring.GiveOrderToUnit(data.unitID, CMD_MOVE, { pos.x, pos.y, pos.z }, { shift = true })
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

local function queueCommandForBuilder(data, cmd)
    giveCommand(data.unitID, cmd, data.assignedCommands > 0)
    data.assignedCommands = data.assignedCommands + 1
end

-- Merges the build commands of all builders, dropping duplicates at the same spot
local function collectSelfOrganizeData(builders)
    local builderData = {}
    local seenCommands = {}
    local mergedCommands = {}
    local totalCommands = 0
    local duplicatesRemoved = 0

    for _, unitID in ipairs(builders) do
        local x, y, z = Spring.GetUnitPosition(unitID)
        if x then
            local commands = Spring.GetUnitCommands(unitID, -1) or {}
            table.insert(builderData, {
                unitID = unitID,
                position = { x = x, y = y, z = z },
                assignedCommands = 0,
            })

            totalCommands = totalCommands + #commands
            -- Non-build commands are skipped; a fresh return-home move is added later
            for _, cmd in ipairs(commands) do
                if cmd.id < 0 and cmd.params then
                    local cmdX = math.floor((cmd.params[1] or 0) / 8 + 0.5) * 8
                    local cmdZ = math.floor((cmd.params[3] or 0) / 8 + 0.5) * 8
                    local key = cmd.id .. "," .. cmdX .. "," .. cmdZ
                    if seenCommands[key] then
                        duplicatesRemoved = duplicatesRemoved + 1
                    else
                        seenCommands[key] = true
                        table.insert(mergedCommands, cmd)
                    end
                end
            end
        else
            Spring.Echo("[Self-Organize] Warning: Could not get position for unit " .. unitID)
        end
    end

    return builderData, mergedCommands, totalCommands, duplicatesRemoved
end

local function distributeBalancedSelfOrganize(builderData, mergedCommands)
    local totalCommands = #mergedCommands
    local builderCount = #builderData

    if SELF_ORGANIZE_PRESERVE_QUEUE_ORDER then
        Spring.Echo(string.format("[Self-Organize] Preserving original queue order for %d commands", totalCommands))
    else
        local centerX, centerZ = getGroupCenter(builderData)
        sortByDistance(mergedCommands, centerX, centerZ)
        Spring.Echo(string.format("[Self-Organize] Sorted %d commands by distance from group center (%.0f, %.0f)",
            totalCommands, centerX, centerZ))
    end

    local commandsPerBuilder = math.floor(totalCommands / builderCount)
    local remainder = totalCommands % builderCount

    Spring.Echo(string.format("[Self-Organize] Distributing %d commands to %d builders (floor=%d, remainder=%d)",
        totalCommands, builderCount, commandsPerBuilder, remainder))

    for i, data in ipairs(builderData) do
        -- This builder's primary share: [startIdx, endIdx]; earlier builders take the remainder
        local startIdx = (i - 1) * commandsPerBuilder + 1 + math.min(i - 1, remainder)
        local endIdx = startIdx + commandsPerBuilder - 1 + (i <= remainder and 1 or 0)
        endIdx = math.min(endIdx, totalCommands)

        Spring.GiveOrderToUnit(data.unitID, CMD_STOP, {}, 0)

        local primaryCount = 0
        for j = startIdx, endIdx do
            giveCommand(data.unitID, mergedCommands[j], primaryCount > 0)
            primaryCount = primaryCount + 1
        end

        -- Everything else as backup
        local backupCount = 0
        for j, cmd in ipairs(mergedCommands) do
            if j < startIdx or j > endIdx then
                giveCommand(data.unitID, cmd, true)
                backupCount = backupCount + 1
            end
        end

        queueReturnHome(data)
        Spring.Echo(string.format("  Builder %d: %d primary + %d backup commands", i, primaryCount, backupCount))

        if i % 3 == 0 then
            coroutine.yield()
        end
    end

    Spring.Echo("[Self-Organize] Complete! Each builder has primary tasks + full backup coverage")
end

-- Hands a chunk of commands to the builders nearest to it, an even share each
local function assignFrontlineChunk(builderData, chunkCommands, chunkIndex)
    local chunkCenterX, chunkCenterZ = 0, 0
    for _, cmd in ipairs(chunkCommands) do
        chunkCenterX = chunkCenterX + (cmd.params[1] or 0)
        chunkCenterZ = chunkCenterZ + (cmd.params[3] or 0)
    end
    chunkCenterX = chunkCenterX / #chunkCommands
    chunkCenterZ = chunkCenterZ / #chunkCommands

    local builderOrder = {}
    for _, data in ipairs(builderData) do
        local distance = (chunkCenterX - data.position.x) ^ 2 + (chunkCenterZ - data.position.z) ^ 2
        table.insert(builderOrder, { data = data, distance = distance })
    end
    table.sort(builderOrder, function(a, b)
        return a.distance < b.distance
    end)

    local commandsPerBuilder = math.floor(#chunkCommands / #builderOrder)
    local remainder = #chunkCommands % #builderOrder
    local cursor = 1
    for orderIdx, info in ipairs(builderOrder) do
        local take = commandsPerBuilder + (orderIdx <= remainder and 1 or 0)
        for _ = 1, take do
            queueCommandForBuilder(info.data, chunkCommands[cursor])
            cursor = cursor + 1
        end
    end

    Spring.Echo(string.format("[Frontline] Chunk %d assigned (%d commands)", chunkIndex, #chunkCommands))
end

local function distributeFrontlineSelfOrganize(builderData, mergedCommands)
    local totalCommands = #mergedCommands

    for _, data in ipairs(builderData) do
        Spring.GiveOrderToUnit(data.unitID, CMD_STOP, {}, 0)
        data.assignedCommands = 0
    end
    sortByDistance(mergedCommands, getGroupCenter(builderData))

    local chunkCount = math.min(FRONTLINE_CHUNK_COUNT, totalCommands)
    local baseChunk = math.floor(totalCommands / chunkCount)
    local remainder = totalCommands % chunkCount

    Spring.Echo(string.format("[Frontline] Prioritizing %d commands into %d chunks (floor=%d, remainder=%d)",
        totalCommands, chunkCount, baseChunk, remainder))

    local startIdx = 1
    for chunk = 1, chunkCount do
        local size = baseChunk + (chunk <= remainder and 1 or 0)
        assignFrontlineChunk(builderData, { unpack(mergedCommands, startIdx, startIdx + size - 1) }, chunk)
        coroutine.yield()
        startIdx = startIdx + size
    end

    if FRONTLINE_ADD_BACKUP then
        for _, data in ipairs(builderData) do
            for _, cmd in ipairs(mergedCommands) do
                giveCommand(data.unitID, cmd, true)
            end
        end
        Spring.Echo("[Frontline] Added backup coverage after prioritized chunks")
    end

    for i, data in ipairs(builderData) do
        queueReturnHome(data)
        if i % 3 == 0 then
            coroutine.yield()
        end
    end

    Spring.Echo(string.format("[Frontline] Complete! %d commands distributed across %d builders using %d chunks",
        totalCommands, #builderData, chunkCount))
end

local function startSelfOrganizeMode(mode)
    local label = (mode == "frontline") and "Frontline" or "Self-Organize"

    if selfOrganizeTask then
        Spring.Echo(string.format("[%s] Already processing, please wait...", label))
        return
    end

    selfOrganizeTask = coroutine.wrap(function()
        local builders = {}
        for _, unitID in ipairs(Spring.GetSelectedUnits()) do
            if builderDefs[Spring.GetUnitDefID(unitID)] then
                table.insert(builders, unitID)
            end
        end

        if #builders < 2 then
            Spring.Echo(string.format("[%s] Need at least 2 builders selected", label))
            selfOrganizeTask = nil
            return
        end

        local builderData, mergedCommands, totalCommands, duplicatesRemoved = collectSelfOrganizeData(builders)

        coroutine.yield()

        if duplicatesRemoved > 0 then
            Spring.Echo(string.format("[%s] Removed %d duplicate commands (%d unique from %d total)",
                label, duplicatesRemoved, #mergedCommands, totalCommands))
        end

        if #builderData == 0 then
            Spring.Echo(string.format("[%s] Error: No valid builders found (position check failed)", label))
        elseif #mergedCommands == 0 then
            Spring.Echo(string.format("[%s] No commands found in selected builders", label))
        elseif mode == "frontline" then
            distributeFrontlineSelfOrganize(builderData, mergedCommands)
        else
            distributeBalancedSelfOrganize(builderData, mergedCommands)
        end

        selfOrganizeTask = nil
    end)

    local success, err = pcall(selfOrganizeTask)
    if not success then
        Spring.Echo(string.format("[%s] Error starting task: %s", label, tostring(err)))
        selfOrganizeTask = nil
    end
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
            startSelfOrganizeMode("balanced")
        elseif key == KEY_W then
            startSelfOrganizeMode("frontline")
        end
    end
    return false
end

function widget:MousePress()
    local alt, ctrl, _, shift = Spring.GetModKeyState()
    ctrlHeldOnPress = ctrl
    altHeldOnPress = alt
    shiftHeldOnPress = shift

    -- A new click starts a new guard batch
    processingBatch = false
    currentUnitIndex = 0
    totalUnitsInBatch = 0

    return false -- don't eat the event
end

-- Guard with modifiers: copy or split the guarded constructor's queue (fires per unit)
function widget:UnitCommand(unitID, unitDefID, _, cmdID, cmdParams)
    local ctrlHeld = ctrlHeldOnPress
    local altHeld = altHeldOnPress
    if not (ctrlHeld or altHeld) or cmdID ~= CMD_GUARD or not builderDefs[unitDefID] then
        return false
    end

    local targetUnitID = cmdParams[1]
    if not targetUnitID or not Spring.ValidUnitID(targetUnitID) then
        return false
    end
    if not builderDefs[Spring.GetUnitDefID(targetUnitID)] then
        return false
    end

    local commands = Spring.GetUnitCommands(targetUnitID, -1)
    if not commands or #commands == 0 then
        return false
    end

    -- First unit of the batch: count the selected constructors (excluding the target)
    if not processingBatch then
        processingBatch = true
        currentUnitIndex = 0

        local selectedConstructorCount = 0
        for _, selUnitID in ipairs(Spring.GetSelectedUnits()) do
            if builderDefs[Spring.GetUnitDefID(selUnitID)] and selUnitID ~= targetUnitID then
                selectedConstructorCount = selectedConstructorCount + 1
            end
        end
        if selectedConstructorCount == 0 then
            return false
        end

        -- Total builders = target (already working) + selected builders
        totalUnitsInBatch = 1 + selectedConstructorCount

        Spring.Echo(string.format(
            "[CopyQueue] Starting batch: %d commands, %d total builders (target + %d selected), CTRL=%s ALT=%s",
            #commands, totalUnitsInBatch, selectedConstructorCount, tostring(ctrlHeld), tostring(altHeld)))
    end

    currentUnitIndex = currentUnitIndex + 1
    -- The target is builder #1, so this selected unit is builder #(currentUnitIndex + 1)
    local builderNumber = currentUnitIndex + 1

    Spring.Echo(string.format("[CopyQueue] Processing selected unit %d (builder #%d/%d total, unitID=%d)",
        currentUnitIndex, builderNumber, totalUnitsInBatch, unitID))

    Spring.GiveOrderToUnit(unitID, CMD_STOP, {}, 0)

    if ctrlHeld and shiftHeldOnPress and not altHeld then
        -- CTRL+SHIFT: full queue, rotated to start at a random position
        local startPos = math.random(1, #commands)
        Spring.Echo(string.format("[CopyQueue] CTRL+SHIFT - Builder starts at random position %d (rotated queue)", startPos))

        for n = 0, #commands - 1 do
            giveCommand(unitID, commands[(startPos - 1 + n) % #commands + 1], n > 0)
        end
        Spring.Echo(string.format("  Total commands: %d (full queue from position %d)", #commands, startPos))
    elseif altHeld and not ctrlHeld then
        -- ALT: full queue in order
        Spring.Echo(string.format("[CopyQueue] Unit %d: Copying full queue (%d commands)", currentUnitIndex, #commands))

        for i, cmd in ipairs(commands) do
            giveCommand(unitID, cmd, i > 1)
        end
    else
        -- CTRL / CTRL+ALT: this builder's sequential share [startIdx, endIdx];
        -- earlier builders take the remainder
        local commandsPerUnit = math.floor(#commands / totalUnitsInBatch)
        local remainder = #commands % totalUnitsInBatch
        local startIdx = (builderNumber - 1) * commandsPerUnit + 1 + math.min(builderNumber - 1, remainder)
        local endIdx = math.min(startIdx + commandsPerUnit - 1 + (builderNumber <= remainder and 1 or 0), #commands)

        if altHeld then
            Spring.Echo(string.format("[CopyQueue] CTRL+ALT - Builder #%d: Sequential portion [%d to %d] ONLY (%d commands)",
                builderNumber, startIdx, endIdx, endIdx - startIdx + 1))
        else
            Spring.Echo(string.format(
                "[CopyQueue] CTRL-ONLY (HYBRID) - Builder #%d: Sequential [%d to %d] THEN the rest [1 to %d]",
                builderNumber, startIdx, endIdx, #commands))
        end

        for i = startIdx, endIdx do
            giveCommand(unitID, commands[i], i > startIdx)
        end

        -- CTRL only: the commands this builder didn't get, as backup
        if not altHeld then
            local backupCount = 0
            for i, cmd in ipairs(commands) do
                if i < startIdx or i > endIdx then
                    giveCommand(unitID, cmd, true)
                    backupCount = backupCount + 1
                end
            end
            Spring.Echo(string.format("  Total commands queued: %d (sequential) + %d (backup) = %d",
                endIdx - startIdx + 1, backupCount, (endIdx - startIdx + 1) + backupCount))
        end
    end

    return true
end

function widget:TextCommand(command)
    if command == "copyqueue" or command == "cq" then
        Spring.Echo("Split Builder Queue commands:")
        Spring.Echo("  - CTRL+ALT+Q: Self-Organize (merge all selected builder queues, return home after)")
        Spring.Echo("  - CTRL+ALT+W: Frontline chunking (4 waves, nearest-first, return home after)")
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
    if selfOrganizeTask and n % 2 == 0 then
        local success, err = pcall(selfOrganizeTask)
        if not success then
            Spring.Echo("[Self-Organize] Error during processing: " .. tostring(err))
            selfOrganizeTask = nil
        end
    end
end

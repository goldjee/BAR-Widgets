local WIDGET_NAME = "Build Orders"

local WIDGET_DESC =
    "Make builders build priority buildings where you place them, reclaiming what blocks them."

local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = WIDGET_NAME,
        desc = WIDGET_DESC,
        author = "Noryon, Insider",
        date = "13.10.2026",
        license = "MIT",
        layer = 0,
        enabled = true,
        version = 2,
    }
end

-- Constants
-- ========================================

-- Defaults ship with the widget; the user's overrides in LuaUI/Config win when present
local DEFAULTS_DIR = "LuaUI/Widgets/build-orders"
local OVERRIDES_DIR = "LuaUI/Config/build-orders"

local RECLAIM_INTERVAL = 1 -- seconds between reclaim calls
local RETRY_DELAY = 15 -- frames before Repeat mode places a destroyed building again
local ORDER_RECHECK_DELAY = 30 * 5 -- frames before re-checking a build order that hasn't started

local KEY_SPACE = 32 -- held while placing: split the placements between the selected builders
local KEY_SKIP = string.byte("n") -- skips the current building of the selected builders

local TILE_SIZE = 8 -- world units per footprint tile
local HALF_TILE_SIZE = TILE_SIZE / 2
local SNAP_SIZE = TILE_SIZE * 2 -- buildings snap to a 16 unit grid

-- order.currentJob: nil = pick the next job, JOB_ORDERED = build order given, else the building's unitID
local JOB_ORDERED = -1

-- Construction turret tiers: a turret can't erase one of the same or a higher tier
local NANO_TIERS = {}
for name, tier in pairs({
    armnanotc = 1,
    cornanotc = 1,
    legnanotc = 1,
    armnanotct2 = 2,
    cornanotct2 = 2,
    legnanotct2 = 2,
    armnanotct3 = 3,
    cornanotct3 = 3,
    legnanotct3 = 3,
}) do
    if UnitDefNames[name] then
        NANO_TIERS[UnitDefNames[name].id] = tier
    end
end

-- Base builders have no collision, so they never block a building
local BASE_BUILDERS = {}
for _, name in ipairs({ "correspawn", "armrespawn", "legnanotcbase" }) do
    if UnitDefNames[name] then
        BASE_BUILDERS[UnitDefNames[name].id] = true
    end
end

-- Construction turrets and their build range: every stationary, non-factory builder
local TURRET_RANGES = {}
local MAX_TURRET_RANGE = 0
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
        TURRET_RANGES[unitDefID] = unitDef.buildDistance
        MAX_TURRET_RANGE = math.max(MAX_TURRET_RANGE, unitDef.buildDistance or 0)
    end
end

-- Commands that cancel a build order unless queued with shift
local CANCEL_CMDS = {}
for _, name in ipairs({
    "MOVE",
    "STOP",
    "FIGHT",
    "ATTACK",
    "PATROL",
    "GUARD",
    "RECLAIM",
    "LOAD_ONTO",
    "LOAD_UNITS",
    "WAIT",
}) do
    if CMD[name] then
        CANCEL_CMDS[CMD[name]] = true
    end
end

-- Inserted at the front of the queue, so turrets reclaim first and resume afterwards
local INSERT_OPTIONS = { "alt" }
local RECLAIM_PARAMS = { 0, CMD.RECLAIM, CMD.OPT_SHIFT, 0 } -- [4] = target, set per order

local CIRCLE_SEGMENTS = 12
local CIRCLE_OFFSETS = {}
for i = 1, CIRCLE_SEGMENTS do
    local angle = (i - 1) / CIRCLE_SEGMENTS * 2 * math.pi
    CIRCLE_OFFSETS[i] = { math.cos(angle), math.sin(angle) }
end

local NOTIFICATION_CAPACITY = 3
local NOTIFICATION_DURATION = 8 -- seconds
local NOTIFICATION_FADE = 0.5 -- seconds
local NOTIFICATION_FONT_SIZE = 16
local NOTIFICATION_LINE_HEIGHT = 30
local NOTIFICATION_COLORS = {
    success = { 0.2, 0.9, 0.2, 1.0 },
    warning = { 1.0, 0.7, 0.1, 1.0 },
    fail = { 1.0, 0.2, 0.2, 1.0 },
    info = { 1.0, 1.0, 1.0, 1.0 },
}

-- Settings saved to the config file, in file order
local PREF_KEYS = {
    "DEBUG_MODE",
    "ALWAYS_DRAW_RENDER_PATH",
    "REPEAT",
    "NOTIFICATIONS",
    "windowX",
    "windowY",
}

-- State
-- ========================================

local prefs = {
    DEBUG_MODE = false,
    ALWAYS_DRAW_RENDER_PATH = false,
    REPEAT = true,
    NOTIFICATIONS = false,
}

local enableBuildOrders = false
local localTeam

-- {builderID = {currentJob, queue = {{buildDef, halfX, halfZ, facing, x, z}}, originalSize,
-- checkTime, updateDelay}}; currentJob is about queue[1]
local buildOrders = {}

-- {unitDefID = {id, name, xsize, zsize, halfX, halfZ, searchRadius}}, see buildLookup()
local priorityDefs = {}
local eraseableDefs = {}
local biggestSearchRadius = 0 -- among priority and eraseable defs

local placementStart -- {x, z} world position where the placement drag started
local toBeReclaimed = {} -- {unitID = true}, reclaimed together every RECLAIM_INTERVAL
local reclaimTimer = 0
local notifications = {} -- {msg, color, t0}, oldest first

local myUI
local uiMainBox
local uiConfigBox
local uiQueueSizeLabel

-- Notifications
-- ========================================

-- Echoes msg and shows it under the window (when enabled); kind picks the color
local function notify(msg, kind)
    Spring.Echo("[" .. WIDGET_NAME .. "] " .. msg)
    if #notifications >= NOTIFICATION_CAPACITY then
        table.remove(notifications, 1)
    end
    table.insert(notifications, {
        msg = msg,
        color = NOTIFICATION_COLORS[kind] or NOTIFICATION_COLORS.info,
        t0 = Spring.GetTimer(),
    })
end

-- Draws the notifications newest first, stacking downwards from (x, y)
local function drawNotifications(x, y)
    local now = Spring.GetTimer()
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        local remaining = NOTIFICATION_DURATION - Spring.DiffTimers(now, notification.t0)
        if remaining <= 0 then
            table.remove(notifications, i)
        else
            local color = notification.color
            local alpha = math.min(1, remaining / NOTIFICATION_FADE)
            gl.Color(color[1], color[2], color[3], color[4] * alpha)
            gl.Text(notification.msg, x, y, NOTIFICATION_FONT_SIZE, "o")
            y = y - NOTIFICATION_LINE_HEIGHT
        end
    end
    gl.Color(1, 1, 1, 1)
end

-- Files
-- ========================================

local function defaultPath(kind)
    return DEFAULTS_DIR .. "/build-orders-" .. kind .. "-default.txt"
end

local function overridePath(kind)
    return OVERRIDES_DIR .. "/build-orders-" .. kind .. ".txt"
end

local function readFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*all")
    file:close()
    return content
end

local function writeOverride(kind, content)
    Spring.CreateDir(OVERRIDES_DIR)
    local file, err = io.open(overridePath(kind), "w")
    if not file then
        return false, err
    end
    file:write(content)
    file:close()
    return true
end

local function loadPreferences()
    local chunk = loadfile(overridePath("config")) or loadfile(defaultPath("config"))
    if not chunk then
        notify("No config file found.", "warning")
        return
    end

    local env = {}
    setfenv(chunk, env)
    if not pcall(chunk) then
        notify("Failed to read the config file.", "fail")
        return
    end
    for _, key in ipairs(PREF_KEYS) do
        if env[key] ~= nil then
            prefs[key] = env[key]
        end
    end
    notify("Config loaded.", "success")
end

local function savePreferences()
    if myUI then
        prefs.windowX, prefs.windowY = myUI.x, myUI.y
    end
    local lines = {}
    for _, key in ipairs(PREF_KEYS) do
        if prefs[key] ~= nil then
            table.insert(lines, key .. " = " .. tostring(prefs[key]))
        end
    end

    local ok, err = writeOverride("config", table.concat(lines, "\n") .. "\n")
    if not ok then
        notify("Failed to save config: " .. tostring(err), "fail")
        return
    end
    notify("Config saved.", "success")
end

-- Reads a unit name list (one per line or comma-separated, # for comments)
local function loadList(kind)
    local content = readFile(overridePath(kind)) or readFile(defaultPath(kind))
    local names = {}
    for line in (content or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            line = line:gsub(",", " "):gsub('"', ""):gsub("'", "")
            for name in line:gmatch("%S+") do
                table.insert(names, name)
            end
        end
    end

    if #names == 0 then
        notify("No valid entries in the " .. kind .. " list.", "warning")
    else
        notify("Loaded " .. kind .. " list with " .. #names .. " entries.", "success")
    end
    return names
end

-- Copies the default list into the user's override file for editing
local function createCustomFile(kind)
    local path = overridePath(kind)
    if readFile(path) then
        notify(path .. " already exists, not overwriting.", "warning")
        return
    end

    local ok, err = writeOverride(kind, readFile(defaultPath(kind)) or "")
    if not ok then
        notify("Failed to create " .. path .. ": " .. tostring(err), "fail")
        return
    end
    notify("Created " .. path .. " from the defaults.", "success")
end

-- Unit def lookup ({unitDefID = buildDef}) for a list of unit def names
local function buildLookup(names)
    local lookup = {}
    for _, name in ipairs(names) do
        local unitDef = UnitDefNames[name]
        if unitDef then
            local halfX = unitDef.xsize * HALF_TILE_SIZE
            local halfZ = unitDef.zsize * HALF_TILE_SIZE
            -- broad phase radius for the blocker search
            local searchRadius = math.sqrt(halfX * halfX + halfZ * halfZ) + TILE_SIZE
            biggestSearchRadius = math.max(biggestSearchRadius, searchRadius)

            lookup[unitDef.id] = {
                id = unitDef.id,
                name = unitDef.translatedHumanName or unitDef.name,
                xsize = unitDef.xsize,
                zsize = unitDef.zsize,
                halfX = halfX,
                halfZ = halfZ,
                searchRadius = searchRadius,
            }
        else
            notify("Unknown unit def '" .. name .. "' in a list.", "fail")
        end
    end
    return lookup
end

-- Placement
-- ========================================

-- Returns isBuilder, canBuild for unitID and all count unit defs in the set buildDefIDs
local function unitCanBuild(unitID, buildDefIDs, count)
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = unitDefID and UnitDefs[unitDefID]
    if not unitDef or not unitDef.isBuilder then
        return false, false
    end
    local matched = 0
    for _, option in ipairs(unitDef.buildOptions) do
        if buildDefIDs[option] then
            matched = matched + 1
        end
    end
    return true, matched == count
end

-- Axis-aligned rectangles given by center and half sizes
local function rectsIntersect(cx1, cz1, halfX1, halfZ1, cx2, cz2, halfX2, halfZ2)
    return math.abs(cx1 - cx2) <= halfX1 + halfX2 and math.abs(cz1 - cz2) <= halfZ1 + halfZ2
end

-- The build def of the active build command, if it's a priority unit
local function getActivePriorityDef()
    local _, cmdID = Spring.GetActiveCommand()
    if cmdID and cmdID < 0 then
        return priorityDefs[-cmdID]
    end
end

-- Snaps a coordinate the way the engine does: footprints of size 2 or 3 (mod 4)
-- center on odd tiles, the others on even ones
local function snapCoordinate(p, size)
    if (size + 0.5) % 4 >= 2 then
        return math.floor(p / SNAP_SIZE) * SNAP_SIZE + TILE_SIZE
    end
    return math.floor((p + TILE_SIZE) / SNAP_SIZE) * SNAP_SIZE
end

local function snapToBuild(px, pz, xsize, zsize)
    return snapCoordinate(px, xsize), snapCoordinate(pz, zsize)
end

-- Line (default), filled rectangle (alt) or hollow rectangle (alt+ctrl) placements
-- between the start and end positions; mimics the engine's placement
local function computePlacements(
    startX,
    startZ,
    endX,
    endZ,
    buildDef,
    facing,
    spacing,
    alt,
    ctrl,
    shift
)
    local xsize, zsize = buildDef.xsize, buildDef.zsize
    if facing == 1 or facing == 3 then
        xsize, zsize = zsize, xsize
    end
    if not shift then
        startX, startZ = endX, endZ
    end
    startX, startZ = snapToBuild(startX, startZ, xsize, zsize)
    endX, endZ = snapToBuild(endX, endZ, xsize, zsize)

    local dx, dz = endX - startX, endZ - startZ
    local tileX = TILE_SIZE * (xsize + spacing * 2)
    local tileZ = TILE_SIZE * (zsize + spacing * 2)
    local xnum = math.max(1, math.floor((math.abs(dx) + tileX * 1.4) / tileX))
    local znum = math.max(1, math.floor((math.abs(dz) + tileZ * 1.4) / tileZ))
    local xstep = dx >= 0 and tileX or -tileX
    local zstep = dz >= 0 and tileZ or -tileZ

    local queue = {}
    -- Pushes count snapped positions from (x, z) on, stepping by (xstep0, zstep0)
    local function fillRow(x, z, xstep0, zstep0, count)
        for i = 0, count - 1 do
            local bx, bz = snapToBuild(x + i * xstep0, z + i * zstep0, xsize, zsize)
            queue[#queue + 1] = { x = bx, z = bz }
        end
    end

    if alt and ctrl then
        -- hollow rectangle, in the engine's order: left, bottom, right, top side
        if xnum == 1 then
            fillRow(startX, startZ, 0, zstep, znum)
        elseif znum == 1 then
            fillRow(startX, startZ, xstep, 0, xnum)
        else
            fillRow(startX, startZ + zstep, 0, zstep, znum - 1)
            fillRow(startX + xstep, startZ + (znum - 1) * zstep, xstep, 0, xnum - 1)
            fillRow(startX + (xnum - 1) * xstep, startZ + (znum - 2) * zstep, 0, -zstep, znum - 1)
            fillRow(startX + (xnum - 2) * xstep, startZ, -xstep, 0, xnum - 1)
        end
    elseif alt then
        -- filled rectangle, snaking through the rows
        for row = 0, znum - 1 do
            local z = startZ + row * zstep
            if row % 2 == 1 then
                fillRow(startX + (xnum - 1) * xstep, z, -xstep, 0, xnum)
            else
                fillRow(startX, z, xstep, 0, xnum)
            end
        end
    elseif math.abs(dx) > math.abs(dz) then
        -- line along x; ctrl keeps it straight, otherwise it follows the slope
        zstep = ctrl and 0 or xstep * (dz / (dx ~= 0 and dx or 1))
        fillRow(startX, startZ, xstep, zstep, xnum)
    else
        xstep = ctrl and 0 or zstep * (dx / (dz ~= 0 and dz or 1))
        fillRow(startX, startZ, xstep, zstep, znum)
    end

    return queue
end

-- Placements of the active priority build command, dragged from placementStart to (endX, endZ)
local function computeActivePlacements(endX, endZ)
    local buildDef = getActivePriorityDef()
    if not buildDef then
        return nil
    end

    local facing = Spring.GetBuildFacing() % 4
    local halfX, halfZ = buildDef.halfX, buildDef.halfZ
    if facing == 1 or facing == 3 then
        halfX, halfZ = halfZ, halfX
    end
    local alt, ctrl, _, shift = Spring.GetModKeyState()

    local positions = computePlacements(
        placementStart.x,
        placementStart.z,
        endX,
        endZ,
        buildDef,
        facing,
        Spring.GetBuildSpacing(),
        alt,
        ctrl,
        shift
    )
    -- Each position becomes a job that knows what to build
    for _, pos in ipairs(positions) do
        pos.buildDef, pos.halfX, pos.halfZ, pos.facing = buildDef, halfX, halfZ, facing
    end
    return { buildDef = buildDef, halfX = halfX, halfZ = halfZ, positions = positions }
end

-- Gives unitID the jobs placements.positions[startIdx, endIdx); shift adds them to its build
-- order. New jobs overlapping queued ones cancel each other out.
local function assignJobs(unitID, placements, startIdx, endIdx, shift)
    local order = buildOrders[unitID]
    if not (shift and order) then
        Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, {})
        order = { currentJob = nil, queue = {} }
        buildOrders[unitID] = order
    end

    local queue = order.queue
    local overlapping = {}
    for i = startIdx, endIdx - 1 do
        local new = placements.positions[i]
        local overlaps = false
        for _, job in ipairs(queue) do
            if
                rectsIntersect(
                    new.x,
                    new.z,
                    new.halfX - HALF_TILE_SIZE,
                    new.halfZ - HALF_TILE_SIZE,
                    job.x,
                    job.z,
                    job.halfX - HALF_TILE_SIZE,
                    job.halfZ - HALF_TILE_SIZE
                )
            then
                table.insert(overlapping, job)
                overlaps = true
            end
        end
        if not overlaps then
            queue[#queue + 1] = new
        end
    end

    for _, job in ipairs(overlapping) do
        for i = #queue, 1, -1 do
            if queue[i] == job then
                table.remove(queue, i)
                break
            end
        end
    end

    order.originalSize = #queue
    notify("Build Order for " .. #queue .. " buildings CREATED.", "success")
end

-- Splits the selection into builders that get build orders and helpers that guard them.
-- Builders can build every job's building. distribute: every one of them gets a share;
-- otherwise only the first one does.
local function splitBuilders(selectedUnits, jobs, distribute)
    local buildDefIDs, count = {}, 0
    for _, job in ipairs(jobs) do
        if not buildDefIDs[job.buildDef.id] then
            buildDefIDs[job.buildDef.id] = true
            count = count + 1
        end
    end

    local builders, helpers = {}, {}
    for _, unitID in ipairs(selectedUnits) do
        local isBuilder, canBuild = unitCanBuild(unitID, buildDefIDs, count)
        if canBuild and (distribute or #builders == 0) then
            builders[#builders + 1] = unitID
        elseif isBuilder then
            helpers[#helpers + 1] = unitID
        end
    end

    -- More builders than jobs: the extra ones help instead
    while distribute and #builders > #jobs do
        helpers[#helpers + 1] = table.remove(builders, 1)
    end
    return builders, helpers
end

-- Gives the placements to the builders among unitIDs (see splitBuilders); the others guard them
local function distributeJobs(unitIDs, placements, distribute, shift)
    local jobCount = #placements.positions
    local builders, helpers = splitBuilders(unitIDs, placements.positions, distribute)
    if #builders == 0 then
        return
    end

    -- Even shares of the placements; the first builders take the remainder
    local share = math.floor(jobCount / #builders)
    local remainder = jobCount - share * #builders
    local nextJob = 1
    for i, unitID in ipairs(builders) do
        local count = share + (i <= remainder and 1 or 0)
        assignJobs(unitID, placements, nextJob, nextJob + count, shift)
        nextJob = nextJob + count
    end

    for i, helperID in ipairs(helpers) do
        Spring.GiveOrderToUnit(
            helperID,
            CMD.GUARD,
            { builders[(i - 1) % #builders + 1] },
            { "shift" }
        )
    end
end

local function hasBuildCommands(unitID)
    for _, cmd in ipairs(Spring.GetUnitCommands(unitID, -1) or {}) do
        if cmd.id < 0 then
            return true
        end
    end
    return false
end

-- Re-splits the build orders of unitIDs between all of them, like placing with SPACE held.
-- Units without an order but with build commands of their own are left out. Returns the
-- units taken over as {unitID = true}, or nil when none of them has a build order. Other
-- widgets (Split Builder Queue) call it through WG.buildOrders.split.
local function resplit(unitIDs)
    local placements = { positions = {} }
    local units = {}
    local taken = {}
    local hadOrders = false
    for _, unitID in ipairs(unitIDs) do
        local order = buildOrders[unitID]
        if order then
            hadOrders = true
            -- A job its builder already got the order for stays with it: another builder
            -- would skip it, blocked by the nanoframe
            local keep = order.currentJob and 1 or 0
            for i = keep + 1, #order.queue do
                table.insert(placements.positions, order.queue[i])
                order.queue[i] = nil
            end
            if keep == 0 then
                buildOrders[unitID] = nil
            end
        end
        if order or not hasBuildCommands(unitID) then
            units[#units + 1] = unitID
            taken[unitID] = true
        end
    end
    if not hadOrders then
        return nil
    end

    -- shift: builders that kept their job add their share to it
    distributeJobs(units, placements, true, true)
    return taken
end

-- Reclaim
-- ========================================

-- Own turrets (other than targetID) that can reach targetID
local function nanosNearTarget(targetID)
    local x, _, z = Spring.GetUnitPosition(targetID)
    if not x then
        return {}
    end

    local nanos = {}
    for _, unitID in ipairs(Spring.GetUnitsInCylinder(x, z, MAX_TURRET_RANGE)) do
        local range = TURRET_RANGES[Spring.GetUnitDefID(unitID)]
        if
            range
            and unitID ~= targetID
            and Spring.GetUnitTeam(unitID) == localTeam
            and Spring.GetUnitSeparation(targetID, unitID, true) + 10 <= range
        then
            nanos[#nanos + 1] = unitID
        end
    end
    return nanos
end

-- Splits the turrets in range evenly between the targets; targets reachable by
-- the fewest turrets pick first
local function reclaimTargets(targetIDs)
    local targets = {}
    local available = {} -- {nanoID = true} until assigned
    local nanoCount = 0
    for targetID in pairs(targetIDs) do
        local nanos = nanosNearTarget(targetID)
        targets[#targets + 1] = { id = targetID, nanos = nanos }
        for _, nanoID in ipairs(nanos) do
            if not available[nanoID] then
                available[nanoID] = true
                nanoCount = nanoCount + 1
            end
        end
    end
    if nanoCount == 0 then
        return
    end

    local share = math.max(1, math.floor(nanoCount / #targets))
    table.sort(targets, function(a, b)
        return #a.nanos < #b.nanos
    end)
    for _, target in ipairs(targets) do
        local picked = {}
        for _, nanoID in ipairs(target.nanos) do
            if #picked >= share then
                break
            end
            if available[nanoID] then
                available[nanoID] = nil
                picked[#picked + 1] = nanoID
            end
        end
        if #picked > 0 then
            RECLAIM_PARAMS[4] = target.id
            Spring.GiveOrderToUnitArray(picked, CMD.INSERT, RECLAIM_PARAMS, INSERT_OPTIONS)
        end
    end
end

-- {unitID = unitDefID} of the ground units (but builderID) overlapping the job's footprint
local function findBlockers(job, builderID)
    local x, z = job.x, job.z
    local halfX, halfZ = job.halfX - HALF_TILE_SIZE, job.halfZ - HALF_TILE_SIZE
    local radius = job.buildDef.searchRadius + biggestSearchRadius
    local blockers = {}
    for _, unitID in ipairs(Spring.GetUnitsInCylinder(x, z, radius)) do
        local ux, _, uz = Spring.GetUnitPosition(unitID)
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = unitDefID and UnitDefs[unitDefID]
        -- aircraft don't block, and base builders have no collision
        if
            unitID ~= builderID
            and ux
            and unitDef
            and not unitDef.canFly
            and not BASE_BUILDERS[unitDefID]
        then
            local xsize, zsize = unitDef.xsize, unitDef.zsize
            local facing = Spring.GetUnitBuildFacing(unitID) or 0
            if facing == 1 or facing == 3 then
                xsize, zsize = zsize, xsize
            end
            ux, uz = snapToBuild(ux, uz, xsize, zsize)
            if
                rectsIntersect(
                    x,
                    z,
                    halfX,
                    halfZ,
                    ux,
                    uz,
                    xsize * HALF_TILE_SIZE,
                    zsize * HALF_TILE_SIZE
                )
            then
                blockers[unitID] = unitDefID
            end
        end
    end
    return blockers
end

-- Blockers that are not eraseable, of the same type, a turret of the same or a higher
-- tier (non-turrets count as tier 100 when building, 0 when blocking), or someone
-- else's make the job skip the spot instead of reclaiming
local function blocksForGood(job, blockerID, blockerDefID)
    return not eraseableDefs[blockerDefID]
        or blockerDefID == job.buildDef.id
        or (NANO_TIERS[job.buildDef.id] or 100) <= (NANO_TIERS[blockerDefID] or 0)
        or Spring.GetUnitTeam(blockerID) ~= localTeam
end

-- Build order update
-- ========================================

-- Orders the next job once its spot is clear: queues blockers for reclaim, or skips
-- the job when it can't be cleared
local function tryNextJob(builderID, order, now)
    local job = order.queue[1]
    if not job then
        order.currentJob = nil
        return
    end

    local blockers = findBlockers(job, builderID)
    if next(blockers) then
        for blockerID, blockerDefID in pairs(blockers) do
            if blocksForGood(job, blockerID, blockerDefID) then
                table.remove(order.queue, 1)
                notify(
                    "Skipping construction: "
                        .. job.buildDef.name
                        .. ": blocked by non-eraseable unit.",
                    "warning"
                )
                order.currentJob = nil
                return
            end
        end
        for blockerID in pairs(blockers) do
            toBeReclaimed[blockerID] = true
        end
        order.currentJob = nil
    elseif order.currentJob ~= JOB_ORDERED then
        order.currentJob = JOB_ORDERED
        order.checkTime = now + ORDER_RECHECK_DELAY
        local y = Spring.GetGroundHeight(job.x, job.z)
        Spring.GiveOrderToUnit(
            builderID,
            -job.buildDef.id,
            { job.x, y, job.z, job.facing },
            { shift = false }
        )
    end
end

local function updateBuildOrder(builderID, order)
    local now = Spring.GetGameFrame()
    if order.updateDelay then
        if order.updateDelay > now then
            return
        end
        order.updateDelay = nil
    end

    -- Move on once the builder dropped the started building (Holo Place does at its threshold)
    if
        order.currentJob
        and order.currentJob ~= JOB_ORDERED
        and Spring.GetUnitCurrentCommand(builderID) ~= -order.queue[1].buildDef.id
    then
        table.remove(order.queue, 1)
        order.currentJob = nil
    end

    if not order.currentJob then
        if #order.queue == 0 then
            buildOrders[builderID] = nil
            notify("Build Order for " .. order.originalSize .. " buildings COMPLETED.", "success")
        else
            tryNextJob(builderID, order, now)
        end
    elseif order.currentJob == JOB_ORDERED and order.checkTime < now then
        tryNextJob(builderID, order, now)
    end
end

-- Cancels the build order of a builder that is gone or no longer ours
local function cancelBuildOrder(unitID, reason, kind)
    local order = buildOrders[unitID]
    if order then
        notify(reason .. " " .. #order.queue .. " buildings CANCELED.", kind)
        buildOrders[unitID] = nil
    end
end

-- Drawing
-- ========================================

local function drawLine(x1, y1, z1, x2, y2, z2)
    gl.BeginEnd(GL.LINES, function()
        gl.Vertex(x1, y1, z1)
        gl.Vertex(x2, y2, z2)
    end)
end

-- Ground-level rectangle around (x, z), raised by yOffset
local function drawFootprint(x, z, halfX, halfZ, yOffset)
    local y = Spring.GetGroundHeight(x, z) + yOffset
    gl.BeginEnd(GL.QUADS, function()
        gl.Vertex(x - halfX, y, z - halfZ)
        gl.Vertex(x + halfX, y, z - halfZ)
        gl.Vertex(x + halfX, y, z + halfZ)
        gl.Vertex(x - halfX, y, z + halfZ)
    end)
end

-- The queued footprints, joined in build order; the next one is orange
local function drawQueue(order, alpha)
    local prevX, prevY, prevZ
    for i, job in ipairs(order.queue) do
        if i == 1 then
            gl.Color(1.0, 0.5, 0.0, alpha)
        else
            gl.Color(0.0, 0.5, 1.0, alpha)
        end
        drawFootprint(job.x, job.z, job.halfX, job.halfZ, 5)

        local y = Spring.GetGroundHeight(job.x, job.z) + 5
        if prevX then
            gl.LineWidth(6)
            drawLine(prevX, prevY, prevZ, job.x, y, job.z)
        end
        prevX, prevY, prevZ = job.x, y, job.z
    end
end

local function drawDebugInfo(builderID, order, x, y, z)
    local height = (Spring.GetUnitHeight(builderID) or 20) + 15
    gl.Color(1, 1, 1, 1)
    gl.PushMatrix()
    gl.Translate(x + 18, y + height, z - 18)
    gl.Billboard()
    gl.Text("Job: " .. (order.currentJob or "nil") .. "\nQueue: " .. #order.queue, 0, -24, 16, "oc")
    gl.PopMatrix()
end

-- Line from the builder to its building, and a circle around the builder
local function drawCurrentJob(order, x, y, z)
    gl.LineWidth(2)
    gl.Color(0.0, 0.5, 1.0, 0.4)
    local tx, ty, tz = Spring.GetUnitPosition(order.currentJob)
    if tx then
        drawLine(x, y, z, tx, ty, tz)
    end

    local radius = 35
    gl.BeginEnd(GL.LINE_LOOP, function()
        for _, offset in ipairs(CIRCLE_OFFSETS) do
            gl.Vertex(x + radius * offset[1], y + 5, z + radius * offset[2])
        end
    end)
end

-- Preview of the placements while dragging a priority building
local function drawPlacementPreview()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    local placements = pos and computeActivePlacements(pos[1], pos[3])
    if not placements then
        return
    end

    gl.Texture(false)
    gl.Blending(true)
    gl.DepthTest(false)
    gl.Color(0.0, 0.35, 1.0, 0.45)
    for _, p in ipairs(placements.positions) do
        drawFootprint(p.x, p.z, placements.halfX, placements.halfZ, 2)
    end
end

-- UI toolkit (keep in sync with layout-planner.lua)
-- ========================================

local TITLE_BAR_HEIGHT = 32
local TOOLTIP_FONT_SIZE = 16
local TRANSPARENT = { 0, 0, 0, 0 }

local currentTooltip = nil -- tooltip of the hovered element, picked while drawing

local function contains(el, mx, my)
    return mx >= el.x and mx <= el.x + el.width and my >= el.y and my <= el.y + el.height
end

-- True if the mouse is over el; also makes el's tooltip the one shown this frame
local function isHovered(el)
    local mx, my = Spring.GetMouseState()
    local hovered = contains(el, mx, my)
    if hovered and el.tooltip then
        currentTooltip = el.tooltip
    end
    return hovered
end

local function lighten(color, factor)
    return {
        color[1] + (1 - color[1]) * factor,
        color[2] + (1 - color[2]) * factor,
        color[3] + (1 - color[3]) * factor,
        color[4] or 1,
    }
end

local function drawBackground(el, color)
    gl.Color(color)
    gl.Rect(el.x, el.y, el.x + el.width, el.y + el.height)
end

-- Draws el.text vertically centered, starting at x
local function drawText(el, x)
    gl.Color(el.fontColor)
    gl.Text(el.text, x, el.y + (el.height - el.fontSize) / 2 + 2, el.fontSize, "")
end

local function drawTooltip()
    if not currentTooltip then
        return
    end

    local padding = 6
    local lineHeight = TOOLTIP_FONT_SIZE + 4
    local lines = {}
    local width = 0
    for line in currentTooltip:gmatch("[^\n]+") do
        table.insert(lines, line)
        width = math.max(width, gl.GetTextWidth(line) * TOOLTIP_FONT_SIZE)
    end
    local height = #lines * lineHeight - 4 + 2 * padding

    local mx, my = Spring.GetMouseState()
    my = math.min(my + 6, select(2, gl.GetViewSizes()) - height - 2) -- keep it on screen
    gl.Color(0.9, 0.5, 0.1, 0.9)
    gl.Rect(mx - 2, my - 6, mx + width + 2 * padding + 2, my + height + 2)
    gl.Color(1, 1, 1, 1)
    local y = my + height - padding - TOOLTIP_FONT_SIZE
    for _, line in ipairs(lines) do
        gl.Text(line, mx + padding, y, TOOLTIP_FONT_SIZE, "")
        y = y - lineHeight
    end
end

-- Elements have x, y (bottom-left), width and height in screen pixels; containers
-- position their children while drawing. MousePress is only called on a hit.
local function makeElement(params)
    return {
        x = 0,
        y = 0,
        width = params.width or 100,
        height = params.height or 30,
        bgColor = params.bgColor or TRANSPARENT,
        margin = params.margin or 0,
        padding = params.padding or 0,
        tooltip = params.tooltip,
        GetSize = function(self)
            return self.width, self.height
        end,
        Draw = function() end,
        MousePress = function()
            return false
        end,
    }
end

local function makeBox(params)
    local box = makeElement(params)
    box.orientation = params.orientation or "vertical"
    box.padding = params.padding or 4
    box.spacing = params.spacing or 4
    box.children = {}

    function box:Add(child)
        table.insert(self.children, child)
    end

    function box:GetSize()
        local width, height = 0, 0
        for i, child in ipairs(self.children) do
            local cw, ch = child:GetSize()
            local gap = i > 1 and self.spacing or 0
            if self.orientation == "vertical" then
                height = height + ch + 2 * child.margin + gap
                width = math.max(width, cw + 2 * child.margin)
            else
                width = width + cw + 2 * child.margin + gap
                height = math.max(height, ch + 2 * child.margin)
            end
        end
        self.width = width + 2 * self.padding
        self.height = height + 2 * self.padding
        return self.width, self.height
    end

    function box:Draw()
        drawBackground(self, self.bgColor)
        local x = self.x + self.padding
        local top = self.y + self.height - self.padding
        for _, child in ipairs(self.children) do
            local cw, ch = child:GetSize()
            child.x = x + child.margin
            child.y = top - ch - child.margin
            child:Draw()
            if self.orientation == "vertical" then
                top = top - ch - 2 * child.margin - self.spacing
            else
                x = x + cw + 2 * child.margin + self.spacing
            end
        end
    end

    function box:MousePress(mx, my, button)
        for _, child in ipairs(self.children) do
            if contains(child, mx, my) and child:MousePress(mx, my, button) then
                return true
            end
        end
        return false
    end

    return box
end

local function makeLabel(params)
    local label = makeElement(params)
    label.text = params.text or ""
    label.fontSize = params.fontSize or 16
    label.fontColor = params.fontColor or { 1, 1, 1, 1 }

    function label:GetSize()
        self.width = gl.GetTextWidth(self.text) * self.fontSize + 10
        self.height = self.fontSize + 10
        return self.width + 2 * self.margin, self.height + 2 * self.margin
    end

    function label:Draw()
        isHovered(self)
        drawBackground(self, self.bgColor)
        drawText(self, self.x + 5)
    end

    return label
end

-- onClick(button)
local function makeButton(params)
    local button = makeLabel(params)
    button.onClick = params.onClick

    function button:Draw()
        drawBackground(self, isHovered(self) and lighten(self.bgColor, 0.4) or self.bgColor)
        drawText(self, self.x + 5)
    end

    function button:MousePress()
        self:onClick()
        return true
    end

    return button
end

-- onToggle(checked)
local function makeCheckbox(params)
    local checkbox = makeLabel(params)
    checkbox.checked = params.checked or false
    checkbox.onToggle = params.onToggle

    function checkbox:GetSize()
        self.width = gl.GetTextWidth(self.text) * self.fontSize + 30
        self.height = self.fontSize + 4
        return self.width + 2 * self.margin + self.height + 10, self.height + 2 * self.margin
    end

    function checkbox:Draw()
        local shade = isHovered(self) and 0.3 or 0.2
        drawBackground(self, self.bgColor)

        local size = self.height
        local x = self.x + 5
        gl.Color(shade, shade, shade, 1)
        gl.Rect(x, self.y, x + size, self.y + size)
        if self.checked then
            gl.Color(0, 0.8, 0.1, 1)
            gl.Rect(x + 2, self.y + 2, x + size - 2, self.y + size - 2)
        end
        drawText(self, x + size + 5)
    end

    function checkbox:MousePress()
        self.checked = not self.checked
        self.onToggle(self.checked)
        return true
    end

    return checkbox
end

-- Draggable window with title bar buttons (params.titleButtons = list of button
-- params, laid out left to right at the right end of the title bar).
-- Unlike other elements, x, y is its top-left corner.
local function makeWindow(params)
    local window = makeElement(params)
    window.title = params.title
    window.fontSize = params.fontSize or 18
    window.fontColor = params.fontColor or { 1, 1, 1, 1 }
    window.content = params.content
    window.dragging = false
    window.dragOffsetX = 0
    window.dragOffsetY = 0

    local titleButtons = {}
    for _, buttonParams in ipairs(params.titleButtons) do
        local titleButton = makeButton(buttonParams)
        titleButton:GetSize() -- the window never sizes them while drawing
        table.insert(titleButtons, titleButton)
    end

    -- Grows with the content, but doesn't shrink when the content is swapped;
    -- always fits the title and its buttons
    function window:GetSize()
        local cw, ch = self.content:GetSize()
        local titleWidth = gl.GetTextWidth(self.title) * self.fontSize + 15
        for _, titleButton in ipairs(titleButtons) do
            titleWidth = titleWidth + titleButton.width + 4
        end
        self.width = math.max(self.width, cw, titleWidth)
        self.height = TITLE_BAR_HEIGHT + self.padding + ch
        return self.width, self.height
    end

    function window:Draw()
        self:GetSize()
        local vsx, vsy = gl.GetViewSizes()
        -- keep the title bar on screen
        self.x = math.max(0, math.min(self.x, vsx - self.width))
        self.y = math.max(TITLE_BAR_HEIGHT, math.min(self.y, vsy))
        local right = self.x + self.width
        currentTooltip = nil

        gl.Color(self.bgColor)
        gl.Rect(self.x, self.y - self.height, right, self.y)
        gl.Color(0.1, 0.1, 0.1, 1)
        gl.Rect(self.x, self.y - TITLE_BAR_HEIGHT, right, self.y)
        gl.Color(self.fontColor)
        gl.Text(self.title, self.x + 5, self.y - TITLE_BAR_HEIGHT + 7, self.fontSize, "")

        local x = right
        for i = #titleButtons, 1, -1 do
            local titleButton = titleButtons[i]
            x = x - titleButton.width - 4
            titleButton.x = x
            titleButton.y = self.y - TITLE_BAR_HEIGHT + 4
            titleButton:Draw()
        end

        self.content.x = self.x
        self.content.y = self.y - self.height
        self.content:Draw()

        drawTooltip()
    end

    function window:MousePress(mx, my, button)
        for _, titleButton in ipairs(titleButtons) do
            if contains(titleButton, mx, my) then
                return titleButton:MousePress()
            end
        end
        local onTitleBar = mx >= self.x
            and mx <= self.x + self.width
            and my <= self.y
            and my >= self.y - TITLE_BAR_HEIGHT
        if onTitleBar then
            self.dragging = true
            self.dragOffsetX = mx - self.x
            self.dragOffsetY = my - self.y
            return true
        end
        return self.content:MousePress(mx, my, button)
    end

    function window:MouseMove(mx, my)
        if self.dragging then
            self.x = mx - self.dragOffsetX
            self.y = my - self.dragOffsetY
        end
    end

    function window:MouseRelease()
        self.dragging = false
    end

    return window
end

-- UI
-- ========================================

local HELP_TEXT = [[
BUILD ORDERS: click "Enable", then place buildings as usual
  Priority buildings get built exactly where you place them:
  blockers on the Eraseable list are reclaimed by turrets in range,
  other blockers are skipped; with no turret in range the order waits
  Non-priority buildings are built normally
  [SHIFT] adds to the queue (any building or rotation); without it the queue is replaced
  Hold [SPACE] while placing to split the buildings between selected builders
  [N] skips the current building of the selected builders
  Move, stop, fight and similar orders without [SHIFT] cancel the build order
  With Holo Place, builders move on at its build progress threshold
  Repeat Mode rebuilds a building destroyed before that threshold
LISTS: unit def names, editable after "Create Custom ... File" in Settings
  Priority: buildings that may reclaim what blocks them
  Eraseable: units that may be reclaimed for them
  A unit can be on both lists; construction turrets are by default
  Eraseable units are reclaimed even when they are also priority
  A turret can't erase a turret of its own or a higher tier
  A builder never reclaims itself]]

-- Button colors by role
local GREY = { 0.3, 0.3, 0.3, 1.0 } -- everything else
local CYAN = { 0.0, 0.6, 0.6, 1.0 } -- toggled on

-- Checkbox for a boolean pref
local function makePrefToggle(text, tooltip, key)
    return makeCheckbox({
        text = text,
        tooltip = tooltip,
        checked = prefs[key],
        onToggle = function(checked)
            prefs[key] = checked
            notify(text .. ": " .. (checked and "ON" or "OFF"))
        end,
    })
end

local function makeCustomFileButton(kind)
    return makeButton({
        text = "Create Custom " .. kind:gsub("^%l", string.upper) .. " File",
        tooltip = "Copy the default " .. kind .. " list to " .. OVERRIDES_DIR .. "/ to edit it",
        bgColor = GREY,
        onClick = function()
            createCustomFile(kind)
        end,
    })
end

local function createUI()
    local mainRow = makeBox({ orientation = "horizontal", spacing = 6, padding = 0 })
    mainRow:Add(makeButton({
        text = "Enable",
        tooltip = "Take over build commands (turning off keeps active orders)",
        bgColor = enableBuildOrders and CYAN or GREY,
        onClick = function(self)
            enableBuildOrders = not enableBuildOrders
            self.bgColor = enableBuildOrders and CYAN or GREY
            notify("Build Orders: " .. (enableBuildOrders and "ON" or "OFF"))
        end,
    }))
    uiQueueSizeLabel = makeLabel({})
    mainRow:Add(uiQueueSizeLabel)
    uiMainBox = makeBox({ padding = 6, spacing = 6 })
    uiMainBox:Add(mainRow)

    uiConfigBox = makeBox({ padding = 6, spacing = 6 })
    for _, toggle in ipairs({
        { "Repeat Mode", "Rebuild a building destroyed before its Holo Place threshold", "REPEAT" },
        { "Notifications", "Show short event messages under the window", "NOTIFICATIONS" },
        {
            "Always Draw Queue",
            "Always draw builders' queues (debug: may cost FPS)",
            "ALWAYS_DRAW_RENDER_PATH",
        },
        { "Debug", "Draw extra build order data (debug: may cost FPS)", "DEBUG_MODE" },
    }) do
        uiConfigBox:Add(makePrefToggle(unpack(toggle)))
    end
    uiConfigBox:Add(makeCustomFileButton("priority"))
    uiConfigBox:Add(makeCustomFileButton("eraseable"))

    myUI = makeWindow({
        title = WIDGET_NAME,
        fontSize = 22,
        fontColor = { 1, 0.6, 0.0, 1.0 },
        -- the window keeps its widest width, so it paints the background, not the content
        bgColor = { 0.15, 0.15, 0.15, 1 },
        content = uiMainBox,
        titleButtons = {
            {
                text = "Settings",
                bgColor = GREY,
                onClick = function(button)
                    local opening = myUI.content == uiMainBox
                    myUI.content = opening and uiConfigBox or uiMainBox
                    button.bgColor = opening and CYAN or GREY
                    if not opening then
                        savePreferences()
                    end
                end,
            },
            {
                text = "?",
                tooltip = HELP_TEXT,
                bgColor = GREY,
                onClick = function() end,
            },
            {
                text = "X",
                tooltip = "Close the widget",
                bgColor = GREY,
                onClick = function()
                    widgetHandler:RemoveWidget()
                end,
            },
        },
    })
    local _, vsy = gl.GetViewSizes()
    myUI.x = prefs.windowX or 50
    myUI.y = prefs.windowY or vsy / 2 - 330
end

-- Widget callins
-- ========================================

function widget:Initialize()
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget()
        return
    end
    localTeam = Spring.GetLocalTeamID()
    loadPreferences()
    priorityDefs = buildLookup(loadList("priority"))
    eraseableDefs = buildLookup(loadList("eraseable"))
    createUI()
    WG.buildOrders = { split = resplit }
end

function widget:Shutdown()
    WG.buildOrders = nil
    if not myUI then -- removed before setup (spectating), nothing to save
        return
    end
    savePreferences()
    notify("Closed")
end

function widget:MousePress(mx, my, button)
    if button == 3 and placementStart then
        Spring.SetActiveCommand(0)
        placementStart = nil
        return false
    end
    if myUI:MousePress(mx, my, button) then
        return true
    end
    if not enableBuildOrders then
        return false
    end
    if button ~= 1 or placementStart then
        placementStart = nil
        return false
    end
    if not getActivePriorityDef() then
        return false
    end

    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if not pos then
        return false
    end
    placementStart = { x = pos[1], z = pos[3] }
    return true
end

function widget:MouseMove(mx, my)
    myUI:MouseMove(mx, my)
end

-- Turns the dragged placement into build orders for the selected builders
function widget:MouseRelease(mx, my, button)
    if button ~= 1 then
        placementStart = nil
        return false
    end
    myUI:MouseRelease()
    if not placementStart then
        return false
    end

    local _, pos = Spring.TraceScreenRay(mx, my, true)
    local placements = pos and computeActivePlacements(pos[1], pos[3])
    local _, _, _, shift = Spring.GetModKeyState()
    if pos and not shift then
        Spring.SetActiveCommand(0)
    end
    placementStart = nil
    if not placements then
        return false
    end

    distributeJobs(Spring.GetSelectedUnits(), placements, Spring.GetKeyState(KEY_SPACE), shift)
    return false
end

function widget:KeyPress(key)
    if key == KEY_SKIP then
        for _, unitID in ipairs(Spring.GetSelectedUnits()) do
            local order = buildOrders[unitID]
            if order then
                table.remove(order.queue, 1)
                order.currentJob = nil
            end
        end
    end
    return false
end

function widget:CommandNotify(cmdID, _, cmdOptions)
    if (cmdID < 0 or CANCEL_CMDS[cmdID]) and not cmdOptions.shift then
        for _, unitID in ipairs(Spring.GetSelectedUnits()) do
            local order = buildOrders[unitID]
            -- only worth a notification if there was more to build than the current building
            if
                order
                and (
                    #order.queue > 1
                    or (
                        #order.queue == 1
                        and (not order.currentJob or order.currentJob == JOB_ORDERED)
                    )
                )
            then
                cancelBuildOrder(unitID, "Worker received NEW COMMANDS.", "warning")
            end
            buildOrders[unitID] = nil
        end
    end
    return false
end

function widget:UnitCreated(unitID, unitDefID, _, builderID)
    local order = builderID and buildOrders[builderID]
    if order and order.queue[1] and order.queue[1].buildDef.id == unitDefID then
        order.currentJob = unitID
    end
end

function widget:UnitFinished(unitID)
    for builderID, order in pairs(buildOrders) do
        if order.currentJob == unitID then
            table.remove(order.queue, 1)
            order.currentJob = nil
            updateBuildOrder(builderID, order)
            break
        end
    end
end

function widget:UnitDestroyed(unitID)
    for builderID, order in pairs(buildOrders) do
        if order.currentJob == unitID then
            order.currentJob = nil
            if prefs.REPEAT then
                order.updateDelay = Spring.GetGameFrame() + RETRY_DELAY
            end
            notify(
                "Unit " .. builderID .. " lost a " .. order.queue[1].buildDef.name .. " job",
                "warning"
            )
        end
    end
    cancelBuildOrder(unitID, "Worker DESTROYED!", "fail")
end

local function forgetChangedTeamWorker(_, unitID)
    cancelBuildOrder(unitID, "Worker changed team", "fail")
end

widget.UnitGiven = forgetChangedTeamWorker
widget.UnitTaken = forgetChangedTeamWorker

-- Workers queue their blockers in toBeReclaimed; they are all reclaimed together
-- every RECLAIM_INTERVAL
function widget:Update(dt)
    for builderID, order in pairs(buildOrders) do
        updateBuildOrder(builderID, order)
    end

    reclaimTimer = reclaimTimer + dt
    if reclaimTimer > RECLAIM_INTERVAL and next(toBeReclaimed) then
        reclaimTimer = 0
        reclaimTargets(toBeReclaimed)
        toBeReclaimed = {}
    end
end

function widget:DrawWorld()
    gl.PushAttrib(GL.ALL_ATTRIB_BITS)
    gl.DepthTest(true)

    for builderID, order in pairs(buildOrders) do
        local x, y, z = Spring.GetUnitPosition(builderID)
        if x then
            if prefs.DEBUG_MODE then
                drawDebugInfo(builderID, order, x, y, z)
            end

            local alpha = (prefs.ALWAYS_DRAW_RENDER_PATH or prefs.DEBUG_MODE) and 0.3 or 0
            if Spring.IsUnitSelected(builderID) then
                alpha = alpha + 0.3
            end
            if alpha > 0 then
                drawQueue(order, alpha)
            end

            if order.currentJob and order.currentJob ~= JOB_ORDERED then
                drawCurrentJob(order, x, y, z)
            end
        end
    end

    if placementStart then
        drawPlacementPreview()
    end

    gl.PopAttrib()
end

function widget:DrawScreen()
    local queued = 0
    for _, order in pairs(buildOrders) do
        queued = queued + #order.queue
    end
    uiQueueSizeLabel.text = "In queue: " .. queued

    myUI:Draw()
    if prefs.NOTIFICATIONS then
        drawNotifications(myUI.x + 8, myUI.y - myUI.height - 20)
    end
end

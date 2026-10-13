local WIDGET_NAME = "Build Orders"

local WIDGET_DESC = [[
This widget stablishes a mechanism of BuildOrders which will take control of constructor units to force the construction of specific buildings.
You define two lists:
    - PRIORITY list have units that can call for reclaim when its build space is blocked.
    - ERASEABLE list define which units this widget can reclaim to give space for priority units.

Declare which units are priority and which units can be erased on the lists on custom files as you want; use the UnitDef name

BuildOrders will try to make sure a priority building is built where you place them, that means:
    - Priority unit will call reclaim on everything blocking its path that is declared on the ERASEABLE list. The reclaim call will use construction turrets at range to reclaim blocking units. <!> If there's no turrets in range it will stall.
    - It will skip the construction of units that is blocked by non-eraseable units
    - Construction of non priority unit will be handled normally by the engine
    - If a priority unit is destroyed during construction before it reachs its YOLO-PLACE percentage, the BuildOrder will try to assign new build commands at the same place if the REPEAT option is enabled

Some notes:
    - A unit can be both priority and eraseable.
    - BuildOrders will try to reclaim anything on the eraseable list! EVEN OTHER PRIORITY UNITS! if they are also declared as eraseable
    - Construction Turrets are both priority and eraseable by default
    - You can hold Shift to queue units of the same type (trying to enqueue different buildings will cause it to ignore the previous build orders)
    - A constructor cannot reclaim itself with its own build order (although other worker might call to reclaim another blocking worker)
    - This works with HOLO PLACE; build orders will proceed once reach the HOLO-PLACE value
    - Construction turrets cannot erase turrets of the same or higher tiers.
]]

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

local UI = true
-- Defaults ship with the widget; the user's overrides in LuaUI/Config win when present
local DEFAULTS_DIR = "LuaUI/Widgets/build-orders"
local OVERRIDES_DIR = "LuaUI/Config/build-orders"
local reclaimCallDelay = 1 --how many seconds between reclaim calls

local REPEAT = true
local DEBUG_MODE = false
local NOTIFICATIONS = false
local ALWAYS_DRAW_RENDER_PATH = false

local BUILDABLE_NANO_TIER = {}

local function safeAssignNanoTier(name, tier)
    local ud = UnitDefNames[name]
    if ud then
        BUILDABLE_NANO_TIER[ud.id] = tier
    end
end

safeAssignNanoTier("armnanotc", 1)
safeAssignNanoTier("cornanotc", 1)
safeAssignNanoTier("legnanotc", 1)

safeAssignNanoTier("armnanotct2", 2)
safeAssignNanoTier("cornanotct2", 2)
safeAssignNanoTier("legnanotct2", 2)

safeAssignNanoTier("armnanotct3", 3)
safeAssignNanoTier("cornanotct3", 3)
safeAssignNanoTier("legnanotct3", 3)

-- Base builders
local BASE_BUILDERS = {}
local function safeAssignBaseBuilder(name)
    local ud = UnitDefNames[name]
    if ud then
        BASE_BUILDERS[ud.id] = true
    end
end

safeAssignBaseBuilder("correspawn")
safeAssignBaseBuilder("armrespawn")
safeAssignBaseBuilder("legnanotcbase")

local enableBuildOrders = false

local knownYolos = {} --map [id] = yolo value
-- Holo Place (holo-place.lua) modes, indexed by mode + 1: off, smart, 90, 60, 30, ins
local CMD_HOLO_PLACE = 28341
local holoToYolo = {
    1, -- off: 100%
    0.3, -- smart: Holo Place's 30% base threshold
    0.9,
    0.6,
    0.3,
    0.001, -- "instant mode" is not really instant
}

local DiffTimers = Spring.DiffTimers
local GetTimer = Spring.GetTimer
local GetKeyState = Spring.GetKeyState
local GetSelectedUnits = Spring.GetSelectedUnits
local GiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local GetGameFrame = Spring.GetGameFrame
local gl = gl
local UnitDefs = UnitDefs
local UnitDefNames = UnitDefNames
local GetActiveCommand = Spring.GetActiveCommand
local TraceScreenRay = Spring.TraceScreenRay
local GetBuildFacing = Spring.GetBuildFacing
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitTeam = Spring.GetUnitTeam
local GetLocalTeamID = Spring.GetLocalTeamID
local SpEcho = Spring.Echo
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitHealth = Spring.GetUnitHealth
local CIRCLE_SEGMENTS = 12
local KEY_SPACE = 32 -- SDL keycode
local circleOffsets
local SpringGetUnitPosition = Spring.GetUnitPosition
local SpringGetGroundHeight = Spring.GetGroundHeight
local SpringGetSelectedUnits = Spring.GetSelectedUnits
local SpringTraceScreenRay = Spring.TraceScreenRay
local SpringGetMouseState = Spring.GetMouseState

local glColor = gl.Color
local PushAttrib = gl.PushAttrib
local PopAttrib = gl.PopAttrib
local glRect = gl.Rect
local glText = gl.Text
local glGetTextWidth = gl.GetTextWidth
local gl_Color = gl.Color
local gl_BeginEnd = gl.BeginEnd
local gl_LineWidth = gl.LineWidth
local gl_PushAttrib = gl.PushAttrib
local gl_PopAttrib = gl.PopAttrib
local gl_DepthTest = gl.DepthTest
local gl_Texture = gl.Texture
local gl_Blasting = gl.Blending
local gl_BeginEnd_QUADS = GL.QUADS
local gl_BeginEnd_LINE_LOOP = GL.LINE_LOOP
local gl_BeginEnd_TRIANGLE_FAN = GL.TRIANGLE_FAN
local gl_Vertex = gl.Vertex

local TILE_SIZE = 8 -- world units per footprint tile
local TWO_TILE_SIZE = TILE_SIZE * 2 -- the building snap grid is based on 16
local HALF_TILE_SIZE = TILE_SIZE / 2 -- to avoid division later :)

local buildOrder = {} -- [builder id] = {buildDef, halfX, halfZ, currentjob, queue = {x, z}}

--those are maps in form [untiid] = {id, xsize, zsize, xhalf, zhalf, searchRadius, name}
local PRIORITY_LOOKUP = {}
local ERASEABLE_LOOKUP = {}

local maxTurretBuildDist = 0
local TURRET_RANGE_LOOKUP = {}

local localTeam = nil

local initialData --{x, z} --store in world position! when the mouse pressed
local biggestSearchRadius = 0 -- biggest search radius among Priority and Eraseable units

local sentCommands = 0

--
-- Simple notification cache for widgets
local Notify = {
    list = {}, -- notifications: { msg=..., type=..., t0=... }
    capacity = 3, -- max items
    duration = 8.0, -- seconds each notification is visible
    spacing = 2, -- pixels between lines when drawing
    fontSize = 16, -- draw font size
}

-- color map for types (r,g,b,a)
local TYPE_COLORS = {
    success = { 0.2, 0.9, 0.2, 1.0 },
    warning = { 1.0, 0.7, 0.1, 1.0 },
    fail = { 1.0, 0.2, 0.2, 1.0 },
    info = { 1.0, 1.0, 1.0, 1.0 },
}

-- Add a notification
local function Echo(msg, typ)
    if not msg then
        return
    end
    SpEcho("[" .. WIDGET_NAME .. "] " .. msg)

    if not Notify then
        return
    end
    typ = typ or "info"
    if not TYPE_COLORS[typ] then
        typ = "info"
    end

    local now = GetTimer()
    -- drop oldest if full
    if #Notify.list >= Notify.capacity then
        table.remove(Notify.list, 1)
    end
    table.insert(Notify.list, { msg = tostring(msg), type = typ, t0 = now })
end

-- Remove expired notifications
function Notify.Update()
    local now = GetTimer()

    local i = 1
    while i <= #Notify.list do
        local n = Notify.list[i]
        local age = DiffTimers(now, n.t0)
        if age >= Notify.duration then
            table.remove(Notify.list, i)
        else
            i = i + 1
        end
    end
end

-- Return shallow copy
function Notify.GetAll()
    local copy = {}
    for i = 1, #Notify.list do
        copy[i] = Notify.list[i]
    end
    return copy
end

-- Draw notifications on screen (newest at top)
function Notify.DrawScreen(x, y)
    if #Notify.list == 0 then
        return
    end
    local now = GetTimer()
    local drawX, drawY = x, y

    PushAttrib(GL.ALL_ATTRIB_BITS)
    -- iterate from newest to oldest
    for i = #Notify.list, 1, -1 do
        local n = Notify.list[i]
        local age = DiffTimers(now, n.t0)
        local remaining = math.max(0, Notify.duration - age)
        local alpha = 1.0
        local fade = 0.5
        if remaining < fade then
            alpha = remaining / fade
        end

        local col = TYPE_COLORS[n.type] or TYPE_COLORS.info
        glColor(col[1], col[2], col[3], (col[4] or 1) * alpha)

        local padding = 6
        local fs = Notify.fontSize
        local text = n.msg

        -- draw text (white)
        glText(text, drawX, drawY, fs, "o")

        -- stack downward
        drawY = drawY - (fs + Notify.spacing + padding * 2)
    end
    PopAttrib()
end

--GUI STUFF
local myUI
local windowX = nil
local windowY = nil
local uiNumOrdersLabel
local uiQueuSizeLabel
local uiNumJobsLabel
local uiContentBox
local uiConfigBox

local function buildLookups(base)
    local dest = {}
    for _, name in ipairs(base) do
        local ud = UnitDefNames[name]
        if ud then
            local xsize = ud.xsize or 1
            local zsize = ud.zsize or 1
            local halfw = xsize * TILE_SIZE * 0.5
            local halfh = zsize * TILE_SIZE * 0.5
            local radius = math.sqrt(halfw * halfw + halfh * halfh) + TILE_SIZE -- cache search radius

            if radius > biggestSearchRadius then
                biggestSearchRadius = radius
            end

            dest[ud.id] = {
                id = ud.id, -- unitdef id
                name = ud.translatedHumanName or ud.name or "Unidentified", -- name
                xsize = xsize,
                zsize = zsize, -- size  (tiles)
                halfX = halfw,
                halfZ = halfh, --half size (word size)
                searchRadius = radius, --search radius for broad phase intersection test
            }
        else
            Echo(
                "Lookup table construction: could not find unitDef '" .. tostring(name) .. "'",
                "fail"
            ) -- should not really happen
        end
    end
    return dest
end

local function unitCanBuild(unitID, buildUnitDefID)
    if not unitID or not buildUnitDefID then
        return false, false
    end

    local uDefID = Spring.GetUnitDefID(unitID)
    if not uDefID then
        return false, false
    end

    local uDef = UnitDefs[uDefID]
    if not uDef then
        return false, false
    end

    local isBuilder = uDef.isBuilder or false
    local canBuild = false

    if isBuilder and uDef.buildOptions then
        for _, opt in ipairs(uDef.buildOptions) do
            if opt == buildUnitDefID then
                canBuild = true
                break
            end
        end
    end

    return isBuilder, canBuild
end

local function clearUnitCommands(unitID)
    buildOrder[unitID] = nil
    pcall(function()
        GiveOrderToUnitArray({ unitID }, CMD.STOP, {}, {}) -- i might use work groups (not sure) that why i'm using array here
        sentCommands = sentCommands + 1
    end)
end

-- rectangle intersection test for axis-aligned rectangles centered at positions
local function rectsIntersect(cx1, cz1, halfX1, halfZ1, cx2, cz2, halfX2, halfZ2)
    return (math.abs(cx1 - cx2) <= (halfX1 + halfX2)) and (math.abs(cz1 - cz2) <= (halfZ1 + halfZ2))
end

local function getBuildDefFromActiveCommand()
    local _, cmdID = GetActiveCommand()
    if not cmdID or cmdID >= 0 then
        return nil
    end

    local buildUD = -cmdID
    if not buildUD or not UnitDefs[buildUD] then
        return nil
    end

    -- only proceed if this UD is in PRIORITY
    local buildDef = PRIORITY_LOOKUP[buildUD]
    if not buildDef then
        return nil
    end

    return buildDef
end

local function has2(n)
    return (n + 0.5) % 4 >= 2
end

local function snapToBuild(px, pz, xsize, zsize)
    xsize = tonumber(xsize) or 1
    zsize = tonumber(zsize) or 1

    local bx, bz
    if has2(xsize) then
        bx = math.floor(px / TWO_TILE_SIZE) * TWO_TILE_SIZE + TILE_SIZE
    else
        bx = math.floor((px + TILE_SIZE) / TWO_TILE_SIZE) * TWO_TILE_SIZE -- bao
    end

    if has2(zsize) then
        bz = math.floor(pz / TWO_TILE_SIZE) * TWO_TILE_SIZE + TILE_SIZE
    else
        bz = math.floor((pz + TILE_SIZE) / TWO_TILE_SIZE) * TWO_TILE_SIZE -- bao
    end

    return bx, bz
end

local function pushRow(queue, startX, startZ, xstep, zstep, count, xsize, zsize)
    for i = 0, count - 1 do
        local x = startX + i * xstep
        local z = startZ + i * zstep
        local bx, bz = snapToBuild(x, z, xsize, zsize)
        queue[#queue + 1] = { x = bx, z = bz }
    end
end

-- compute rectangle (filled/hollow) and line placements. Mimics the engine
local function computePlacements(
    startX,
    startZ,
    endX,
    endZ,
    buildDef,
    facing,
    buildSpacingTiles,
    altKey,
    ctrlKey,
    shiftKey
)
    buildSpacingTiles = buildSpacingTiles or 0
    altKey = altKey and true or false
    ctrlKey = ctrlKey and true or false

    local xsize, zsize
    if facing == 1 or facing == 3 then
        xsize, zsize = buildDef.zsize, buildDef.xsize --invert
    else
        xsize, zsize = buildDef.xsize, buildDef.zsize
    end

    if not shiftKey then
        startX, startZ = endX, endZ
    end

    startX, startZ = snapToBuild(startX, startZ, xsize, zsize)
    endX, endZ = snapToBuild(endX, endZ, xsize, zsize)

    local queue = {}

    local dx = endX - startX
    local dz = endZ - startZ

    local txsize = TILE_SIZE * ((xsize or 1) + buildSpacingTiles * 2)
    local tzsize = TILE_SIZE * ((zsize or 1) + buildSpacingTiles * 2)

    local absdx = math.abs(dx)
    local absdz = math.abs(dz)

    local xnum = math.floor((absdx + txsize * 1.4) / txsize)
    local znum = math.floor((absdz + tzsize * 1.4) / tzsize)
    if xnum < 1 then
        xnum = 1
    end
    if znum < 1 then
        znum = 1
    end

    local xstep = (dx >= 0) and txsize or -txsize
    local zstep = (dz >= 0) and tzsize or -tzsize

    -- Helper: FillRowOfBuildPos equivalent
    -- startX/startZ: start position (world coords, already a build-pos)
    -- xstep/zstep: step per element
    -- count: how many positions to push
    local function FillRowOfBuildPos(startX0, startZ0, xstep0, zstep0, count)
        pushRow(queue, startX0, startZ0, xstep0, zstep0, count, xsize, zsize)
    end

    if altKey then
        -- build rectangle (filled or hollow depending on ctrlKey)
        if ctrlKey then
            -- hollow rectangle (outline)
            -- replicate the C++ ordering (left -> bottom -> right -> top)
            -- compute the required offsets similar to C++ code
            -- note: C++ used start/end modified by other building size in circle case; here we assume basic rectangle
            -- go "down" on the "left" side
            FillRowOfBuildPos(startX, startZ + zstep, 0, zstep, znum - 1)
            -- go "right" on the "bottom" side
            FillRowOfBuildPos(startX + xstep, startZ + (znum - 1) * zstep, xstep, 0, xnum - 1)
            -- go "up" on the "right" side
            FillRowOfBuildPos(
                startX + (xnum - 1) * xstep,
                startZ + (znum - 2) * zstep,
                0,
                -zstep,
                znum - 1
            )
            -- go "left" on the "top" side
            FillRowOfBuildPos(startX + (xnum - 2) * xstep, startZ, -xstep, 0, xnum - 1)
            -- handle degenerate cases where xnum==1 or znum==1 as in C++:
            if xnum == 1 and znum > 0 then
                queue = {}
                FillRowOfBuildPos(startX, startZ, 0, zstep, znum)
            elseif znum == 1 and xnum > 0 then
                queue = {}
                FillRowOfBuildPos(startX, startZ, xstep, 0, xnum)
            end
        else
            -- filled rectangle: snake through rows
            local zcur = startZ
            for zn = 0, znum - 1 do
                if (zn % 2) == 1 then
                    -- odd line: right -> left
                    FillRowOfBuildPos(startX + (xnum - 1) * xstep, zcur, -xstep, 0, xnum)
                else
                    -- even line: left -> right
                    FillRowOfBuildPos(startX, zcur, xstep, 0, xnum)
                end
                zcur = zcur + zstep
            end
        end
    else
        -- line placement
        local xDominatesZ = (absdx > absdz)

        if xDominatesZ then
            -- when not ctrl, zstep is proportional to dx/dz to create a slanted line
            if ctrlKey then
                zstep = 0
            else
                zstep = xstep * (dz / (dx ~= 0 and dx or 1))
            end
            FillRowOfBuildPos(startX, startZ, xstep, zstep, xnum)
        else
            if ctrlKey then
                xstep = 0
            else
                xstep = zstep * (dx / (dz ~= 0 and dz or 1))
            end
            FillRowOfBuildPos(startX, startZ, xstep, zstep, znum)
        end
    end

    return queue
end

local function computePlacementFromActiveCommand(ex, ez)
    local buildDef = getBuildDefFromActiveCommand()
    if not buildDef then
        return nil
    end

    local facing = 0
    if GetBuildFacing then
        local ok, f = pcall(GetBuildFacing)
        if ok and type(f) == "number" then
            facing = f
        end
    end

    facing = facing % 4

    local placementHalfX, placementHalfZ
    if facing == 1 or facing == 3 then
        placementHalfX, placementHalfZ = buildDef.halfZ, buildDef.halfX
    else
        placementHalfX, placementHalfZ = buildDef.halfX, buildDef.halfZ
    end

    local placements = {
        buildDef = buildDef,
        halfX = placementHalfX,
        halfZ = placementHalfZ,
        facing = facing,
        positions = nil,
    }

    local alt, ctrl, _, shift = Spring.GetModKeyState()
    local spacing = Spring.GetBuildSpacing()

    placements.positions = computePlacements(
        initialData.x,
        initialData.z,
        ex,
        ez,
        buildDef,
        facing,
        spacing,
        alt,
        ctrl,
        shift
    )

    return placements
end

local function nanosNearTarget(targetUnitID)
    local tx, _, tz = GetUnitPosition(targetUnitID)
    if not tx then
        return {}
    end
    local candidates = GetUnitsInCylinder(tx, tz, maxTurretBuildDist) or {}
    local nanos = {}
    for _, candID in ipairs(candidates) do
        if candID ~= targetUnitID and GetUnitTeam(candID) == localTeam then
            local candDefID = GetUnitDefID(candID)
            local buildDist = TURRET_RANGE_LOOKUP[candDefID]
            if buildDist then
                local sep = GetUnitSeparation(targetUnitID, candID, true) + 10
                if sep <= buildDist then
                    nanos[#nanos + 1] = candID
                end
            end
        end
    end
    return nanos
end

local INSERT_OPT = { "alt" }
local REC_PARAMS = { 0, CMD.RECLAIM, CMD.OPT_SHIFT, 0 } -- reuse/copy as needed

-- this method can be better. Too messy and heavy?
local function reclaimHitsImmediate(hits) --hits = map[int] = true
    -- build map[targetID] = { nanoID, ... } and nanoTag set
    local map = {}
    local nanoTag = {} -- nanoTag[nanoID] = true
    local minNanos = math.huge

    local targetCount = 0
    for hitUnitId, _ in pairs(hits) do
        local nanosInRange = nanosNearTarget(hitUnitId) or {}
        map[hitUnitId] = nanosInRange
        targetCount = targetCount + 1

        -- track all unique nanos
        for _, nid in ipairs(nanosInRange) do
            nanoTag[nid] = true
        end

        if #nanosInRange < minNanos then
            minNanos = #nanosInRange
        end
    end

    -- count unique nanos
    local nanoCount = 0
    for _ in pairs(nanoTag) do
        nanoCount = nanoCount + 1
    end
    if nanoCount == 0 then
        return
    end

    -- share = how many nanos to use per target (floor division), at least 1
    local share = math.max(1, math.floor(nanoCount / math.max(1, targetCount)))

    -- build sortable list of targets and sort by ascending number of reachable nanos
    local targets = {}
    for tid, nanos in pairs(map) do
        targets[#targets + 1] = { id = tid, nanos = nanos }
    end
    table.sort(targets, function(a, b)
        return (#a.nanos < #b.nanos)
    end)

    -- for each target, pick up to `share` still-available nanos and issue reclaim
    for _, t in ipairs(targets) do
        local tid = t.id
        if tid then
            local availableNanos = {}
            for _, nid in ipairs(t.nanos) do
                if nanoTag[nid] then
                    -- reserve this nano
                    nanoTag[nid] = nil
                    availableNanos[#availableNanos + 1] = nid
                end
                if #availableNanos >= share then
                    break
                end
            end

            if #availableNanos > 0 then
                REC_PARAMS[4] = tid
                Spring.GiveOrderToUnitArray(availableNanos, CMD.INSERT, REC_PARAMS, INSERT_OPT)
                sentCommands = sentCommands + 1
            end
        end
    end
end

local function findIntersectingUnits(order, wx, wz, ignoreUnit)
    local radius = order.buildDef.searchRadius + biggestSearchRadius
    local candidates = GetUnitsInCylinder(wx, wz, radius) or {} --broad phase with cyulinder

    local halfX, halfZ = order.halfX - HALF_TILE_SIZE, order.halfZ - HALF_TILE_SIZE
    local hits = {} -- structure: [id] = unitDefId
    for _, uid in ipairs(candidates) do
        if uid ~= ignoreUnit then
            local ux, _, uz = GetUnitPosition(uid)
            if ux then
                local unitDefID = GetUnitDefID(uid)
                local uDef = UnitDefs[unitDefID]

                if uDef and not uDef.canFly and not BASE_BUILDERS[unitDefID] then --ignore flying units, i can build where they are
                    --ignore base builders, since they dont have collision (would be nice to have a dynamic flag, but i didn't find one yet)

                    local xsize = uDef.xsize
                    local zsize = uDef.zsize

                    local facing = Spring.GetUnitBuildFacing(uid) or 0
                    if facing == 1 or facing == 3 then
                        xsize, zsize = zsize, xsize
                    end

                    local uHalfX = xsize * HALF_TILE_SIZE
                    local uHalfZ = zsize * HALF_TILE_SIZE

                    ux, uz = snapToBuild(ux, uz, xsize, zsize)
                    if rectsIntersect(wx, wz, halfX, halfZ, ux, uz, uHalfX, uHalfZ) then
                        hits[uid] = unitDefID
                    end
                end
            end
        end
    end

    return hits
end

local function resetPlacementLocalData()
    initialData = nil
end

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

local function SaveUserPreferences()
    local lines = {
        "DEBUG_MODE = " .. tostring(DEBUG_MODE),
        "ALWAYS_DRAW_RENDER_PATH = " .. tostring(ALWAYS_DRAW_RENDER_PATH),
        "REPEAT = " .. tostring(REPEAT),
        "NOTIFICATIONS = " .. tostring(NOTIFICATIONS),
    }
    if myUI then
        table.insert(lines, "windowX = " .. myUI.x)
        table.insert(lines, "windowY = " .. myUI.y)
    end

    local ok, err = writeOverride("config", table.concat(lines, "\n") .. "\n")
    if not ok then
        Echo("Failed to save config: " .. tostring(err), "fail")
        return
    end
    Echo("Config saved.", "success")
end

-- Reads a unit name list (one per line or comma-separated, # for comments)
local function InitializeList(kind)
    local content = readFile(overridePath(kind)) or readFile(defaultPath(kind))
    local parsed = {}
    for line in (content or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        if line ~= "" and not line:match("^#") then
            -- Replace commas with spaces and remove quotes
            line = line:gsub(",", " "):gsub('"', ""):gsub("'", "")
            for word in line:gmatch("%S+") do
                table.insert(parsed, word)
            end
        end
    end

    if #parsed == 0 then
        Echo("No valid entries in the " .. kind .. " list.", "warning")
    else
        Echo("Loaded " .. kind .. " list with " .. #parsed .. " entries.", "success")
    end
    return parsed
end

local function InitializePriorityAndEraseables()
    PRIORITY_LOOKUP = buildLookups(InitializeList("priority"))
    ERASEABLE_LOOKUP = buildLookups(InitializeList("eraseable"))
end

-- Copies the default list into the user's override file for editing
local function CreateCustomFile(kind)
    if readFile(overridePath(kind)) then
        Echo(overridePath(kind) .. " already exists, not overwriting.", "warning")
        return
    end

    local ok, err = writeOverride(kind, readFile(defaultPath(kind)) or "")
    if not ok then
        Echo("Failed to create " .. overridePath(kind) .. ": " .. tostring(err), "fail")
        return
    end
    Echo("Created " .. overridePath(kind) .. " from the defaults.", "success")
end

local function LoadUserPreferences()
    local chunk = loadfile(overridePath("config")) or loadfile(defaultPath("config"))
    if not chunk then
        Echo("No config file found.", "warning")
        return
    end

    local env = {}
    setfenv(chunk, env)
    chunk()

    DEBUG_MODE = env.DEBUG_MODE ~= false
    ALWAYS_DRAW_RENDER_PATH = env.ALWAYS_DRAW_RENDER_PATH ~= false
    REPEAT = env.REPEAT ~= false
    NOTIFICATIONS = env.NOTIFICATIONS ~= false
    windowX = env.windowX or windowX
    windowY = env.windowY or windowY

    Echo("Config loaded.", "success")
end

local currentToolTip = nil
--------------------------------------------------------------------------------
-- Base Component
local function BaseElement(params)
    return {
        x = params.x or 0,
        y = params.y or 0,
        width = params.width or 100,
        height = params.height or 30,
        bgColor = params.bgColor or { 0.1, 0.1, 0.1, 0.8 },
        margin = params.margin or 0,
        padding = params.padding or 0,
        tooltip = params.tooltip,

        Draw = function() end,
        MousePress = function()
            return false
        end,
        KeyPress = function() end,

        GetSize = function(self)
            return self.width, self.height
        end,

        Hover = function(self, mx, my)
            if
                self.tooltip
                and mx >= self.x
                and mx <= self.x + self.width
                and my >= self.y
                and my <= self.y + self.height
            then
                currentToolTip = self.tooltip
                return true
            end
            return false
        end,
    }
end

local function Box(params)
    local box = BaseElement(params)
    box.orientation = params.orientation or "vertical"
    box.padding = params.padding or 4
    box.spacing = params.spacing or 4
    box.children = {}

    function box:Add(child)
        table.insert(self.children, child)
    end

    function box:Remove(child)
        for i, c in ipairs(self.children) do
            if c == child then
                table.remove(self.children, i)
                return true -- successfully removed
            end
        end
        return false -- child not found
    end

    function box:Hover(mx, my)
        for _, child in ipairs(self.children) do
            if child:Hover(mx, my) then
                return true
            end
        end
        return false
    end

    function box:GetSize()
        local totalWidth, totalHeight = 0, 0

        for i, child in ipairs(self.children) do
            local cw, ch = child:GetSize()
            local margin = child.margin or 0

            if self.orientation == "vertical" then
                totalHeight = totalHeight + ch + 2 * margin
                if i > 1 then
                    totalHeight = totalHeight + self.spacing
                end
                totalWidth = math.max(totalWidth, cw + 2 * margin)
            else
                totalWidth = totalWidth + cw + 2 * margin
                if i > 1 then
                    totalWidth = totalWidth + self.spacing
                end
                totalHeight = math.max(totalHeight, ch + 2 * margin)
            end
        end

        self.width = totalWidth + 2 * self.padding
        self.height = totalHeight + 2 * self.padding
        return self.width, self.height
    end

    function box:Draw()
        glColor(self.bgColor)
        glRect(self.x, self.y, self.x + self.width, self.y + self.height)

        local cx = self.x + self.padding
        local cyTop = self.y + self.height - self.padding -- Top Y

        if self.orientation == "vertical" then
            local cy = cyTop
            for _, child in ipairs(self.children) do
                local _, ch = child:GetSize()
                local margin = child.margin or 0
                cy = cy - ch - 2 * margin
                child.x = cx + margin
                child.y = cy + margin
                child:Draw()
                cy = cy - self.spacing
            end
        else
            for _, child in ipairs(self.children) do
                local cw, ch = child:GetSize()
                local margin = child.margin or 0
                child.x = cx + margin
                -- Align to top of box (subtract height and margin from top)
                child.y = cyTop - ch - margin
                child:Draw()
                cx = cx + cw + 2 * margin + self.spacing
            end
        end
    end

    function box:MousePress(mx, my, button)
        for _, child in ipairs(self.children) do
            if
                mx >= child.x
                and mx <= child.x + child.width
                and my >= child.y
                and my <= child.y + child.height
            then
                if child:MousePress(mx, my, button) then
                    return true
                end
            end
        end
        return false
    end

    function box:KeyPress(char)
        for _, child in ipairs(self.children) do
            if child.KeyPress then
                child:KeyPress(char)
            end
        end
    end

    return box
end

local function MakeLabel(params)
    local label = BaseElement(params)
    label.text = params.text or ""
    label.fontSize = params.fontSize or 14
    label.fontColor = params.fontColor or { 1, 1, 1, 1 }

    function label:GetSize()
        local textWidth = glGetTextWidth(self.text) * self.fontSize
        local textHeight = self.fontSize
        self.width = textWidth + 10
        self.height = textHeight + 18
        return self.width + 2 * self.margin, self.height + 2 * self.margin
    end

    function label:Draw()
        glColor(self.bgColor)
        glRect(self.x, self.y, self.x + self.width, self.y + self.height)
        glColor(self.fontColor)
        glText(
            self.text,
            self.x + 5,
            self.y + (self.height - self.fontSize) / 2 + 2,
            self.fontSize,
            ""
        )
    end

    return label
end

local function MakeCheckbox(params)
    local cb = MakeLabel(params)
    cb.checked = params.checked or false
    cb.onToggle = params.onToggle or function(_) end
    cb.hovered = false

    function cb:Draw()
        --background
        glColor(self.bgColor)
        glRect(self.x, self.y, self.x + self.width, self.y + self.height)
        --selection box
        local boxSize = self.height * 1
        local boxX = self.x + 5
        local boxY = self.y + (self.height - boxSize) / 2
        if self.hovered then
            glColor(0.3, 0.3, 0.3, 1)
            self.hovered = false
        else
            glColor(0.2, 0.2, 0.2, 1)
        end

        glRect(boxX, boxY, boxX + boxSize, boxY + boxSize)
        if self.checked then
            local inset = 2
            glColor(0, 0.8, 0.1, 1)
            glRect(boxX + inset, boxY + inset, boxX + boxSize - inset, boxY + boxSize - inset)
        end
        --text
        glColor(self.fontColor)
        glText(
            self.text,
            boxSize + self.x + 10,
            self.y + (self.height - self.fontSize) / 2 + 2,
            self.fontSize,
            ""
        )
    end

    function cb:GetSize()
        local textWidth = glGetTextWidth(self.text) * self.fontSize
        local textHeight = self.fontSize
        self.height = textHeight + 4
        self.width = textWidth + 10 + 20
        return self.width + 2 * self.margin + self.height + 10, self.height + 2 * self.margin
    end

    function cb:Hover(mx, my)
        cb.hovered = mx >= self.x
            and mx <= self.x + self.width
            and my >= self.y
            and my <= self.y + self.height
        if cb.hovered and self.tooltip then
            currentToolTip = self.tooltip
        end
        return cb.hovered
    end

    function cb:MousePress(mx, my)
        if
            mx >= self.x
            and mx <= self.x + self.width
            and my >= self.y
            and my <= self.y + self.height
        then
            self.checked = not self.checked
            self.onToggle(self.checked)
            return true
        end
        return false
    end

    return cb
end

local function lightenColor(color, factor)
    factor = math.max(0, math.min(factor or 0.4, 1))

    local r = color[1] + (1 - color[1]) * factor
    local g = color[2] + (1 - color[2]) * factor
    local b = color[3] + (1 - color[3]) * factor
    local a = color[4] or 1

    return { r, g, b, a }
end

local function MakeButton(params)
    local button = MakeLabel(params)
    button.onClick = params.onClick or function() end
    button.hovered = false
    function button:MousePress(mx, my)
        if
            mx >= self.x
            and mx <= self.x + self.width
            and my >= self.y
            and my <= self.y + self.height
        then
            self:onClick()
            return true
        end
        return false
    end

    function button:Draw()
        if self.hovered then
            glColor(lightenColor(self.bgColor))
            self.hovered = false
        else
            glColor(self.bgColor)
        end

        glRect(self.x, self.y, self.x + self.width, self.y + self.height)
        glColor(self.fontColor)
        glText(
            self.text,
            self.x + 5,
            self.y + (self.height - self.fontSize) / 2 + 2,
            self.fontSize,
            ""
        )
    end

    function button:Hover(mx, my)
        button.hovered = mx >= self.x
            and mx <= self.x + self.width
            and my >= self.y
            and my <= self.y + self.height
        if button.hovered and self.tooltip then
            currentToolTip = self.tooltip
        end
        return button.hovered
    end

    return button
end

local function MakeWindow(params)
    local window = BaseElement(params)
    window.title = params.title or "Window"
    window.dragging = false
    window.fontSize = params.fontSize or 18
    window.fontColor = params.fontColor or { 1, 1, 1, 1 }
    window.bgColor = params.bgColor or { 0.2, 0.2, 0.2, 0.9 }
    window.offsetX = 0
    window.offsetY = 0
    window.content = params.content
    window.closed = false

    local titleBarHeight = 32
    local padding = 4

    local configButton = MakeButton({
        bgColor = { 0.2, 0.2, 0.6, 1.0 },
        height = titleBarHeight - 8,
        text = " Open Config ",
        config = false,
        onClick = function(self)
            -- toggle config state
            self.config = not self.config
            if self.config then
                self.text = "Close Config"
                myUI.content = uiConfigBox
            else
                self.text = "Open Config"
                myUI.content = uiContentBox
                SaveUserPreferences()
            end
        end,
    })

    window.closeButton = configButton

    -- DRAW
    function window:Draw()
        if self.closed then
            return
        end

        -- Compute content size
        local cw, ch = self.content:GetSize()
        self.width = math.max(self.width or 0, cw)
        self.height = titleBarHeight + padding + ch -- total window height

        -- Draw window background
        glColor(self.bgColor)
        glRect(self.x, self.y - self.height, self.x + self.width, self.y)

        -- Draw title bar at the top
        glColor({ 0.1, 0.1, 0.1, 1 })
        glRect(self.x, self.y - titleBarHeight, self.x + self.width, self.y)
        glColor(unpack(self.fontColor))
        glText(self.title, self.x + 5, self.y - titleBarHeight + 7, self.fontSize, "")

        -- Close button
        if self.closeButton then
            self.closeButton.x = self.x + self.width - 104
            self.closeButton.y = self.y - titleBarHeight + 4
            self.closeButton:Draw()
        end
        -- Draw content below title bar
        if self.content then
            self.content.x = self.x
            self.content.y = self.y - titleBarHeight - padding - ch -- top-left of content
            self.content:Draw()
        end

        -- Tooltip
        if currentToolTip then
            local mx, my = Spring.GetMouseState()
            my = my + 6
            local tooltipFontSize = 16
            local lineSpacing = 4
            local tooltipPadding = 6
            local border = 2

            local lines = {}
            for line in currentToolTip:gmatch("[^\n]+") do
                table.insert(lines, line)
            end

            local maxLineWidth = 0
            for _, line in ipairs(lines) do
                maxLineWidth = math.max(maxLineWidth, glGetTextWidth(line) * tooltipFontSize)
            end

            local tooltipWidth = maxLineWidth + 2 * tooltipPadding
            local tooltipHeight = (#lines * (tooltipFontSize + lineSpacing))
                - lineSpacing
                + 2 * tooltipPadding

            glColor(0.9, 0.5, 0.1, 0.9)
            glRect(
                mx - border,
                my - border - 4,
                mx + tooltipWidth + border,
                my + tooltipHeight + border
            )

            glColor(1, 1, 1, 1)
            local textY = my + tooltipHeight - tooltipPadding - tooltipFontSize
            for _, line in ipairs(lines) do
                glText(line, mx + tooltipPadding, textY, tooltipFontSize, "")
                textY = textY - (tooltipFontSize + lineSpacing)
            end
        end
    end

    -- HOVER
    function window:Hover(mx, my)
        if self.closeButton and self.closeButton:Hover(mx, my) then
            return true
        end
        if self.content then
            return self.content:Hover(mx, my)
        end
        return false
    end

    -- MOUSE PRESS
    function window:MousePress(mx, my, button)
        if self.closeButton and self.closeButton:MousePress(mx, my) then
            return true
        elseif
            mx >= self.x
            and mx <= self.x + self.width
            and my <= self.y
            and my >= self.y - titleBarHeight
        then
            self.dragging = true
            self.offsetX = mx - self.x
            self.offsetY = my - self.y
            return true
        elseif self.content and self.content:MousePress(mx, my, button) then
            return true
        end
        return false
    end

    -- MOUSE MOVE
    function window:MouseMove(mx, my)
        if self.dragging then
            self.x = mx - self.offsetX
            self.y = my - self.offsetY
        end
    end

    -- MOUSE RELEASE
    function window:MouseRelease()
        self.dragging = false
    end

    return window
end

local function setJobList(unitID, placements, startIdx, endIdx, shift)
    if not unitID or not placements or not placements.positions then
        return
    end

    local order = buildOrder[unitID]
    if
        shift
        and order
        and order.buildDef == placements.buildDef
        and order.facing == placements.facing
    then
    --queue = order.queue --enqueue commands
    else
        clearUnitCommands(unitID)

        --Create a new build order
        buildOrder[unitID] =
            { -- hmm i probably can cache placements data on every unitid here, and create work groups that can assume other jobs when complete. But not now
                buildDef = placements.buildDef,
                halfX = placements.halfX,
                halfZ = placements.halfZ,
                facing = placements.facing,
                yoloplace = knownYolos[unitID] or 1.0,
                currentjob = nil,
                queue = {},
            }

        order = buildOrder[unitID]
    end

    local queue = order.queue
    local positions = placements.positions

    --Remove overlap orders
    local halfXi = placements.halfX - HALF_TILE_SIZE
    local halfZi = placements.halfZ - HALF_TILE_SIZE
    local acceptedJobs = 0
    local overlappingQueueItems = {} -- collect actual queue objects

    for i = startIdx, endIdx - 1 do
        local pos = positions[i]
        local px, pz = pos.x, pos.z

        local hasOverlap = false
        for _, queuePos in ipairs(queue) do
            if rectsIntersect(px, pz, halfXi, halfZi, queuePos.x, queuePos.z, halfXi, halfZi) then
                table.insert(overlappingQueueItems, queuePos)
                hasOverlap = true
            end
        end

        if not hasOverlap then
            queue[#queue + 1] = {
                ud = placements.buildDef.id,
                x = px,
                z = pz,
            }
            acceptedJobs = acceptedJobs + 1
        end
    end

    -- Remove overlapping items from the queue
    for _, item in ipairs(overlappingQueueItems) do
        for i = #queue, 1, -1 do
            if queue[i] == item then
                table.remove(queue, i)
                break
            end
        end
    end
    order.originalSize = #queue
    Echo("Build Order for " .. #queue .. "x " .. placements.buildDef.name .. " CREATED.", "success")
    return acceptedJobs
end

function widget:MousePress(mx, my, button)
    if button == 3 and initialData then -- Right button
        Spring.SetActiveCommand(0)
        resetPlacementLocalData()
        return false
    end

    if myUI and myUI:MousePress(mx, my, button) then
        return true
    end

    if not enableBuildOrders then
        return false
    end
    if button ~= 1 then -- Left Button
        resetPlacementLocalData()
        return false
    end

    if initialData then
        resetPlacementLocalData()
        return false
    end

    local buildDef = getBuildDefFromActiveCommand()
    if not buildDef then
        return false
    end

    resetPlacementLocalData()

    if not mx or not my then
        return false
    end

    local _, pos = TraceScreenRay(mx, my, true)
    if not pos then
        return false
    end

    initialData = { x = pos[1], z = pos[3] }
    return true
end

function widget:MouseRelease(mx, my, button)
    if button ~= 1 then
        resetPlacementLocalData()
        return false
    end

    if myUI then
        myUI:MouseRelease()
    end

    if not mx or not my or not initialData then
        resetPlacementLocalData()
        return false
    end

    local _, pos = TraceScreenRay(mx, my, true)
    if not pos then
        resetPlacementLocalData()
        return false
    end
    local sx, sz = pos[1], pos[3]

    local placements = computePlacementFromActiveCommand(sx, sz)
    local _, _, _, shift = Spring.GetModKeyState()
    if not shift then
        Spring.SetActiveCommand(0)
    end

    resetPlacementLocalData()
    if not placements then
        return false
    end

    if not placements or not placements.buildDef then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then
        return
    end

    local distributeOrders = GetKeyState(KEY_SPACE)

    --collect builders and helpers among selected untis
    local allowedBuilders = {}
    local helpers = {}
    local jobsToDo = #placements.positions

    if distributeOrders then
        for _, unitID in ipairs(selectedUnits) do
            local isBuilder, canBuild = unitCanBuild(unitID, placements.buildDef.id)
            if canBuild then
                allowedBuilders[#allowedBuilders + 1] = unitID
            elseif isBuilder then
                helpers[#helpers + 1] = unitID
            end
        end

        local workerCount = #allowedBuilders
        if jobsToDo < workerCount then --if there is more workers than JOBS, send exceeding works to helpers
            local transfer = workerCount - jobsToDo
            for _ = 1, transfer do
                helpers[#helpers + 1] = allowedBuilders[1]
                table.remove(allowedBuilders, 1)
            end
        end
    else
        -- Not distributing order: set one as builder, and others as helpers
        for _, unitID in ipairs(selectedUnits) do
            local isBuilder, canBuild = unitCanBuild(unitID, placements.buildDef.id)
            if isBuilder then
                if #allowedBuilders == 0 and canBuild then
                    allowedBuilders[#allowedBuilders + 1] = unitID
                else
                    helpers[#helpers + 1] = unitID
                end
            end
        end
    end

    if #allowedBuilders == 0 then
        resetPlacementLocalData()
        return false
    end

    local workerCount = #allowedBuilders

    --split work more less equally among workers
    local jobShare = math.floor(jobsToDo / workerCount) -- this should be a integer but we are in floating hell
    local remainderJobs = jobsToDo - (jobShare * workerCount)

    local originalJobQueuePointer = 1 --?
    for _, unitID in ipairs(allowedBuilders) do
        local workerJobs = jobShare
        if remainderJobs > 0 then
            workerJobs = workerJobs + 1
            remainderJobs = remainderJobs - 1
        end
        setJobList(
            unitID,
            placements,
            originalJobQueuePointer,
            originalJobQueuePointer + workerJobs,
            shift
        )
        originalJobQueuePointer = originalJobQueuePointer + workerJobs
    end

    local workerIdx = 1
    for _, helper in ipairs(helpers) do
        local worker = allowedBuilders[workerIdx]
        Spring.GiveOrderToUnit(helper, CMD.GUARD, { worker }, { "shift" })
        sentCommands = sentCommands + 1
        workerIdx = workerIdx + 1
        if workerIdx > workerCount then
            workerIdx = 1
        end
    end
    return false
end

local accumulator = 0

function widget:MouseMove(x, y)
    if myUI then
        return myUI:MouseMove(x, y)
    end
end

local toBeReclaimed = {}

local function updateWorker(unitid, entry)
    if not entry then
        return
    end

    local now = GetGameFrame()

    if entry.updateDelay then
        if entry.updateDelay > now then
            return
        else
            entry.updateDelay = nil
        end
    end

    local queue = entry.queue

    --worker might yolo its jobzb
    if entry.currentjob and entry.currentjob ~= -1 then
        local _, _, _, _, buildProgress = GetUnitHealth(entry.currentjob)
        if buildProgress and buildProgress >= entry.yoloplace then
            table.remove(entry.queue, 1) -- drop the queue element, and yolo the next building
            entry.currentjob = nil
            --Echo("Unit "..unitid.." yoloing its way to progress!")
        end
    end

    local function checkAndClearSpace()
        local nextOrder = queue[1]

        if nextOrder == nil then
            entry.currentjob = -1
            entry.queue = nil
            return
        end

        local hits = findIntersectingUnits(entry, nextOrder.x, nextOrder.z, unitid)
        if next(hits) then -- check if hits has anything
            local removeNext = false
            for hitUnitId, hitUnitDefId in pairs(hits) do
                -- Cancel queue item if a blocker:
                --    is not eraseable
                --    is the same unitDef as the one being built
                --    if blocker and unit are nanos, but blocker have the same or higher tier (if a unit is not a nano, i give it a high "tier" (100) just to pass the test over any nano)
                --    if blocker is from another player
                if
                    not ERASEABLE_LOOKUP[hitUnitDefId]
                    or hitUnitDefId == entry.buildDef.id
                    or ((BUILDABLE_NANO_TIER[entry.buildDef.id] or 100) - (BUILDABLE_NANO_TIER[hitUnitDefId] or 0)) <= 0
                    or GetUnitTeam(hitUnitId) ~= localTeam
                then
                    removeNext = true
                    break
                end
            end
            if removeNext then
                table.remove(queue, 1) -- drop the queue element, osme block cannot be reclaimed
                Echo(
                    "Skipping construction: "
                        .. entry.buildDef.name
                        .. ": blocked by non-eraseable unit. ",
                    "warning"
                )
            else
                for hitUnitID, _ in pairs(hits) do
                    toBeReclaimed[hitUnitID] = true
                end
            end
            entry.currentjob = nil
        elseif entry.currentjob ~= -1 then
            -- Remove the next order from the queue
            entry.currentjob = -1 --place holder so the widget does not call the order again next update
            entry.checktime = now + 30 * 5
            local terrainY = Spring.GetGroundHeight(nextOrder.x, nextOrder.z)
            Spring.GiveOrderToUnit(
                unitid,
                -entry.buildDef.id,
                { nextOrder.x, terrainY, nextOrder.z, entry.facing },
                { shift = false }
            )
            sentCommands = sentCommands + 1
        end
    end

    --search next job:
    if not entry.currentjob then
        if not queue or #queue == 0 then
            buildOrder[unitid] = nil
            Echo(
                "Build Order for "
                    .. entry.originalSize
                    .. "x "
                    .. entry.buildDef.name
                    .. " COMPLETED.",
                "success"
            )
        else
            checkAndClearSpace()
        end
    elseif entry.currentjob == -1 and (entry.checktime or 0) < now then
        checkAndClearSpace()
    end
end

--[[
  update all worker, they will mark everything to be reclaimed on the same list, so further on the update I can reclaim everything at once.
  buildorders will regiester the interest to reclaim something on the "tobereclaimed" set. The widget will call reclaim base on reclaimCallDelay
]]
function widget:Update(dt)
    if myUI then
        currentToolTip = nil
        local mx, my = Spring.GetMouseState()
        myUI:Hover(mx, my)
        Notify.Update()
    end

    --update all workers
    for unitid, entry in pairs(buildOrder) do
        updateWorker(unitid, entry)
    end

    accumulator = accumulator + dt
    if accumulator > reclaimCallDelay and next(toBeReclaimed) then -- delay between reclaim calls
        accumulator = 0
        reclaimHitsImmediate(toBeReclaimed)
        toBeReclaimed = {}
    end
end

local function ensureCircleOffsets()
    if circleOffsets then
        return
    end
    circleOffsets = {}
    for i = 0, CIRCLE_SEGMENTS - 1 do
        local t = (i / CIRCLE_SEGMENTS) * 2 * math.pi
        circleOffsets[i + 1] = { math.cos(t), math.sin(t) }
    end
end

local function DrawLineBetweenPoints(x1, y1, z1, x2, y2, z2)
    gl.PushAttrib(GL.ALL_ATTRIB_BITS)
    gl.DepthTest(true)

    gl.BeginEnd(GL.LINES, function()
        gl.Vertex(x1, y1, z1)
        gl.Vertex(x2, y2, z2)
    end)

    gl.LineWidth(1)
    gl.Color(1, 1, 1, 1)
    gl.PopAttrib()
end

function widget:DrawWorld()
    ensureCircleOffsets()

    local selectedUnits = SpringGetSelectedUnits() or {}

    gl_PushAttrib(GL.ALL_ATTRIB_BITS)
    gl_DepthTest(true)
    gl_LineWidth(2)

    local function drawBuildOrderPath(order, alpha)
        local px, py, pz
        if order and order.queue then
            for idx = 1, #order.queue do
                local pos = order.queue[idx]
                local halfX, halfZ = order.halfX, order.halfZ
                local x1, z1 = pos.x - halfX, pos.z - halfZ
                local x2, z2 = pos.x + halfX, pos.z + halfZ
                local y = (SpringGetGroundHeight and SpringGetGroundHeight(pos.x, pos.z) or 0) + 5

                if idx == 1 then
                    gl_Color(1.0, 0.5, 0.0, alpha)
                else
                    gl_Color(0.0, 0.5, 1.0, alpha)
                end

                gl_BeginEnd(gl_BeginEnd_TRIANGLE_FAN, function()
                    gl_Vertex(x1, y, z1)
                    gl_Vertex(x2, y, z1)
                    gl_Vertex(x2, y, z2)
                    gl_Vertex(x1, y, z2)
                end)

                if px then
                    gl_LineWidth(6)
                    DrawLineBetweenPoints(px, py, pz, pos.x, y, pos.z)
                end

                px = pos.x
                py = y
                pz = pos.z
            end
        end
    end

    for builderID, order in pairs(buildOrder) do
        if order then
            local ux, uy, uz = SpringGetUnitPosition(builderID)
            if ux then
                if DEBUG_MODE then
                    gl.Color(1, 1, 1, 1)
                    gl.Texture("#" .. order.buildDef.id)
                    local height = (Spring.GetUnitHeight(builderID) or 20) + 15 -- offset above turret
                    gl.PushMatrix()
                    gl.Translate(ux + 18, uy + height, uz - 18)
                    gl.Billboard() -- make it always face the camera
                    local size = 16 -- icon size in world units
                    -- gl.TexRect(-size, -size, size, size)

                    local text = "Job: "
                        .. (order.currentjob or "nil")
                        .. "\nQueue: "
                        .. #order.queue
                    gl.Text(text, 0, -size - 8, 16, "oc") -- (string, x, y, size, options)
                    gl.PopMatrix()
                end

                local alpha = 0
                if ALWAYS_DRAW_RENDER_PATH or DEBUG_MODE then
                    alpha = 0.3
                end
                for _, unitID in ipairs(selectedUnits) do
                    if unitID == builderID then
                        alpha = alpha + 0.3
                        break
                    end
                end

                if alpha > 0 then
                    drawBuildOrderPath(order, alpha)
                end

                if order.currentjob and order.currentjob ~= -1 then
                    gl_LineWidth(2)
                    gl_Color(0.0, 0.5, 1.0, 0.4)
                    local tx, ty, tz = SpringGetUnitPosition(order.currentjob)
                    --draws a line from the constructor position to the working location
                    DrawLineBetweenPoints(ux, uy, uz, tx, ty, tz)
                    --draw a circle around the worker
                    local radius = 35
                    local oy = (uy or 0) + 5
                    gl_BeginEnd(gl_BeginEnd_LINE_LOOP, function()
                        for j = 1, CIRCLE_SEGMENTS do
                            local off = circleOffsets[j]
                            gl_Vertex(ux + radius * off[1], oy, uz + radius * off[2])
                        end
                    end)
                end
            end
        end
    end

    gl_LineWidth(1)
    gl_Color(1, 1, 1, 1)
    gl_PopAttrib()

    if initialData then
        local mx, my = SpringGetMouseState()
        local _, pos = SpringTraceScreenRay(mx, my, true)
        if not pos then
            return
        end
        local sx, sz = pos[1], pos[3]
        local placements = computePlacementFromActiveCommand(sx, sz)
        if not placements or not placements.positions then
            return
        end

        local baseHalfX = tonumber(placements.halfX) or 1
        local baseHalfZ = tonumber(placements.halfZ) or 1

        gl_Texture(false)
        gl_Blasting(true)
        gl_DepthTest(false)
        gl_Color(0.0, 0.35, 1.0, 0.45)

        for i = 1, #placements.positions do
            local p = placements.positions[i]
            local cx = p[1] or p.x
            local cz = p[2] or p.z
            if cx and cz then
                local hx, hz = baseHalfX, baseHalfZ
                local x1 = cx - hx
                local x2 = cx + hx
                local z1 = cz - hz
                local z2 = cz + hz
                local y = (SpringGetGroundHeight and SpringGetGroundHeight(cx, cz) or 0) + 2

                gl_BeginEnd(gl_BeginEnd_QUADS, function()
                    gl_Vertex(x1, y, z1)
                    gl_Vertex(x2, y, z1)
                    gl_Vertex(x2, y, z2)
                    gl_Vertex(x1, y, z2)
                end)
            end
        end

        gl_Color(1, 1, 1, 1)
        gl_DepthTest(true)
        gl_Blasting(false)
        gl_Texture(true)
    end
end

function widget:KeyPress(key)
    -- advance the buildorder queue manually with the N key
    if key == 110 then
        local selectedUnits = Spring.GetSelectedUnits()
        for _, unitID in ipairs(selectedUnits) do
            local order = buildOrder[unitID]
            if order then
                if order.queue and #order.queue > 0 then
                    table.remove(order.queue, 1)
                end
                order.currentjob = nil
            end
        end
    end

    return false
end

function widget:UnitCreated(unitID, unitDefID, _, builderID)
    if builderID and builderID ~= 0 and buildOrder[builderID] then
        local entry = buildOrder[builderID]
        if entry and entry.buildDef.id == unitDefID then
            entry.currentjob = unitID
        end
    end
end

function widget:UnitFinished(unitID)
    for builderID, entry in pairs(buildOrder) do
        if entry.currentjob == unitID then
            table.remove(entry.queue, 1) --finished a job
            entry.currentjob = nil
            updateWorker(builderID, entry)
            break
        end
    end
end

function widget:UnitDestroyed(unitID)
    for builderID, entry in pairs(buildOrder) do
        if entry.currentjob == unitID then
            entry.currentjob = nil
            if REPEAT then
                entry.updateDelay = GetGameFrame() + 15
            end
            Echo("Unit " .. builderID .. " lost a " .. entry.buildDef.name .. " job", "warning")
        end
    end

    -- also remove buildOrder if the builder itself is destroyed
    if buildOrder[unitID] then
        local entry = buildOrder[unitID]
        Echo(
            "Worker DESTROYED! " .. #entry.queue .. "x " .. entry.buildDef.name .. " CANCELED.",
            "fail"
        )
        buildOrder[unitID] = nil
    end
    if knownYolos[unitID] then
        knownYolos[unitID] = nil
    end
end

-- a builder changed team, remove its buildOrder entry
local function forgetChangedTeamWorker(_, unitID)
    if buildOrder[unitID] then
        local entry = buildOrder[unitID]
        Echo(
            "Worker changed team " .. #entry.queue .. "x " .. entry.buildDef.name .. " CANCELED.",
            "fail"
        )
        buildOrder[unitID] = nil
    end
    knownYolos[unitID] = nil
end

widget.UnitGiven = forgetChangedTeamWorker
widget.UnitTaken = forgetChangedTeamWorker

local CANCEL_CMDS = {}
local CANCEL_CMD_NAMES = {
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
}
for _, name in ipairs(CANCEL_CMD_NAMES) do
    local c = CMD[name]
    if type(c) == "number" then
        CANCEL_CMDS[c] = true
    end
end

local function optsHasShift(opts)
    if not opts then
        return false
    end
    if type(opts) == "table" then
        if opts.shift == true then
            return true
        end
        for _, v in ipairs(opts) do
            if v == "shift" then
                return true
            end
        end
    end
    return false
end

local function setYoloPlace(val)
    local sel = GetSelectedUnits() or {}
    for _, uid in ipairs(sel) do
        knownYolos[uid] = val
        if buildOrder and buildOrder[uid] then
            buildOrder[uid].yoloplace = val
        end
    end
    --Echo("Holo Place "..val)
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    if not cmdID then
        return false
    end

    if cmdID == CMD_HOLO_PLACE then -- Use Holo as Yolo
        local yolo = holoToYolo[cmdParams[1] + 1]
        setYoloPlace(yolo)
        return
    end

    local isBuildCmd = (type(cmdID) == "number" and cmdID < 0)
    local shouldCancel = false
    if isBuildCmd then
        shouldCancel = true
    elseif CANCEL_CMDS[cmdID] then
        shouldCancel = true
    end

    if shouldCancel and not optsHasShift(cmdOptions) then
        local sel = Spring.GetSelectedUnits() or {}
        for _, uid in ipairs(sel) do
            if buildOrder and buildOrder[uid] then
                local entry = buildOrder[uid]
                if
                    #entry.queue > 1
                    or (#entry.queue == 1 and (not entry.currentjob or entry.currentjob == -1))
                then
                    Echo(
                        "Worker received NEW COMMANDS. "
                            .. #entry.queue
                            .. "x "
                            .. entry.buildDef.name
                            .. " CANCELED.",
                        "warning"
                    )
                end
                buildOrder[uid] = nil
            end
        end
    end

    return false
end

function widget:Initialize()
    -- if Spring.GetSpectatingState() then
    --		widgetHandler:RemoveWidget()
    --	return
    --	end
    localTeam = GetLocalTeamID()
    LoadUserPreferences()

    for udid, ud in pairs(UnitDefs) do
        if ud.isBuilder and not ud.canMove and not ud.isFactory then
            TURRET_RANGE_LOOKUP[udid] = ud.buildDistance
            --Echo(ud.name)
            if ud.buildDistance and ud.buildDistance > maxTurretBuildDist then
                maxTurretBuildDist = ud.buildDistance
            end
        end
    end

    InitializePriorityAndEraseables()

    if not UI then
        enableBuildOrders = true
        return
    end

    -- GUI
    uiNumOrdersLabel = MakeLabel({
        text = "a",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
    })
    uiQueuSizeLabel = MakeLabel({
        text = "b",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
    })
    uiNumJobsLabel = MakeLabel({
        text = "c",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
    })
    uiContentBox = Box({
        bgColor = { 0.15, 0.15, 0.15, 0 },
        orientation = "vertical",
        spacing = 0,
        padding = 2,
    })

    uiContentBox:Add(MakeCheckbox({
        text = "Enable Build Order",
        checked = enableBuildOrders,
        tooltip = "Enable this widget to intercept and manage building commands.\nDisabling does not terminate active Build Orders!",
        fontSize = 20,
        bgColor = { 0, 0, 0, 0 },
        onToggle = function(state)
            enableBuildOrders = state
            --if not enableBuildOrders then buildOrder = {}  end
            Echo("Build Orders: " .. (enableBuildOrders and "ON" or "OFF"))
        end,
    }))

    uiConfigBox = Box({
        bgColor = { 0.15, 0.15, 0.15, 0 },
        orientation = "vertical",
        spacing = 4,
        padding = 4,
    })
    uiConfigBox:Add(MakeCheckbox({
        text = "Repeat Mode",
        checked = REPEAT,
        tooltip = "Workers will repeat build orders again on the same place, if the construction get destroyed before it reachs the HOLO-PLACE value.",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
        onToggle = function(state)
            REPEAT = state
            Echo("Repeat: " .. (REPEAT and "ON" or "OFF"))
        end,
    }))

    uiConfigBox:Add(MakeCheckbox({
        text = "Enable notifications",
        checked = NOTIFICATIONS,
        tooltip = "Widget will print brief custom event messages",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
        onToggle = function(state)
            NOTIFICATIONS = state
            Echo("Notifications: " .. (NOTIFICATIONS and "ON" or "OFF"))
        end,
    }))

    uiConfigBox:Add(MakeCheckbox({
        text = "Always Draw Queue",
        checked = ALWAYS_DRAW_RENDER_PATH,
        tooltip = "[❗NOT RECOMMENDED, THIS IS A DEBUG/DEVELOPMENT OPTION AND MIGHT CAUSE FPS ISSUES]\nAlways render the construction queue of your workers.",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
        onToggle = function(state)
            ALWAYS_DRAW_RENDER_PATH = state
            Echo("Always Draw Queue: " .. (ALWAYS_DRAW_RENDER_PATH and "ON" or "OFF"))
        end,
    }))
    uiConfigBox:Add(MakeCheckbox({
        text = "DEBUG",
        checked = DEBUG_MODE,
        tooltip = "[❗NOT RECOMMENDED, THIS IS A DEBUG/DEVELOPMENT OPTION AND MIGHT CAUSE FPS ISSUES]\nRender aditional data about Build Orders",
        fontSize = 16,
        bgColor = { 0, 0, 0, 0 },
        onToggle = function(state)
            DEBUG_MODE = state
            Echo("DEBUG MODE: " .. (DEBUG_MODE and "ON" or "OFF"))
        end,
    }))

    uiConfigBox:Add(MakeButton({
        text = "  Create Custom Priority File   ",
        tooltip = "Copy the default priority list to LuaUI/Config/build-orders/ to customize it.\nThe widget will use the units defined on the file instead of the default ones.",
        fontSize = 16,
        bgColor = { 0.6, 0.6, 0.6, 1 },
        onClick = function()
            CreateCustomFile("priority")
        end,
    }))
    uiConfigBox:Add(MakeButton({
        text = "Create Custom Eraseable File",
        tooltip = "Copy the default eraseable list to LuaUI/Config/build-orders/ to customize it.\nThe widget will use the units defined on the file instead of the default ones.",
        fontSize = 16,
        bgColor = { 0.6, 0.6, 0.6, 1 },
        onClick = function()
            CreateCustomFile("eraseable")
        end,
    }))
    --uiContentBox:Add(uiNumOrdersLabel)
    uiContentBox:Add(uiQueuSizeLabel)
    --uiContentBox:Add(uiNumJobsLabel)
    --[[uiContentBox:Add(MakeButton({
    text = "Invisible Mode",
    tooltip = "Enable Build Orders and disable this widget GUI",
    bgColor = {0.34, 0.34, 0.4, 1.0},
    fontSize = 16,
    onClick = function() UI = false enableBuildOrders = true myUI = nil end
  }))]]
    -- uiContentBox:Add(uiButtonBox)

    uiConfigBox:Add(
        MakeLabel({
            bgColor = { 0.45, 0.16, 0.025, 1.0 },
            text = "DON'T PANIC!",
            fontSize = 14,
            tooltip = WIDGET_DESC,
        })
    )

    myUI = MakeWindow({
        title = WIDGET_NAME,
        fontSize = 22,
        fontColor = { 1, 0.6, 0.0, 1.0 },
        bgColor = { 0, 0, 0, 0.3 },
        content = uiContentBox,
    })
    local _, vsy = gl.GetViewSizes()
    local _, h = myUI:GetSize()
    myUI.x, myUI.y = windowX or 50, windowY or vsy / 2 - h - 300
end

function widget:DrawScreen()
    if myUI then
        -- compute stats
        local numOrders, totalQueued, numBuilding = 0, 0, 0
        for _, entry in pairs(buildOrder) do
            if entry then
                numOrders = numOrders + 1
                totalQueued = totalQueued + #(entry.queue or {})
                if entry.currentjob and entry.currentjob ~= -1 then
                    numBuilding = numBuilding + 1
                end
            end
        end

        if numOrders == 0 then
            sentCommands = 0
        end
        uiNumOrdersLabel.text = "Orders: " .. numOrders
        uiQueuSizeLabel.text = "Itens in Queue: " .. totalQueued
        uiNumJobsLabel.text = "In progress: " .. numBuilding

        myUI:Draw()

        if not NOTIFICATIONS then
            return
        end

        Notify.DrawScreen(myUI.x + 8, myUI.y - myUI.height - 20)
    end
end

function widget:Shutdown()
    SaveUserPreferences()
    Echo("Closed")
end

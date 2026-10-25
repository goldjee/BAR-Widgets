local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Layout Planner",
        desc = "Plan, save and load base layouts using in game interface.",
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

-- The default config ships with the widget; the user's override and saved layouts live in LuaUI/Config
local DEFAULTS_DIR = "LuaUI/Widgets/layout-planner"
local USER_DIR = "LuaUI/Config/layout-planner"
local DEFAULT_CONFIG_PATH = DEFAULTS_DIR .. "/layout-planner-config-default.txt"
local CONFIG_PATH = USER_DIR .. "/layout-planner-config.txt"

-- Layouts are drawn in BUs (building units): 1 BU = 16 world units, the smallest
-- building size (cameras). A chunk is 12x12 BUs, a multiple of most building sizes.
local BU_SIZE = 16
local HALF_BU = BU_SIZE / 2
local CHUNK_SIZE = 12 * BU_SIZE

-- Building sizes in BUs; every layout has a building group per size
local LAYOUT_SIZES = { 1, 2, 3, 4, 6, 12 }
local SIZE_DRAW_ORDER = { 12, 6, 4, 3, 2, 1 } -- big first, so small ones stay visible

local BUILDING_TYPES = {
    {
        name = "Small",
        size = 2,
        tooltip = "e.g.: Wall, Dragon's Maw/Claw/Fury",
        color = { 0.60, 0.70, 0.85, 0.6 }, -- desaturated blue
    },
    {
        name = "Square",
        size = 3,
        tooltip = "e.g.: T1 Con. Turret, T1 Wind, T1 Converter",
        color = { 0.65, 0.78, 0.65, 0.6 }, -- pale green
    },
    {
        name = "Big",
        size = 4,
        tooltip = "e.g.: T2 Con. Turret, T2 Converter, Basilica",
        color = { 0.80, 0.72, 0.55, 0.6 }, -- muted gold
    },
    {
        name = "Large",
        size = 6,
        tooltip = "e.g.: AFUS, T3 Con. Turret, T2 Wind, Olympus, Basilisk",
        color = { 0.75, 0.60, 0.60, 0.6 }, -- dusty rose
    },
    {
        name = "Chunk",
        size = 12,
        tooltip = "e.g.: EFUS",
        color = { 0.70, 0.65, 0.85, 0.6 }, -- soft purple
    },
}

local SIZE_COLORS = {}
for _, buildingType in ipairs(BUILDING_TYPES) do
    SIZE_COLORS[buildingType.size] = buildingType.color
end

local KEY_UNDO = string.byte("z") -- with ctrl
local KEY_REDO = string.byte("a") -- with ctrl
local KEY_ROTATE = string.byte("r")
local KEY_INVERT = string.byte("i")
-- Shifts the layout, relative to the camera, as {dx, dz}
local TRANSLATE_KEYS = {
    [string.byte("w")] = { 0, 1 },
    [string.byte("s")] = { 0, -1 },
    [string.byte("a")] = { -1, 0 },
    [string.byte("d")] = { 1, 0 },
}

local DRAW_HEIGHT = 5 -- drawn above the ground
local GRID_RADIUS_CHUNKS = 8 -- chunk grid around the mouse

-- Rendering as map marks: the engine drops marks sent too fast
local MARK_HEIGHT = 100
local LINES_PER_BATCH = 10
local BATCH_INTERVAL = 0.1 -- seconds

local LOADED_HINTS = {
    "Press [R] to rotate",
    "Press [I] to invert",
    "Hold [ALT] while placing to merge with current layout.",
}
local DRAWING_HINTS = {
    "Use [left mouse button] to place buildings. Hold [ALT] to place in area",
    "Use [right mouse button] to place lines. Hold [ALT] to remove crossed lines",
    "Use [left mouse button] + [CTRL] + [ALT] to draw traced lines instead of area. (The amount of traces is based on the building Size)",
}

-- Settings saved to the config file, in file order
local PREF_KEYS = {
    "allowTranslationByKeys",
    "snapBuilding",
    "drawChunkGrid",
    "differTypesByColor",
    "showUsageTips",
    "windowX",
    "windowY",
}

-- State
-- ========================================

local prefs = {
    allowTranslationByKeys = true, -- WASD shift the layout
    snapBuilding = true, -- snap buildings to a grid of their size
    drawChunkGrid = true,
    differTypesByColor = false, -- a color per building size
    showUsageTips = true, -- usage hints on screen
}

local drawingMode = false
local currentSizeIndex = 1 -- into BUILDING_TYPES

-- Layouts: {buildings = {[size] = {{x, z}}}, lines = {{x1, z1, x2, z2}}}, in BUs
local currentLayout
---Loaded layout file waiting to be placed
---@class LoadedLayout
---@field width integer
---@field height integer
---@field minSize integer smallest building size in the layout
---@field layout table
---@type LoadedLayout?
local loadedData = nil
local layoutRotation = 0

local dragStart = nil -- {bx, bz, size} while placing buildings
local lineStart = nil -- {bx, bz} while drawing a line

local commandHistory = {}
local historyPointer = 0

local markQueue = {} -- {x1, z1, x2, z2} world lines waiting to become map marks
local markTimer = 0

local myUI

-- Helpers
-- ========================================

local function log(msg)
    Spring.Echo("Layout Planner: " .. msg)
end

local function worldToBU(x, z)
    return math.floor(x / BU_SIZE), math.floor(z / BU_SIZE)
end

local function buToWorld(bx, bz)
    return bx * BU_SIZE, bz * BU_SIZE
end

-- BU under the mouse (pos from TraceScreenRay)
local function buildingAnchor(pos)
    return worldToBU(pos[1], pos[3])
end

-- Nearest BU corner to the mouse, where lines start and end
local function lineAnchor(pos)
    return worldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU)
end

local function snapToSize(bx, bz, size)
    if prefs.snapBuilding then
        return math.floor(bx / size) * size, math.floor(bz / size) * size
    end
    return bx, bz
end

-- Ground position under the screen point, or nil
local function traceGround(mx, my)
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    return pos
end

-- Layouts
-- ========================================

local function newLayout()
    local layout = { buildings = {}, lines = {} }
    for _, size in ipairs(LAYOUT_SIZES) do
        layout.buildings[size] = {}
    end
    return layout
end

currentLayout = newLayout()

local function copyLayout(source)
    local copy = newLayout()
    for size, group in pairs(source.buildings) do
        for _, pos in ipairs(group) do
            table.insert(copy.buildings[size], { pos[1], pos[2] })
        end
    end
    for _, line in ipairs(source.lines) do
        table.insert(copy.lines, { line[1], line[2], line[3], line[4] })
    end
    return copy
end

-- Bounds of the building positions and line ends; with includeFootprint, of the
-- whole buildings. Returns nothing for an empty layout.
local function layoutBounds(layout, includeFootprint)
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for size, group in pairs(layout.buildings) do
        local extent = includeFootprint and size - 1 or 0
        for _, pos in ipairs(group) do
            minX, maxX = math.min(minX, pos[1]), math.max(maxX, pos[1] + extent)
            minZ, maxZ = math.min(minZ, pos[2]), math.max(maxZ, pos[2] + extent)
        end
    end
    for _, line in ipairs(layout.lines) do
        minX, maxX = math.min(minX, line[1], line[3]), math.max(maxX, line[1], line[3])
        minZ, maxZ = math.min(minZ, line[2], line[4]), math.max(maxZ, line[2], line[4])
    end
    if minX ~= math.huge then
        return minX, maxX, minZ, maxZ
    end
end

local function translateLayout(layout, dx, dz)
    for _, group in pairs(layout.buildings) do
        for _, pos in ipairs(group) do
            pos[1], pos[2] = pos[1] + dx, pos[2] + dz
        end
    end
    for _, line in ipairs(layout.lines) do
        line[1], line[2], line[3], line[4] = line[1] + dx, line[2] + dz, line[3] + dx, line[4] + dz
    end
end

-- Orders the ends of a line, so equal lines compare equal
local function normalizeLine(x1, z1, x2, z2)
    if x2 < x1 or (x2 == x1 and z2 < z1) then
        return x2, z2, x1, z1
    end
    return x1, z1, x2, z2
end

local function addLine(layout, x1, z1, x2, z2)
    if x1 ~= x2 or z1 ~= z2 then
        table.insert(layout.lines, { normalizeLine(x1, z1, x2, z2) })
    end
end

local function removeLine(layout, x1, z1, x2, z2)
    x1, z1, x2, z2 = normalizeLine(x1, z1, x2, z2)
    for i = #layout.lines, 1, -1 do
        local line = layout.lines[i]
        if line[1] == x1 and line[2] == z1 and line[3] == x2 and line[4] == z2 then
            table.remove(layout.lines, i)
            return
        end
    end
end

local function findBuilding(layout, x, z, size)
    for i, pos in ipairs(layout.buildings[size]) do
        if pos[1] == x and pos[2] == z then
            return i
        end
    end
end

local function addBuilding(layout, x, z, size)
    table.insert(layout.buildings[size], { x, z })
end

local function removeBuilding(layout, x, z, size)
    local i = findBuilding(layout, x, z, size)
    if i then
        table.remove(layout.buildings[size], i)
    end
end

-- Undo / redo
-- ========================================

-- Undoable layout edits: {do, undo}, both called as fn(layout, ...)
local EDITS = {
    addLine = { addLine, removeLine },
    removeLine = { removeLine, addLine },
    addBuilding = { addBuilding, removeBuilding },
    removeBuilding = { removeBuilding, addBuilding },
    translate = {
        translateLayout,
        function(layout, dx, dz)
            translateLayout(layout, -dx, -dz)
        end,
    },
}

-- A command is a list of edits, done and undone together
local function pushEdit(command, edit, layout, ...)
    table.insert(command, { edit = edit, layout = layout, args = { ... } })
end

local function applyEdit(action, undo)
    local fns = EDITS[action.edit]
    local fn = undo and fns[2] or fns[1]
    fn(action.layout, unpack(action.args))
end

local function runCommand(command)
    if #command == 0 then
        return
    end
    -- a new command drops the redo history
    for i = #commandHistory, historyPointer + 1, -1 do
        commandHistory[i] = nil
    end
    table.insert(commandHistory, command)
    historyPointer = historyPointer + 1
    for _, action in ipairs(command) do
        applyEdit(action, false)
    end
end

local function undo()
    local command = commandHistory[historyPointer]
    if command then
        for i = #command, 1, -1 do
            applyEdit(command[i], true)
        end
        historyPointer = historyPointer - 1
    end
end

local function redo()
    local command = commandHistory[historyPointer + 1]
    if command then
        historyPointer = historyPointer + 1
        for _, action in ipairs(command) do
            applyEdit(action, false)
        end
    end
end

local function pushClearLayout(command, layout)
    for _, line in ipairs(layout.lines) do
        pushEdit(command, "removeLine", layout, unpack(line))
    end
    for size, group in pairs(layout.buildings) do
        for _, pos in ipairs(group) do
            pushEdit(command, "removeBuilding", layout, pos[1], pos[2], size)
        end
    end
end

-- Adds everything from source to the current layout
local function pushAddLayout(command, source)
    for _, line in ipairs(source.lines) do
        pushEdit(command, "addLine", currentLayout, unpack(line))
    end
    for size, group in pairs(source.buildings) do
        for _, pos in ipairs(group) do
            pushEdit(command, "addBuilding", currentLayout, pos[1], pos[2], size)
        end
    end
end

-- Camera
-- ========================================

-- Camera facing snapped to 0/90/180/270 degrees in the XZ plane
local function getCameraSnappedAngle()
    local dirX, _, dirZ = Spring.GetCameraDirection()
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 0.0001 then
        return 0 -- looking straight down: ambiguous
    end
    local tx = math.floor(dirX / length + 0.5)
    local tz = math.floor(dirZ / length + 0.5)
    if tx == 0 and tz > 0 then
        return 270
    elseif tx > 0 and tz == 0 then
        return 180
    elseif tx == 0 and tz < 0 then
        return 90
    end
    return 0
end

-- Turns screen-relative input (dx right, dz forward) into a snapped world direction
local function getSnappedCameraDirection(dx, dz)
    local dirX, _, dirZ = Spring.GetCameraDirection()
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 0.0001 then
        return 0, 0 -- looking straight down: ambiguous
    end
    local forwardX, forwardZ = dirX / length, dirZ / length
    local rightX, rightZ = -forwardZ, forwardX
    local inputLength = math.sqrt(dx * dx + dz * dz)
    dx, dz = dx / inputLength, dz / inputLength
    local worldX = dx * rightX + dz * forwardX
    local worldZ = dx * rightZ + dz * forwardZ
    return math.floor(worldX + 0.5), math.floor(worldZ + 0.5)
end

-- Rotates (x, z) clockwise by a multiple of 90 degrees
local function rotate(x, z, rotation)
    if rotation == 90 then
        return -z, x
    elseif rotation == 180 then
        return -x, -z
    elseif rotation == 270 then
        return z, -x
    end
    return x, z
end

-- Rotates the layout around its center and/or inverts it along the camera's axis, in place
local function rotateAndInvert(layout, rotation, invert)
    local minX, maxX, minZ, maxZ = layoutBounds(layout, true)
    if not minX or (rotation == 0 and not invert) then
        return
    end
    local cx = (minX + maxX + 1) / 2
    local cz = (minZ + maxZ + 1) / 2
    local cameraAngle = invert and getCameraSnappedAngle()
    local mirrorX = invert and (cameraAngle == 90 or cameraAngle == 270)
    local mirrorZ = invert and not mirrorX

    -- size is the building size, or 0 for a line end
    local function transform(x, z, size)
        local half = size / 2
        local rx, rz = rotate(x + half - cx, z + half - cz, rotation)
        local nx = math.floor(cx + rx - half + 0.5)
        local nz = math.floor(cz + rz - half + 0.5)
        if mirrorX then
            nx = 2 * cx - nx - size
        elseif mirrorZ then
            nz = 2 * cz - nz - size
        end
        return nx, nz
    end

    for size, group in pairs(layout.buildings) do
        for _, pos in ipairs(group) do
            pos[1], pos[2] = transform(pos[1], pos[2], size)
        end
    end
    for _, line in ipairs(layout.lines) do
        line[1], line[2] = transform(line[1], line[2], 0)
        line[3], line[4] = transform(line[3], line[4], 0)
    end
end

-- Geometry
-- ========================================

-- 0 = collinear, 1 = clockwise, 2 = counterclockwise
local function orientation(px, pz, qx, qz, rx, rz)
    local value = (qz - pz) * (rx - qx) - (qx - px) * (rz - qz)
    if value == 0 then
        return 0
    end
    return value > 0 and 1 or 2
end

-- Whether q lies on segment pr, given the three are collinear
local function onSegment(px, pz, qx, qz, rx, rz)
    return math.min(px, rx) <= qx
        and qx <= math.max(px, rx)
        and math.min(pz, rz) <= qz
        and qz <= math.max(pz, rz)
end

local function linesIntersect(a, b)
    local x1, z1, x2, z2 = a[1], a[2], a[3], a[4]
    local x3, z3, x4, z4 = b[1], b[2], b[3], b[4]
    local o1 = orientation(x1, z1, x2, z2, x3, z3)
    local o2 = orientation(x1, z1, x2, z2, x4, z4)
    local o3 = orientation(x3, z3, x4, z4, x1, z1)
    local o4 = orientation(x3, z3, x4, z4, x2, z2)
    return (o1 ~= o2 and o3 ~= o4)
        or (o1 == 0 and onSegment(x1, z1, x3, z3, x2, z2))
        or (o2 == 0 and onSegment(x1, z1, x4, z4, x2, z2))
        or (o3 == 0 and onSegment(x3, z3, x1, z1, x4, z4))
        or (o4 == 0 and onSegment(x3, z3, x2, z2, x4, z4))
end

-- Indices of the layout lines crossing segment
local function getIntersectingLineIndices(layout, segment)
    local indices = {}
    for i, line in ipairs(layout.lines) do
        if linesIntersect(segment, line) then
            table.insert(indices, i)
        end
    end
    return indices
end

-- Building positions from start to (endX, endZ): the whole area, or a line of them
local function getBuildingList(start, endX, endZ, area)
    local size = start.size
    local x, z = start.bx, start.bz
    local results = {}

    if area then
        for ax = math.min(x, endX), math.max(x, endX), size do
            for az = math.min(z, endZ), math.max(z, endZ), size do
                results[#results + 1] = { x = ax, z = az }
            end
        end
        return results
    end

    -- Bresenham, stepping by the building size
    local dx, dz = math.abs(endX - x), math.abs(endZ - z)
    local sx = endX >= x and size or -size
    local sz = endZ >= z and size or -size
    if dx > dz then
        local err = dx / 2
        while (sx > 0 and x <= endX) or (sx < 0 and x >= endX) do
            results[#results + 1] = { x = x, z = z }
            x = x + sx
            err = err - dz
            if err < 0 then
                z = z + sz
                err = err + dx
            end
        end
    else
        local err = dz / 2
        while (sz > 0 and z <= endZ) or (sz < 0 and z >= endZ) do
            results[#results + 1] = { x = x, z = z }
            z = z + sz
            err = err - dx
            if err < 0 then
                x = x + sx
                err = err + dz
            end
        end
    end
    return results
end

-- Tick marks tracing the rectangle from start to (endX, endZ): corners, plus one per building size
local function traceRectangleBounds(start, endX, endZ)
    local size = start.size
    local tick = size > 4 and 1 or 0.5
    local cornerTick = tick * 2
    -- bounds of both ends, shrunk inward by 1 BU
    local x1 = math.min(start.bx, endX) + 1
    local x2 = math.max(start.bx, endX) + size - 1
    local z1 = math.min(start.bz, endZ) + 1
    local z2 = math.max(start.bz, endZ) + size - 1

    local lines = {}
    -- {x, z, inward x direction, inward z direction}
    for _, corner in ipairs({
        { x1, z1, 1, 1 },
        { x2, z1, -1, 1 },
        { x2, z2, -1, -1 },
        { x1, z2, 1, -1 },
    }) do
        local x, z, dirX, dirZ = corner[1], corner[2], corner[3], corner[4]
        table.insert(lines, { x, z, x + dirX * cornerTick, z })
        table.insert(lines, { x, z, x, z + dirZ * cornerTick })
    end
    for x = x1 + size - 1, x2 - 1, size do
        table.insert(lines, { x - tick, z1, x + tick, z1 })
        table.insert(lines, { x - tick, z2, x + tick, z2 })
    end
    for z = z1 + size - 1, z2 - 1, size do
        table.insert(lines, { x1, z - tick, x1, z + tick })
        table.insert(lines, { x2, z - tick, x2, z + tick })
    end
    return lines
end

-- Merges touching collinear edges (all horizontal or all vertical) into single lines
local function mergeEdges(edges, horizontal)
    -- horizontal edges vary in x (indices 1, 3) at a fixed z (index 2); vertical ones the other way
    local from, to, fixed = 2, 4, 1
    if horizontal then
        from, to, fixed = 1, 3, 2
    end

    local groups = {}
    for _, edge in ipairs(edges) do
        local key = edge[fixed]
        groups[key] = groups[key] or {}
        table.insert(groups[key], { edge[from], edge[to] })
    end

    local merged = {}
    local function emit(coord, a, b)
        table.insert(merged, horizontal and { a, coord, b, coord } or { coord, a, coord, b })
    end
    for coord, segments in pairs(groups) do
        table.sort(segments, function(s1, s2)
            return s1[1] < s2[1]
        end)
        local a, b = segments[1][1], segments[1][2]
        for i = 2, #segments do
            local segment = segments[i]
            if segment[1] <= b then
                b = math.max(b, segment[2])
            else
                emit(coord, a, b)
                a, b = segment[1], segment[2]
            end
        end
        emit(coord, a, b)
    end
    return merged
end

-- The outlines of the buildings plus the layout's lines, in BUs
local function collectEdges()
    -- Building edges shared by two buildings are inside a shape, so they cancel out.
    -- Edges are written low end first, so a shared edge has the same key both times.
    local edges = {}
    for size, group in pairs(currentLayout.buildings) do
        for _, pos in ipairs(group) do
            local x, z = pos[1], pos[2]
            for _, edge in ipairs({
                { x, z, x + size, z },
                { x + size, z, x + size, z + size },
                { x, z + size, x + size, z + size },
                { x, z, x, z + size },
            }) do
                local key = table.concat(edge, ",")
                if edges[key] then
                    edges[key] = nil
                else
                    edges[key] = edge
                end
            end
        end
    end

    local horizontal, vertical = {}, {}
    for _, edge in pairs(edges) do
        table.insert(edge[2] == edge[4] and horizontal or vertical, edge)
    end

    local result = mergeEdges(horizontal, true)
    for _, edge in ipairs(mergeEdges(vertical, false)) do
        table.insert(result, edge)
    end
    for _, line in ipairs(currentLayout.lines) do
        table.insert(result, line)
    end
    return result
end

-- Queues the current layout's outlines and lines to be drawn as map marks
local function renderLayout()
    local edges = collectEdges()
    log("rendering " .. #edges .. " lines")
    markQueue = {}
    for _, edge in ipairs(edges) do
        local x1, z1 = buToWorld(edge[1], edge[2])
        local x2, z2 = buToWorld(edge[3], edge[4])
        local dx, dz = x2 - x1, z2 - z1
        local segments = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / CHUNK_SIZE))
        for i = 0, segments - 1 do
            local t1, t2 = i / segments, (i + 1) / segments
            table.insert(markQueue, { x1 + dx * t1, z1 + dz * t1, x1 + dx * t2, z1 + dz * t2 })
        end
    end
end

-- Files
-- ========================================

local function layoutPath(slot)
    return USER_DIR .. "/layout_" .. slot .. ".txt"
end

-- Slot numbers of the saved layouts, sorted
local function listSlots()
    local slots = {}
    for _, path in ipairs(VFS.DirList(USER_DIR, "layout_*.txt", VFS.RAW)) do
        local slot = tonumber(path:match("layout_(%d+)%.txt$"))
        if slot then
            table.insert(slots, slot)
        end
    end
    table.sort(slots)
    return slots
end

local function deleteLayout(slot)
    local path = layoutPath(slot)
    if os.remove(path) then
        log("layout deleted: " .. path)
    else
        log("ERROR - failed to delete " .. path)
    end
end

local function serializeLayout(layout)
    local out = { "{", "    buildings = {" }
    for size, group in pairs(layout.buildings) do
        table.insert(out, "        [" .. size .. "] = {")
        for _, pos in ipairs(group) do
            table.insert(out, string.format("            {%d, %d},", pos[1], pos[2]))
        end
        table.insert(out, "        },")
    end
    table.insert(out, "    },")
    table.insert(out, "    lines = {")
    for _, line in ipairs(layout.lines) do
        table.insert(
            out,
            string.format("        {%d, %d, %d, %d},", line[1], line[2], line[3], line[4])
        )
    end
    table.insert(out, "    },")
    table.insert(out, "}")
    return table.concat(out, "\n")
end

-- Saves the layout moved to the origin, with the size info placing it again needs.
-- Returns true if a file was written.
local function saveLayout(slot, layout)
    local minX, maxX, minZ, maxZ = layoutBounds(layout, false)
    if not minX then
        log("nothing to save")
        return
    end

    local minSize = math.huge
    for size, group in pairs(layout.buildings) do
        if #group > 0 then
            minSize = math.min(minSize, size)
        end
    end
    if minSize == math.huge then
        minSize = 1
    end

    local copy = copyLayout(layout)
    translateLayout(copy, -minX, -minZ)

    local path = layoutPath(slot)
    Spring.CreateDir(USER_DIR)
    local file = io.open(path, "w")
    if not file then
        log("ERROR - failed to open " .. path)
        return
    end
    file:write("return {\n")
    file:write("    width = " .. (maxX - minX + 1) .. ",\n")
    file:write("    height = " .. (maxZ - minZ + 1) .. ",\n")
    file:write("    minSize = " .. minSize .. ",\n")
    file:write("    layout = " .. serializeLayout(copy) .. ",\n")
    file:write("}\n")
    file:close()
    log("layout saved: " .. path)
    return true
end

-- Converts a save from the old "x, z, size" per line format
local function convertLegacyLayout(slot)
    local file = io.open(layoutPath(slot), "r")
    if not file then
        log("no layout in slot " .. slot)
        return
    end

    local layout = newLayout()
    for line in file:lines() do
        local x, z, size = line:match("^(%-?%d+),%s*(%-?%d+),%s*(%d+)$")
        if not x then
            log("ERROR - can't parse layout file line: " .. line)
            file:close()
            return
        end
        addBuilding(layout, tonumber(x), tonumber(z), tonumber(size))
    end
    file:close()

    saveLayout(slot, layout)
    log("converted an old layout file, load it again")
end

local function loadLayout(slot)
    local path = layoutPath(slot)
    local chunk = loadfile(path) -- fails on old format files, which aren't Lua
    local ok, data = false, nil
    if chunk then
        ok, data = pcall(chunk)
    end
    if ok and type(data) == "table" and type(data.layout) == "table" then
        loadedData = data
        log("layout loaded: " .. path)
    else
        convertLegacyLayout(slot)
    end
end

local function loadPreferences()
    local chunk = loadfile(CONFIG_PATH) or loadfile(DEFAULT_CONFIG_PATH)
    if not chunk then
        log("no config file found")
        return
    end

    local env = {}
    setfenv(chunk, env)
    if not pcall(chunk) then
        log("ERROR - failed to read the config file")
        return
    end
    for _, key in ipairs(PREF_KEYS) do
        if env[key] ~= nil then
            prefs[key] = env[key]
        end
    end
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

    Spring.CreateDir(USER_DIR)
    local file = io.open(CONFIG_PATH, "w")
    if not file then
        log("ERROR - failed to save config")
        return
    end
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
end

-- Drawing
-- ========================================

-- Square building footprint at BU (bx, bz)
local function drawSquare(bx, bz, size)
    local x, z = buToWorld(bx, bz)
    local y = Spring.GetGroundHeight(x, z) + DRAW_HEIGHT
    local length = BU_SIZE * size
    gl.BeginEnd(GL.QUADS, function()
        gl.Vertex(x, y, z)
        gl.Vertex(x + length, y, z)
        gl.Vertex(x + length, y, z + length)
        gl.Vertex(x, y, z + length)
    end)
end

-- Lines in BUs, shifted by (dx, dz) BUs and raised by yOffset
local function drawLines(lines, dx, dz, yOffset)
    gl.BeginEnd(GL.LINES, function()
        for _, line in ipairs(lines) do
            local x1, z1 = buToWorld(line[1] + dx, line[2] + dz)
            local x2, z2 = buToWorld(line[3] + dx, line[4] + dz)
            gl.Vertex(x1, Spring.GetGroundHeight(x1, z1) + yOffset, z1)
            gl.Vertex(x2, Spring.GetGroundHeight(x2, z2) + yOffset, z2)
        end
    end)
end

-- Chunk grid around (cx, cz), fading out with the distance
local function drawChunkGrid(cx, cz)
    local maxDistSq = (GRID_RADIUS_CHUNKS * CHUNK_SIZE) ^ 2
    local centerX = math.floor(cx / CHUNK_SIZE)
    local centerZ = math.floor(cz / CHUNK_SIZE)

    -- One chunk-long grid line, faded by the distance of the chunk it starts at
    local function segment(x1, z1, x2, z2)
        local distSq = (x1 + CHUNK_SIZE / 2 - cx) ^ 2 + (z1 + CHUNK_SIZE / 2 - cz) ^ 2
        if distSq <= maxDistSq then
            gl.Color(1, 1, 1, 1 - distSq / maxDistSq)
            gl.Vertex(x1, Spring.GetGroundHeight(x1, z1) + DRAW_HEIGHT, z1)
            gl.Vertex(x2, Spring.GetGroundHeight(x2, z2) + DRAW_HEIGHT, z2)
        end
    end

    gl.LineWidth(2)
    gl.BeginEnd(GL.LINES, function()
        for i = -GRID_RADIUS_CHUNKS, GRID_RADIUS_CHUNKS do
            for j = -GRID_RADIUS_CHUNKS, GRID_RADIUS_CHUNKS - 1 do
                local x, z = (centerX + i) * CHUNK_SIZE, (centerZ + j) * CHUNK_SIZE
                segment(x, z, x, z + CHUNK_SIZE)
                x, z = (centerX + j) * CHUNK_SIZE, (centerZ + i) * CHUNK_SIZE
                segment(x, z, x + CHUNK_SIZE, z)
            end
        end
    end)
end

local function drawLayout(layout)
    for _, size in ipairs(SIZE_DRAW_ORDER) do
        if prefs.differTypesByColor and SIZE_COLORS[size] then
            gl.Color(SIZE_COLORS[size])
        else
            gl.Color(0, 1, 0, 0.3)
        end
        for _, pos in ipairs(layout.buildings[size]) do
            drawSquare(pos[1], pos[2], size)
        end
    end
    gl.Color(0, 1, 0, 0.6)
    gl.LineWidth(3)
    drawLines(layout.lines, 0, 0, DRAW_HEIGHT)
end

-- Offset that centers a loaded layout on BU (bx, bz)
---@param data LoadedLayout
local function loadedOffset(data, bx, bz)
    return bx - math.floor((data.width + data.minSize) / 2),
        bz - math.floor((data.height + data.minSize) / 2)
end

-- Preview of what a click at pos would do
local function drawPreview(pos)
    local alt, ctrl = Spring.GetModKeyState()
    local bx, bz = buildingAnchor(pos)
    gl.Color(1, 1, 0, 0.4)

    if loadedData then
        local dx, dz = loadedOffset(loadedData, bx, bz)
        for size, group in pairs(loadedData.layout.buildings) do
            for _, b in ipairs(group) do
                drawSquare(b[1] + dx, b[2] + dz, size)
            end
        end
        gl.LineWidth(3)
        drawLines(loadedData.layout.lines, dx, dz, DRAW_HEIGHT + 1)
    elseif drawingMode and lineStart then
        local ex, ez = lineAnchor(pos)
        if alt then
            gl.Color(1, 0.5, 0, 1)
        else
            gl.Color(1, 1, 0, 1)
        end
        gl.LineWidth(3)
        drawLines({ { lineStart.bx, lineStart.bz, ex, ez } }, 0, 0, DRAW_HEIGHT)

        if alt then
            local crossed = {}
            for _, i in
                ipairs(
                    getIntersectingLineIndices(
                        currentLayout,
                        { lineStart.bx, lineStart.bz, ex, ez }
                    )
                )
            do
                table.insert(crossed, currentLayout.lines[i])
            end
            gl.LineWidth(4)
            gl.Color(0.7, 0.3, 1, 1)
            drawLines(crossed, 0, 0, DRAW_HEIGHT)
        end
    elseif drawingMode then
        local size = dragStart and dragStart.size or BUILDING_TYPES[currentSizeIndex].size
        bx, bz = snapToSize(bx, bz, size)
        if dragStart and alt and ctrl then
            drawLines(traceRectangleBounds(dragStart, bx, bz), 0, 0, DRAW_HEIGHT)
            return
        end

        local list = dragStart and getBuildingList(dragStart, bx, bz, alt) or { { x = bx, z = bz } }
        if #list == 1 then
            -- marks where a right click would start a line
            local x, z = buToWorld(lineAnchor(pos))
            local y = Spring.GetGroundHeight(x, z) + DRAW_HEIGHT
            gl.BeginEnd(GL.QUADS, function()
                gl.Vertex(x - 2, y, z - 2)
                gl.Vertex(x + 2, y, z - 2)
                gl.Vertex(x + 2, y, z + 2)
                gl.Vertex(x - 2, y, z + 2)
            end)
        end
        for _, b in ipairs(list) do
            drawSquare(b.x, b.z, size)
        end
    end
end

-- Mouse actions
-- ========================================

-- Places a loaded layout centered on BU (bx, bz); merge keeps the current layout
-- and the loaded one for more placements
---@param data LoadedLayout
local function placeLoadedLayout(data, bx, bz, merge)
    local layout = copyLayout(data.layout)
    translateLayout(layout, loadedOffset(data, bx, bz))
    local command = {}
    if not merge then
        pushClearLayout(command, currentLayout)
        loadedData = nil
    end
    pushAddLayout(command, layout)
    runCommand(command)
    log("layout placed")
end

-- Toggles the buildings from dragStart to (bx, bz), or traces the rectangle with ctrl+alt
local function finishBuildingDrag(start, bx, bz)
    local alt, ctrl = Spring.GetModKeyState()
    local command = {}
    if alt and ctrl then
        for _, line in ipairs(traceRectangleBounds(start, bx, bz)) do
            pushEdit(command, "addLine", currentLayout, unpack(line))
        end
    else
        for _, b in ipairs(getBuildingList(start, bx, bz, alt)) do
            local exists = findBuilding(currentLayout, b.x, b.z, start.size)
            pushEdit(
                command,
                exists and "removeBuilding" or "addBuilding",
                currentLayout,
                b.x,
                b.z,
                start.size
            )
        end
    end
    runCommand(command)
end

-- Adds the line from lineStart to (ex, ez), or removes the lines it crosses with alt
local function finishLineDrag(start, ex, ez)
    local alt = Spring.GetModKeyState()
    local command = {}
    if alt then
        for _, i in
            ipairs(getIntersectingLineIndices(currentLayout, { start.bx, start.bz, ex, ez }))
        do
            pushEdit(command, "removeLine", currentLayout, unpack(currentLayout.lines[i]))
        end
    else
        pushEdit(command, "addLine", currentLayout, start.bx, start.bz, ex, ez)
    end
    runCommand(command)
end

-- UI toolkit (keep in sync with build-orders.lua)
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
DRAW: click "Draw", pick a building size
  [LMB] place or remove a building; drag for a line of them
  [ALT]+drag fills an area, [CTRL]+[ALT]+drag traces its outline
  [RMB] drag draws a line, [ALT]+[RMB] drag removes crossed lines
  The square previews a building, the dot marks where a line starts
  Touching buildings of one size render as a single outline
  [CTRL]+[Z] / [CTRL]+[A] undo / redo, [W][A][S][D] shift the layout
SAVE AND LOAD
  "Save New" saves the current layout; each row can Load, Overwrite or Delete
  A loaded layout follows the mouse: [R] rotates, [I] inverts,
  [LMB] places it, [ALT]+[LMB] merges it into the current one, [RMB] cancels
  "Render" draws the current layout on the map as line marks
TIPS
  Align layouts to chunks: their size fits almost every building
  Keep "Snap" (in Settings) on for grid-aligned layouts
  Drag the window by its title bar
  Trouble? Ask on the widget's Discord page]]

-- Button colors by role
local BLUE = { 0.2, 0.35, 0.9, 1.0 } -- main actions
local GREEN = { 0.15, 0.6, 0.25, 1.0 } -- creating
local RED = { 0.6, 0.1, 0.0, 1.0 } -- armed destructive action
local GREY = { 0.3, 0.3, 0.3, 1.0 } -- everything else
local CYAN = { 0.0, 0.6, 0.6, 1.0 } -- toggled on

-- Horizontal box without its own padding or background, so rows line up
local function makeRow()
    return makeBox({ orientation = "horizontal", spacing = 6, padding = 0 })
end

-- Checkbox for a boolean pref
local function makePrefToggle(text, tooltip, key)
    return makeCheckbox({
        text = text,
        tooltip = tooltip,
        checked = prefs[key],
        onToggle = function(checked)
            prefs[key] = checked
            log(text .. ": " .. (checked and "ON" or "OFF"))
        end,
    })
end

-- Button that turns into a red "Sure?" on the first click and calls onConfirm() on
-- the second; moving the mouse away disarms it
local function makeConfirmButton(params)
    local button = makeButton(params)
    -- keeps its width while saying "Sure?", so the buttons next to it don't shift
    local width = button:GetSize()
    function button:GetSize()
        return width, self.height
    end

    local draw = button.Draw
    function button:Draw()
        if self.text == "Sure?" and not isHovered(self) then
            self.text, self.bgColor = params.text, params.bgColor
        end
        draw(self)
    end

    button.onClick = function(self)
        if self.text ~= "Sure?" then
            self.text, self.bgColor = "Sure?", RED
            return
        end
        params.onConfirm()
    end
    return button
end

local slotsBox -- rows of the saved layouts, rebuilt by refreshSlots()

local function refreshSlots()
    local slots = listSlots()
    slotsBox.children = {}
    local header = makeRow()
    header:Add(makeLabel({ text = "Layouts" }))
    -- ponytail: deleted slot numbers stay as gaps; renumber the files if that bothers people
    header:Add(makeButton({
        text = "Save New",
        tooltip = "Save the current layout as a new one",
        bgColor = GREEN,
        onClick = function()
            if saveLayout((slots[#slots] or 0) + 1, currentLayout) then
                refreshSlots()
            end
        end,
    }))
    slotsBox:Add(header)
    for _, slot in ipairs(slots) do
        local row = makeRow()
        row:Add(makeLabel({
            text = string.format("%02d", slot),
        }))
        row:Add(makeButton({
            text = "Load",
            tooltip = "Pick up this layout, then place it with [LMB]",
            bgColor = BLUE,
            onClick = function()
                loadLayout(slot)
            end,
        }))
        row:Add(makeConfirmButton({
            text = "Overwrite",
            tooltip = "Replace this layout with the current one",
            bgColor = GREY,
            onConfirm = function()
                saveLayout(slot, currentLayout)
                refreshSlots()
            end,
        }))
        row:Add(makeConfirmButton({
            text = "Delete",
            bgColor = GREY,
            onConfirm = function()
                deleteLayout(slot)
                refreshSlots()
            end,
        }))
        slotsBox:Add(row)
    end
end

local function createUI()
    -- Loading and rendering come first; drawing is used much less
    local content = makeBox({ padding = 6, spacing = 6 })

    local sizeRow = makeRow()
    for i, buildingType in ipairs(BUILDING_TYPES) do
        sizeRow:Add(makeButton({
            text = buildingType.name,
            tooltip = buildingType.tooltip,
            bgColor = i == currentSizeIndex and CYAN or GREY,
            onClick = function()
                currentSizeIndex = i
                for j, button in ipairs(sizeRow.children) do
                    button.bgColor = j == i and CYAN or GREY
                end
            end,
        }))
    end

    local actionRow = makeRow()
    actionRow:Add(makeButton({
        text = "Render",
        tooltip = "Draw the current layout on the map as line marks",
        bgColor = BLUE,
        onClick = renderLayout,
    }))
    actionRow:Add(makeButton({
        text = "Clear",
        tooltip = "Empty the current layout ([CTRL]+[Z] to undo)",
        bgColor = GREY,
        onClick = function()
            local command = {}
            pushClearLayout(command, currentLayout)
            runCommand(command)
        end,
    }))
    actionRow:Add(makeButton({
        text = "Draw",
        tooltip = "Place building shapes with [LMB] and lines with [RMB]",
        bgColor = GREY,
        onClick = function(self)
            drawingMode = not drawingMode
            self.bgColor = drawingMode and CYAN or GREY
            -- the size row goes last, so nothing above it moves
            content.children[3] = drawingMode and sizeRow or nil
            log("Drawing: " .. (drawingMode and "ON" or "OFF"))
        end,
    }))
    actionRow:Add(makeButton({
        text = "Remind Allies",
        tooltip = "Tell allies in chat how to stop map marks from being auto-erased",
        bgColor = GREY,
        onClick = function()
            Spring.SendCommands({
                'say a: Go to Settings -> Interface, turn off "Auto Erase Map Marks" so you never lose the layout lines again :)',
            })
        end,
    }))

    slotsBox = makeBox({ spacing = 6, padding = 0 })
    refreshSlots()

    content:Add(actionRow)
    content:Add(slotsBox)

    local settingsContent = makeBox({ padding = 6, spacing = 6 })
    for _, toggle in ipairs({
        { "Snap", "Snap buildings to a grid of their own size", "snapBuilding" },
        { "Shift Layout", "Move the current layout with [W][A][S][D]", "allowTranslationByKeys" },
        { "Draw Chunk Grid", "Show the chunk grid around the mouse", "drawChunkGrid" },
        { "Colored types", "Give each building size its own color", "differTypesByColor" },
        { "Display Text Hints", "Show usage hints on screen", "showUsageTips" },
    }) do
        settingsContent:Add(makePrefToggle(unpack(toggle)))
    end

    myUI = makeWindow({
        title = "Layout Planner",
        fontSize = 22,
        fontColor = { 1, 0.6, 0.0, 1.0 },
        -- the window keeps its widest width, so it paints the background, not the content
        bgColor = { 0.15, 0.15, 0.15, 1 },
        content = content,
        titleButtons = {
            {
                text = "Settings",
                bgColor = GREY,
                onClick = function(button)
                    local opening = myUI.content == content
                    myUI.content = opening and settingsContent or content
                    button.bgColor = opening and CYAN or GREY
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
    local _, contentHeight = content:GetSize()
    myUI.x = prefs.windowX or 50
    myUI.y = prefs.windowY or vsy / 2 - 330 + contentHeight
end

-- Widget callins
-- ========================================

function widget:Initialize()
    loadPreferences()
    createUI()
end

function widget:Shutdown()
    savePreferences()
end

function widget:MousePress(mx, my, button)
    if button == 1 then
        if myUI:MousePress(mx, my, button) then
            return true
        end
        if lineStart then
            lineStart = nil
            return true
        end

        local pos = traceGround(mx, my)
        if not pos then
            return false
        end
        local bx, bz = buildingAnchor(pos)
        if loadedData then
            local alt = Spring.GetModKeyState()
            placeLoadedLayout(loadedData, bx, bz, alt)
            return true
        elseif drawingMode then
            local size = BUILDING_TYPES[currentSizeIndex].size
            bx, bz = snapToSize(bx, bz, size)
            dragStart = { bx = bx, bz = bz, size = size }
            return true
        end
    elseif button == 3 and loadedData then
        loadedData = nil
        return true
    elseif button == 3 and drawingMode then
        if dragStart then
            dragStart = nil
            return true
        end
        local pos = traceGround(mx, my)
        if not pos then
            return false
        end
        local bx, bz = lineAnchor(pos)
        lineStart = { bx = bx, bz = bz }
        return true
    end
    return false
end

function widget:MouseMove(mx, my)
    myUI:MouseMove(mx, my)
end

function widget:MouseRelease(mx, my, button)
    local pos = traceGround(mx, my)
    if button == 1 then
        myUI:MouseRelease()
        local start = dragStart
        dragStart = nil
        if start and pos then
            local bx, bz = buildingAnchor(pos)
            finishBuildingDrag(start, snapToSize(bx, bz, start.size))
        end
    elseif button == 3 and lineStart then
        local start = lineStart
        lineStart = nil
        if pos then
            finishLineDrag(start, lineAnchor(pos))
        end
    end
end

function widget:KeyPress(key, mods)
    if mods.ctrl and key == KEY_UNDO then
        undo()
        return true
    end
    if mods.ctrl and key == KEY_REDO then
        redo()
        return true
    end

    if loadedData and key == KEY_ROTATE then
        layoutRotation = (layoutRotation + 90) % 360
        rotateAndInvert(loadedData.layout, 90, false)
        log("rotation: " .. layoutRotation)
        return true
    end
    if loadedData and key == KEY_INVERT then
        rotateAndInvert(loadedData.layout, 0, true)
        log("layout inverted")
        return true
    end

    local direction = prefs.allowTranslationByKeys and TRANSLATE_KEYS[key]
    if direction then
        local dx, dz = getSnappedCameraDirection(direction[1], direction[2])
        if dx ~= 0 or dz ~= 0 then
            local command = {}
            pushEdit(command, "translate", currentLayout, dx, dz)
            runCommand(command)
        end
    end
    return false
end

-- Sends the queued map marks in batches
function widget:Update(dt)
    if #markQueue == 0 then
        return
    end
    markTimer = markTimer + dt
    if markTimer < BATCH_INTERVAL then
        return
    end
    markTimer = 0

    for _ = 1, LINES_PER_BATCH do
        local line = table.remove(markQueue, 1)
        if not line then
            break
        end
        Spring.MarkerAddLine(line[1], MARK_HEIGHT, line[2], line[3], MARK_HEIGHT, line[4])
    end
    if #markQueue == 0 then
        log("all lines rendered")
    end
end

function widget:DrawWorld()
    gl.PushAttrib(GL.ALL_ATTRIB_BITS)
    gl.DepthTest(true)

    local mx, my = Spring.GetMouseState()
    local pos = traceGround(mx, my)
    if prefs.drawChunkGrid and pos then
        drawChunkGrid(pos[1], pos[3])
    end
    drawLayout(currentLayout)
    if pos then
        drawPreview(pos)
    end

    gl.PopAttrib()
end

function widget:DrawScreen()
    myUI:Draw()
    if not prefs.showUsageTips then
        return
    end

    local hints = {}
    for _, hint in ipairs(loadedData and LOADED_HINTS or drawingMode and DRAWING_HINTS or {}) do
        table.insert(hints, hint)
    end
    if prefs.allowTranslationByKeys then
        table.insert(hints, "Translate layout using [W][A][S][D] keys")
    end
    if historyPointer > 0 then
        table.insert(hints, "Undo last action with [CTRL]+[Z]")
    end
    if historyPointer < #commandHistory then
        table.insert(hints, "Redo next action with [CTRL]+[A]")
    end

    local vsx, vsy = gl.GetViewSizes()
    local x = (vsx - 19 * 18) / 2
    gl.Color(1, 1, 0.5, 1)
    for i, hint in ipairs(hints) do
        gl.Text(hint, x, vsy * 0.4 - (i - 1) * 20, 18, "o")
    end
end

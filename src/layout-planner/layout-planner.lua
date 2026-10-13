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

------------------------------------------------------------------------------------------
------------------------------USER PREFERENCES / DEFAULT VALUES---------------------------
------------------------------------------------------------------------------------------
local slots = 20 --AMOUNT OF [SAVE/LOAD] SLOTS YOU WANT THE WIDGET TO DISPLAY               [0, ~)
local slotsPerRow = 5 --HOW MANY SLOTS WILL BE DISPLAYED PER ROW                            [1, ~)
local allowTranslationByKeys = true --WHETHER LAYOUT CAN BE SHIFTED USING KEYBOARD KEYS     [true, false]
local snapBuilding = true --SNAP BUILDING TO GRID                                           [true, false]
local drawChunkGrid = true --DRAW A CHUNK ALIGNED GRID                                      [true, false]
local differTypesByColor = false --WHETHER BUILDIND TYPE ARE RENDERED WITH DIFFERENT COLORS [true, false]
local showUsageTips = true --TEXT USAGE HINTS
local windowX
local windowY
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- Constants
local BU_SIZE = 16 -- 1 BU = 16 game units (BU stand for Building Unit, the smallest unit size i could find, which is Cameras)
local HALF_BU = BU_SIZE / 2
local SQUARE_SIZE = 3 * BU_SIZE -- 1 square = 3x3 BUs = 48 units
local CHUNK_SIZE = 4 * SQUARE_SIZE -- 1 chunk = 4x4 squares = 12x12 BUs

-- Building types (in BUs)
-- Building types (in BUs)
local buildingTypes = {
    -- { name = "1x1", size = 1, tooltip = "e.g.: Camera (lol)", color = {0.75, 0.75, 0.75, 1.0} }, -- soft gray
    {
        name = "Small",
        size = 2,
        tooltip = "e.g.: Wall, Dragon's Maw/Claw/Fury",
        color = { 0.60, 0.70, 0.85, 0.6 },
    }, -- desaturated blue
    {
        name = "Square",
        size = 3,
        tooltip = "e.g.: T1 Con. Turret, T1 Wind, T1 Converter",
        color = { 0.65, 0.78, 0.65, 0.6 },
    }, -- pale green
    {
        name = "Big",
        size = 4,
        tooltip = "e.g.: T2 Con. Turret, T2 Converter, Basilica",
        color = { 0.80, 0.72, 0.55, 0.6 },
    }, -- muted gold
    {
        name = "Large",
        size = 6,
        tooltip = "e.g.: AFUS, T3 Con. Turret, T2 Wind, Olympus, Basilisk",
        color = { 0.75, 0.60, 0.60, 0.6 },
    }, -- dusty rose
    {
        name = "Chunk",
        size = 12,
        tooltip = "e.g.: EFUS",
        color = { 0.70, 0.65, 0.85, 0.6 },
    }, -- soft purple
}

--------------------------------------------------------------------------------
-- UI Instance
local myUI

-- The default config ships with the widget; the user's override and saved layouts live in LuaUI/Config
local DEFAULTS_DIR = "LuaUI/Widgets/layout-planner"
local USER_DIR = "LuaUI/Config/layout-planner"
local DEFAULT_CONFIG_PATH = DEFAULTS_DIR .. "/layout-planner-config-default.txt"
local CONFIG_PATH = USER_DIR .. "/layout-planner-config.txt"

local function layoutPath(slot)
    return USER_DIR .. "/layout_" .. slot .. ".txt"
end

-- Forward declarations (defined further down, used earlier)
local GetCameraSnappedAngle, GetSnappedCameraDirection

-- Control Variables
local drawingToGame = false

--Command modifiers
local altMode = false
local ctrlMode = false

local currentLayout = {
    buildings = {
        [1] = {},
        [2] = {},
        [3] = {},
        [4] = {},
        [6] = {},
        [12] = {},
    },
    lines = {},
} --Stores the current working layout

local drawingMode = false
local currentSizeIndex = 1 -- which index into the "buildingTypes" array is selected
local loadedData = nil -- stores loaded layout
local dragging = false
local dragStart = nil
local lineStart = nil
local layoutRotation = 0

--Render stuff
local drawLineQueue = {}
local timer = 0
local renderingToGame = false

-- Convert between world space and BU grid coordinates
local function WorldToBU(x, z)
    return math.floor(x / BU_SIZE), math.floor(z / BU_SIZE)
end

local function BUToWorld(bx, bz)
    return bx * BU_SIZE, bz * BU_SIZE
end

local function GetIntersectingLineIndices(layout, r)
    local function orientation(px, pz, qx, qz, rx, rz)
        local val = (qz - pz) * (rx - qx) - (qx - px) * (rz - qz)
        if val == 0 then
            return 0
        elseif val > 0 then
            return 1
        else
            return 2
        end
    end

    local function onSegment(px, pz, qx, qz, rx, rz)
        return math.min(px, rx) <= qx
            and qx <= math.max(px, rx)
            and math.min(pz, rz) <= qz
            and qz <= math.max(pz, rz)
    end

    local function DoLinesIntersect(a, b)
        local x1, z1, x2, z2 = a[1], a[2], a[3], a[4]
        local x3, z3, x4, z4 = b[1], b[2], b[3], b[4]

        local o1 = orientation(x1, z1, x2, z2, x3, z3)
        local o2 = orientation(x1, z1, x2, z2, x4, z4)
        local o3 = orientation(x3, z3, x4, z4, x1, z1)
        local o4 = orientation(x3, z3, x4, z4, x2, z2)

        if o1 ~= o2 and o3 ~= o4 then
            return true
        end
        if o1 == 0 and onSegment(x1, z1, x3, z3, x2, z2) then
            return true
        end
        if o2 == 0 and onSegment(x1, z1, x4, z4, x2, z2) then
            return true
        end
        if o3 == 0 and onSegment(x3, z3, x1, z1, x4, z4) then
            return true
        end
        if o4 == 0 and onSegment(x3, z3, x2, z2, x4, z4) then
            return true
        end

        return false
    end

    local indices = {}
    for i, line in ipairs(layout.lines) do
        if DoLinesIntersect(r, line) then
            table.insert(indices, i)
        end
    end
    return indices
end

local function TranslateLayout(layout, dx, dz)
    for _, group in pairs(layout.buildings) do
        for _, pos in ipairs(group) do
            pos[1] = pos[1] + dx
            pos[2] = pos[2] + dz
        end
    end
    for _, line in ipairs(layout.lines) do
        line[1] = line[1] + dx
        line[3] = line[3] + dx
        line[2] = line[2] + dz
        line[4] = line[4] + dz
    end
end

local function AddLine(x1, z1, x2, z2, layout)
    if x1 == x2 and z1 == z2 then
        return
    end

    -- Normalize coordinates: sort by (x, z)
    if x2 < x1 or (x2 == x1 and z2 < z1) then
        x1, z1, x2, z2 = x2, z2, x1, z1
    end

    local workLayout = layout or currentLayout
    table.insert(workLayout.lines, { x1, z1, x2, z2 })
end

local function RemLine(x1, z1, x2, z2, layout)
    -- Normalize coordinates the same way as in AddLine
    if x2 < x1 or (x2 == x1 and z2 < z1) then
        x1, z1, x2, z2 = x2, z2, x1, z1
    end

    local workLayout = layout or currentLayout
    for i = #workLayout.lines, 1, -1 do
        local line = workLayout.lines[i]
        if line[1] == x1 and line[2] == z1 and line[3] == x2 and line[4] == z2 then
            table.remove(workLayout.lines, i)
            return
        end
    end
end

local function AddBuilding(x, z, size, layout)
    local workLayout = layout or currentLayout

    local group = workLayout.buildings[size]
    table.insert(group, { x, z })
end

local function RemBuilding(x, z, size, layout)
    local workLayout = layout or currentLayout

    local group = workLayout.buildings[size]
    for i, pos in ipairs(group) do
        if pos[1] == x and pos[2] == z then
            table.remove(group, i)
            return
        end
    end
end

---------------------------------------
------------------------COMMAND PATTERN
---------------------------------------

local commandHistory = {}
local historyPointer = 0

local function CreateCommand()
    return {
        actions = {},
        execute = function(self)
            for _, action in ipairs(self.actions) do
                action.doAction()
            end
        end,
        undo = function(self)
            for i = #self.actions, 1, -1 do
                self.actions[i].undoAction()
            end
        end,
    }
end

local function PushTranslateAction(command, layout, dx, dz)
    table.insert(command.actions, {
        doAction = function()
            TranslateLayout(layout, dx, dz)
        end,
        undoAction = function()
            TranslateLayout(layout, -dx, -dz)
        end,
    })
end

local function PushAddLineAction(command, layout, x1, z1, x2, z2)
    table.insert(command.actions, {
        doAction = function()
            AddLine(x1, z1, x2, z2, layout)
        end,
        undoAction = function()
            RemLine(x1, z1, x2, z2, layout)
        end,
    })
end

local function PushRemLineAction(command, layout, x1, z1, x2, z2)
    table.insert(command.actions, {
        doAction = function()
            RemLine(x1, z1, x2, z2, layout)
        end,
        undoAction = function()
            AddLine(x1, z1, x2, z2, layout)
        end,
    })
end

local function PushAddBuildingAction(command, layout, x, z, size)
    table.insert(command.actions, {
        doAction = function()
            AddBuilding(x, z, size, layout)
        end,
        undoAction = function()
            RemBuilding(x, z, size, layout)
        end,
    })
end

local function PushRemBuildingAction(command, layout, x, z, size)
    table.insert(command.actions, {
        doAction = function()
            RemBuilding(x, z, size, layout)
        end,
        undoAction = function()
            AddBuilding(x, z, size, layout)
        end,
    })
end

local function RunCommand(command)
    -- Prune forward history
    for i = #commandHistory, historyPointer + 1, -1 do
        commandHistory[i] = nil
    end

    table.insert(commandHistory, command)
    historyPointer = historyPointer + 1
    command:execute()

    Spring.Echo("[Layout Planner] Command stack size: " .. #commandHistory)
end

local function Undo()
    if historyPointer > 0 then
        commandHistory[historyPointer]:undo()
        historyPointer = historyPointer - 1
    end
end

local function Redo()
    if historyPointer < #commandHistory then
        historyPointer = historyPointer + 1
        commandHistory[historyPointer]:execute()
    end
end

-------------------------------------END COMMAND PATTERN-------------------------------------

local function ClearLayoutActions(cmd, workLayout)
    -- Remove all lines
    for _, line in ipairs(workLayout.lines) do
        PushRemLineAction(cmd, workLayout, unpack(line))
    end

    -- Remove all buildings
    for size, group in pairs(workLayout.buildings) do
        for _, pos in ipairs(group) do
            PushRemBuildingAction(cmd, workLayout, pos[1], pos[2], size)
        end
    end
end

local function ClearLayout(layout)
    local cmd = CreateCommand()
    ClearLayoutActions(cmd, layout)
    RunCommand(cmd)
end

local function MakeLayoutActions(cmd, workLayout)
    -- Add all lines
    for _, line in ipairs(workLayout.lines) do
        PushAddLineAction(cmd, currentLayout, unpack(line))
    end

    -- Add all buildings
    for size, group in pairs(workLayout.buildings) do
        for _, pos in ipairs(group) do
            PushAddBuildingAction(cmd, currentLayout, pos[1], pos[2], size)
        end
    end
end

--It gets a layout and returns a new one, rotated and inverted
local function ApplyRotationAndInversion(layout, rotation, invert)
    --local rotation = (targetOrientation - layoutOrientation) % 360
    if rotation == 0 and not invert then
        return -- no changes needed
    end

    -- Step 1: Compute bounds
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for size, list in pairs(layout.buildings) do
        for _, pos in ipairs(list) do
            minX = math.min(minX, pos[1])
            maxX = math.max(maxX, pos[1] + size - 1)
            minZ = math.min(minZ, pos[2])
            maxZ = math.max(maxZ, pos[2] + size - 1)
        end
    end

    for _, line in ipairs(layout.lines) do
        local x1, z1, x2, z2 = line[1], line[2], line[3], line[4]
        minX = math.min(minX, x1, x2)
        maxX = math.max(maxX, x1, x2)
        minZ = math.min(minZ, z1, z2)
        maxZ = math.max(maxZ, z1, z2)
    end

    local width = maxX - minX + 1
    local height = maxZ - minZ + 1
    local cx = minX + width / 2
    local cz = minZ + height / 2

    -- Step 2: Transform each position in-place
    for size, list in pairs(layout.buildings) do
        for _, pos in ipairs(list) do
            local ox = pos[1] + size / 2 - cx
            local oz = pos[2] + size / 2 - cz

            local rx, rz
            if rotation == 0 then
                rx, rz = ox, oz
            elseif rotation == 90 then
                rx, rz = -oz, ox
            elseif rotation == 180 then
                rx, rz = -ox, -oz
            elseif rotation == 270 then
                rx, rz = oz, -ox
            else
                error("Unsupported rotation: " .. tostring(rotation))
            end

            local newX = math.floor(cx + rx - size / 2 + 0.5)
            local newZ = math.floor(cz + rz - size / 2 + 0.5)

            if invert then
                local camAngle = GetCameraSnappedAngle()
                if camAngle == 90 or camAngle == 270 then
                    newX = 2 * cx - newX - size
                else
                    newZ = 2 * cz - newZ - size
                end
            end

            pos[1] = newX
            pos[2] = newZ
        end
    end
    -- TRANSFROM LINES
    for _, line in ipairs(layout.lines) do
        local x1, z1 = line[1], line[2]
        local x2, z2 = line[3], line[4]

        local function transformPoint(x, z)
            local ox = x - cx
            local oz = z - cz

            local rx, rz
            if rotation == 0 then
                rx, rz = ox, oz
            elseif rotation == 90 then
                rx, rz = -oz, ox
            elseif rotation == 180 then
                rx, rz = -ox, -oz
            elseif rotation == 270 then
                rx, rz = oz, -ox
            else
                error("Unsupported rotation: " .. tostring(rotation))
            end

            local nx = math.floor(cx + rx + 0.5)
            local nz = math.floor(cz + rz + 0.5)

            if invert then
                local camAngle = GetCameraSnappedAngle()
                if camAngle == 90 or camAngle == 270 then
                    nx = 2 * cx - nx
                else
                    nz = 2 * cz - nz
                end
            end

            return nx, nz
        end

        line[1], line[2] = transformPoint(x1, z1)
        line[3], line[4] = transformPoint(x2, z2)
    end
end

local function DrawEdges(edges)
    Spring.Echo("[LayoutPlanner] Queuing " .. tostring(#edges) .. " edges for rendering.")
    drawLineQueue = {} -- Clear old queue

    for _, edge in ipairs(edges) do
        local x1, z1 = BUToWorld(edge.x1, edge.z1)
        local x2, z2 = BUToWorld(edge.x2, edge.z2)
        local y = 100

        local dx = x2 - x1
        local dz = z2 - z1
        local dist = math.sqrt(dx * dx + dz * dz)

        local segments = math.ceil(dist / CHUNK_SIZE)
        if segments <= 1 then
            table.insert(drawLineQueue, {
                startX = x1,
                startZ = z1,
                endX = x2,
                endZ = z2,
                y = y,
            })
        else
            for i = 0, segments - 1 do
                local t1 = i / segments
                local t2 = (i + 1) / segments
                local sx = x1 + dx * t1
                local sz = z1 + dz * t1
                local ex = x1 + dx * t2
                local ez = z1 + dz * t2
                table.insert(drawLineQueue, {
                    startX = sx,
                    startZ = sz,
                    endX = ex,
                    endZ = ez,
                    y = y,
                })
            end
        end
    end
    renderingToGame = true
end

local function CollectEdges()
    Spring.Echo("[LayoutPlanner] Collecting and merging outer edges...")

    local function edgeKey(x1, z1, x2, z2)
        -- Normalize to avoid reversed duplicates keys
        if x1 > x2 or (x1 == x2 and z1 > z2) then
            x1, z1, x2, z2 = x2, z2, x1, z1
        end
        return x1 .. "," .. z1 .. "," .. x2 .. "," .. z2
    end

    local rawEdges = {}

    -- 1. Generate 4 outer edges per building
    for size, buildings in pairs(currentLayout.buildings) do
        for _, pos in ipairs(buildings) do
            local bx, bz = pos[1], pos[2]
            local edges = {
                { bx, bz, bx + size, bz }, -- top
                { bx + size, bz, bx + size, bz + size }, -- right
                { bx + size, bz + size, bx, bz + size }, -- bottom
                { bx, bz + size, bx, bz }, -- left
            }

            for _, e in ipairs(edges) do
                local k = edgeKey(unpack(e))
                if rawEdges[k] then
                    rawEdges[k] = nil -- shared/internal edge — remove it
                else
                    rawEdges[k] = { x1 = e[1], z1 = e[2], x2 = e[3], z2 = e[4] }
                end
            end
        end
    end

    -- 2. Group by horizontal and vertical
    local horizontal, vertical = {}, {}
    for _, edge in pairs(rawEdges) do
        if edge.z1 == edge.z2 then
            table.insert(horizontal, edge)
        elseif edge.x1 == edge.x2 then
            table.insert(vertical, edge)
        end
    end

    local function mergeLines(edges, isHorizontal)
        local merged = {}
        local axis1, axis2 = isHorizontal and "x" or "z", isHorizontal and "z" or "x"

        -- Group by fixed axis2 (e.g., all z for horizontal lines)
        local groups = {}
        for _, e in ipairs(edges) do
            local key = tostring(e[axis2 .. "1"])
            groups[key] = groups[key] or {}
            local a1 = math.min(e[axis1 .. "1"], e[axis1 .. "2"])
            local a2 = math.max(e[axis1 .. "1"], e[axis1 .. "2"])
            table.insert(groups[key], { a1 = a1, a2 = a2 })
        end

        for coord, segs in pairs(groups) do
            table.sort(segs, function(a, b)
                return a.a1 < b.a1
            end)

            local currentA1, currentA2 = segs[1].a1, segs[1].a2
            for i = 2, #segs do
                local seg = segs[i]
                if seg.a1 <= currentA2 then
                    currentA2 = math.max(currentA2, seg.a2) -- merge
                else
                    -- emit previous
                    local line = isHorizontal
                            and {
                                x1 = currentA1,
                                z1 = tonumber(coord),
                                x2 = currentA2,
                                z2 = tonumber(coord),
                            }
                        or {
                            x1 = tonumber(coord),
                            z1 = currentA1,
                            x2 = tonumber(coord),
                            z2 = currentA2,
                        }
                    table.insert(merged, line)
                    currentA1, currentA2 = seg.a1, seg.a2
                end
            end
            -- final segment
            local line = isHorizontal
                    and {
                        x1 = currentA1,
                        z1 = tonumber(coord),
                        x2 = currentA2,
                        z2 = tonumber(coord),
                    }
                or { x1 = tonumber(coord), z1 = currentA1, x2 = tonumber(coord), z2 = currentA2 }
            table.insert(merged, line)
        end

        return merged
    end

    -- 3. Merge all segments
    local result = {}
    for _, e in ipairs(mergeLines(horizontal, true)) do
        table.insert(result, e)
    end
    for _, e in ipairs(mergeLines(vertical, false)) do
        table.insert(result, e)
    end

    for _, line in ipairs(currentLayout.lines) do
        table.insert(result, { x1 = line[1], z1 = line[2], x2 = line[3], z2 = line[4] })
    end

    Spring.Echo("[LayoutPlanner] Final edge count:", #result)
    return result
end

local function CollectAndDraw()
    DrawEdges(CollectEdges())
end

local function CopyLayout(src)
    local copy = {
        buildings = {
            [1] = {},
            [2] = {},
            [3] = {},
            [4] = {},
            [6] = {},
            [12] = {},
        },
        lines = {},
    } -- new layout
    for size, group in pairs(src.buildings) do
        --copy.buildings[size] = {}
        for _, pos in ipairs(group) do
            table.insert(copy.buildings[size], { pos[1], pos[2] })
        end
    end
    for _, line in ipairs(src.lines) do
        table.insert(copy.lines, { line[1], line[2], line[3], line[4] })
    end
    return copy
end

local function SaveLayout(slot, layout)
    local workLayout = layout or currentLayout

    local filename = layoutPath(slot)
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    local minSize = math.huge

    for k, v in pairs(workLayout.buildings) do
        if #v > 0 and k < minSize then
            minSize = k
        end
    end
    for _, positions in pairs(workLayout.buildings) do
        for _, pos in ipairs(positions) do
            local x, z = pos[1], pos[2]
            if x < minX then
                minX = x
            end
            if x > maxX then
                maxX = x
            end
            if z < minZ then
                minZ = z
            end
            if z > maxZ then
                maxZ = z
            end
        end
    end
    for _, line in ipairs(workLayout.lines) do
        local x, z = line[1], line[2]
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if z < minZ then
            minZ = z
        end
        if z > maxZ then
            maxZ = z
        end
        x, z = line[3], line[4]
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if z < minZ then
            minZ = z
        end
        if z > maxZ then
            maxZ = z
        end
    end
    if maxX == math.huge then
        Spring.Echo("[LayoutPlanner] Nothing to save.")
        return
    end

    if minSize == math.huge then
        minSize = 1
    end

    local width = maxX - minX + 1
    local height = maxZ - minZ + 1

    local function SerializeLayout(wLayout)
        local result = {}
        local indentLevel = 0

        local function indent()
            return string.rep("  ", indentLevel)
        end

        local function addLine(line)
            table.insert(result, indent() .. line)
        end

        addLine("{")
        indentLevel = indentLevel + 1

        -- Serialize buildings
        addLine("buildings = {")
        indentLevel = indentLevel + 1
        for size, positions in pairs(wLayout.buildings) do
            addLine("[" .. size .. "] = {")
            indentLevel = indentLevel + 1
            for _, pos in ipairs(positions) do
                addLine(string.format("{%d, %d},", pos[1], pos[2]))
            end
            indentLevel = indentLevel - 1
            addLine("},")
        end
        indentLevel = indentLevel - 1
        addLine("},")

        -- Serialize lines
        addLine("lines = {")
        indentLevel = indentLevel + 1
        --Spring.Echo("Saving lines .. "..#workLayout.lines)
        for _, line in ipairs(wLayout.lines) do
            addLine(string.format("{%d, %d, %d, %d},", line[1], line[2], line[3], line[4]))
        end
        indentLevel = indentLevel - 1
        addLine("}")

        indentLevel = indentLevel - 1
        addLine("}")

        return table.concat(result, "\n")
    end

    Spring.CreateDir(USER_DIR)
    local file = io.open(filename, "w")
    if not file then
        Spring.Echo("[LayoutPlanner] Failed to open file for saving layout: " .. filename)
        return
    end

    local layoutCopy = CopyLayout(workLayout)
    TranslateLayout(layoutCopy, -minX, -minZ)

    file:write("return {\n")
    file:write("  width = " .. width .. ",\n")
    file:write("  height = " .. height .. ",\n")
    file:write("  maxX = " .. maxX .. ",\n")
    file:write("  maxZ = " .. maxZ .. ",\n")
    file:write("  minSize = " .. minSize .. ",\n")
    file:write("  layout = " .. SerializeLayout(layoutCopy) .. "\n")
    file:write("}\n")
    file:close()

    Spring.Echo("[LayoutPlanner] Layout saved: " .. filename)
end

local function LoadLayout(slot)
    local filename = layoutPath(slot)
    local chunk, err = loadfile(filename)

    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            loadedData = result
            -- ClearLayout()
            Spring.Echo("[LayoutPlanner] Layout loaded: " .. filename)
            return
        else
            Spring.Echo("[LayoutPlanner] Error running chunk, attempting legacy fallback")
        end
    else
        Spring.Echo("[LayoutPlanner] Failed to load layout file:", err)
    end

    -- Legacy fallback
    local file = io.open(filename, "r")
    if not file then
        Spring.Echo("[LayoutPlanner] Could not find file", filename)
        return
    end

    Spring.Echo("[LayoutPlanner] Trying to convert legacy save format")
    local tempLayout = {
        buildings = {
            [1] = {},
            [2] = {},
            [3] = {},
            [4] = {},
            [6] = {},
            [12] = {},
        },
        lines = {},
    } --Stores the current working layout

    for line in file:lines() do
        local x, z, size = line:match("^(%-?%d+),%s*(%-?%d+),%s*(%d+)$")
        local nx, nz, nsize = tonumber(x), tonumber(z), tonumber(size)
        if nx and nz and nsize then
            AddBuilding(nx, nz, nsize, tempLayout)
        else
            Spring.Echo("[LayoutPlanner] Could not parse line in legacy format:", line)
            file:close()
            return
        end
    end

    file:close()
    SaveLayout(slot, tempLayout)
    Spring.Echo("[LayoutPlanner] Legacy format converted and saved. Reload the layout.")
end

local GRID_COLOR = { 1, 1, 1, 1 } -- Yellow with transparency
local LINE_WIDTH = 2
local HEIGHT_OFFSET = 5 -- raise lines above ground
local RADIUS_CHUNKS = 8 -- how many chunks out from center

local function DrawChunkGrid(cx, cz)
    gl.PushAttrib(GL.ALL_ATTRIB_BITS)
    gl.Color(GRID_COLOR)
    gl.DepthTest(true)
    gl.LineWidth(LINE_WIDTH)

    gl.BeginEnd(GL.LINES, function()
        local centerChunkX = math.floor(cx / CHUNK_SIZE)
        local centerChunkZ = math.floor(cz / CHUNK_SIZE)

        local minChunkX = centerChunkX - RADIUS_CHUNKS
        local maxChunkX = centerChunkX + RADIUS_CHUNKS
        local minChunkZ = centerChunkZ - RADIUS_CHUNKS
        local maxChunkZ = centerChunkZ + RADIUS_CHUNKS

        -- At the top (optional for performance)
        local maxDistSq = (RADIUS_CHUNKS * CHUNK_SIZE) ^ 2

        -- Vertical lines (x lines, varying z)
        for chunkX = minChunkX, maxChunkX do
            local x = chunkX * CHUNK_SIZE
            for chunkZ = minChunkZ, maxChunkZ - 1 do
                local z1 = chunkZ * CHUNK_SIZE
                local z2 = z1 + CHUNK_SIZE
                local midX = x + CHUNK_SIZE / 2
                local midZ = z1 + CHUNK_SIZE / 2
                local dx = midX - cx
                local dz = midZ - cz
                local distSq = dx * dx + dz * dz
                if distSq <= maxDistSq then
                    local alpha = 1.0 - (distSq / maxDistSq) -- 1 at center, 0 at edge
                    alpha = alpha * GRID_COLOR[4] -- scale by original alpha
                    local y1 = Spring.GetGroundHeight(x, z1) + HEIGHT_OFFSET
                    local y2 = Spring.GetGroundHeight(x, z2) + HEIGHT_OFFSET
                    gl.Color(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], alpha)
                    gl.Vertex(x, y1, z1)
                    gl.Vertex(x, y2, z2)
                end
            end
        end

        -- Horizontal lines (z lines, varying x)
        for chunkZ = minChunkZ, maxChunkZ do
            local z = chunkZ * CHUNK_SIZE
            for chunkX = minChunkX, maxChunkX - 1 do
                local x1 = chunkX * CHUNK_SIZE
                local x2 = x1 + CHUNK_SIZE
                local midX = x1 + CHUNK_SIZE / 2
                local midZ = z + CHUNK_SIZE / 2
                local dx = midX - cx
                local dz = midZ - cz
                local distSq = dx * dx + dz * dz
                if distSq <= maxDistSq then
                    local alpha = 1.0 - (distSq / maxDistSq)
                    alpha = alpha * GRID_COLOR[4]
                    local y1 = Spring.GetGroundHeight(x1, z) + HEIGHT_OFFSET
                    local y2 = Spring.GetGroundHeight(x2, z) + HEIGHT_OFFSET
                    gl.Color(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], alpha)
                    gl.Vertex(x1, y1, z)
                    gl.Vertex(x2, y2, z)
                end
            end
        end
    end)

    gl.LineWidth(1)
    gl.Color(1, 1, 1, 1)
    gl.DepthTest(true)
    gl.PopAttrib()
end

--------------------------------------------------------------------------------
-- PREFERENCES TO FILE
local function SaveUserPreferences()
    Spring.CreateDir(USER_DIR)
    local file = io.open(CONFIG_PATH, "w")
    if not file then
        Spring.Echo("[LayoutPlanner] Failed to save config.")
        return
    end

    --file:write("slots = ", slots, "\n")
    --file:write("slotsPerRow = ", slotsPerRow, "\n")
    file:write("allowTranslationByKeys = ", tostring(allowTranslationByKeys), "\n")
    file:write("snapBuilding = ", tostring(snapBuilding), "\n")
    file:write("drawChunkGrid = ", tostring(drawChunkGrid), "\n")
    file:write("differTypesByColor = ", tostring(differTypesByColor), "\n")
    file:write("showUsageTips = ", tostring(showUsageTips), "\n")

    if myUI then
        file:write("windowX = ", myUI.x, "\n")
        file:write("windowY = ", myUI.y, "\n")
    end

    file:close()
    Spring.Echo("[LayoutPlanner] Config saved.")
end

local function LoadUserPreferences()
    local chunk = loadfile(CONFIG_PATH) or loadfile(DEFAULT_CONFIG_PATH)
    if not chunk then
        Spring.Echo("[LayoutPlanner] No config file found.")
        return
    end

    local env = {}
    setfenv(chunk, env)
    chunk()

    slots = env.slots or slots
    slotsPerRow = env.slotsPerRow or slotsPerRow
    allowTranslationByKeys = env.allowTranslationByKeys ~= false -- default true
    snapBuilding = env.snapBuilding ~= false
    drawChunkGrid = env.drawChunkGrid ~= false
    differTypesByColor = env.differTypesByColor ~= false
    showUsageTips = env.showUsageTips ~= false
    windowX = env.windowX or windowX
    windowY = env.windowY or windowY

    Spring.Echo("[LayoutPlanner] Config loaded.")
end

local function DisableWidget()
    SaveUserPreferences()
    Spring.Echo("[LayoutPlanner] Closed")
    widgetHandler:RemoveWidget()
end

local gl = gl
local glColor = gl.Color
local glRect = gl.Rect
local glText = gl.Text
local glGetTextWidth = gl.GetTextWidth
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

--------------------------------------------------------------------------------
-- Box (Container)
local function Box(params)
    local box = BaseElement(params)
    box.orientation = params.orientation or "vertical"
    box.padding = params.padding or 4
    box.spacing = params.spacing or 4
    box.children = {}

    function box:Add(child)
        table.insert(self.children, child)
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

--------------------------------------------------------------------------------
-- Label

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

--------------------------------------------------------------------------------
-- Button
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
            self.onClick()
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

--------------------------------------------------------------------------------
-- Checkbox

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
--------------------------------------------------------------------------------
-- Selection Group

local function MakeSelectionGroup(params)
    local group = BaseElement(params)
    group.options = params.options or {}
    group.selected = params.selected or 1
    group.hoveredIdx = -1
    group.onSelect = params.onSelect or function(_) end
    group.fontSize = params.fontSize or 14
    group.itemBgColor = params.itemBgColor or { 0.2, 0.2, 0.2, 1 }
    group.fontColor = params.fontColor or { 1, 1, 1, 1 }
    group.optionTooltips = params.optionTooltips or {}

    function group:GetSize()
        local height = 0
        local width = 0
        for _, opt in ipairs(self.options) do
            local w = glGetTextWidth(opt.name) * self.fontSize + 30
            width = math.max(width, w)
            height = height + self.fontSize + 10
        end
        self.width = width
        self.height = height
        return self.width + 2 * self.margin, self.height + 2 * self.margin
    end

    function group:Hover(mx, my)
        if not group.optionTooltips then
            return false
        end

        local boxSize = self.fontSize + 4
        local spacing = 6
        local offsetY = self.y + self.height - boxSize

        for i = 1, #self.options do
            local boxX = self.x - 2
            local boxY = offsetY - 2
            local text = self.options[i].name
            local textWidth = glGetTextWidth(text) * self.fontSize + 5 + 2
            local totalWidth = boxSize + 5 + textWidth + 2
            local areaX2 = boxX + totalWidth
            local areaY2 = boxY + boxSize

            if
                mx >= boxX
                and mx <= areaX2
                and my >= boxY
                and my <= areaY2
                and #group.options >= i
            then
                group.hoveredIdx = i
                currentToolTip = group.options[i].tooltip
                return true
            end

            offsetY = offsetY - (boxSize + spacing)
        end
        return false
    end

    function group:Draw()
        glColor(self.bgColor)
        glRect(self.x, self.y, self.x + self.width, self.y + self.height)

        local boxSize = self.fontSize + 4
        local spacing = 6
        local offsetY = self.y + self.height - boxSize

        for i, option in ipairs(self.options) do
            local isSelected = (i == self.selected)
            local boxX = self.x
            local boxY = offsetY
            --if differTypesByColor then
            --  local r,g,b,a = unpack(option.color)
            --  a = 0.8
            --  glColor(r,g,b,a)
            --else
            --    glColor(0.2, 0.2, 0.2, 1)
            --end
            if self.hoveredIdx == i then
                glColor(0.3, 0.3, 0.3, 1)
                self.hoveredIdx = -1
            else
                glColor(0.2, 0.2, 0.2, 1)
            end

            glRect(boxX, boxY, boxX + boxSize, boxY + boxSize)
            if isSelected then
                glColor(0, 0.8, 0.8, 1)
                glRect(boxX + 2, boxY + 2, boxX + boxSize - 2, boxY + boxSize - 2)
            end
            glColor(self.fontColor)
            glText(
                option.name,
                boxX + boxSize + 5,
                boxY + (boxSize - self.fontSize) / 2 + 2,
                self.fontSize,
                ""
            )
            offsetY = offsetY - (boxSize + spacing)
        end
    end

    function group:MousePress(mx, my)
        local boxSize = self.fontSize + 4
        local spacing = 6
        local offsetY = self.y + self.height - boxSize

        for i = 1, #self.options do
            local boxX = self.x - 2
            local boxY = offsetY - 2
            local text = self.options[i].name
            local textWidth = glGetTextWidth(text) * self.fontSize + 5 + 2
            local totalWidth = boxSize + 5 + textWidth + 2
            local areaX2 = boxX + totalWidth
            local areaY2 = boxY + boxSize

            if mx >= boxX and mx <= areaX2 and my >= boxY and my <= areaY2 then
                self.selected = i
                self.onSelect(i)
                return true
            end

            offsetY = offsetY - (boxSize + spacing)
        end
        return false
    end

    return group
end
--------------------------------------------------------------------------------
-- Window

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

    local titleBarHeight = 32
    local closeButton = MakeButton({
        bgColor = { 0.6, 0.1, 0.0, 1.0 },
        height = titleBarHeight - 8,
        text = "Close Widget",
        onClick = params.onClose,
    })
    window.closeButton = closeButton

    function window:Draw()
        if self.closed then
            return
        end
        --glColor({0,0,0,1})
        --glRect(self.x, self.y, self.x + self.width, self.y + self.height)

        -- Draw title bar
        glColor({ 0.1, 0.1, 0.1, 1 })
        glRect(
            self.x,
            self.y + self.height - titleBarHeight,
            self.x + self.width,
            self.y + self.height
        )
        glColor(unpack(self.fontColor))
        glText(self.title, self.x + 5, self.y + self.height - titleBarHeight + 7, self.fontSize, "")

        -- Position and draw close button
        self.closeButton.x = self.x + self.width - 104
        self.closeButton.y = self.y + self.height - titleBarHeight + 4
        self.closeButton:Draw()

        -- Position and draw content
        if self.content then
            self.content.x = self.x
            self.content.y = self.y - titleBarHeight
            -- self.content.width = self.width
            -- self.content.height = self.height - titleBarHeight
            self.content:Draw()
        end

        if currentToolTip then
            local mx, my = Spring.GetMouseState()
            my = my + 6

            local tooltipFontSize = 16
            local lineSpacing = 4
            local padding = 6
            local border = 2

            -- Split text into lines
            local lines = {}
            for line in currentToolTip:gmatch("[^\n]+") do
                table.insert(lines, line)
            end

            -- Measure width and height
            local maxLineWidth = 0
            for _, line in ipairs(lines) do
                local lineWidth = glGetTextWidth(line) * tooltipFontSize
                maxLineWidth = math.max(maxLineWidth, lineWidth)
            end

            local tooltipWidth = maxLineWidth + 2 * padding
            local tooltipHeight = (#lines * (tooltipFontSize + lineSpacing))
                - lineSpacing
                + 2 * padding

            -- Draw background box
            glColor(0.9, 0.5, 0.1, 0.9)
            glRect(
                mx - border,
                my - border - 4,
                mx + tooltipWidth + border,
                my + tooltipHeight + border
            )

            -- Draw text
            glColor(1, 1, 1, 1)
            local textY = my + tooltipHeight - padding - tooltipFontSize
            for _, line in ipairs(lines) do
                glText(line, mx + padding, textY, tooltipFontSize, "")
                textY = textY - (tooltipFontSize + lineSpacing)
            end
        end

        local cw, ch = self.content:GetSize()
        self.width = cw
        self.height = ch
    end

    function window:Hover(mx, my)
        if closeButton:Hover(mx, my) then
            return
        end
        self.content:Hover(mx, my)
    end

    function window:MousePress(mx, my, button)
        if self.closeButton:MousePress(mx, my) then
            return true
        elseif
            mx >= self.x
            and mx <= self.x + self.width
            and my >= self.y + self.height - titleBarHeight
            and my <= self.y + self.height
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

    function window:MouseMove(mx, my)
        if self.dragging then
            self.x = mx - self.offsetX
            self.y = my - self.offsetY
        end
    end

    function window:MouseRelease()
        self.dragging = false
    end

    return window
end

-------------------------------------------------------------------------------------

function widget:Initialize()
    LoadUserPreferences()

    if slots < 0 then
        Spring.Echo("[LayoutPlanner] Slot amount cannot be negative")
        DisableWidget()
        return
    end
    if slotsPerRow < 1 then
        Spring.Echo("[LayoutPlanner] Slots per row must be greater than 0")
        DisableWidget()
        return
    end

    local drawBox = Box({ orientation = "horizontal", spacing = 6, padding = 4 })

    drawBox:Add(MakeCheckbox({
        text = "Enable Layout Draw",
        tooltip = "Allow placing of buildings (LMB) and lines (RMB)",
        checked = drawingMode,
        fontSize = 16,
        onToggle = function(state)
            drawingMode = state
            Spring.Echo("[LayoutPlanner] Drawing: " .. (drawingMode and "ON" or "OFF"))
        end,
    }))

    drawBox:Add(MakeCheckbox({
        text = "Snap",
        checked = snapBuilding,
        tooltip = "Snap the building to the grid according to the selected size",
        fontSize = 16,
        onToggle = function(state)
            snapBuilding = state
            Spring.Echo("[LayoutPlanner] Snap: " .. (snapBuilding and "ON" or "OFF"))
        end,
    }))

    --Building sizes
    drawBox:Add(MakeSelectionGroup({
        options = buildingTypes,
        fontSize = 16,
        onSelect = function(i)
            Spring.Echo("[LayoutPlanner] Current Size: " .. i)
            currentSizeIndex = i
        end,
    }))

    local layoutButtons = Box({ orientation = "horizontal", spacing = 6, padding = 4 })
    layoutButtons:Add(MakeButton({
        text = "Clear Layout",
        tooltip = "Removes all buildings and lines from the current layout",
        bgColor = { 0.8, 0.4, 0.1, 1.0 },
        fontSize = 20,
        onClick = function()
            ClearLayout(currentLayout)
        end,
    }))
    layoutButtons:Add(MakeButton({
        text = "Render",
        tooltip = "Render all buildings and lines of the current layout as line marks in the game world",
        fontSize = 20,
        bgColor = { 0.0, 0.2, 0.8, 1.0 },
        onClick = function()
            CollectAndDraw()
        end,
    }))

    local content = Box({
        bgColor = { 0.15, 0.15, 0.15, 1 },
        orientation = "vertical",
        spacing = 6,
        padding = 4,
    })
    content:Add(drawBox)

    local shiftAndGridBox = Box({ orientation = "horizontal", spacing = 6, padding = 4 })
    content:Add(shiftAndGridBox)
    shiftAndGridBox:Add(MakeCheckbox({
        text = "Shift Layout",
        checked = allowTranslationByKeys,
        tooltip = "Whether the active layout can be shifted using the keyboard WASD keys",
        fontSize = 16,
        onToggle = function(state)
            allowTranslationByKeys = state
            Spring.Echo("[LayoutPlanner] Shift: " .. (allowTranslationByKeys and "ON" or "OFF"))
        end,
    }))
    shiftAndGridBox:Add(MakeCheckbox({
        text = "Draw Chunk Grid",
        checked = drawChunkGrid,
        tooltip = "Display a chunk aligned grid around mouse",
        fontSize = 16,
        onToggle = function(state)
            drawChunkGrid = state
            Spring.Echo("[LayoutPlanner] Draw chunk grid: " .. (drawChunkGrid and "ON" or "OFF"))
        end,
    }))

    local hintsBox = Box({ orientation = "horizontal", spacing = 6, padding = 4 })
    content:Add(hintsBox)
    hintsBox:Add(MakeCheckbox({
        text = "Colored types",
        checked = differTypesByColor,
        tooltip = "Display each unit type with different colors",
        fontSize = 16,
        onToggle = function(state)
            differTypesByColor = state
            Spring.Echo(
                "[LayoutPlanner] Different colors: " .. (differTypesByColor and "ON" or "OFF")
            )
        end,
    }))
    hintsBox:Add(MakeCheckbox({
        text = "Display Text Hints",
        checked = showUsageTips,
        tooltip = "Display text usage hints on the screen",
        fontSize = 16,
        onToggle = function(state)
            showUsageTips = state
            Spring.Echo("[LayoutPlanner] Usage hints: " .. (showUsageTips and "ON" or "OFF"))
        end,
    }))
    content:Add(layoutButtons)
    content:Add(MakeButton({
        text = "Auto Erase Reminder",
        fontSize = 20,
        bgColor = { 0.0, 0.2, 0.1, 1.0 },
        tooltip = "Send a message about how to disable auto erase. New players on your lobby might need to know this. :)",
        onClick = function()
            Spring.SendCommands({
                'say Go to Settings -> Interface, turn off "Auto Erase Map Marks" so you never lose the layout lines again :)',
            })
        end,
    }))

    content:Add(MakeLabel({ bgColor = { 0, 0, 0, 0 }, text = "Layout Slots:", fontSize = 14 }))

    local rows = math.ceil(slots / slotsPerRow)

    for h = 0, rows - 1 do
        local row = Box({ orientation = "horizontal", spacing = 13, padding = 4 })

        for i = 1, slotsPerRow do
            local slotId = h * slotsPerRow + i
            if slotId > slots then
                break
            end

            local slotName = slotId < 10 and "0" .. tostring(slotId) or tostring(slotId)

            local slot = Box({
                orientation = "vertical",
                spacing = 6,
                padding = 4,
                bgColor = { 0.0, 0.0, 0, 1 },
            })
            slot:Add(MakeButton({
                text = "Save " .. slotName,
                bgColor = { 0.15, 0.6, 0.25, 1.0 },
                onClick = function()
                    SaveLayout(slotId)
                end,
            }))
            slot:Add(MakeButton({
                text = "Load " .. slotName,
                bgColor = { 0.3, 0.4, 1, 1.0 },
                onClick = function()
                    LoadLayout(slotId)
                end,
            }))
            row:Add(slot)
        end

        content:Add(row)
    end

    content:Add(MakeLabel({
        bgColor = { 0.45, 0.16, 0.025, 1.0 },
        text = "DON'T PANIC!",
        fontSize = 14,
        tooltip = [[
DON'T PANIC!
    To draw your layout, first click on "Enable Layout Draw". You will see a square at your mouse position; it is a preview of where you will draw to the layout. The small dot is where a line will begin.
    Use [left mouse button] to place buildings, use [ALT] or [ALT + CTRL] keys to change the way it is placed.
    Use [right mouse button] to render arbitrary lines to your layout; hold the [ALT] key so you can remove lines.
    You can draw your layout using different size of buildings (Small, Square, Big, Large or Chunk). Adjacent buildings of the same size will be rendered together (i.e.: a single contour for the shape defined by buildings of the same type).
    You can use CTRL+Z/CTRL+A to undo/redo your actions over the active layout.
    Once the layout is created, save it on a slot using a Save button below, you can load it anytime later pressing the Load button with same slot number.
    A loaded layout can be rotated with the [R] key and inverted with the [I] key before being placed.
    Press "Render" to draw the active layout to the game.
    You can click and drag the widget window by the title bar.


IF YOUR ARE NEW:
    Draw your layout alligned to chunks. The size of a chunk is a multiple of almost every building in the game! You can optimize your layout space based on this.
    Use the "Snap" option! Its the best way to render regular layouts, which will be alligned to the grid.

Check and use the widget discord page if you have any trouble with this widget.]],
    }))

    myUI = MakeWindow({
        title = "Layout Planner",
        fontSize = 22,
        fontColor = { 1, 0.6, 0.0, 1.0 },
        content = content,
        onClose = DisableWidget,
    })
    local _, vsy = gl.GetViewSizes()
    local _, h = myUI:GetSize()
    myUI.x, myUI.y = windowX or 50, windowY or vsy / 2 - h - 300
end

--------------------------------------------------------------------------------
-- Drawing and Input

function widget:DrawScreen()
    if myUI then
        myUI:Draw()
    end

    if not showUsageTips then
        return
    end

    local vsx, vsy = gl.GetViewSizes()
    local textWidth = 19 * 18
    vsy = vsy * 0.4

    -- Placement hint text
    if loadedData and loadedData.layout then
        gl.Color(1, 1, 0.5, 1)
        gl.Text("Press [R] to rotate", (vsx - textWidth) / 2, vsy, 18, "o")
        gl.Text("Press [I] to invert", (vsx - textWidth) / 2, vsy - 20, 18, "o")
        gl.Text(
            "Hold [ALT] while placing to merge with current layout.",
            (vsx - textWidth) / 2,
            vsy - 40,
            18,
            "o"
        )
        vsy = vsy - 60
    elseif drawingMode then --Drawing
        gl.Color(1, 1, 0.5, 1)
        gl.Text(
            "Use [left mouse button] to place buildings. Hold [ALT] to place in area",
            (vsx - textWidth) / 2,
            vsy,
            18,
            "o"
        )
        gl.Text(
            "Use [right mouse button] to place lines. Hold [ALT] to remove crossed lines",
            (vsx - textWidth) / 2,
            vsy - 20,
            18,
            "o"
        )
        gl.Text(
            "Use [left mouse button] + [CTRL] + [ALT] to draw traced lines instead of area. (The amount of traces is based on the building Size)",
            (vsx - textWidth) / 2,
            vsy - 40,
            18,
            "o"
        )
        vsy = vsy - 60
    end
    if allowTranslationByKeys then --Translation
        gl.Color(1, 1, 0.5, 1)
        gl.Text("Translate layout using [W][A][S][D] keys", (vsx - textWidth) / 2, vsy, 18, "o")
        vsy = vsy - 20
    end

    if #commandHistory > 0 and historyPointer > 0 then
        gl.Text("Undo last action with [CTRL]+[Z]", (vsx - textWidth) / 2, vsy, 18, "o")
        vsy = vsy - 20
    end
    if historyPointer < #commandHistory then
        gl.Text("Redo next action with [CTRL]+[A]", (vsx - textWidth) / 2, vsy, 18, "o")
        vsy = vsy - 20
    end
end

function widget:MousePress(mx, my, button)
    --1 left
    --3 right
    if button == 1 then
        if myUI and myUI:MousePress(mx, my, button) then
            return true
        end
        if lineStart then
            lineStart = nil
            return true
        end

        local _, pos = Spring.TraceScreenRay(mx, my, true)
        if not pos then
            return false
        end

        local bx, bz = WorldToBU(pos[1], pos[3])
        local size = buildingTypes[currentSizeIndex].size

        if loadedData and loadedData.layout then
            if not altMode then
                local shiftX = math.floor((loadedData.width + loadedData.minSize) / 2)
                local shiftZ = math.floor((loadedData.height + loadedData.minSize) / 2)
                TranslateLayout(loadedData.layout, bx - shiftX, bz - shiftZ)
                local cmd = CreateCommand()
                ClearLayoutActions(cmd, currentLayout)
                MakeLayoutActions(cmd, loadedData.layout)
                --currentLayout = loadedData.layout
                RunCommand(cmd)
                loadedData = nil
            else
                local copy = CopyLayout(loadedData.layout)
                local shiftX = math.floor((loadedData.width + loadedData.minSize) / 2)
                local shiftZ = math.floor((loadedData.height + loadedData.minSize) / 2)
                TranslateLayout(copy, bx - shiftX, bz - shiftZ)

                local cmd = CreateCommand()
                MakeLayoutActions(cmd, copy)
                --currentLayout = loadedData.layout
                RunCommand(cmd)
            end

            Spring.Echo("[LayoutPlanner] Layout placed.")
            return true
        elseif drawingMode then
            if snapBuilding then
                bx = math.floor(bx / size) * size
                bz = math.floor(bz / size) * size
            end
            dragging = true
            dragStart = { bx = bx, bz = bz, size = size }
            return true
        end

        return false
    elseif button == 3 and loadedData then
        loadedData = nil
        return true
    elseif button == 3 and drawingMode then
        if dragStart then
            dragStart = nil
            return true
        end

        local _, pos = Spring.TraceScreenRay(mx, my, true)
        if not pos then
            return false
        end
        local bx, bz = WorldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU)
        lineStart = { bx = bx, bz = bz }
        return true
    end
    return false
end

local function GetBuildingList(dragStart, rx, rz, altMode)
    local results = {}
    local bx, bz = dragStart.bx, dragStart.bz
    local ex, ez = rx, rz
    local size = dragStart.size

    if altMode then
        local minX, maxX = math.min(bx, ex), math.max(bx, ex)
        local minZ, maxZ = math.min(bz, ez), math.max(bz, ez)

        for x = minX, maxX, size do
            for z = minZ, maxZ, size do
                results[#results + 1] = { x = x, z = z }
            end
        end
        return results
    end

    local dx = math.abs(ex - bx)
    local dz = math.abs(ez - bz)

    local sx = (ex >= bx) and size or -size
    local sz = (ez >= bz) and size or -size

    local x = bx
    local z = bz

    if dx > dz then
        local err = dx / 2
        while (sx > 0 and x <= ex) or (sx < 0 and x >= ex) do
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
        while (sz > 0 and z <= ez) or (sz < 0 and z >= ez) do
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

local function TraceRectangleBounds(startPos, endPos)
    local size = startPos.size or 1
    local TICK = size > 4 and 1 or 0.5
    local CORNER_TICK_LEN = TICK * 2

    local bx1, bz1 = startPos.bx, startPos.bz
    local bx2, bz2 = endPos.bx, endPos.bz

    -- Calculate actual footprint of the dragged shape
    local sx1 = bx1
    local sz1 = bz1
    local sx2 = bx2
    local sz2 = bz2

    -- Get the final bounding box including both the shape and the cursor
    local xMin = math.min(sx1, sx2, bx2)
    local xMax = math.max(sx1, sx2, bx2) + size
    local zMin = math.min(sz1, sz2, bz2)
    local zMax = math.max(sz1, sz2, bz2) + size

    -- Shrink bounds inward by 1 BU
    local x1 = xMin + 1
    local x2 = xMax - 1
    local z1 = zMin + 1
    local z2 = zMax - 1

    local lines = {}
    local function Add(x1, z1, x2, z2)
        table.insert(lines, { x1, z1, x2, z2 })
    end

    -- Corner ticks
    Add(x1, z1, x1 + CORNER_TICK_LEN, z1)
    Add(x1, z1, x1, z1 + CORNER_TICK_LEN)
    Add(x2, z1, x2 - CORNER_TICK_LEN, z1)
    Add(x2, z1, x2, z1 + CORNER_TICK_LEN)
    Add(x2, z2, x2 - CORNER_TICK_LEN, z2)
    Add(x2, z2, x2, z2 - CORNER_TICK_LEN)
    Add(x1, z2, x1 + CORNER_TICK_LEN, z2)
    Add(x1, z2, x1, z2 - CORNER_TICK_LEN)

    -- Horizontal ticks (top and bottom) → left-right ticks
    for x = x1 + size - 1, x2 - 1, size do
        Add(x - TICK, z1, x + TICK, z1) -- top edge
        Add(x - TICK, z2, x + TICK, z2) -- bottom edge
    end

    -- Vertical ticks (left and right) → up-down ticks
    for z = z1 + size - 1, z2 - 1, size do
        Add(x1, z - TICK, x1, z + TICK) -- left edge
        Add(x2, z - TICK, x2, z + TICK) -- right edge
    end

    return lines
end

function widget:MouseRelease(mx, my, button)
    if button == 1 then
        if myUI and myUI:MouseRelease(mx, my, button) then
            return true
        end

        if not dragging or not dragStart then
            return
        end

        local _, pos = Spring.TraceScreenRay(mx, my, true)
        if not pos then
            return
        end

        if dragging and dragStart then
            local bx, bz = WorldToBU(pos[1], pos[3])
            local size = dragStart.size

            if snapBuilding then
                bx = math.floor(bx / size) * size
                bz = math.floor(bz / size) * size
            end

            if ctrlMode and altMode then
                --RENDER STUFF WITH TRACED BOUNDS
                --local bounds = TraceRectangleBounds(dragStart, {bx = bx, bz = bz})
                --for _, line in ipairs(bounds) do
                --  AddLine(unpack(line))
                --end

                local linesToAdd = TraceRectangleBounds(dragStart, { bx = bx, bz = bz })
                local cmd = CreateCommand()
                for _, line in ipairs(linesToAdd) do
                    PushAddLineAction(cmd, currentLayout, unpack(line))
                end
                RunCommand(cmd)

            --Spring.Echo("Traced Bounds")
            else
                --RENDER STUFF WITH BUILDINGS
                --local list = GetBuildingList(dragStart, bx, bz, altMode)
                --for _, v in ipairs(list) do
                --  ToggleBuilding(v.x, v.z, size)
                --end

                -- TOGGLE BUILDINGS
                local cmd = CreateCommand()
                local list = GetBuildingList(dragStart, bx, bz, altMode)

                for _, v in ipairs(list) do
                    local found = false
                    local group = currentLayout.buildings[size]

                    for _, pos in ipairs(group) do
                        if pos[1] == v.x and pos[2] == v.z then
                            PushRemBuildingAction(cmd, currentLayout, v.x, v.z, size)
                            found = true
                            break
                        end
                    end

                    if not found then
                        PushAddBuildingAction(cmd, currentLayout, v.x, v.z, size)
                    end
                end
                RunCommand(cmd)
            end
        end
        dragging = false
        dragStart = nil
    elseif button == 3 and lineStart then
        local _, pos = Spring.TraceScreenRay(mx, my, true)
        if not pos then
            lineStart = nil
            return
        end
        local ex, ez = WorldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU)

        if altMode then
            local linesToRemoveIndices =
                GetIntersectingLineIndices(currentLayout, { lineStart.bx, lineStart.bz, ex, ez })

            local cmd = CreateCommand()
            for _, lineIndex in ipairs(linesToRemoveIndices) do
                local line = currentLayout.lines[lineIndex]
                PushRemLineAction(cmd, currentLayout, unpack(line))
            end
            RunCommand(cmd)
        else
            local cmd = CreateCommand()
            PushAddLineAction(cmd, currentLayout, lineStart.bx, lineStart.bz, ex, ez)
            RunCommand(cmd)
            --AddLine(lineStart.bx, lineStart.bz, ex, ez)
        end
        lineStart = nil
    end
end

function widget:MouseMove(x, y)
    if myUI then
        return myUI:MouseMove(x, y)
    end
end

function GetCameraSnappedAngle()
    local dirX, _, dirZ = Spring.GetCameraDirection()
    local camLen = math.sqrt(dirX * dirX + dirZ * dirZ)

    if camLen < 0.0001 then
        Spring.Echo("Camera facing straight down — direction is ambiguous")
        return 0
    end

    -- Normalize camera direction in XZ plane
    local forwardX = dirX / camLen
    local forwardZ = dirZ / camLen

    -- Snap to nearest integer step
    local tx = math.floor(forwardX + 0.5)
    local tz = math.floor(forwardZ + 0.5)

    -- Determine cardinal angle
    local angle
    if tx == 0 and tz > 0 then
        angle = 270 -- forward
    elseif tx > 0 and tz == 0 then
        angle = 180 -- right
    elseif tx == 0 and tz < 0 then
        angle = 90 -- backward
    elseif tx < 0 and tz == 0 then
        angle = 0 -- left
    else
        angle = 0 -- ambiguous or diagonal
    end

    return angle
end

-- Transforms input vector (dx, dz) based on camera, snaps to grid, and returns direction and angle
function GetSnappedCameraDirection(dx, dz)
    if dx == 0 and dz == 0 then
        return 0, 0, nil -- no input
    end

    local inputLen = math.sqrt(dx * dx + dz * dz)
    dx = dx / inputLen
    dz = dz / inputLen

    local dirX, _, dirZ = Spring.GetCameraDirection()
    local camLen = math.sqrt(dirX * dirX + dirZ * dirZ)
    if camLen < 0.0001 then
        Spring.Echo("Camera facing straight down — input transform is ambiguous")
        return 0, 0, nil
    end

    local forwardX = dirX / camLen
    local forwardZ = dirZ / camLen
    local rightX = -forwardZ
    local rightZ = forwardX

    local worldDX = dx * rightX + dz * forwardX
    local worldDZ = dx * rightZ + dz * forwardZ

    local tx = math.floor(worldDX + 0.5)
    local tz = math.floor(worldDZ + 0.5)

    return tx, tz
end

function widget:KeyPress(key)
    --a 97
    --s 115
    --w 119
    --d 100
    --ALT 308
    --up 273
    --down 274
    --left 276
    --right 275

    --z 122
    --a 97
    if key == 308 then -- ALT
        altMode = true
        return false
    end

    if key == 306 then
        ctrlMode = true
        return false
    end

    if key == 122 and ctrlMode then -- CTRL + Z
        Undo()
        return true
    end

    if key == 97 and ctrlMode then -- CTRL + A
        Redo()
        return true
    end

    --Spring.Echo("Key ".. tostring(key))
    if loadedData and loadedData.layout then
        if key == string.byte("r") then
            layoutRotation = (layoutRotation + 90) % 360
            ApplyRotationAndInversion(loadedData.layout, 90, false)
            Spring.Echo("[LayoutPlanner] Rotation:", layoutRotation)
            return true
        end
        if key == string.byte("i") then
            ApplyRotationAndInversion(loadedData.layout, 0, true)
            Spring.Echo("[LayoutPlanner] Layout Inverted")
            return true
        end
    end

    if allowTranslationByKeys and currentLayout then
        --translation in world space
        local dx, dz = 0, 0

        if key == 119 then
            dz = dz + 1
        end -- W
        if key == 115 then
            dz = dz - 1
        end -- S
        if key == 97 then
            dx = dx - 1
        end -- A
        if key == 100 then
            dx = dx + 1
        end -- D

        if dx ~= 0 or dz ~= 0 then
            -- d = input as input vector
            -- get camera basis vector in XZ plane
            -- transfrom "d" to camera space
            local tx, tz = GetSnappedCameraDirection(dx, dz)

            if tx ~= 0 or tz ~= 0 then
                local cmd = CreateCommand()
                PushTranslateAction(cmd, currentLayout, tx, tz)
                RunCommand(cmd)
            end
        end
    end
end

function widget:KeyRelease(key)
    if key == 308 then --ALT
        altMode = false
        return false --hmm, true seems to block the ALT key reach the game, so we can't rotate camera lol
    end
    if key == 306 then --CTRL
        ctrlMode = false
        return false
    end
end

local sizeIteratinOrder = {}
for size in pairs(currentLayout.buildings) do
    table.insert(sizeIteratinOrder, size)
end
table.sort(sizeIteratinOrder, function(a, b)
    return a > b
end) -- descending

function widget:DrawWorld()
    if drawingToGame then
        return
    end

    gl.DepthTest(true)

    if drawChunkGrid then
        local mx, mz = Spring.GetMouseState()
        local _, pos = Spring.TraceScreenRay(mx, mz, true)
        if pos then
            DrawChunkGrid(pos[1], pos[3])
        end
    end

    -- Draw layout
    -- Iterate in order
    for _, size in ipairs(sizeIteratinOrder) do
        local positions = currentLayout.buildings[size]
        for _, pos in ipairs(positions) do
            local bx, bz = pos[1], pos[2]
            local wx, wz = BUToWorld(bx, bz)
            local wy = Spring.GetGroundHeight(wx, wz)

            if differTypesByColor then
                for _, building in ipairs(buildingTypes) do
                    if building.size == size then
                        gl.Color(unpack(building.color))
                        break
                    end
                end
            else
                gl.Color(0, 1, 0, 0.3)
            end

            gl.BeginEnd(GL.QUADS, function()
                gl.Vertex(wx, wy + 5, wz)
                gl.Vertex(wx + BU_SIZE * size, wy + 5, wz)
                gl.Vertex(wx + BU_SIZE * size, wy + 5, wz + BU_SIZE * size)
                gl.Vertex(wx, wy + 5, wz + BU_SIZE * size)
            end)
        end
    end
    -- Render Lines
    gl.Color(0, 1, 0, 0.6)
    gl.LineWidth(3)
    gl.BeginEnd(GL.LINES, function()
        for _, line in ipairs(currentLayout.lines) do
            local x1, z1 = BUToWorld(line[1], line[2])
            local x2, z2 = BUToWorld(line[3], line[4])
            local y1 = Spring.GetGroundHeight(x1, z1)
            local y2 = Spring.GetGroundHeight(x2, z2)

            gl.Vertex(x1, y1 + 5, z1)
            gl.Vertex(x2, y2 + 5, z2)
        end
    end)

    -- Draw preview
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
        local bx, bz = WorldToBU(pos[1], pos[3])

        gl.Color(1, 1, 0, 0.4)

        if loadedData then
            for size, buildings in pairs(loadedData.layout.buildings) do
                for _, b in ipairs(buildings) do
                    local shiftX = b[1] - math.floor((loadedData.width + loadedData.minSize) / 2)
                    local shiftZ = b[2] - math.floor((loadedData.height + loadedData.minSize) / 2)

                    local pbx, pbz = math.floor(bx + shiftX), math.floor(bz + shiftZ)
                    local wx, wz = BUToWorld(pbx, pbz)
                    local wy = Spring.GetGroundHeight(wx, wz)

                    gl.BeginEnd(GL.QUADS, function()
                        gl.Vertex(wx, wy + 5, wz)
                        gl.Vertex(wx + BU_SIZE * size, wy + 5, wz)
                        gl.Vertex(wx + BU_SIZE * size, wy + 5, wz + BU_SIZE * size)
                        gl.Vertex(wx, wy + 5, wz + BU_SIZE * size)
                    end)
                end
            end

            -- Render layout lines
            gl.LineWidth(3)
            gl.BeginEnd(GL.LINES, function()
                for _, line in ipairs(loadedData.layout.lines) do
                    local shiftX1 = line[1]
                        - math.floor((loadedData.width + loadedData.minSize) / 2)
                    local shiftZ1 = line[2]
                        - math.floor((loadedData.height + loadedData.minSize) / 2)
                    local shiftX2 = line[3]
                        - math.floor((loadedData.width + loadedData.minSize) / 2)
                    local shiftZ2 = line[4]
                        - math.floor((loadedData.height + loadedData.minSize) / 2)

                    local pbx1, pbz1 = math.floor(bx + shiftX1), math.floor(bz + shiftZ1)
                    local pbx2, pbz2 = math.floor(bx + shiftX2), math.floor(bz + shiftZ2)

                    local wx1, wz1 = BUToWorld(pbx1, pbz1)
                    local wx2, wz2 = BUToWorld(pbx2, pbz2)

                    local wy1 = Spring.GetGroundHeight(wx1, wz1)
                    local wy2 = Spring.GetGroundHeight(wx2, wz2)

                    gl.Vertex(wx1, wy1 + 6, wz1)
                    gl.Vertex(wx2, wy2 + 6, wz2)
                end
            end)
        elseif drawingMode then
            if not lineStart then
                local list
                local size = dragStart and dragStart.size or buildingTypes[currentSizeIndex].size

                if snapBuilding then
                    bx = math.floor(bx / size) * size
                    bz = math.floor(bz / size) * size
                end
                if altMode and ctrlMode and dragStart then
                    gl.Color(1, 1, 0, 0.4)
                    local lines = TraceRectangleBounds(dragStart, { bx = bx, bz = bz })
                    for _, line in ipairs(lines) do
                        local x1, z1 = BUToWorld(line[1], line[2])
                        local x2, z2 = BUToWorld(line[3], line[4])

                        local y1 = Spring.GetGroundHeight(x1, z1)
                        local y2 = Spring.GetGroundHeight(x2, z2)
                        gl.BeginEnd(GL.LINES, function()
                            gl.Vertex(x1, y1 + 5, z1)
                            gl.Vertex(x2, y2 + 5, z2)
                        end)
                    end
                else
                    if dragStart then
                        list = GetBuildingList(dragStart, bx, bz, altMode)
                    else
                        list = { { x = bx, z = bz } }
                    end
                    if #list == 1 then
                        local lsx, lsz = BUToWorld(WorldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU))
                        local wy = Spring.GetGroundHeight(lsx, lsz)
                        gl.BeginEnd(GL.QUADS, function()
                            gl.Vertex(lsx - 2, wy + 5, lsz - 2)
                            gl.Vertex(lsx + 2, wy + 5, lsz - 2)
                            gl.Vertex(lsx + 2, wy + 5, lsz + 2)
                            gl.Vertex(lsx - 2, wy + 5, lsz + 2)
                        end)
                    end
                    for _, v in ipairs(list) do
                        local wx, wz = BUToWorld(v.x, v.z)
                        local wy = Spring.GetGroundHeight(wx, wz)

                        gl.BeginEnd(GL.QUADS, function()
                            gl.Vertex(wx, wy + 5, wz)
                            gl.Vertex(wx + BU_SIZE * size, wy + 5, wz)
                            gl.Vertex(wx + BU_SIZE * size, wy + 5, wz + BU_SIZE * size)
                            gl.Vertex(wx, wy + 5, wz + BU_SIZE * size)
                        end)
                    end
                end
            else
                if altMode then
                    gl.Color(1, 0.5, 0, 1)
                else
                    gl.Color(1, 1, 0, 1)
                end

                gl.LineWidth(3)
                local bx, bz = BUToWorld(lineStart.bx, lineStart.bz)
                local ex, ez = BUToWorld(WorldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU))

                local y1 = Spring.GetGroundHeight(bx, bz)
                local y2 = Spring.GetGroundHeight(ex, ez)

                gl.BeginEnd(GL.LINES, function()
                    gl.Vertex(bx, y1 + 5, bz)
                    gl.Vertex(ex, y2 + 5, ez)
                end)

                if altMode then
                    ex, ez = WorldToBU(pos[1] + HALF_BU, pos[3] + HALF_BU)
                    local indices = GetIntersectingLineIndices(
                        currentLayout,
                        { lineStart.bx, lineStart.bz, ex, ez }
                    )
                    gl.LineWidth(4)
                    gl.Color(0.7, 0.3, 1, 1)
                    --Spring.Echo("REM LINES ", tostring(#indices))
                    gl.BeginEnd(GL.LINES, function()
                        for _, idx in ipairs(indices) do
                            local line = currentLayout.lines[idx]
                            local x1, z1 = BUToWorld(line[1], line[2])
                            local x2, z2 = BUToWorld(line[3], line[4])
                            local y1 = Spring.GetGroundHeight(x1, z1)
                            local y2 = Spring.GetGroundHeight(x2, z2)

                            gl.Vertex(x1, y1 + 5, z1)
                            gl.Vertex(x2, y2 + 5, z2)
                        end
                    end)
                end
            end
        end
    end

    gl.Color(1, 1, 1, 1)
    gl.DepthTest(false)
end

function widget:Update(dt)
    if not renderingToGame then
        if myUI then
            currentToolTip = nil
            local mx, my = Spring.GetMouseState()
            myUI:Hover(mx, my)
        end
        return
    end
    timer = timer + dt
    if timer > 0.1 then
        for _ = 1, 10 do
            if #drawLineQueue == 0 then
                Spring.Echo("[LayoutPlanner] All lines rendered..")
                renderingToGame = false
                return
            end

            local data = table.remove(drawLineQueue, 1)
            Spring.MarkerAddLine(data.startX, data.y, data.startZ, data.endX, data.y, data.endZ)
        end
        timer = 0
    end
end

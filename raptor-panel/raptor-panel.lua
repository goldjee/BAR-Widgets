function widget:GetInfo()
	return {
		name = 'Raptor Panel',
		desc = 'Shows raptor and player statistics in a compact interface',
		author = 'Insider',
		date = '16.10.2025',
		layer = 0,
		enabled = true,
		version = 3,
	}
end

--------------------------------------------------------------------------------
-- Imports and Constants
--------------------------------------------------------------------------------
local Harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')
local HarmonyRaptor = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')
local modOptions = Spring.GetModOptions()
local nBosses = modOptions.raptor_queen_count or 1

-- Configuration
local CONFIG = {
	-- UI Dimensions
	PANEL_WIDTH = 380,
	PANEL_HEIGHT = 510,
	HEADER_HEIGHT = 30,
	STATUS_HEIGHT = 100,
	TAB_HEIGHT = 35,
	PADDING = 10,

	-- Font Sizes
	FONT_SIZE = 16,
	SMALL_FONT_SIZE = 14,

	-- UI Positioning
	PANEL_MARGIN_X = 20,
	PANEL_MARGIN_Y = 80,

	-- Threat Thresholds
	THREAT_HIGH = 1.7,
	THREAT_MED = 1.2,

	-- Update Frequency
	UPDATE_INTERVAL = 30, -- frames

	-- UI Layout
	ROW_SPACING = 8,
	LINE_SPACING = 5,
	MAX_BOSS_DISPLAY = 50,
	MAX_RESISTANCE_DISPLAY = 3,

	-- Tab Layout (Economy tab column positions)
	ECO_COL_PLAYER = 5,
	ECO_COL_MULT = 180,
	ECO_COL_SHARE = 250,
	ECO_COL_BAR = 290,

	-- Tab Layout (Damage tab column positions)
	DMG_COL_RANK = 5,
	DMG_COL_PLAYER = 50,
	DMG_COL_DAMAGE = 220,
	DMG_COL_RELATIVE = 310,

	-- Tab Layout (Boss tab column positions)
	BOSS_COL_UNIT = 10,
	BOSS_COL_RESIST = 220,
	BOSS_COL_DAMAGE = 290,
}

-- Consolidated color palette
local COLORS = {
	-- Text
	TEXT_PRIMARY = {1, 1, 1, 1},
	TEXT_DIM = {0.7, 0.7, 0.7, 1},
	TEXT_ACCENT = {1, 1, 0.5, 1},

	-- Status/Threat
	RED = {1, 0.3, 0.3, 1},
	ORANGE = {1, 0.8, 0.3, 1},
	GREEN = {0.3, 1, 0.3, 1},
	BLUE = {0.8, 0.8, 1, 1},

	-- Backgrounds
	BG_PANEL = {0.1, 0.1, 0.1, 0.85},
	BG_HEADER = {0.15, 0.15, 0.15, 0.9},
	BG_ACTIVE = {0.25, 0.35, 0.45, 0.9},
	BG_HIGHLIGHT = {0.3, 0.3, 0.5, 0.3},

	-- Borders
	BORDER = {1, 1, 1, 0.25},
}

-- Font
local font
local fontSize = CONFIG.FONT_SIZE
local smallFontSize = CONFIG.SMALL_FONT_SIZE

-- Panel state
local panelX, panelY
local uiScale = 1
local screenScale = 1
local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0
local currentTab = 1  -- 1: Economy, 2: Damage, 3: Queens
local vsx, vsy
local scaledWidth, scaledHeight
local initialScaleSet = false
local dynamicPanelHeight = CONFIG.PANEL_HEIGHT
local dynamicHeightCalculated = false

-- Cached scaled dimensions and layout positions
local scaled = {}
local layout = {}

-- Game data
local gameInfo = {}
local playerEcoData = {}
local bossData = {}
local teamIDs = {}
local raptorsTeamID
local playerEcoAttractionsRaw = {}

-- Performance caching
local textWidthCache = {}

-- Boss colors for health bars
local bossColors = {
	{0.709, 0.537, 0.000}, -- yellow
	{0.796, 0.294, 0.086}, -- orange
	{0.862, 0.196, 0.184}, -- red
	{0.827, 0.211, 0.509}, -- magenta
	{0.423, 0.443, 0.768}, -- violet
	{0.149, 0.545, 0.823}, -- blue
	{0.164, 0.631, 0.596}, -- cyan
	{0.521, 0.600, 0.000}, -- green
}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------
local function updateUIScale()
	-- Calculate screen scale based on resolution
	screenScale = (0.75 + (vsx * vsy / 10000000))
	uiScale = screenScale

	-- Update scaled dimensions
	scaledWidth = CONFIG.PANEL_WIDTH * uiScale
	scaledHeight = dynamicPanelHeight * uiScale

	-- Update font sizes
	fontSize = CONFIG.FONT_SIZE * uiScale
	smallFontSize = CONFIG.SMALL_FONT_SIZE * uiScale

	-- Cache all scaled dimensions
	scaled.headerHeight = CONFIG.HEADER_HEIGHT * uiScale
	scaled.statusHeight = CONFIG.STATUS_HEIGHT * uiScale
	scaled.tabHeight = CONFIG.TAB_HEIGHT * uiScale
	scaled.padding = CONFIG.PADDING * uiScale
	scaled.rowSpacing = CONFIG.ROW_SPACING * uiScale
	scaled.lineSpacing = CONFIG.LINE_SPACING * uiScale
	scaled.smallFontSize = smallFontSize
	scaled.fontSize = fontSize
end

local function updateLayout()
	layout.headerY = panelY + scaledHeight - scaled.headerHeight
	layout.statusY = layout.headerY - scaled.statusHeight
	layout.tabY = layout.statusY - scaled.tabHeight
	layout.contentY = panelY
	layout.contentStartY = layout.tabY - scaled.padding - fontSize
end

local function FormatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	else
		return tostring(math.floor(num))
	end
end

local function getRowHeight()
	return smallFontSize + (4 * uiScale) + scaled.rowSpacing
end

local function getThreatColor(multiplier)
	if multiplier > CONFIG.THREAT_HIGH then
		return COLORS.RED
	elseif multiplier > CONFIG.THREAT_MED then
		return COLORS.ORANGE
	else
		return COLORS.GREEN
	end
end

local function calculateRequiredPanelHeight()
	-- Count non-raptor/scavenger teams
	local playerCount = 0
	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local playerName = Harmony.getPlayerName(teamID)
		if playerName and playerName ~= '' and not (playerName:find('Raptors') or playerName:find('Scavengers')) then
			playerCount = playerCount + 1
		end
	end

	-- Calculate required content height
	local rowHeight = CONFIG.SMALL_FONT_SIZE + 4 + CONFIG.ROW_SPACING
	local contentHeight = 40 + rowHeight * playerCount

	-- Calculate total panel height
	local requiredHeight = CONFIG.HEADER_HEIGHT + CONFIG.STATUS_HEIGHT + CONFIG.TAB_HEIGHT + (CONFIG.PADDING * 4) + contentHeight

	-- Use at least the minimum configured height
	return math.max(CONFIG.PANEL_HEIGHT, requiredHeight)
end

-- Formats time in seconds to human-readable format ("12 minutes", "5m 30s", "45 seconds")
-- Replaces removed HarmonyRaptor.formatGraceTime from v1
local function formatGraceTime(seconds)
	if seconds <= 0 then
		return "0 seconds"
	end

	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)

	if minutes > 0 and secs > 0 then
		return minutes .. "m " .. secs .. "s"
	elseif minutes > 0 then
		return minutes .. " minute" .. (minutes > 1 and "s" or "")
	else
		return secs .. " seconds"
	end
end

-- Returns anger gain components from gameInfo table
-- Replaces removed HarmonyRaptor.getAngerComponents from v1
local function getAngerComponents()
	local base = gameInfo.angerGainBase or 0
	local eco = gameInfo.angerGainEco or 0
	local aggression = gameInfo.angerGainAggression or 0
	return {
		base = base,
		eco = eco,
		aggression = aggression,
		total = base + eco + aggression
	}
end

--------------------------------------------------------------------------------
-- Data Update Functions
--------------------------------------------------------------------------------
local function UpdateGameInfo()
	HarmonyRaptor.updateGameInfo()
	gameInfo = HarmonyRaptor.getGameInfo()
end

local function UpdatePlayerEcoData()
	local myTeamId = Spring.GetMyTeamID()
	playerEcoData = {}
	local sum = 0

	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local playerName = Harmony.getPlayerName(teamID)

		if playerName and playerName ~= '' and not (playerName:find('Raptors') or playerName:find('Scavengers')) then
			local ecoValue = playerEcoAttractionsRaw[teamID] or 0
			ecoValue = math.max(0, ecoValue)
			sum = sum + ecoValue

			table.insert(playerEcoData, {
				name = playerName,
				value = ecoValue,
				teamID = teamID,
				isMe = (myTeamId == teamID)
			})
		end
	end

	-- Calculate percentages and multipliers
	if sum > 0 then
		for _, data in ipairs(playerEcoData) do
			data.percentage = (data.value / sum) * 100
			data.multiplier = (#playerEcoData * data.value) / sum
		end
	else
		-- Set defaults when no eco value exists yet
		for _, data in ipairs(playerEcoData) do
			data.percentage = 0
			data.multiplier = 0
		end
	end

	-- Sort by value descending
	table.sort(playerEcoData, function(a, b) return a.value > b.value end)
end

local function UpdateBossData()
	bossData = HarmonyRaptor.getBossInfo()

	-- Assign colors to boss healths
	for i, health in ipairs(bossData.healths) do
		health.color = bossColors[((i - 1) % #bossColors) + 1]
	end
end

--------------------------------------------------------------------------------
-- Drawing Functions
--------------------------------------------------------------------------------
local function DrawRect(x, y, width, height, color)
	gl.Color(color)
	gl.Rect(x, y, x + width, y + height)
end

local function DrawText(text, x, y, size, color, align)
	size = size or fontSize
	color = color or COLORS.TEXT_PRIMARY
	align = align or ""

	font:Begin()
	font:SetTextColor(color)
	font:Print(text, x, y, size, align)
	font:End()
end

local function DrawProgressBar(x, y, width, height, percentage, color)
	-- Background
	DrawRect(x, y, width, height, {0.2, 0.2, 0.2, 0.8})

	-- Progress
	local fillWidth = (width - 2) * (percentage / 100)
	if fillWidth > 0 then
		DrawRect(x + 1, y + 1, fillWidth, height - 2, color)
	end

	-- Border
	gl.Color(COLORS.BORDER)
	gl.LineWidth(1)
	gl.Shape(GL.LINE_LOOP, {
		{v = {x, y}},
		{v = {x + width, y}},
		{v = {x + width, y + height}},
		{v = {x, y + height}}
	})
end

local function drawSectionHeader(x, y, title)
	DrawText(title, x, y, fontSize, COLORS.TEXT_ACCENT)
	return y - scaled.padding
end

local function drawTableHeader(x, y, columns)
	for _, col in ipairs(columns) do
		DrawText(col.label, x + (col.x * uiScale), y, smallFontSize, COLORS.TEXT_DIM)
	end
	y = y - scaled.lineSpacing

	-- Draw separator line
	gl.Color(COLORS.BORDER)
	gl.LineWidth(1)
	gl.Shape(GL.LINES, {
		{v = {x, y}},
		{v = {x + scaledWidth - scaled.padding * 2, y}}
	})

	return y - scaled.lineSpacing
end

local function drawHeader()
	local x = panelX
	local y = layout.headerY

	DrawRect(x, y, scaledWidth, scaled.headerHeight, COLORS.BG_HEADER)

	-- Title
	local title = "RAPTOR PANEL"
	DrawText(title, x + scaled.padding, y + (scaled.headerHeight - fontSize) / 2, fontSize, COLORS.TEXT_PRIMARY)

	-- Difficulty
	local difficulty = modOptions.raptor_difficulty or "unknown"
	local endless = modOptions.raptor_endless and " (Endless)" or ""
	local diffText = difficulty:upper() .. endless
	local diffX = x + scaledWidth - scaled.padding
	DrawText(diffText, diffX, y + (scaled.headerHeight - smallFontSize) / 2, smallFontSize, COLORS.BLUE, "ro")
end

local function drawStatusPanel()
	local x = panelX
	local y = layout.statusY

	DrawRect(x, y, scaledWidth, scaled.statusHeight, COLORS.BG_HEADER)

	local stage = gameInfo.stage  -- v2: Read from gameInfo table
	local textY = y + scaled.statusHeight - scaled.padding - fontSize

	if gameInfo.stage == "grace" then  -- v2: Check stage directly
		-- Grace Period
		local remaining = gameInfo.gracePeriodRemaining  -- v2: Read from gameInfo table
		local labelText = "Grace Period Remaining:"
		DrawText(labelText, x + scaled.padding, textY, fontSize, COLORS.GREEN)

		-- Align timer on the same line, right side
		local timerText = formatGraceTime(remaining)  -- v2: Use local function
		local timerX = x + scaledWidth - scaled.padding
		DrawText(timerText, timerX, textY, fontSize, COLORS.TEXT_PRIMARY, "ro")
		textY = textY - fontSize - scaled.lineSpacing

	elseif stage == "main" then
		-- Queen Anger Phase
		local anger = gameInfo.queenHatchProgress  -- v2: Read from gameInfo table
		local techAnger = gameInfo.angerTech  -- v2: Read from gameInfo table
		DrawText(string.format("Queen Anger: %d%% (%d%% Evolution)", anger, techAnger), x + scaled.padding, textY, fontSize, COLORS.ORANGE)
		textY = textY - fontSize - scaled.lineSpacing

		-- ETA
		local eta = HarmonyRaptor.getQueenETA()  -- v2: Still a function (unchanged)
		DrawText("ETA: " .. formatGraceTime(eta), x + scaled.padding, textY, fontSize, COLORS.TEXT_PRIMARY)  -- v2: Use local function
		textY = textY - fontSize - scaled.lineSpacing

		-- Anger Rate Breakdown
		local components = getAngerComponents()  -- v2: Use local function
		DrawText(string.format("Rate: %.2f/s", components.total), x + scaled.padding, textY, smallFontSize, COLORS.TEXT_DIM)
		textY = textY - smallFontSize - scaled.lineSpacing

		-- Single format string for better performance
		local breakdownText = string.format("Base: %.2f/s  Eco: %.2f/s  Aggro: %.2f/s",
			components.base, components.eco, components.aggression)
		DrawText(breakdownText, x + scaled.padding, textY, smallFontSize, COLORS.TEXT_DIM)

	elseif stage == "boss" then
		-- Boss Phase
		DrawText("QUEEN ACTIVE", x + scaled.padding, textY, fontSize * 1.2, COLORS.RED)
		textY = textY - (fontSize * 1.2) - scaled.lineSpacing

		local queenHealth = gameInfo.queenHealth  -- v2: Read from gameInfo table
		local queensKilled = gameInfo.queenCountKilled  -- v2: Read from gameInfo table (renamed field)
		local statusString = string.format("Total health: %d%%", queenHealth)
		if queensKilled and nBosses > 1 then
			statusString = statusString .. string.format(", Killed: %d/%d", queensKilled, nBosses)
		end

		DrawText(statusString, x + scaled.padding, textY, fontSize, COLORS.TEXT_PRIMARY)
		textY = textY - scaled.lineSpacing
		DrawProgressBar(x + scaled.padding, textY - (20 * uiScale), scaledWidth - scaled.padding * 2, 18 * uiScale, queenHealth, COLORS.RED)
		textY = textY - (25 * uiScale)
	end
end

local function drawTabs()
	local x = panelX
	local y = layout.tabY

	local tabWidth = scaledWidth / 3
	local tabs = {"ECONOMY", "DAMAGE", "QUEENS"}

	for i, tabName in ipairs(tabs) do
		local tabX = x + (i - 1) * tabWidth
		local color = (i == currentTab) and COLORS.BG_ACTIVE or COLORS.BG_HEADER

		DrawRect(tabX, y, tabWidth, scaled.tabHeight, color)

		-- Tab border
		gl.Color(COLORS.BORDER)
		gl.LineWidth(1)
		gl.Shape(GL.LINE_LOOP, {
			{v = {tabX, y}},
			{v = {tabX + tabWidth, y}},
			{v = {tabX + tabWidth, y + scaled.tabHeight}},
			{v = {tabX, y + scaled.tabHeight}}
		})

		DrawText(tabName, tabX + tabWidth / 2, y + scaled.tabHeight / 2, fontSize, COLORS.TEXT_PRIMARY, "cvo")
	end
end

local function drawEconomyTab()
	local x = panelX + scaled.padding
	local y = layout.contentStartY

	-- Header
	y = drawSectionHeader(x, y, "Player Eco Attractions")

	if #playerEcoData == 0 then
		y = y - fontSize - scaled.padding
		DrawText("No economy data yet", x, y, smallFontSize, COLORS.TEXT_DIM)
	else
		-- Table header
		y = y - smallFontSize
		y = drawTableHeader(x, y, {
			{label = "Player", x = CONFIG.ECO_COL_PLAYER},
			{label = "Mult", x = CONFIG.ECO_COL_MULT},
			{label = "Share", x = CONFIG.ECO_COL_SHARE}
		})

		-- Rows
		local tabContentHeight = (dynamicPanelHeight - CONFIG.HEADER_HEIGHT - CONFIG.STATUS_HEIGHT - CONFIG.TAB_HEIGHT - (CONFIG.PADDING * 4)) * uiScale
		local rowTotalHeight = getRowHeight() - scaled.rowSpacing
		local rowHeight = getRowHeight()
		local maxRows = math.floor((tabContentHeight - (40 * uiScale)) / rowHeight)

		for i, data in ipairs(playerEcoData) do
			if i > maxRows then break end

			local color = getThreatColor(data.multiplier)

			-- Position row
			y = y - rowTotalHeight
			local textY = y + (rowTotalHeight - smallFontSize) / 2

			-- Background highlight for current player
			if data.isMe then
				DrawRect(x, y, scaledWidth - scaled.padding * 2, rowTotalHeight, COLORS.BG_HIGHLIGHT)
			end

			-- Player name
			local namePrefix = data.isMe and "> " or "  "
			DrawText(namePrefix .. data.name, x + (CONFIG.ECO_COL_PLAYER * uiScale), textY, smallFontSize, color)

			-- Multiplier
			DrawText(string.format("%.1fX", data.multiplier), x + (CONFIG.ECO_COL_MULT * uiScale), textY, smallFontSize, color)

			-- Percentage
			DrawText(string.format("%.0f%%", data.percentage), x + (CONFIG.ECO_COL_SHARE * uiScale), textY, smallFontSize, color)

			-- Progress bar
			local barX = x + (CONFIG.ECO_COL_BAR * uiScale)
			local barWidth = scaledWidth - scaled.padding * 2 - (CONFIG.ECO_COL_BAR * uiScale)
			DrawProgressBar(barX, y, barWidth, rowTotalHeight, data.percentage, color)

			y = y - scaled.rowSpacing
		end
	end
end

local function drawDamageTab()
	local x = panelX + scaled.padding
	local y = layout.contentStartY

	-- Header
	y = drawSectionHeader(x, y, "Player Damage to Queens")

	if #bossData.playerDamages == 0 then
		y = y - fontSize - scaled.padding
		DrawText("No damage data yet", x, y, smallFontSize, COLORS.TEXT_DIM)
	else
		-- Table header
		y = y - smallFontSize
		y = drawTableHeader(x, y, {
			{label = "Rank", x = CONFIG.DMG_COL_RANK},
			{label = "Player", x = CONFIG.DMG_COL_PLAYER},
			{label = "Damage", x = CONFIG.DMG_COL_DAMAGE},
			{label = "Rel", x = CONFIG.DMG_COL_RELATIVE}
		})

		-- Rows
		local medals = {"#1", "#2", "#3"}
		local tabContentHeight = (dynamicPanelHeight - CONFIG.HEADER_HEIGHT - CONFIG.STATUS_HEIGHT - CONFIG.TAB_HEIGHT - (CONFIG.PADDING * 4)) * uiScale
		local rowTotalHeight = getRowHeight() - scaled.rowSpacing
		local rowHeight = getRowHeight()
		local maxRows = math.floor((tabContentHeight - (40 * uiScale)) / rowHeight)

		for i, data in ipairs(bossData.playerDamages) do
			if i > maxRows then break end

			-- Position row
			y = y - rowTotalHeight
			local textY = y + (rowTotalHeight - smallFontSize) / 2

			-- Medal or rank number
			local rankText = medals[i] or ("#" .. tostring(i))
			DrawText(rankText, x + (CONFIG.DMG_COL_RANK * uiScale), textY, smallFontSize, COLORS.TEXT_PRIMARY)

			-- Player name
			DrawText(data.name, x + (CONFIG.DMG_COL_PLAYER * uiScale), textY, smallFontSize, COLORS.TEXT_PRIMARY)

			-- Damage
			DrawText(FormatNumber(data.damage), x + (CONFIG.DMG_COL_DAMAGE * uiScale), textY, smallFontSize, COLORS.BLUE)

			-- Relative
			DrawText(string.format("%.1fX", data.relative), x + (CONFIG.DMG_COL_RELATIVE * uiScale), textY, smallFontSize, COLORS.BLUE)

			y = y - scaled.rowSpacing
		end
	end
end

local function drawBossTab()
	local x = panelX + scaled.padding
	local y = layout.contentStartY

	-- Header
	y = drawSectionHeader(x, y, "Queen Health Status")

	if #bossData.healths == 0 and #bossData.resistances == 0 then
		y = y - fontSize - scaled.padding
		DrawText("No boss data yet", x, y, smallFontSize, COLORS.TEXT_DIM)
	else
		-- Boss Health Status (Horizontal Flow)
		if #bossData.healths > 0 then
			-- Display up to configured max bosses in horizontal flow
			local maxBosses = math.min(CONFIG.MAX_BOSS_DISPLAY, #bossData.healths)
			local rowX = x + (CONFIG.ECO_COL_PLAYER * uiScale)
			local maxRowWidth = scaledWidth - scaled.padding * 2 - (CONFIG.ECO_COL_PLAYER * uiScale)
			local lineHeight = smallFontSize + (6 * uiScale)

			y = y - smallFontSize

			-- Draw boss health percentages with wrapping
			font:Begin()
			for i = 1, maxBosses do
				local health = bossData.healths[i]
				local healthText = string.format("%.0f%%", health.percentage)
				local textWidth = font:GetTextWidth(healthText) * smallFontSize
				local itemWidth = textWidth + scaled.lineSpacing

				-- Check if we need to wrap to next line
				if rowX + itemWidth > x + maxRowWidth and rowX > x + (CONFIG.ECO_COL_PLAYER * uiScale) then
					y = y - lineHeight
					rowX = x + (CONFIG.ECO_COL_PLAYER * uiScale)
				end

				-- Draw the health percentage with color
				if health.color then
					font:SetTextColor(health.color[1], health.color[2], health.color[3], 1)
				else
					font:SetTextColor(1, 1, 1, 1)
				end
				font:Print(healthText, rowX, y, smallFontSize, "o")

				rowX = rowX + itemWidth
			end
			font:SetTextColor(1, 1, 1, 1) -- Reset to default color
			font:End()

			y = y - (lineHeight - smallFontSize) - (scaled.padding * 2)
		end

		-- Resistances
		if #bossData.resistances > 0 then
			DrawText(string.format("Resistances (Top %d)", CONFIG.MAX_RESISTANCE_DISPLAY), x, y, fontSize, COLORS.TEXT_ACCENT)
			y = y - scaled.padding

			-- Table header
			y = y - smallFontSize
			y = drawTableHeader(x, y, {
				{label = "Unit", x = CONFIG.BOSS_COL_UNIT},
				{label = "Resist", x = CONFIG.BOSS_COL_RESIST},
				{label = "Damage", x = CONFIG.BOSS_COL_DAMAGE}
			})

			-- Resistance rows
			local rowTotalHeight = smallFontSize + (4 * uiScale)
			for i, resistance in ipairs(bossData.resistances) do
				if i > CONFIG.MAX_RESISTANCE_DISPLAY then break end

				-- Position row
				y = y - rowTotalHeight
				local textY = y + (rowTotalHeight - smallFontSize) / 2

				DrawText(resistance.name, x + (CONFIG.BOSS_COL_UNIT * uiScale), textY, smallFontSize, COLORS.TEXT_PRIMARY)
				DrawText(string.format("%.0f%%", resistance.percent * 100), x + (CONFIG.BOSS_COL_RESIST * uiScale), textY, smallFontSize, COLORS.RED)
				DrawText(FormatNumber(resistance.damage), x + (CONFIG.BOSS_COL_DAMAGE * uiScale), textY, smallFontSize, COLORS.TEXT_DIM)

				y = y - scaled.rowSpacing
			end
		end
	end
end

local function drawTabContent()
	local x = panelX
	local y = layout.contentY
	local contentHeight = scaledHeight - scaled.headerHeight - scaled.statusHeight - scaled.tabHeight

	-- Content background
	DrawRect(x, y, scaledWidth, contentHeight, COLORS.BG_PANEL)

	if currentTab == 1 then
		drawEconomyTab()
	elseif currentTab == 2 then
		drawDamageTab()
	elseif currentTab == 3 then
		drawBossTab()
	end
end

--------------------------------------------------------------------------------
-- Widget Callbacks
--------------------------------------------------------------------------------
function widget:Initialize()
	if not Spring.Utilities.Gametype.IsRaptors() then  -- v2: Direct Spring API call
		widgetHandler:RemoveWidget()
        return
	end

	vsx, vsy = Spring.GetViewGeometry()
	updateUIScale()

	panelX = vsx - scaledWidth - (CONFIG.PANEL_MARGIN_X * uiScale)
	panelY = vsy - scaledHeight - (CONFIG.PANEL_MARGIN_Y * uiScale)
	updateLayout()

	-- Get font with error handling
	if WG['fonts'] and WG['fonts'].getFont then
		font = WG['fonts'].getFont()
	else
		Spring.Echo("Raptor Panel: Warning - Font system not available")
		widgetHandler:RemoveWidget()
		return
	end

	-- Initialize team data
	raptorsTeamID = HarmonyRaptor.getRaptorsTeamID()
	local playerTeams = HarmonyRaptor.getPlayerTeams()

	teamIDs = Spring.GetTeamList()

	for i = 1, #playerTeams do
		playerEcoAttractionsRaw[playerTeams[i]] = 0
	end

	-- Initialize eco value cache
	HarmonyRaptor.initEcoValueCache()

	-- Register existing units
	local allUnits = Spring.GetAllUnits()
	for i = 1, #allUnits do
		local unitID = allUnits[i]
		local unitDefID = Spring.GetUnitDefID(unitID)
		local unitTeamID = Spring.GetUnitTeam(unitID)
		if unitTeamID ~= raptorsTeamID then
			HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
		end
	end

	UpdateGameInfo()
	UpdatePlayerEcoData()
	UpdateBossData()
end

function widget:Shutdown()
	-- Cleanup
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	updateUIScale()
	initialScaleSet = true

	-- Keep panel in view
	panelX = math.min(panelX, vsx - scaledWidth)
	panelY = math.min(panelY, vsy - scaledHeight)
	panelX = math.max(0, panelX)
	panelY = math.max(0, panelY)

	updateLayout()
end

function widget:DrawScreen()
	if not font then return end

	-- Calculate dynamic panel height on first draw
	if not dynamicHeightCalculated then
		dynamicPanelHeight = calculateRequiredPanelHeight()
		updateUIScale()
		panelX = vsx - scaledWidth - (CONFIG.PANEL_MARGIN_X * uiScale)
		panelY = vsy - scaledHeight - (CONFIG.PANEL_MARGIN_Y * uiScale)
		updateLayout()
		dynamicHeightCalculated = true
	end

	-- Ensure UI scale is properly calculated on first draw
	if not initialScaleSet then
		vsx, vsy = Spring.GetViewGeometry()
		updateUIScale()
		panelX = vsx - scaledWidth - (CONFIG.PANEL_MARGIN_X * uiScale)
		panelY = vsy - scaledHeight - (CONFIG.PANEL_MARGIN_Y * uiScale)
		updateLayout()
		initialScaleSet = true
	end

	gl.PushMatrix()

	-- Use pcall to ensure PopMatrix is always called
	local success, err = pcall(function()
		drawTabContent()
		drawTabs()
		drawStatusPanel()
		drawHeader()
	end)

	gl.PopMatrix()

	-- Report errors after cleaning up
	if not success then
		Spring.Echo("Raptor Panel draw error: " .. tostring(err))
	end
end

function widget:MousePress(x, y, button)
	-- Check if clicking on tabs
	local tabY = layout.tabY
	if x >= panelX and x <= panelX + scaledWidth and y >= tabY and y <= tabY + scaled.tabHeight then
		local tabWidth = scaledWidth / 3
		local tabIndex = math.floor((x - panelX) / tabWidth) + 1
		if tabIndex >= 1 and tabIndex <= 3 then
			currentTab = tabIndex
			return true
		end
	end

	-- Check if clicking on header for dragging
	local headerY = layout.headerY
	if x >= panelX and x <= panelX + scaledWidth and y >= headerY and y <= headerY + scaled.headerHeight then
		isDragging = true
		dragOffsetX = x - panelX
		dragOffsetY = y - panelY
		return true
	end

	return false
end

function widget:MouseRelease(x, y, button)
	isDragging = false
	return false
end

function widget:MouseMove(x, y, dx, dy)
	if isDragging then
		panelX = x - dragOffsetX
		panelY = y - dragOffsetY

		-- Keep panel in bounds
		panelX = math.max(0, math.min(panelX, vsx - scaledWidth))
		panelY = math.max(0, math.min(panelY, vsy - scaledHeight))

		updateLayout()

		return true
	end
	return false
end

function widget:GameFrame(n)
	if n % CONFIG.UPDATE_INTERVAL == 0 then
		UpdateGameInfo()
		UpdatePlayerEcoData()
		UpdateBossData()
	end
end

function widget:UnitCreated(unitID, unitDefID, unitTeamID)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, true)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, oldTeam, false)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, false)
end

function widget:GetInfo()
	return {
		name = 'Raptor Stats Panel',
		desc = 'Shows raptor and player statistics in a compact interface',
		author = 'Insider',
		date = '16.10.2025',
		layer = 0,
		enabled = true,
		version = 2,
	}
end

--------------------------------------------------------------------------------
-- Imports and Constants
--------------------------------------------------------------------------------
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

	-- Colors
	COLOR_BG = {0.1, 0.1, 0.1, 0.85},
	COLOR_HEADER = {0.15, 0.15, 0.15, 0.9},
	COLOR_STATUS = {0.12, 0.12, 0.12, 0.9},
	COLOR_TAB_INACTIVE = {0.2, 0.2, 0.2, 0.9},
	COLOR_TAB_ACTIVE = {0.25, 0.35, 0.45, 0.9},
	COLOR_TEXT = {1, 1, 1, 1},
	COLOR_DANGER_HIGH = {1, 0.3, 0.3, 1},
	COLOR_DANGER_MED = {1, 0.8, 0.3, 1},
	COLOR_DANGER_LOW = {0.3, 1, 0.3, 1},
	COLOR_BOSS_HEALTH = {0.8, 0.2, 0.2, 1},
	COLOR_GRACE = {0.3, 1, 0.3, 1},
	COLOR_ANGER = {1, 0.8, 0.3, 1},
	COLOR_DIFFICULTY = {0.8, 0.8, 1, 1},
	COLOR_SUBTITLE = {0.7, 0.7, 0.7, 1},
	COLOR_HEADER_TEXT = {1, 1, 0.5, 1},
	COLOR_DAMAGE_VALUE = {0.8, 0.8, 1, 1},
	COLOR_DAMAGE_RELATIVE = {0.7, 0.9, 1, 1},
	COLOR_RESISTANCE = {1, 0.5, 0.5, 1},
	COLOR_MUTED = {0.5, 0.5, 0.5, 1},
	COLOR_BORDER = {1, 1, 1, 0.3},
	COLOR_LINE = {1, 1, 1, 0.2},
	COLOR_HIGHLIGHT = {0.3, 0.3, 0.5, 0.3},
	COLOR_PROGRESS_BG = {0.2, 0.2, 0.2, 0.8},

	-- Threat Thresholds
	THREAT_HIGH = 1.7,
	THREAT_MED = 1.2,

	-- Update Frequency
	UPDATE_INTERVAL = 30, -- frames

	-- UI Layout
	ROW_SPACING = 8,
	LINE_SPACING = 5,
	SECTION_SPACING = 10,
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

-- Derived constants
local TAB_CONTENT_HEIGHT = CONFIG.PANEL_HEIGHT - CONFIG.HEADER_HEIGHT - CONFIG.STATUS_HEIGHT - CONFIG.TAB_HEIGHT - (CONFIG.PADDING * 4)

-- Legacy color constants for backward compatibility
local COLOR_BG = CONFIG.COLOR_BG
local COLOR_HEADER = CONFIG.COLOR_HEADER
local COLOR_STATUS = CONFIG.COLOR_STATUS
local COLOR_TAB_INACTIVE = CONFIG.COLOR_TAB_INACTIVE
local COLOR_TAB_ACTIVE = CONFIG.COLOR_TAB_ACTIVE
local COLOR_TEXT = CONFIG.COLOR_TEXT
local COLOR_DANGER_HIGH = CONFIG.COLOR_DANGER_HIGH
local COLOR_DANGER_MED = CONFIG.COLOR_DANGER_MED
local COLOR_DANGER_LOW = CONFIG.COLOR_DANGER_LOW
local COLOR_BOSS_HEALTH = CONFIG.COLOR_BOSS_HEALTH

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
local initialScaleSet = false  -- Track if UI scale has been properly initialized

-- Game data
local gameInfo = {}
local playerEcoData = {}
local playerDamageData = {}
local bossData = {}
local teamIDs = {}
local raptorsTeamID
local cachedPlayerNames = {}

-- Performance caching
local textWidthCache = {}
local scaledDimensionsCache = {}

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

-- Eco value calculation
local isObject = {}
for udefID, def in ipairs(UnitDefs) do
	if def.modCategories['object'] or def.customParams.objectify then
		isObject[udefID] = true
	end
end

local function EcoValueDef(unitDef)
	if (unitDef.canMove and not (unitDef.customParams and unitDef.customParams.iscommander)) or isObject[unitDef.name] then
		return 0
	end

	local ecoValue = 1
	if unitDef.energyMake then
		ecoValue = ecoValue + unitDef.energyMake
	end
	if unitDef.energyUpkeep and unitDef.energyUpkeep < 0 then
		ecoValue = ecoValue - unitDef.energyUpkeep
	end
	if unitDef.windGenerator then
		ecoValue = ecoValue + unitDef.windGenerator * 0.75
	end
	if unitDef.tidalGenerator then
		ecoValue = ecoValue + unitDef.tidalGenerator * 15
	end
	if unitDef.extractsMetal and unitDef.extractsMetal > 0 then
		ecoValue = ecoValue + 200
	end

	if unitDef.customParams then
		if unitDef.customParams.energyconv_capacity then
			ecoValue = ecoValue + tonumber(unitDef.customParams.energyconv_capacity) / 2
		end
		if unitDef.customParams.decoyfor == 'armfus' then
			ecoValue = ecoValue + 1000
		end
		if unitDef.customParams.techlevel and tonumber(unitDef.customParams.techlevel) > 1 then
			ecoValue = ecoValue * tonumber(unitDef.customParams.techlevel) * 2
		end
		if unitDef.customParams.unitgroup == 'antinuke' or unitDef.customParams.unitgroup == 'nuke' then
			ecoValue = 1000
		end
	end

	return ecoValue
end

local defIDsEcoValues = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	local ecoValue = EcoValueDef(unitDef) or 0
	if ecoValue > 0 then
		defIDsEcoValues[unitDefID] = ecoValue
	end
end

local playerEcoAttractionsRaw = {}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------
local function updateUIScale()
	-- Calculate screen scale based on resolution
	screenScale = (0.75 + (vsx * vsy / 10000000))

	-- Apply screen scale to get final UI scale
	uiScale = screenScale

	-- Update scaled dimensions
	scaledWidth = CONFIG.PANEL_WIDTH * uiScale
	scaledHeight = CONFIG.PANEL_HEIGHT * uiScale

	-- Update font sizes (use base config values, not accumulated)
	fontSize = CONFIG.FONT_SIZE * uiScale
	smallFontSize = CONFIG.SMALL_FONT_SIZE * uiScale
end

local function getPlayerName(teamID)
	-- Return cached name if available
	if cachedPlayerNames[teamID] then
		return cachedPlayerNames[teamID]
	end

	local playerName = ''
	local playerList = Spring.GetPlayerList(teamID)

	if playerList and #playerList > 0 then
		if #playerList == 1 then
			playerName = select(1, Spring.GetPlayerInfo(playerList[1]))
		else
			-- Multiple players on same team
			local names = {}
			for _, player in ipairs(playerList) do
				if player then
					local name = select(1, Spring.GetPlayerInfo(player))
					if name then
						names[#names + 1] = name
					end
				end
			end
			playerName = table.concat(names, ' & ')
		end
	else
		-- Try AI name
		_, playerName = Spring.GetAIInfo(teamID)
	end

	-- Cache the name
	if playerName and playerName ~= '' then
		cachedPlayerNames[teamID] = playerName
	end

	return playerName or ''
end

-- Use raptor_harmony's time formatter for consistency
local function FormatTime(seconds)
	return HarmonyRaptor.formatGraceTime(seconds)
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

--------------------------------------------------------------------------------
-- Data Update Functions
--------------------------------------------------------------------------------
local function UpdateGameInfo()
	gameInfo = HarmonyRaptor.getGameInfo()
end

local function UpdatePlayerEcoData()
	local myTeamId = Spring.GetMyTeamID()
	playerEcoData = {}
	local sum = 0

	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local playerName = getPlayerName(teamID)

		if playerName and not (playerName:find('Raptors') or playerName:find('Scavengers')) then
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
	local bossInfoRaw = Spring.GetGameRulesParam('pveBossInfo')
	if not bossInfoRaw then
		return
	end

	-- Safely decode JSON with error handling
	local success, decoded = pcall(Json.decode, bossInfoRaw)
	if not success or not decoded then
		Spring.Echo("Raptor Panel: Failed to decode boss info JSON")
		return
	end

	bossInfoRaw = decoded
	bossData = {
		resistances = {},
		playerDamages = {},
		healths = {}
	}

	-- Process resistances
	for defID, resistance in pairs(bossInfoRaw.resistances or {}) do
		if resistance.percent >= 0.1 then
			local name = UnitDefs[tonumber(defID)].translatedHumanName
			table.insert(bossData.resistances, {
				name = name,
				percent = resistance.percent,
				damage = resistance.damage
			})
		end
	end
	table.sort(bossData.resistances, function(a, b) return a.damage > b.damage end)

	-- Process player damages
	local totalDamage = 0
	for _, damage in pairs(bossInfoRaw.playerDamages or {}) do
		totalDamage = totalDamage + damage
	end

	for teamID, damage in pairs(bossInfoRaw.playerDamages or {}) do
		local name = getPlayerName(teamID)
		table.insert(bossData.playerDamages, {
			name = name,
			damage = damage,
			relative = damage / math.max(totalDamage, 1)
		})
	end
	table.sort(bossData.playerDamages, function(a, b) return a.damage > b.damage end)

	-- Process boss healths
	for queenID, status in pairs(bossInfoRaw.statuses or {}) do
		if not status.isDead and status.health > 0 then
			table.insert(bossData.healths, {
				id = tonumber(queenID),
				health = status.health,
				maxHealth = status.maxHealth,
				percentage = (status.health / status.maxHealth) * 100
			})
		end
	end
	table.sort(bossData.healths, function(a, b) return a.percentage < b.percentage end)

	-- Assign colors
	for i, health in ipairs(bossData.healths) do
		health.color = bossColors[((i - 1) % #bossColors) + 1]
	end
end

local function RegisterUnit(unitDefID, unitTeamID)
	if playerEcoAttractionsRaw[unitTeamID] then
		local ecoValue = defIDsEcoValues[unitDefID]
		if ecoValue and ecoValue > 0 then
			playerEcoAttractionsRaw[unitTeamID] = playerEcoAttractionsRaw[unitTeamID] + ecoValue
		end
	end
end

local function DeregisterUnit(unitDefID, unitTeamID)
	if playerEcoAttractionsRaw[unitTeamID] then
		playerEcoAttractionsRaw[unitTeamID] = playerEcoAttractionsRaw[unitTeamID] - (defIDsEcoValues[unitDefID] or 0)
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
	color = color or COLOR_TEXT
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
	gl.Color(1, 1, 1, 0.3)
	gl.LineWidth(1)
	gl.Shape(GL.LINE_LOOP, {
		{v = {x, y}},
		{v = {x + width, y}},
		{v = {x + width, y + height}},
		{v = {x, y + height}}
	})
end

local function drawHeader()
	local x = panelX
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale)
	local headerHeight = CONFIG.HEADER_HEIGHT * uiScale
	local padding = CONFIG.PADDING * uiScale

	DrawRect(x, y, scaledWidth, headerHeight, COLOR_HEADER)

	-- Title
	local title = "RAPTOR PANEL"
	DrawText(title, x + padding, y + (headerHeight - fontSize) / 2, fontSize, COLOR_TEXT)

	-- Difficulty
	local difficulty = modOptions.raptor_difficulty or "unknown"
	local endless = modOptions.raptor_endless and " (Endless)" or ""
	local diffText = difficulty:upper() .. endless
	local diffX = x + scaledWidth - padding
	DrawText(diffText, diffX, y + (headerHeight - smallFontSize) / 2, smallFontSize, CONFIG.COLOR_DIFFICULTY, "ro")
end

local function drawStatusPanel()
	local x = panelX
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale)
	local statusHeight = CONFIG.STATUS_HEIGHT * uiScale
	local padding = CONFIG.PADDING * uiScale
	local lineSpacing = CONFIG.LINE_SPACING * uiScale

	DrawRect(x, y, scaledWidth, statusHeight, COLOR_STATUS)

	local stage = HarmonyRaptor.getRaptorStage()
	local textY = y + statusHeight - padding - fontSize

	if HarmonyRaptor.isInGracePeriod() then
		-- Grace Period
		local remaining = HarmonyRaptor.getGraceTimeRemaining()
		local labelText = "Grace Period Remaining:"
		DrawText(labelText, x + padding, textY, fontSize, CONFIG.COLOR_GRACE)

		-- Align timer on the same line, right side
		local timerText = FormatTime(remaining)
		local timerX = x + scaledWidth - padding
		DrawText(timerText, timerX, textY, fontSize, COLOR_TEXT, "ro")
		textY = textY - fontSize - lineSpacing

	elseif stage == "main" then
		-- Queen Anger Phase
		local anger = HarmonyRaptor.getQueenHatchProgress()
		local techAnger = HarmonyRaptor.getTechAnger()
		DrawText(string.format("Queen Anger: %d%% (%d%% Evolution)", anger, techAnger), x + padding, textY, fontSize, CONFIG.COLOR_ANGER)
		textY = textY - fontSize - lineSpacing

		-- ETA
		local eta = HarmonyRaptor.getQueenETA()
		DrawText("ETA: " .. FormatTime(eta), x + padding, textY, fontSize, COLOR_TEXT)
		textY = textY - fontSize - lineSpacing

		-- Anger Rate Breakdown
		local components = HarmonyRaptor.getAngerComponents()
		DrawText(string.format("Rate: %.2f/s", components.total), x + padding, textY, smallFontSize, CONFIG.COLOR_SUBTITLE)
		textY = textY - smallFontSize - lineSpacing

		-- Single format string for better performance
		local breakdownText = string.format("Base: %.2f/s  Eco: %.2f/s  Aggro: %.2f/s",
			components.base, components.eco, components.aggression)
		DrawText(breakdownText, x + padding, textY, smallFontSize, CONFIG.COLOR_SUBTITLE)

	elseif stage == "boss" then
		-- Boss Phase
		DrawText("QUEEN ACTIVE", x + padding, textY, fontSize * 1.2, COLOR_DANGER_HIGH)
		textY = textY - (fontSize * 1.2) - lineSpacing

		local queenHealth = HarmonyRaptor.getQueenHealth()
		local queensKilled = HarmonyRaptor.getQueensKilled()
		local statusString = string.format("Total health: %d%%", queenHealth)
		if queensKilled and nBosses > 1 then
			statusString = statusString .. string.format(", Killed: %d/%d", queensKilled, nBosses)
		end

		DrawText(statusString, x + padding, textY, fontSize, COLOR_TEXT)
		textY = textY - lineSpacing
		DrawProgressBar(x + padding, textY - (20 * uiScale), scaledWidth - padding * 2, 18 * uiScale, queenHealth, COLOR_BOSS_HEALTH)
		textY = textY - (25 * uiScale)
	end
end

local function drawTabs()
	local x = panelX
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale)
	local tabHeight = CONFIG.TAB_HEIGHT * uiScale

	local tabWidth = scaledWidth / 3
	local tabs = {"ECONOMY", "DAMAGE", "QUEENS"}

	for i, tabName in ipairs(tabs) do
		local tabX = x + (i - 1) * tabWidth
		local color = (i == currentTab) and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE

		DrawRect(tabX, y, tabWidth, tabHeight, color)

		-- Tab border
		gl.Color(CONFIG.COLOR_BORDER)
		gl.LineWidth(1)
		gl.Shape(GL.LINE_LOOP, {
			{v = {tabX, y}},
			{v = {tabX + tabWidth, y}},
			{v = {tabX + tabWidth, y + tabHeight}},
			{v = {tabX, y + tabHeight}}
		})

		DrawText(tabName, tabX + tabWidth / 2, y + tabHeight / 2, fontSize, COLOR_TEXT, "cvo")
	end
end

local function drawEconomyTab()
	local padding = CONFIG.PADDING * uiScale
	local x = panelX + padding
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale) - padding - fontSize

	-- Header
	DrawText("Player Eco Attractions", x, y, fontSize, CONFIG.COLOR_HEADER_TEXT)
	y = y - (CONFIG.SECTION_SPACING * uiScale)

	if not playerEcoData or next(playerEcoData) == nil then
		y = y - fontSize - (CONFIG.SECTION_SPACING * uiScale)
		DrawText("No economy data yet", x, y, smallFontSize, CONFIG.COLOR_MUTED)
	else
		-- Table header
		y = y - smallFontSize
		DrawText("Player", x + (CONFIG.ECO_COL_PLAYER * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		DrawText("Mult", x + (CONFIG.ECO_COL_MULT * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		DrawText("Share", x + (CONFIG.ECO_COL_SHARE * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		y = y - (CONFIG.LINE_SPACING * uiScale)

		-- Draw line
		gl.Color(CONFIG.COLOR_LINE)
		gl.LineWidth(1)
		gl.Shape(GL.LINES, {
			{v = {x, y}},
			{v = {x + scaledWidth - padding * 2, y}}
		})
		y = y - (CONFIG.LINE_SPACING * uiScale)

		-- Rows
		local tabContentHeight = (TAB_CONTENT_HEIGHT * uiScale)
		local rowHeight = smallFontSize + (CONFIG.ROW_SPACING * uiScale)
		local maxRows = math.floor((tabContentHeight - (40 * uiScale)) / rowHeight)
		for i, data in ipairs(playerEcoData) do
			if i > maxRows then break end

			-- Determine color based on multiplier
			local color
			if data.multiplier and data.multiplier > CONFIG.THREAT_HIGH then
				color = COLOR_DANGER_HIGH
			elseif data.multiplier and data.multiplier > CONFIG.THREAT_MED then
				color = COLOR_DANGER_MED
			else
				color = COLOR_DANGER_LOW
			end

			y = y - smallFontSize

			-- Background highlight for current player
			if data.isMe then
				DrawRect(x, y - (2 * uiScale), scaledWidth - padding * 2, smallFontSize + (4 * uiScale), CONFIG.COLOR_HIGHLIGHT)
			end

			-- Player name
			local namePrefix = data.isMe and "> " or "  "
			DrawText(namePrefix .. data.name, x + (CONFIG.ECO_COL_PLAYER * uiScale), y, smallFontSize, color)

			-- Multiplier
			DrawText(string.format("%.1fX", data.multiplier), x + (CONFIG.ECO_COL_MULT * uiScale), y, smallFontSize, color)

			-- Percentage
			DrawText(string.format("%.0f%%", data.percentage), x + (CONFIG.ECO_COL_SHARE * uiScale), y, smallFontSize, color)

			-- Progress bar
			local barX = x + (CONFIG.ECO_COL_BAR * uiScale)
			local barWidth = scaledWidth - padding * 2 - (CONFIG.ECO_COL_BAR * uiScale)
			DrawProgressBar(barX, y - (2 * uiScale), barWidth, smallFontSize + (2 * uiScale), data.percentage, color)

			y = y - (CONFIG.ROW_SPACING * uiScale)
		end
	end
end

local function drawDamageTab()
	local padding = CONFIG.PADDING * uiScale
	local x = panelX + padding
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale) - padding - fontSize

	-- Header
	DrawText("Player Damage to Queens", x, y, fontSize, CONFIG.COLOR_HEADER_TEXT)
	y = y - (CONFIG.SECTION_SPACING * uiScale)

	if not #bossData.playerDamages or #bossData.playerDamages == 0 then
		y = y - fontSize - (CONFIG.SECTION_SPACING * uiScale)
		DrawText("No damage data yet", x, y, smallFontSize, CONFIG.COLOR_MUTED)
	else
		-- Table header
		y = y - smallFontSize
		DrawText("Rank", x + (CONFIG.DMG_COL_RANK * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		DrawText("Player", x + (CONFIG.DMG_COL_PLAYER * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		DrawText("Damage", x + (CONFIG.DMG_COL_DAMAGE * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		DrawText("Rel", x + (CONFIG.DMG_COL_RELATIVE * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
		y = y - (CONFIG.LINE_SPACING * uiScale)

		-- Draw line
		gl.Color(CONFIG.COLOR_LINE)
		gl.LineWidth(1)
		gl.Shape(GL.LINES, {
			{v = {x, y}},
			{v = {x + scaledWidth - padding * 2, y}}
		})
		y = y - (CONFIG.LINE_SPACING * uiScale)

		-- Rows
		local medals = {"#1", "#2", "#3"}
		local tabContentHeight = (TAB_CONTENT_HEIGHT * uiScale)
		local maxRows = math.floor((tabContentHeight - (40 * uiScale)) / (smallFontSize + (CONFIG.ROW_SPACING * uiScale)))
		for i, data in ipairs(bossData.playerDamages) do
			if i > maxRows then break end

			y = y - smallFontSize

			-- Medal or rank number
			local rankText = medals[i] or ("#" .. tostring(i))
			DrawText(rankText, x + (CONFIG.DMG_COL_RANK * uiScale), y, smallFontSize, COLOR_TEXT)

			-- Player name
			DrawText(data.name, x + (CONFIG.DMG_COL_PLAYER * uiScale), y, smallFontSize, COLOR_TEXT)

			-- Damage
			DrawText(FormatNumber(data.damage), x + (CONFIG.DMG_COL_DAMAGE * uiScale), y, smallFontSize, CONFIG.COLOR_DAMAGE_VALUE)

			-- Relative
			DrawText(string.format("%.1fX", data.relative), x + (CONFIG.DMG_COL_RELATIVE * uiScale), y, smallFontSize, CONFIG.COLOR_DAMAGE_RELATIVE)

			y = y - (CONFIG.ROW_SPACING * uiScale)
		end
	end
end

local function drawBossTab()
	local padding = CONFIG.PADDING * uiScale
	local x = panelX + padding
	local y = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale) - padding - fontSize

	-- Header
	DrawText("Queen Health Status", x, y, fontSize, CONFIG.COLOR_HEADER_TEXT)
	y = y - (CONFIG.SECTION_SPACING * uiScale)

	if not #bossData.healths or not #bossData.resistances or (#bossData.healths == 0 and #bossData.resistances == 0) then
		y = y - fontSize - (CONFIG.SECTION_SPACING * uiScale)
		DrawText("No boss data yet", x, y, smallFontSize, CONFIG.COLOR_MUTED)
	else
		-- Boss Health Status (Horizontal Flow)
		if #bossData.healths > 0 then
			-- Display up to configured max bosses in horizontal flow
			local maxBosses = math.min(CONFIG.MAX_BOSS_DISPLAY, #bossData.healths)
			local rowX = x + (CONFIG.ECO_COL_PLAYER * uiScale)
			local maxRowWidth = scaledWidth - padding * 2 - (CONFIG.ECO_COL_PLAYER * uiScale)
			local lineHeight = smallFontSize + (6 * uiScale)

			y = y - smallFontSize

			-- Draw boss health percentages with wrapping
			font:Begin()
			for i = 1, maxBosses do
				local health = bossData.healths[i]
				local healthText = string.format("%.0f%%", health.percentage)
				local textWidth = font:GetTextWidth(healthText) * smallFontSize
				local itemWidth = textWidth + (CONFIG.LINE_SPACING * uiScale)

				-- Check if we need to wrap to next line
				if rowX + itemWidth > x + maxRowWidth and rowX > x + (CONFIG.ECO_COL_PLAYER * uiScale) then
					y = y - lineHeight
					rowX = x + (CONFIG.ECO_COL_PLAYER * uiScale)
				end

				-- Draw the health percentage with color (without nested Begin/End)
				font:SetTextColor(health.color[1], health.color[2], health.color[3], 1)
				font:Print(healthText, rowX, y, smallFontSize, "o")

				rowX = rowX + itemWidth
			end
			font:SetTextColor(1, 1, 1, 1) -- Reset to default color
			font:End()

			y = y - (lineHeight - smallFontSize) - (CONFIG.SECTION_SPACING * uiScale * 2)
		end

		-- Resistances
		if #bossData.resistances > 0 then
			DrawText(string.format("Resistances (Top %d)", CONFIG.MAX_RESISTANCE_DISPLAY), x, y, fontSize, CONFIG.COLOR_HEADER_TEXT)
			y = y - (CONFIG.SECTION_SPACING * uiScale)

			-- Table header
			y = y - smallFontSize
			DrawText("Unit", x + (CONFIG.BOSS_COL_UNIT * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
			DrawText("Resist", x + (CONFIG.BOSS_COL_RESIST * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
			DrawText("Damage", x + (CONFIG.BOSS_COL_DAMAGE * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)
			y = y - (CONFIG.LINE_SPACING * uiScale)

			-- Draw line
			gl.Color(CONFIG.COLOR_LINE)
			gl.LineWidth(1)
			gl.Shape(GL.LINES, {
				{v = {x, y}},
				{v = {x + scaledWidth - padding * 2, y}}
			})
			y = y - (CONFIG.LINE_SPACING * uiScale)

			-- Resistance rows
			for i, resistance in ipairs(bossData.resistances) do
				if i > CONFIG.MAX_RESISTANCE_DISPLAY then break end

				y = y - smallFontSize

				DrawText(resistance.name, x + (CONFIG.BOSS_COL_UNIT * uiScale), y, smallFontSize, COLOR_TEXT)
				DrawText(string.format("%.0f%%", resistance.percent * 100), x + (CONFIG.BOSS_COL_RESIST * uiScale), y, smallFontSize, CONFIG.COLOR_RESISTANCE)
				DrawText(FormatNumber(resistance.damage), x + (CONFIG.BOSS_COL_DAMAGE * uiScale), y, smallFontSize, CONFIG.COLOR_SUBTITLE)

				y = y - (CONFIG.ROW_SPACING * uiScale)
			end
		end
	end
end

local function drawTabContent()
	local x = panelX
	local y = panelY
	local contentY = scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale)

	-- Content background
	DrawRect(x, y, scaledWidth, contentY, COLOR_BG)

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
	if not HarmonyRaptor.isRaptors() then
		widgetHandler:RemoveWidget()
        return
	end

	vsx, vsy = Spring.GetViewGeometry()
	updateUIScale()

	panelX = vsx - scaledWidth - (CONFIG.PANEL_MARGIN_X * uiScale)
	panelY = vsy - scaledHeight - (CONFIG.PANEL_MARGIN_Y * uiScale)

	-- Get font with error handling
	if WG['fonts'] and WG['fonts'].getFont then
		font = WG['fonts'].getFont()
	else
		Spring.Echo("Raptor Panel: Warning - Font system not available")
		return false
	end

	-- Initialize team data using raptor_harmony
	raptorsTeamID = HarmonyRaptor.getRaptorsTeamID()
	local playerTeams = HarmonyRaptor.getPlayerTeams()

	teamIDs = Spring.GetTeamList()
	for i = 1, #playerTeams do
		playerEcoAttractionsRaw[playerTeams[i]] = 0
	end

	-- Register existing units
	local allUnits = Spring.GetAllUnits()
	for i = 1, #allUnits do
		local unitID = allUnits[i]
		local unitDefID = Spring.GetUnitDefID(unitID)
		local unitTeamID = Spring.GetUnitTeam(unitID)
		if unitTeamID ~= raptorsTeamID then
			RegisterUnit(unitDefID, unitTeamID)
		end
	end

	UpdateGameInfo()
	UpdatePlayerEcoData()
end

function widget:Shutdown()
	-- Cleanup
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	updateUIScale()
	initialScaleSet = true  -- Mark as set after resize

	-- Keep panel in view
	panelX = math.min(panelX, vsx - scaledWidth)
	panelY = math.min(panelY, vsy - scaledHeight)
	panelX = math.max(0, panelX)
	panelY = math.max(0, panelY)
end

function widget:DrawScreen()
	if not font then return end

	-- Ensure UI scale is properly calculated on first draw
	if not initialScaleSet then
		vsx, vsy = Spring.GetViewGeometry()
		updateUIScale()
		panelX = vsx - scaledWidth - (CONFIG.PANEL_MARGIN_X * uiScale)
		panelY = vsy - scaledHeight - (CONFIG.PANEL_MARGIN_Y * uiScale)
		initialScaleSet = true
	end

	gl.PushMatrix()

	-- Use pcall to ensure PopMatrix is always called, even if there's an error
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
	local tabY = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale) - (CONFIG.STATUS_HEIGHT * uiScale) - (CONFIG.TAB_HEIGHT * uiScale)
	local tabHeight = CONFIG.TAB_HEIGHT * uiScale
	if x >= panelX and x <= panelX + scaledWidth and y >= tabY and y <= tabY + tabHeight then
		local tabWidth = scaledWidth / 3
		local tabIndex = math.floor((x - panelX) / tabWidth) + 1
		if tabIndex >= 1 and tabIndex <= 3 then
			currentTab = tabIndex
			return true
		end
	end

	-- Check if clicking on header for dragging
	local headerY = panelY + scaledHeight - (CONFIG.HEADER_HEIGHT * uiScale)
	local headerHeight = CONFIG.HEADER_HEIGHT * uiScale
	if x >= panelX and x <= panelX + scaledWidth and y >= headerY and y <= headerY + headerHeight then
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
	RegisterUnit(unitDefID, unitTeamID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	RegisterUnit(unitDefID, unitTeam)
	DeregisterUnit(unitDefID, oldTeam)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	DeregisterUnit(unitDefID, unitTeam)
end

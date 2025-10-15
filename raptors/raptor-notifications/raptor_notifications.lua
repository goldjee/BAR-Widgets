function widget:GetInfo()
	return {
		name = 'NuttyB Raptor Reminders',
		desc = 'Shows timing reminders for NuttyB Raptor spawns and aggro',
		author = 'Insider',
		date = '27.09.2025',
		layer = 0,
		enabled = true,
		version = 1,
	}
end

local isDebug = false
local notificationSound = 'LuaUI/Widgets/alert.mp3'
local gameInfo = {}
local stageGrace = 0
local stageMain = 1
local stageBoss = 2

-- Game rules
local rules = {
	'raptorDifficulty',
	'raptorGracePeriod',
	'scavBossAnger',
	'raptorQueenAnger',
	'RaptorQueenAngerGain_Aggression',
	'RaptorQueenAngerGain_Base',
	'RaptorQueenAngerGain_Eco',
	'raptorQueenHealth',
	'raptorQueensKilled',
	'raptorQueenTime',
	'raptorTechAnger',
}
local nilDefaultRules = {
	['raptorQueensKilled'] = true,
}

-- Notification messages
local gameStartNotification = "Focus on building your base and economy during the grace period."
local firstWaveNotification = "First wave of Raptors will spawn soon. You should start working on defences."
local queenHatchNotification60 = "Queen hatch at 60%. Consider strenghtening your defences and building LRPCs."
local queenHatchNotification80 = "Queen hatch at 80%. Consider walling off your base."
local queenHatchNotification100 = "Queen hatched. Brace for impact!"

-- Notification flags
local gameStartNotified = false
local firstWaveNotified = false
local queenHatchNotified60 = false
local queenHatchNotified80 = false
local queenHatchNotified100 = false

local function isRaptors()
	return Spring.Utilities.Gametype.IsRaptors()
end

local function isSpectating()
	return Spring.GetSpectatingState() or Spring.IsReplay()
end

local function UpdateRules()
	for i = 1, #rules do
		local rule = rules[i]
		gameInfo[rule] = Spring.GetGameRulesParam(rule) or (nilDefaultRules[rule] and nil or 0)
	end
end

local function getRaptorStage(currentTime)
	local stage = stageGrace
	if (currentTime and currentTime or Spring.GetGameSeconds()) > gameInfo.raptorGracePeriod then
		if (gameInfo.raptorQueenAnger < 100) then
			stage = stageMain
		else
			stage = stageBoss
		end
	end
	return stage
end

local function getGraceElapsedTime()
    local currentTime = Spring.GetGameSeconds()
    return (((currentTime - gameInfo.raptorGracePeriod) * -1) - 0.5)
end

local function getQueenHatchProgress()
    return math.min(100, math.floor(0.5 + gameInfo.raptorQueenAnger))
end

local function notify(msg)
	Spring.PlaySoundFile(notificationSound, 1.0, 'ui')
    Spring.SendCommands("say a: " .. msg)
end

function widget:Initialize()
	if not isRaptors() or (not isDebug and isSpectating()) then
		widgetHandler:RemoveWidget()
        return
	end

    UpdateRules()
end

function widget:GameFrame(n)
    if n % 30 == 17 then
		UpdateRules()

        local currentTime = Spring.GetGameSeconds()
        local stage = getRaptorStage(currentTime)

        if stage == stageGrace then
            if not gameStartNotified then
                notify(gameStartNotification)
                gameStartNotified = true
            elseif getGraceElapsedTime() <= 6 * 60 and not firstWaveNotified then
                notify(firstWaveNotification)
                firstWaveNotified = true
            end
        elseif stage == stageMain then
            if getQueenHatchProgress() >= 60 and not queenHatchNotified60 then
                notify(queenHatchNotification60)
                queenHatchNotified60 = true
            elseif getQueenHatchProgress() >= 80 and not queenHatchNotified80 then
                notify(queenHatchNotification80)
                queenHatchNotified80 = true
            end
		elseif stage == stageBoss and not queenHatchNotified100 then
			notify(queenHatchNotification100)
			queenHatchNotified100 = true
        end
	end
end
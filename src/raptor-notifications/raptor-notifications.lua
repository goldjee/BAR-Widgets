function widget:GetInfo()
    return {
        name = "Raptor Timing Notifications",
        desc = "Shows timing reminders for NuttyB Raptor spawns and aggro",
        author = "Insider",
        date = "27.09.2025",
        layer = 0,
        enabled = true,
        version = 2,
    }
end

local HarmonyRaptor = require("harmony-raptor")

local isDebug = false
local notificationSound = "LuaUI/Widgets/raptor-notifications/alert.mp3"

-- Notification messages
local gameStartNotification = "Focus on building your base and economy during the grace period."
local firstWaveNotification =
    "First wave of Raptors will spawn soon. You should start working on defences."
local queenHatchNotification60 =
    "Queen hatch at 60%. Consider strenghtening your defences and building LRPCs."
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

local function notify(msg)
    Spring.PlaySoundFile(notificationSound, 1.0, "ui")
    if isDebug then
        Spring.Echo("Raptor Notification: " .. msg)
    end
    Spring.SendCommands("say a: " .. msg)
end

function widget:Initialize()
    if not isRaptors() or (not isDebug and isSpectating()) then
        widgetHandler:RemoveWidget()
        return
    end

    HarmonyRaptor.updateGameInfo()
end

function widget:GameFrame(n)
    if n % 30 == 17 then
        HarmonyRaptor.updateGameInfo()
        local gameInfo = HarmonyRaptor.getGameInfo()
        local stage = gameInfo.stage
        local gracePeriodRemaining = gameInfo.gracePeriodRemaining

        if stage == "grace" then
            if not gameStartNotified then
                notify(gameStartNotification)
                gameStartNotified = true
            end
            if gracePeriodRemaining <= 6 * 60 and not firstWaveNotified then
                notify(firstWaveNotification)
                firstWaveNotified = true
            end
        elseif stage == "main" then
            if gracePeriodRemaining >= 60 and not queenHatchNotified60 then
                notify(queenHatchNotification60)
                queenHatchNotified60 = true
            end
            if gracePeriodRemaining >= 80 and not queenHatchNotified80 then
                notify(queenHatchNotification80)
                queenHatchNotified80 = true
            end
        elseif stage == "boss" and not queenHatchNotified100 then
            notify(queenHatchNotification100)
            queenHatchNotified100 = true
        end
    end
end

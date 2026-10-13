local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Raptor Timing Notifications",
        desc = "Shows timing reminders for NuttyB Raptor spawns and aggro",
        author = "Insider",
        date = "27.09.2025",
        layer = 0,
        enabled = true,
        version = 3,
    }
end

local IS_DEBUG = false
local NOTIFICATION_SOUND = "LuaUI/Widgets/raptor-notifications/alert.mp3"

local MSG = {
    gameStart = "Focus on building your base and economy during the grace period.",
    firstWave = "First wave of Raptors will spawn soon. You should start working on defences.",
    queenHatch60 = "Queen hatch at 60%. Consider strengthening your defences and building LRPCs.",
    queenHatch80 = "Queen hatch at 80%. Consider walling off your base.",
    queenHatch100 = "Queen hatched. Brace for impact!",
}

local notified = {}

-- Sends msg unless it was already sent; returns true if it was sent now
local function notifyOnce(msg)
    if notified[msg] then
        return false
    end
    notified[msg] = true

    Spring.PlaySoundFile(NOTIFICATION_SOUND, 1.0, "ui")
    if IS_DEBUG then
        Spring.Echo("Raptor Notification: " .. msg)
    end
    -- Intentionally broadcasts to ally chat so the whole team sees the reminder;
    -- teammates running this widget too will produce duplicate messages.
    Spring.SendCommands("say a: " .. msg)
    return true
end

function widget:Initialize()
    local isSpectating = Spring.GetSpectatingState() or Spring.IsReplay()
    if not BAR.Utilities.Gametype.IsRaptors() or (not IS_DEBUG and isSpectating) then
        widgetHandler:RemoveWidget()
    end
end

function widget:GameFrame(n)
    if n % 30 ~= 17 then
        return
    end

    local graceRemaining = (Spring.GetGameRulesParam("raptorGracePeriod") or 0)
        - Spring.GetGameSeconds()
    local anger = Spring.GetGameRulesParam("raptorQueenAnger") or 0
    local hatchProgress = math.floor(anger + 0.5)

    if graceRemaining >= 0 then
        -- the first-wave reminder waits a cycle so it never stacks on the
        -- game-start one when the grace period is shorter than 6 minutes
        if not notifyOnce(MSG.gameStart) and graceRemaining <= 6 * 60 then
            notifyOnce(MSG.firstWave)
        end
    elseif anger < 100 then
        if hatchProgress >= 60 then
            notifyOnce(MSG.queenHatch60)
        end
        if hatchProgress >= 80 then
            notifyOnce(MSG.queenHatch80)
        end
    else
        notifyOnce(MSG.queenHatch100)
    end
end

# Harmony - Shared Utility Library for BAR Widgets

Harmony is a collection of shared utility libraries designed to provide common functionality across Beyond All Reason (BAR) LuaUI widgets. The library promotes code reuse and standardization by centralizing frequently-needed utilities.

## Installation

Put the **harmony** folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\` folder.

## Library Components

### `harmony.lua` - Core Utilities
The base harmony library providing fundamental game utilities.

#### Usage
```lua
local harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')
```

#### Functions
- **`harmony.getTime()`** - Returns current game time in seconds

---

### `harmony-raptor.lua` - Raptor Game Mode Utilities
Specialized library for widgets interacting with the Raptors game mode. Provides comprehensive access to raptor game state, boss information, and threat mechanics.

#### Usage
```lua
local harmonyRaptor = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')
```

#### Game State Functions

**`harmonyRaptor.isRaptors()`**
Returns `true` if current game mode is Raptors.

**`harmonyRaptor.isSpectating()`**
Returns `true` if player is spectating or watching a replay.

**`harmonyRaptor.getGameInfo()`**
Updates and returns table containing all raptor game rules including:
- `raptorDifficulty` - Current difficulty setting
- `raptorGracePeriod` - Grace period duration
- `raptorQueenAnger` - Current queen anger level (0-100)
- `raptorQueenHealth` - Current queen health percentage
- `raptorQueensKilled` - Number of queens killed
- `raptorTechAnger` - Tech anger level
- And more...

**`harmonyRaptor.getRaptorStage()`**
Returns current game stage: `"grace"`, `"main"`, or `"boss"`

#### Grace Period Functions

**`harmonyRaptor.getGraceTimeRemaining()`**
Returns time remaining in grace period (in seconds), or 0 if ended.

**`harmonyRaptor.getGraceElapsedTime()`**
Returns time remaining in grace period with offset adjustment.

**`harmonyRaptor.formatGraceTime(seconds)`**
Formats time in seconds to human-readable format ("12 minutes", "5m 30s", "45 seconds").

**`harmonyRaptor.isInGracePeriod()`**
Returns `true` if currently in grace period.

#### Queen & Boss Functions

**`harmonyRaptor.getQueenHatchProgress()`**
Returns queen hatch progress as percentage (0-100).

**`harmonyRaptor.getQueenETA()`**
Returns estimated time until queen spawns (in seconds), or 0 if already spawned.

**`harmonyRaptor.getBossCount()`**
Returns number of queens/bosses configured for this match.

**`harmonyRaptor.getQueenHealth()`**
Returns current queen health percentage (0-100), or 0 if queen not spawned.

**`harmonyRaptor.getQueensKilled()`**
Returns number of queens killed, or `nil` if not tracked.

#### Mini Boss Detection

**`harmonyRaptor.getMiniBossInfo()`**
Returns table with all mini boss definitions (names and descriptions).

**`harmonyRaptor.getMiniBossName(unitDefName)`**
Returns display name for a mini boss unit (or `nil` if not a mini boss).

**`harmonyRaptor.getMiniBossDescription(unitDefName)`**
Returns description for a mini boss unit (or `nil` if not a mini boss).

**`harmonyRaptor.isMiniBoss(unitDefName)`**
Returns `true` if the given unit def name is a mini boss.

**`harmonyRaptor.isQueenling(unitDefName)`**
Returns `true` if the given unit def name is a Queenling.

**Supported Mini Bosses:**
- `raptor_miniq_a` - Queenling Prima
- `raptor_miniq_b` - Queenling Secunda
- `raptor_miniq_c` - Queenling Tertia
- `raptor_mama_ba` - Matrona
- `raptor_mama_fi` - Pyro Matrona
- `raptor_mama_el` - Paralyzing Matrona
- `raptor_mama_ac` - Acid Matrona
- `raptor_consort` - Raptor Consort
- `raptor_doombringer` - Doombringer

#### Tech Anger & Threat Detection

**`harmonyRaptor.getTechAnger()`**
Returns current tech anger level (0-100+).

**`harmonyRaptor.getNukeWarningLevel()`**
Returns nuke warning level: `"none"`, `"warning"`, or `"critical"`.
Based on tech anger thresholds (65/90 for Raptors, 50/85 for Scavengers).

**`harmonyRaptor.shouldShowNukeWarning(hasAntiNuke, teamID)`**
Returns `true` if nuke warning should be displayed based on:
- Anti-nuke status
- Tech anger in warning range
- Sufficient energy storage (>1000)
- Team has more than 3 units

#### Anger Breakdown

**`harmonyRaptor.getAngerGainRate()`**
Returns total anger gain rate per second.

**`harmonyRaptor.getAngerComponents()`**
Returns table with anger gain components:
```lua
{
    base = number,        -- Base anger gain
    eco = number,         -- Economy-based anger gain
    aggression = number,  -- Aggression-based anger gain
    total = number        -- Total combined anger gain
}
```

#### Team & Player Utilities

**`harmonyRaptor.getRaptorsTeamID()`**
Returns the Raptors/Gaia team ID.

**`harmonyRaptor.isRaptorUnit(unitID)`**
Returns `true` if the given unit belongs to the Raptors team.

**`harmonyRaptor.getPlayerTeams()`**
Returns list of player team IDs (excluding Raptors/Scavengers/Gaia).

## Design Philosophy

Harmony libraries are designed to:
1. **Centralize common logic** - Avoid duplicating code across multiple widgets
2. **Provide stable APIs** - Widget developers can rely on consistent interfaces
3. **Reduce maintenance burden** - Updates to shared logic happen in one place
4. **Improve performance** - Shared caching and optimized data access

## Development Guidelines

When adding new utilities to Harmony:
- Keep functions focused and single-purpose
- Document all parameters and return values
- Use consistent naming conventions
- Avoid dependencies on specific widgets
- Consider backward compatibility when making changes

## Example Usage

```lua
-- Basic raptor widget example
function widget:GetInfo()
    return {
        name = "My Raptor Widget",
        -- ...
    }
end

local harmonyRaptor = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')

function widget:GameFrame(n)
    if not harmonyRaptor.isRaptors() then
        return
    end

    local stage = harmonyRaptor.getRaptorStage()

    if stage == "grace" then
        local timeLeft = harmonyRaptor.getGraceTimeRemaining()
        Spring.Echo("Grace period: " .. harmonyRaptor.formatGraceTime(timeLeft))
    elseif stage == "main" then
        local anger = harmonyRaptor.getQueenHatchProgress()
        Spring.Echo("Queen anger: " .. anger .. "%")
    elseif stage == "boss" then
        local health = harmonyRaptor.getQueenHealth()
        Spring.Echo("Queen health: " .. health .. "%")
    end
end
```

## Version History

The Harmony library evolves with BAR development. Check git history for detailed changes.

## Contributing

When contributing to Harmony:
1. Ensure new utilities are broadly useful across multiple widgets
2. Add comprehensive documentation
3. Test with existing widgets to avoid breaking changes
4. Follow the established code style and patterns

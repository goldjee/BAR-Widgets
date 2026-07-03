# Harmony - Shared Utility Library for BAR Widgets

Harmony is a collection of shared utility libraries designed to provide common functionality across Beyond All Reason (BAR) LuaUI widgets. The library promotes code reuse and standardization by centralizing frequently-needed utilities.

## Installation

Put the **harmony** folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\` folder.

## Library Components

### `harmony.lua` - Core Utilities
The base harmony library providing fundamental game utilities.

#### Usage
```lua
-- Without luapack
local Harmony = VFS.Include('LuaUI/Widgets/harmony/harmony.lua')
local HarmonyRaptor = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')

-- With luapack
local Harmony = require("harmony")
local HarmonyRaptor = require("harmony-raptor")
```

#### Functions

**`harmony.getTime()`**
Returns current game time in seconds.

**`harmony.getPlayerName(teamID)`**
Returns player or AI name for a given team ID. Uses caching for performance.
- Returns player name(s) for human players
- For teams with multiple players, returns names joined with " & "
- Falls back to AI name if no human players
- Always returns a string (empty string if no name found)

---

### `harmony-raptor.lua` - Raptor Game Mode Utilities
Specialized library for widgets interacting with the Raptors game mode. Provides comprehensive access to raptor game state, boss information, and threat mechanics.

#### Usage
```lua
local HarmonyRaptor = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')
```

#### Core Game Info Functions

**`hr.updateGameInfo()`**
Updates the internal `gameInfo` table with the latest game rules from the engine. Call this before reading game state to ensure data is current.

**`hr.getGameInfo()`**
Returns the `gameInfo` table containing current raptor game state. This table includes:

**Game Info Table Structure:**
```lua
{
    -- Basic settings
    gracePeriod = number,          -- Grace period duration (seconds)

    -- Anger system
    anger = number,                -- Queen anger level (0-100)
    angerTech = number,            -- Tech anger level (0-100+)
    angerGainBase = number,        -- Base anger gain rate
    angerGainEco = number,         -- Economy-based anger gain
    angerGainAggression = number,  -- Aggression-based anger gain

    -- Queen status
    queenHealth = number,          -- Queen health percentage (0-100)
    queenCount = number,           -- Number of queens in this match
    queenCountKilled = number,     -- Number of queens killed (nil if not tracked)
    queenTime = number,            -- Time when queen spawned
    queenHatchProgress = number,   -- Queen spawn progress percentage (0-100)
    queenStaggerActive = boolean,  -- true while queens are staggered (paralyzed, resistances halved)
    queenStaggerPercentage = number, -- Stagger bar remaining (0-100); recovery progress while staggered

    -- Current game phase
    stage = string,                -- "grace", "main", or "boss"
    gracePeriodRemaining = number, -- Seconds remaining in grace period (0 if ended)

    -- Threat level
    nukeThreatLevel = string       -- "none", "warning", or "critical"
}
```

The `gameInfo` table provides a comprehensive snapshot of the current raptor game state. All fields are computed from game rules and mod options. Note that `hr.updateGameInfo()` must be called to refresh these values.

#### Queen & Boss Functions

**`hr.getQueenETA()`**
Returns estimated time until queen spawns (in seconds), or `nil` if not in main stage or if the anger gain rate is zero (infinite time).

**`hr.getQueenDamageMultiplier()`**
Returns the multiplier the base game applies to player damage against queens, based on total queen health ("bosses get stronger the less health they have"): `>50%: x2`, `>25%: x1`, `>10%: x0.75`, `>5%: x0.5`, `<=5%: x0.25`. Returns `1` outside the boss stage.

**`hr.getBossInfo()`**
Returns comprehensive boss/queen information with guaranteed structure. Always returns a table with the following fields, even when no boss data is available yet:

```lua
{
    resistances = {
        {name = string, percent = number, damage = number},
        -- ... sorted by damage dealt (descending)
    },
    playerDamages = {
        {name = string, damage = number, relative = number},
        -- ... sorted by damage dealt (descending)
    },
    healths = {
        {id = number, health = number, maxHealth = number, percentage = number},
        -- ... sorted by health percentage (ascending)
    }
}
```

**Features:**
- Safely parses boss info JSON with error handling
- Returns empty arrays when boss data not available (before boss spawns)
- Filters resistances to show only those >= 10%
- Calculates relative damage as a fraction of total damage
- Automatically sorts all arrays for easy consumption

**Use Case:** This is the primary function for accessing boss statistics. Use this instead of directly calling `Spring.GetGameRulesParam('pveBossInfo')` to ensure consistent data structure and avoid JSON parsing errors.

#### Mini Boss Detection

**`hr.isMiniBoss(unitDefName)`**
Returns `true` if the given unit def name is a mini boss.

**`hr.isQueenling(unitDefName)`**
Returns `true` if the given unit def name is a Queenling (mini queen variant).

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

#### Team & Player Utilities

**`hr.isRaptors()`**
Returns `true` if the current game is a Raptors game. Thin wrapper around
`Spring.Utilities.Gametype.IsRaptors()` — use it to guard widget initialization so the widget
self-removes in non-raptor games.

**`hr.getRaptorsTeamID()`**
Returns the Raptors/Gaia team ID. Checks all teams for Raptors LuaAI, falls back to Gaia team.

**`hr.isRaptorUnit(unitID)`**
Returns `true` if the given unit belongs to the Raptors team.

**`hr.getPlayerTeams()`**
Returns list of player team IDs (excluding Raptors/Scavengers/Gaia).

#### Eco Value Calculation (Raptor Targeting)

These functions help calculate "eco attraction" values - how much raptors are attracted to attack a player's units based on their economic value.

**`hr.initEcoValueCache()`**
Initializes the eco value cache for all unit definitions. Call once during widget initialization for optimal performance. Returns the cache table.

**`hr.getUnitEcoValue(unitDefID)`**
Returns the eco attraction value for a unit definition ID. Uses cached values for performance.
- Higher values = more attractive to raptors
- Based on energy production, metal extraction, tech level, and special buildings
- Returns 0 for mobile units (except commanders) and objects
- Automatically initializes cache if not already done

**`hr.updatePlayerEcoValues(playerEcoTable, unitDefID, teamID, isAdd)`**
Updates player eco values when units are created/destroyed.
- **playerEcoTable**: table of `{teamID = ecoValue}`
- **unitDefID**: the unit definition ID
- **teamID**: the team owning the unit
- **isAdd**: `true` to add eco value, `false` to subtract

**`hr.getPlayerEcoThreat(playerEcoAttractionsRaw)`**
Computes per-player eco threat from a raw eco attraction table (the `{teamID = ecoValue}` table
maintained via `hr.updatePlayerEcoValues`). Returns a list **sorted by value descending** of:

```lua
{
    {
        name = string,         -- player/AI name
        value = number,        -- eco attraction value (clamped to >= 0)
        teamID = number,
        percentage = number,   -- share of total eco (0-100)
        multiplier = number,   -- eco relative to the average player
        threatLevel = string,  -- "high" (>1.7x), "medium" (>1.2x), or "low"
    },
    -- ...
}
```

Only includes named player teams (uses `hr.getPlayerTeams()` + `harmony.getPlayerName()`
internally, so Raptors/Scavengers/Gaia are excluded). Threat math (percentage, multiplier,
threshold classification) lives here so widgets only need to add presentation formatting.

**Example:**
```lua
local RaptorHarmony = VFS.Include('LuaUI/Widgets/harmony/harmony-raptor.lua')
local playerEcoAttractionsRaw = {}

-- Initialize eco value cache
RaptorHarmony.initEcoValueCache()

-- Initialize player eco tracking
for _, teamID in ipairs(RaptorHarmony.getPlayerTeams()) do
    playerEcoAttractionsRaw[teamID] = 0
end

-- Track unit creation
function widget:UnitCreated(unitID, unitDefID, unitTeamID)
    RaptorHarmony.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
end

-- Track unit destruction
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    RaptorHarmony.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, false)
end
```

## Design Philosophy

Harmony libraries are designed to:
1. **Centralize common logic** - Avoid duplicating code across multiple widgets
2. **Provide stable APIs** - Widget developers can rely on consistent interfaces
3. **Reduce maintenance burden** - Updates to shared logic happen in one place
4. **Improve performance** - Shared caching and optimized data access

## Contributing

When contributing to Harmony:
1. Ensure new utilities are broadly useful across multiple widgets
2. Add comprehensive documentation
3. Test with existing widgets to avoid breaking changes
4. Follow the established code style and patterns

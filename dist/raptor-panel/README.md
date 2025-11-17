# Raptor Stats Panel

![Grace](https://github.com/goldjee/BAR-Widgets/blob/e5aff38b7a0c4ff6326ad82a35eac84a75efccf2/raptor-panel/panel-grace.png) ![Hatching](https://github.com/goldjee/BAR-Widgets/blob/e5aff38b7a0c4ff6326ad82a35eac84a75efccf2/raptor-panel/panel-hatching.png)

A comprehensive UI widget for Beyond All Reason that displays real-time statistics and information about the Raptor game mode in a clean interface.

## Overview

The Raptor Stats Panel provides players with critical information about the Raptor threat, including economy-based targeting, damage statistics, and boss health tracking.

## Installation

Take all files from `../dist/raptor-panel/` into your `[...]\Beyond-All-Reason\data\LuaUI\RmlWidgets\raptor-panel\` folder and enable the "Raptor Panel" widget from the in-game settings menu.

## Features

### Dynamic Status Panel

The status panel automatically adapts to display relevant information based on the current game stage:

#### Grace Period Stage

- **Grace Period Timer** - Countdown until raptors begin spawning

#### Main Phase (Queen Anger)

- **Queen Anger Level** - Current hatch progress percentage (0-100%)
- **Evolution Progress** - Tech anger level indicating threat escalation
- **Queen ETA** - Estimated time until queen spawns

#### Boss Phase

- **Active Boss Alert** - High-visibility warning when queen(s) spawn
- **Total Health Percentage** - Combined health across all queens
- **Queens Killed Counter** - Tracks boss elimination progress (multi-queen games)
- **Health Progress Bar** - Visual representation of remaining bosses combined health

### Tab 1: Economy Analysis

Displays player economy values and their relative threat to raptors based on economic development.

**Information Displayed:**
- **Player Names** - All human/AI players in the match
- **Multiplier** - Relative threat level compared to average (e.g., 1.5X means 50% more threatening)
- **Share Percentage** - Player's portion of total economy
- **Visual Progress Bars** - Quick identification of high-threat players
- **Color Coding:**
  - Red: High threat (>1.7X multiplier)
  - Yellow: Medium threat (1.2X - 1.7X)
  - Green: Low threat (<1.2X)
- **Current Player Highlight** - Your slot is highlighted with a subtle background

**Economy Calculation:**
The economy value calculation considers:
- Energy production (generators, wind, tidal)
- Metal extraction structures
- Energy conversion capacity
- Tech level multipliers
- Strategic structures (nukes, anti-nukes)

### Tab 2: Damage Statistics

Tracks and ranks player damage dealt to queen bosses during the boss phase.

**Information Displayed:**
- **Rank** - Leaderboard position (#1, #2, #3, etc.)
- **Player Name** - Team identification
- **Total Damage** - Raw damage dealt to queens (formatted: K = thousands, M = millions)
- **Relative Damage** - Damage multiplier compared to average player

### Tab 3: Queens Status

Provides detailed information about active queen bosses and their vulnerabilities.

**Information Displayed:**

#### Boss Health Status

- **Individual Queen Health** - Health percentage for each active queen
- **Color-Coded Display** - Each queen assigned a unique color for tracking
- **Multi-Boss Support** - Displays up to 50 queens simultaneously
- **Horizontal Flow Layout** - Health percentages flow across available space

#### Resistance Analysis

- **Resistance Percentage** - How much damage is mitigated (0-100%)
- **Total Damage Received** - Amount of damage dealt by that unit type

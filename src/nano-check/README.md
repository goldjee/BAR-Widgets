# Construction Turrets Range Check

A widget that stops construction turrets from being assigned to targets out of their reach. When you give selected turrets a repair, guard, reclaim or attack order, it checks their queues shortly afterwards. Any order whose target is out of build range is removed, and turrets left with nothing in range are stopped.

Works with every stationary builder, including Legion and T3 construction turrets. It's disabled while spectating.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\nano-check` folder and enable the "Construction Turrets Range Check" widget from the in-game settings menu.

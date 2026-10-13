# Split Builder Queue

A widget that copies and splits build queues between constructors (mobile builders and nano turrets), so a group of builders shares the work instead of crowding around the same task.

## Self-organize

Select 2 or more builders with queues and press:

- **CTRL+ALT+Q** - merges the build queues of all selected builders (dropping duplicates) and splits them evenly in queue order. Each builder gets its share first, then the rest as backup, so everything gets built even if some builders die.
- **CTRL+ALT+W** - frontline mode: same as above, but sorts the tasks by distance from the group and hands them out nearest-first in 4 waves. Each wave goes to the builders closest to it. The full queue is added as backup.

Both modes send the builders back to their starting positions when they're done.

## Guard modifiers

Select constructors and order them to guard another constructor while holding:

- **ALT** - copy its full queue
- **CTRL+ALT** - take an even, sequential share of its queue (the guarded constructor counts as one of the builders)
- **CTRL** - take a share first, then the rest of the queue as backup
- **CTRL+SHIFT** - copy its full queue, starting at a random position

Type `/luaui copyqueue` (or `/luaui cq`) in chat to print this list.

## Installation

Take all files from this folder into your `[...]\Beyond-All-Reason\data\LuaUI\Widgets\split-builder-queue` folder and enable the "Split Builder Queue" widget from the in-game settings menu.

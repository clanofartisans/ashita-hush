<img align="right" height="300px" src="https://github.com/clanofartisans/ashita-hush/raw/main/mandy_yell.png">

# Installation
Install to your addons folder (e.g. `.\HorizonXI\Game\addons\hush\hush.lua`).

## Usage
* `/hush`: Opens a GUI with options for filtering certain messages.

GM shouts and yells, and HorizonXI's hardcore-death announcements, are never hushed, even with "Hush all shouts" turned on.

## Using other chat addons
If you use an addon that shows chat in its own window, such as FancyChat, load Hush **before** it in your Ashita default script. Otherwise that addon picks up each message before Hush gets a chance to hush it.

**SimpleLog:** "Hush others' defeated enemies" doesn't work while SimpleLog is loaded. The game marks a defeat message differently depending on who got the kill (you, your party, or someone else), and Hush uses that to find other players' defeats. SimpleLog replaces the game's battle messages with its own and marks every defeat as if it were yours, so Hush can't tell them apart. To hide other players' battle messages with SimpleLog, use the `others` section of SimpleLog's own `filters.lua` instead. That hides all of their battle messages, not only defeats.

## Preview
![Hush Settings Preview](https://github.com/clanofartisans/ashita-hush/raw/main/settings.png)

## Experimental
The hushing of command errors should be considered "Experimental" at the moment. It could have some unforeseen false positives in its filtering so things you might want to see could get hushed by accident. Please let me know if you have this enabled and notice something missing that shouldn't be.

## Attribution
The beautiful mandragora art is used with permission from Consumelivebees <3
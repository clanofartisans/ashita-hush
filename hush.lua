--[[
* Addons - Copyright (c) 2021 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name      = 'hush';
addon.author    = 'Hugin';
addon.version   = '1.5.2';
addon.desc      = 'Hides yells, teleport requests, Eco-Warrior, and other annoying messages.';
addon.link      = 'https://github.com/clanofartisans/ashita-hush';

require('common');
local chat = require('chat');
local imgui = require('imgui');
local settings = require('settings');
local memMgr = AshitaCore:GetMemoryManager();
local partyMgr = memMgr:GetParty();

-- Default Settings
local default_settings = T{
    remote     = false,
    hushLocal  = false,
    teleport   = false,
    ecowarrior = false,
	highwind   = false,
    synth      = false,
    fish       = false,
    allshouts  = false,
    defeats    = false,
    cmderror   = false,
	merrymaker = false
};

-- Hush Variables
local hush = T{
    bastok = T{
        '[BastokMark]: ',
        '[BastokMine]: ',
        '[Metalworks]: ',
        '[PortBastok]: '
    },
    jeuno = T{
        '[LowJeuno]: ',
        '[PortJeuno]: ',
        '[RuLudeGard]: ',
        '[UpJeuno]: '
    },
    sandy = T{
        '[ChatdOrag]: ',
        '[NSandOria]: ',
        '[PSandOria]: ',
        '[SSandOria]: '
    },
    windurst = T{
        '[HeavenTowr]: ',
        '[PortWind]: ',
        '[WindWalls]: ',
        '[WindWaters]: ',
        '[WindWoods]: '
    },
    teleports = T{
        '{Teleport-Altep}',
        '{Teleport-Dem}',
        '{Teleport-Holla}',
        '{Teleport-Mea}',
        '{Teleport-Yhoat}',
        '{Teleport-Vahzl}'
    },
    settings = settings.load(default_settings),
	guiOpen = { false }
};

--[[
* Returns a string cleaned from FFXI specific tags and special characters.
*
* @param {string} str - The string to clean.
* @return {string} The cleaned string.
--]]
local function clean_str(str)
    -- Parse the strings auto-translate tags..
    str = AshitaCore:GetChatManager():ParseAutoTranslate(str, true);

    -- Strip FFXI-specific color and translate tags..
    str = str:strip_colors();
    str = str:strip_translate(true);

    return str;
end

--[[
* Tests if the current message contains the local player's name.
*
* @param e - The chat event?
* @return {bool} True if the message contains the player's name, otherwise false.
--]]
local function contains_name(e)
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    return name ~= nil and e.message_modified:lower():contains(name:lower());
end

--[[
* Returns the ID for the player's current zone.
*
* @return {int} The current zone ID.
--]]
local function get_zone()
    local zoneId = partyMgr:GetMemberZone(0);
    if zoneId then
        return zoneId;
    end
end

--[[
* Determines if the message is part of a "command error".
*
* @param e - The chat event?
* @return {bool} True if the message is part of a "command error", otherwise false.
--]]
local function is_cmd_error(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find command errors..
    k = (msg:contains('A command error occurred') or msg:contains('>> '));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is another player's defeated enemy.
*
* @param e - The chat event?
* @return {bool} True if the message is another player's defeated enemy, otherwise false.
--]]
local function is_defeats(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find others' defeated enemies..
    k = msg:contains(' defeats ');

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is another player's fishing result.
*
* @param e - The chat event?
* @return {bool} True if the message is another player's fishing results, otherwise false.
--]]
local function is_fish(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find others' fishing results..
    k = (msg:contains(' caught ') and not contains_name(e) and not msg:contains('Something'));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the a message is "local" or not.
*
* @param e - The chat event?
* @return {bool} True if local, otherwise false.
--]]
local function is_local(e)
    local zone = get_zone();
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Local is Bastok..
    if (zone >= 234 and zone <= 237) then
        -- Find a matching Bastok entry..
        k, _ = hush.bastok:find_if(function (v, _)
            if (msg:contains(v)) then
                return true;
            end
            return false;
        end);
    end

    -- Local is Jeuno..
    if (zone >= 243 and zone <= 246) then
        -- Find a matching Jeuno entry..
        k, _ = hush.jeuno:find_if(function (v, _)
            if (msg:contains(v)) then
                return true;
            end
            return false;
        end);
    end

    -- Local is San d'Oria..
    if (zone >= 230 and zone <= 233) then
        -- Find a matching San d'Oria entry..
        k, _ = hush.sandy:find_if(function (v, _)
            if (msg:contains(v)) then
                return true;
            end
            return false;
        end);
    end

    -- Local is Windurst..
    if (zone >= 238 and zone <= 242) then
        -- Find a matching Windurst entry..
        k, _ = hush.windurst:find_if(function (v, _)
            if (msg:contains(v)) then
                return true;
            end
            return false;
        end);
    end

    -- Local is Mhaura/Selbina..
    if (zone == 248 or zone == 249) then
        -- Find a matching Mhaura/Selbina entry..
        k = (msg:contains('[Mhaura]: ') or msg:contains('[Selbina]: '));
    end

    -- Local is Kazham..
    if (zone == 250) then
        -- Find a matching Kazham entry..
        k = (msg:contains('[Kazham]: '));
    end

    -- Local is Norg..
    if (zone == 252) then
        -- Find a matching Norg entry..
        k = (msg:contains('[Norg]: '));
    end

    -- Local is Rabao..
    if (zone == 247) then
        -- Find a matching Rabao entry..
        k = (msg:contains('[Rabao]: '));
    end
	
	-- Local is Tavnazian Safehold..
    if (zone == 26) then
        -- Find a matching TavSafehld entry..
        k = (msg:contains('[TavSafehld]: '));
    end

    if (k ~= nil) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is another player's synthesis result.
*
* @param e - The chat event?
* @return {bool} True if someone else's result, otherwise false.
]]--
local function is_synth(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find successful synthesis..
    k = (msg:contains(' synthesized ') and not msg:contains('You synthesized '));

    if (k) then
        return true;
    end

    -- Find failed synthesis..
    k = (msg:contains(' lost ') and not msg:contains('You lost '));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is a teleport request or advertisement.
*
* @param e - The chat event?
* @return {bool} True if it's teleport related, otherwise false.
--]]
local function is_teleport(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find a auto-translate teleports..
    k, _ = hush.teleports:find_if(function (v, _)
        if (msg:contains(v)) then
            return true;
        end
        return false;
    end);

    if (k ~= nil) then
        return true;
    end

    -- Find taxi teleports..
    return (msg:contains('Dem') and msg:contains('Holla') and msg:contains('Mea'));
end

--[[
* Determines if the message is a Eco-Warrior request or advertisement.
*
* @param e - The chat event?
* @return {bool} True if it's Eco-Warrior related, otherwise false.
--]]
local function is_ecowarrior(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find the word "eco"..
    k = ((e.message_modified:lower():contains('eco')) and not contains_name(e));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is a Highwind shout.
*
* @param e - The chat event?
* @return {bool} True if it's Highwind related, otherwise false.
--]]
local function is_highwind(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find the word "highwind", hopefully including if it's misspelled..
    k = ((e.message_modified:lower():match('hi.*wind') or e.message_modified:lower():match(' hw')) and not contains_name(e));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Determines if the message is a Goblin Merrymaker.
*
* @param e - The chat event?
* @return {bool} True if it's a Goblin Merrymaker, otherwise false.
--]]
local function is_merrymaker(e)
    local msg = clean_str(e.message_modified);
    local k = false;

    -- Find the NPC name..
    k = (e.message_modified:contains('Goblin Merrymaker'));

    if (k) then
        return true;
    end

    return false;
end

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hush', "Displays the addon's configuration window." },
        { '/hush help', "Displays the addon's help information." },
    };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        hush.settings = s;
    end

    -- Save the current settings..
    settings.save();
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings);

--[[
* event: d3d_present
* desc : Event called when the addon opens the configuration GUI.
--]]
ashita.events.register('d3d_present', 'd3d_present_cb', function ()
    if (not hush.guiOpen[1]) then return end
    
    if (imgui.Begin('Hush Settings##HushSettingsWindow', hush.guiOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
        if imgui.Checkbox('Hush remote /yells##HushRemoteCheck', { hush.settings.remote }) then
            hush.settings.remote = not hush.settings.remote;
            update_settings();
        end
        if imgui.Checkbox('Hush local /yells##HushLocalCheck', { hush.settings.hushLocal }) then
            hush.settings.hushLocal = not hush.settings.hushLocal;
            update_settings();
        end
        if imgui.Checkbox('Hush teleport shouts/yells##HushTeleportCheck', { hush.settings.teleport }) then
            hush.settings.teleport = not hush.settings.teleport;
            update_settings();
        end
        if imgui.Checkbox('Hush Eco-Warrior shouts/yells##HushEcoWarriorCheck', { hush.settings.ecowarrior }) then
            hush.settings.ecowarrior = not hush.settings.ecowarrior;
            update_settings();
        end
        if imgui.Checkbox('Hush Highwind shouts/yells##HushHighwindCheck', { hush.settings.highwind }) then
            hush.settings.highwind = not hush.settings.highwind;
            update_settings();
        end
        if imgui.Checkbox('Hush all shouts##HushAllShoutsCheck', { hush.settings.allshouts }) then
            hush.settings.allshouts = not hush.settings.allshouts;
            update_settings();
        end
        if imgui.Checkbox('Hush others\' synthesis results##HushSynthCheck', { hush.settings.synth }) then
            hush.settings.synth = not hush.settings.synth;
            update_settings();
        end
        if imgui.Checkbox('Hush others\' fishing results##HushFishCheck', { hush.settings.fish }) then
            hush.settings.fish = not hush.settings.fish;
            update_settings();
        end
        if imgui.Checkbox('Hush others\' defeated enemies##HushDefeatsCheck', { hush.settings.defeats }) then
            hush.settings.defeats = not hush.settings.defeats;
            update_settings();
        end
        if imgui.Checkbox('Hush Goblin Merrymakers##HushMerrymakerCheck', { hush.settings.merrymaker }) then
            hush.settings.merrymaker = not hush.settings.merrymaker;
            update_settings();
        end
        if imgui.Checkbox('Hush "command errors" (experimental)##HushCmdErrCheck', { hush.settings.cmderror }) then
            hush.settings.cmderror = not hush.settings.cmderror;
            update_settings();
        end
        imgui.End();
    end
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or (args[1] ~= '/hush')) then
        return;
    end

    -- Block all hush related commands..
    e.blocked = true;

    -- Handle: /hush - Shows the addon help.
    if (#args == 1) then
        --print_help(false);
        hush.guiOpen[1] = (not hush.guiOpen[1]);
        return;
    end

    -- Handle: /hush help - Shows the addon help.
    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: text_in
* desc : Event called when the addon is processing incoming text.
--]]
ashita.events.register('text_in', 'text_in_cb', function (e)
    local cm = bit.band(e.mode,  0x000000FF);

    -- Hush all shouts..
    if (cm == 10 and hush.settings.allshouts == true) then
        e.blocked = true;
        return;
    end

    -- Hush /shouted teleports..
    if ((cm == 10 or cm == 11) and hush.settings.teleport == true) then
        if(is_teleport(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush Eco-Warrior..
    if ((cm == 10 or cm == 11) and hush.settings.ecowarrior == true) then
        if(is_ecowarrior(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush Highwind..
    if ((cm == 10 or cm == 11) and hush.settings.highwind == true) then
        if(is_highwind(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush /yelled messages..
    if (cm == 11) then
        -- Hush remote /yells..
        if (hush.settings.remote == true and not is_local(e)) then
            e.blocked = true;
            return;
        end

        -- Hush local /yells..
        if (hush.settings.hushLocal == true and is_local(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush others' synthesis results..
    if (cm == 121 and hush.settings.synth == true) then
        if(is_synth(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush others' fishing results..
    if (cm == 142 and hush.settings.fish == true) then
        if(is_fish(e)) then
            e.blocked = true;
            return;
        end
    end

    -- Hush others' defeated enemies..
    if (cm == 44 and hush.settings.defeats == true) then
        if(is_defeats(e)) then
            e.blocked = true;
			return;
		end
    end

    -- Hush Goblin Merrymakers..
    if (cm == 142 and hush.settings.merrymaker == true) then
        if(is_merrymaker(e)) then
            e.blocked = true;
			return;
		end
    end

    -- Hush command errors..
    if (cm == 157 and hush.settings.cmderror == true) then
        if(is_cmd_error(e)) then
            e.blocked = true;
			return;
		end
    end

    return;
end);
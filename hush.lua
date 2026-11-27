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
addon.version   = '1.5.6';
addon.desc      = 'Hides yells, teleport requests, Eco-Warrior, and other annoying messages.';
addon.link      = 'https://github.com/clanofartisans/ashita-hush';

require('common');
local chat = require('chat');
local imgui = require('imgui');
local settings = require('settings');
local partyMgr = AshitaCore:GetMemoryManager():GetParty();

-- Hush Variables
local hush = T{
    --[[
    * Towns whose /yells can be "local". Each entry lists the zone ids that make up the town and the
    * tags its /yells carry (the zone's short name, as in "Name[LowJeuno]: text"). Zones that share
    * an entry are local to each other: Selbina/Mhaura (the ferry) and Whitegate/Al Zahbi.
    --]]
    towns = T{
        -- San d'Oria..
        {
            zones = T{ 230, 231, 232, 233 },
            tags  = T{ '[ChatdOrag]: ', '[NSandOria]: ', '[PSandOria]: ', '[SSandOria]: ' }
        },
        -- Bastok..
        {
            zones = T{ 234, 235, 236, 237 },
            tags  = T{ '[BastokMark]: ', '[BastokMine]: ', '[Metalworks]: ', '[PortBastok]: ' }
        },
        -- Windurst..
        {
            zones = T{ 238, 239, 240, 241, 242 },
            tags  = T{ '[HeavenTowr]: ', '[PortWind]: ', '[WindWalls]: ', '[WindWaters]: ', '[WindWoods]: ' }
        },
        -- Jeuno..
        {
            zones = T{ 243, 244, 245, 246 },
            tags  = T{ '[LowJeuno]: ', '[PortJeuno]: ', '[RuLudeGard]: ', '[UpJeuno]: ' }
        },
        -- Selbina/Mhaura..
        { zones = T{ 248, 249 }, tags = T{ '[Mhaura]: ', '[Selbina]: ' } },
        -- Aht Urhgan Whitegate/Al Zahbi..
        { zones = T{ 48, 50 }, tags = T{ '[AlZahbi]: ', '[Whitegate]: ' } },
        -- Rabao, Kazham, Norg, Tavnazian Safehold and Nashmau..
        { zones = T{ 247 }, tags = T{ '[Rabao]: ' } },
        { zones = T{ 250 }, tags = T{ '[Kazham]: ' } },
        { zones = T{ 252 }, tags = T{ '[Norg]: ' } },
        { zones = T{ 26 }, tags = T{ '[TavSafehld]: ' } },
        { zones = T{ 53 }, tags = T{ '[Nashmau]: ' } }
    },
    teleports = T{
        '{Teleport-Altep}',
        '{Teleport-Dem}',
        '{Teleport-Holla}',
        '{Teleport-Mea}',
        '{Teleport-Yhoat}',
        '{Teleport-Vahzl}'
    },
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
* @param {table} e - The text_in event.
* @return {bool} True if the message contains the player's name, otherwise false.
--]]
local function contains_name(e)
    local name = partyMgr:GetMemberName(0);
    return name ~= nil and e.message_modified:lower():contains(name:lower());
end

--[[
* Returns the ID for the player's current zone.
*
* @return {int} The current zone ID.
--]]
local function get_zone()
    return partyMgr:GetMemberZone(0);
end

--[[
* Determines if the message is part of a "command error".
*
* @param {table} e - The text_in event.
* @return {bool} True if the message is part of a "command error", otherwise false.
--]]
local function is_cmd_error(e)
    local msg = clean_str(e.message_modified);

    -- Find command errors..
    return (msg:contains('A command error occurred') or msg:contains('>> '));
end

--[[
* Determines if the message is another player's defeated enemy.
*
* @param {table} e - The text_in event.
* @return {bool} True if the message is another player's defeated enemy, otherwise false.
--]]
local function is_defeats(e)
    local msg = clean_str(e.message_modified);

    -- Find others' defeated enemies..
    return msg:contains(' defeats ');
end

--[[
* Determines if the message is another player's fishing result.
*
* @param {table} e - The text_in event.
* @return {bool} True if the message is another player's fishing results, otherwise false.
--]]
local function is_fish(e)
    local msg = clean_str(e.message_modified);

    -- Find others' fishing results..
    return (msg:contains(' caught ') and not contains_name(e) and not msg:contains('Something'));
end

--[[
* Determines if the message was sent by a GM. Only the sender is checked (the text before the first
* ": ", as in "[GM]Name : text"), and player names are letters only, so a player can't pass for a
* GM by typing "[GM]" into their message.
*
* @param {table} e - The text_in event.
* @return {bool} True if a GM sent the message, otherwise false.
--]]
local function is_gm(e)
    local msg = clean_str(e.message_modified);
    local sender = msg:match('^(.-) ?: ');

    return (sender ~= nil and sender:contains('[GM]'));
end

--[[
* Determines if the message is HorizonXI's announcement that a hardcore adventurer has died:
* "Name has fallen as a hardcore adventurer. While playing as: ...". It has no " : " sender, which
* every player's shout does, so a player can't pass for one by shouting the same words.
*
* @param {table} e - The text_in event.
* @return {bool} True if it's a hardcore-death announcement, otherwise false.
--]]
local function is_hardcore_death(e)
    local msg = clean_str(e.message_modified);

    return (msg:contains(' has fallen as a hardcore adventurer.') and not msg:contains(' : '));
end

--[[
* Determines if a message is "local" or not.
*
* @param {table} e - The text_in event.
* @return {bool} True if local, otherwise false.
--]]
local function is_local(e)
    local zone = get_zone();
    if (zone == nil) then
        return false;
    end

    -- Find the town the player is in; outside a known town, every /yell is remote..
    local _, town = hush.towns:find_if(function (v)
        return v.zones:contains(zone);
    end);

    if (town == nil) then
        return false;
    end

    -- Local if the /yell carries one of the town's tags..
    local msg = clean_str(e.message_modified);
    return town.tags:any(function (v)
        return msg:contains(v);
    end);
end

--[[
* Determines if the message is another player's synthesis result.
*
* @param {table} e - The text_in event.
* @return {bool} True if someone else's result, otherwise false.
--]]
local function is_synth(e)
    local msg = clean_str(e.message_modified);

    -- Find successful synthesis, then failed synthesis..
    return ((msg:contains(' synthesized ') and not msg:contains('You synthesized '))
        or (msg:contains(' lost ') and not msg:contains('You lost ')));
end

--[[
* Determines if the message is a teleport request or advertisement.
*
* @param {table} e - The text_in event.
* @return {bool} True if it's teleport related, otherwise false.
--]]
local function is_teleport(e)
    local msg = clean_str(e.message_modified);

    -- Find auto-translate teleports, then taxi teleports..
    return (hush.teleports:any(function (v)
            return msg:contains(v);
        end)
        or (msg:contains('Dem') and msg:contains('Holla') and msg:contains('Mea')));
end

--[[
* Determines if the message is a Eco-Warrior request or advertisement.
*
* @param {table} e - The text_in event.
* @return {bool} True if it's Eco-Warrior related, otherwise false.
--]]
local function is_ecowarrior(e)
    local msg = clean_str(e.message_modified);

    -- Find the word "eco" at the start of a word, so not inside "second" or "become"..
    return (msg:lower():match('%f[%a]eco') ~= nil and not contains_name(e));
end

--[[
* Determines if the message is a Highwind shout.
*
* @param {table} e - The text_in event.
* @return {bool} True if it's Highwind related, otherwise false.
--]]
local function is_highwind(e)
    local msg = clean_str(e.message_modified):lower();

    -- Find the word "highwind", hopefully including if it's misspelled or split ("high wind"),
    -- but only where "hi" starts a word, so not "this Wind Crystal" or a "Name[WindWoods]: " yell..
    return ((msg:match('%f[%a]hi%a*%s?wind') or msg:match(' hw')) ~= nil and not contains_name(e));
end

--[[
* Determines if the message is a Goblin Merrymaker.
*
* @param {table} e - The text_in event.
* @return {bool} True if it's a Goblin Merrymaker, otherwise false.
--]]
local function is_merrymaker(e)
    local msg = clean_str(e.message_modified);

    -- Find the NPC name..
    return msg:contains('Goblin Merrymaker');
end

--[[
* The filters, in the settings window's order. Each has its settings key, its checkbox label and
* ImGui id, the chat modes it runs on and its test. The settings keys are saved per character, so
* never rename one (hushLocal included).
--]]
hush.filters = T{
    { key = 'remote',     label = 'Hush remote /yells',                   id = 'HushRemoteCheck',     modes = T{ 11 },     test = function (e) return not is_local(e); end },
    { key = 'hushLocal',  label = 'Hush local /yells',                    id = 'HushLocalCheck',      modes = T{ 11 },     test = is_local },
    { key = 'teleport',   label = 'Hush teleport shouts/yells',           id = 'HushTeleportCheck',   modes = T{ 10, 11 }, test = is_teleport },
    { key = 'ecowarrior', label = 'Hush Eco-Warrior shouts/yells',        id = 'HushEcoWarriorCheck', modes = T{ 10, 11 }, test = is_ecowarrior },
    { key = 'highwind',   label = 'Hush Highwind shouts/yells',           id = 'HushHighwindCheck',   modes = T{ 10, 11 }, test = is_highwind },
    { key = 'allshouts',  label = 'Hush all shouts',                      id = 'HushAllShoutsCheck',  modes = T{ 10 },     test = function () return true; end },
    { key = 'synth',      label = 'Hush others\' synthesis results',      id = 'HushSynthCheck',      modes = T{ 121 },    test = is_synth },
    { key = 'fish',       label = 'Hush others\' fishing results',        id = 'HushFishCheck',       modes = T{ 142 },    test = is_fish },
    { key = 'defeats',    label = 'Hush others\' defeated enemies',       id = 'HushDefeatsCheck',    modes = T{ 44 },     test = is_defeats },
    { key = 'merrymaker', label = 'Hush Goblin Merrymakers',              id = 'HushMerrymakerCheck', modes = T{ 142 },    test = is_merrymaker },
    { key = 'cmderror',   label = 'Hush "command errors" (experimental)', id = 'HushCmdErrCheck',     modes = T{ 157 },    test = is_cmd_error },
};

-- Default Settings: every filter off..
local default_settings = T{};
for _, v in ipairs(hush.filters) do
    default_settings[v.key] = false;
end

hush.settings = settings.load(default_settings);

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
        for _, v in ipairs(hush.filters) do
            if (imgui.Checkbox(('%s##%s'):fmt(v.label, v.id), { hush.settings[v.key] })) then
                hush.settings[v.key] = not hush.settings[v.key];
                update_settings();
            end
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

    -- Handle: /hush - Opens or closes the configuration window.
    if (#args == 1) then
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

    -- Never hush a GM's shouts or /yells..
    if ((cm == 10 or cm == 11) and is_gm(e)) then
        return;
    end

    -- Never hush a hardcore-death announcement..
    if (cm == 10 and is_hardcore_death(e)) then
        return;
    end

    -- Hush the line if any filter that's on, and runs on its chat mode, matches it..
    for _, v in ipairs(hush.filters) do
        if (hush.settings[v.key] == true and v.modes:contains(cm) and v.test(e)) then
            e.blocked = true;
            return;
        end
    end
end);
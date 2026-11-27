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
addon.version   = '1.7.0';
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
* Determines if the message is another player's emote. Every line on the emote mode is someone's
* emote, so only the player's own and those aimed at the player are kept.
*
* @param {table} e - The text_in event.
* @return {bool} True if the message is another player's emote, otherwise false.
--]]
local function is_emote(e)
    -- Find others' emotes, except those aimed at the player..
    return (not contains_name(e));
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
* Determines if the emote was made by a GM, as in "[GM]Name makes like a tree…". An emote has no
* ": " sender, and its text is free, so a player's "/em [GM]: hi" would fool is_gm. But an emote
* starts with the actor's name, and player names are letters only, so only a GM's starts "[GM]".
*
* @param {table} e - The text_in event.
* @return {bool} True if a GM made the emote, otherwise false.
--]]
local function is_gm_emote(e)
    local msg = clean_str(e.message_modified);

    return (msg:match('^%[GM%]') ~= nil);
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
* Determines if the message is another player's /random roll: "Dice roll! Name rolls 657!". The
* player's own rolls come in the same shape, so the roller's name is compared with the player's.
*
* @param {table} e - The text_in event.
* @return {bool} True if someone else's roll, otherwise false.
--]]
local function is_random(e)
    local msg = clean_str(e.message_modified);
    local roller = msg:match('^Dice roll! (%a+) rolls %d+!');

    -- Find others' rolls..
    return (roller ~= nil and roller ~= partyMgr:GetMemberName(0));
end

--[[
* Determines if the message is another player's synthesis result.
*
* @param {table} e - The text_in event.
* @return {bool} True if someone else's result, otherwise false.
--]]
local function is_synth(e)
    local msg = clean_str(e.message_modified);

    -- Find successful synthesis, then "Name obtained …" (seen since August 2026; the player's own
    -- form is unknown, so a line with the player's name stays), then failed synthesis..
    return ((msg:contains(' synthesized ') and not msg:contains('You synthesized '))
        or (msg:contains(' obtained ') and not msg:contains('You obtained ') and not contains_name(e))
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
    { key = 'random',     label = 'Hush others\' /random rolls',          id = 'HushRandomCheck',     modes = T{ 121 },    test = is_random },
    { key = 'emote',      label = 'Hush others\' emotes',                 id = 'HushEmoteCheck',      modes = T{ 15 },     test = is_emote },
    { key = 'cmderror',   label = 'Hush "command errors" (experimental)', id = 'HushCmdErrCheck',     modes = T{ 157 },    test = is_cmd_error },
};

-- Default Settings: every filter off..
local default_settings = T{};
for _, v in ipairs(hush.filters) do
    default_settings[v.key] = false;
end

hush.settings = settings.load(default_settings);

--[[
* Debug mode records what Hush decides about each line of chat to a file, to help with "I'm still
* seeing X" reports. It's never saved, so it ends on a reload, logout or character switch.
--]]
hush.debug = T{
    on   = false,   -- Recording..
    all  = false,   -- ..every chat mode, not only the ones Hush's filters run on..
    path = nil,     -- The current record..
    zone = nil,     -- The zone last written to it..
};

-- The chat modes Hush's filters run on..
hush.modes = T{};
for _, v in ipairs(hush.filters) do
    for _, m in ipairs(v.modes) do
        if (not hush.modes:contains(m)) then
            hush.modes:append(m);
        end
    end
end

--[[
* Returns a zone's id and name, as in "245 Lower Jeuno".
*
* @param {number} zone - The zone id.
* @return {string} The zone's id and name.
--]]
local function zone_name(zone)
    return ('%d %s'):fmt(zone, AshitaCore:GetResourceManager():GetString('zones.names', zone) or '(unknown)');
end

--[[
* Appends a line to the debug record. A failure raises an error; run it through debug_safely.
*
* @param {string} line - The line to write.
--]]
local function debug_write(line)
    local f = assert(io.open(hush.debug.path, 'a'));
    f:write(line .. '\n');
    f:close();
end

--[[
* Returns which chat modes the debug record covers, in words.
*
* @return {string} The scope.
--]]
local function debug_scope()
    return hush.debug.all and 'every chat mode' or 'Hush\'s chat modes';
end

--[[
* Stops debug mode, if it's on.
*
* @param {string} reason - Why it stopped, when it wasn't asked to. (Optional.)
--]]
local function debug_stop(reason)
    if (not hush.debug.on) then
        return;
    end

    hush.debug.on = false;
    hush.debug.all = false;
    pcall(debug_write, '-- stopped: ' .. os.date('%Y-%m-%d %H:%M:%S'));

    local msg = (reason ~= nil) and ('Debug off (%s). The record is '):fmt(reason) or 'Debug off. The record is ';
    print(chat.header(addon.name):append(chat.message(msg)):append(chat.success(hush.debug.path)));
end

--[[
* Runs a debug function so that a failure in it switches debug off instead of raising an error,
* so debug mode can never get in the way of hushing.
*
* @param {function} f - The function to run.
* @param {any} ... - Its arguments.
--]]
local function debug_safely(f, ...)
    local ok, err = pcall(f, ...);
    if (not ok) then
        if (hush.debug.on) then
            debug_stop('error: ' .. tostring(err));
        else
            print(chat.header(addon.name):append(chat.error('Debug couldn\'t start: ' .. tostring(err))));
        end
    end
end

--[[
* Starts debug mode, or changes which chat modes it covers if it's already on.
*
* @param {boolean} all - True to record every chat mode, false for only the ones Hush's filters run on.
--]]
local function debug_start(all)
    if (hush.debug.on) then
        if (hush.debug.all ~= all) then
            hush.debug.all = all;
            debug_write('-- scope: ' .. debug_scope());
        end
    else
        local name = partyMgr:GetMemberName(0);
        if (name == nil or name:len() == 0) then
            print(chat.header(addon.name):append(chat.error('Log in to a character before turning debug on.')));
            return;
        end

        local dir = ('%s\\config\\addons\\%s\\debug\\'):fmt(AshitaCore:GetInstallPath(), addon.name);
        if (not ashita.fs.exists(dir)) then
            ashita.fs.create_dir(dir);
        end

        hush.debug.path = ('%s%s_%s.log'):fmt(dir, name, os.date('%Y.%m.%d_%H%M%S'));
        hush.debug.all = all;
        hush.debug.zone = get_zone() or 0;

        -- Every filter, on or off..
        local filters = T{};
        for _, v in ipairs(hush.filters) do
            filters:append(('%s %s'):fmt(v.key, (hush.settings[v.key] == true) and 'on' or 'off'));
        end

        -- The loaded addons in Ashita's order, with their versions, where this Ashita can list them..
        local addons = T{};
        if (AddonManager == nil) then
            addons:append('(AddonManager unavailable)');
        else
            for n = 0, AddonManager:Count() - 1 do
                local a = AddonManager:Get(n);
                if (a ~= nil) then
                    local ok, ver = pcall(function () return AddonManager:GetVersion(a); end);
                    addons:append(('%s %s'):fmt(a, ok and tostring(ver) or '(no version)'));
                end
            end
        end

        debug_write(('-- Hush %s debug record'):fmt(addon.version));
        debug_write('-- started: ' .. os.date('%Y-%m-%d %H:%M:%S'));
        debug_write('-- character: ' .. name);
        debug_write('-- zone: ' .. zone_name(hush.debug.zone));
        debug_write('-- scope: ' .. debug_scope());
        debug_write('-- filters: ' .. table.concat(filters, ', '));
        debug_write('-- addons: ' .. table.concat(addons, ', '));
        hush.debug.on = true;
    end

    print(chat.header(addon.name):append(chat.message(('Debug on (%s). Recording to '):fmt(debug_scope()))):append(chat.success(hush.debug.path)));
end

--[[
* Writes a chat line, and what Hush decided about it, to the debug record.
*
* @param {table} e - The text_in event.
* @param {number} cm - The line's chat mode.
* @param {boolean} pre - True if another addon had blocked the line before Hush saw it.
* @param {string} exempt - 'gm' or 'hardcore' if the line is never hushed, otherwise nil.
* @param {table} hushed - The filter that hushed the line, otherwise nil.
--]]
local function debug_line(e, cm, pre, exempt, hushed)
    local watched = hush.modes:contains(cm);
    if (not watched and not hush.debug.all) then
        return;
    end

    -- A "-- zone:" line first, if the zone has changed..
    local zone = get_zone() or 0;
    if (zone ~= hush.debug.zone) then
        hush.debug.zone = zone;
        debug_write('-- zone: ' .. zone_name(zone));
    end

    -- Every other filter on this chat mode that matches the line, on or off..
    local matches = T{};
    if (watched) then
        for _, v in ipairs(hush.filters) do
            if (v ~= hushed and v.modes:contains(cm) and v.test(e)) then
                matches:append(('%s %s'):fmt(v.key, (hush.settings[v.key] == true) and 'on' or 'off'));
            end
        end
    end

    -- The verdict; a line on a chat mode no filter runs on gets none..
    local verdict = '';
    if (exempt ~= nil) then
        verdict = 'exempt: ' .. exempt;
    elseif (hushed ~= nil) then
        verdict = 'hushed: ' .. hushed.key;
    elseif (watched) then
        verdict = 'shown';
    end
    if (#matches > 0) then
        verdict = verdict .. ((verdict == 'shown') and ': ' or '; ') .. table.concat(matches, ', ');
    end
    if (pre) then
        verdict = (verdict:len() > 0) and ('pre-blocked; ' .. verdict) or 'pre-blocked';
    end

    -- One line per entry, so line breaks in the text are written as "\n"..
    local text = clean_str(e.message_modified):gsub('\r', ''):gsub('[\n\7]', '\\n');
    debug_write(('[%s] %-5s %-28s | %s'):fmt(os.date('%H:%M:%S'), ('[%d]'):fmt(cm), verdict, text));
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
        { '/hush debug', 'Records what Hush decides about each line of chat to a file.' },
        { '/hush debug all', 'The same, for every chat mode.' },
        { '/hush debug off', 'Stops recording.' },
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
        debug_stop('character changed or logged out');
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

                if (hush.debug.on) then
                    debug_safely(debug_write, ('-- setting: %s %s'):fmt(v.key, hush.settings[v.key] and 'on' or 'off'));
                end
            end
        end

        -- Debug mode; ticking "every chat mode" turns debug on too, and unticking debug clears both..
        imgui.Separator();
        if (imgui.Checkbox('Debug: record what Hush decides##HushDebugCheck', { hush.debug.on })) then
            if (hush.debug.on) then
                debug_stop();
            else
                debug_safely(debug_start, false);
            end
        end
        if (imgui.Checkbox('...for every chat mode##HushDebugAllCheck', { hush.debug.all })) then
            debug_safely(debug_start, not hush.debug.all);
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

    -- Handle: /hush debug [all | off] - Records what Hush decides to a file, or stops..
    if (args[2]:any('debug')) then
        if (#args == 2) then
            debug_safely(debug_start, false);
        elseif (#args == 3 and args[3]:any('all')) then
            debug_safely(debug_start, true);
        elseif (#args == 3 and args[3]:any('off')) then
            if (hush.debug.on) then
                debug_stop();
            else
                print(chat.header(addon.name):append(chat.message('Debug is already off.')));
            end
        else
            print_help(true);
        end
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
    local pre = (e.blocked == true);

    -- Never hush a GM's shouts, /yells or emotes, or a hardcore-death announcement..
    local exempt = nil;
    if ((cm == 10 or cm == 11) and is_gm(e)) then
        exempt = 'gm';
    elseif (cm == 15 and is_gm_emote(e)) then
        exempt = 'gm';
    elseif (cm == 10 and is_hardcore_death(e)) then
        exempt = 'hardcore';
    end

    -- Otherwise, hush the line if any filter that's on, and runs on its chat mode, matches it..
    local hushed = nil;
    if (exempt == nil) then
        for _, v in ipairs(hush.filters) do
            if (hush.settings[v.key] == true and v.modes:contains(cm) and v.test(e)) then
                hushed = v;
                e.blocked = true;
                break;
            end
        end
    end

    -- Record the decision, if debug is on..
    if (hush.debug.on) then
        debug_safely(debug_line, e, cm, pre, exempt, hushed);
    end
end);

--[[
* event: packet_in
* desc : Event called when the addon is processing incoming packets.
--]]
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- Packet: Zone Exit, to the title screen (a logout), which ends debug mode..
    if (e.id == 0x000B and struct.unpack('b', e.data, 0x04 + 0x01) == 1) then
        debug_stop('logged out');
    end
end);
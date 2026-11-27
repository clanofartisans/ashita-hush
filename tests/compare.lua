--[[
compare.lua -- run two copies of hush.lua over mode-tagged chat logs and compare what each hushes.

Usage:
  luajit tests/compare.lua --libs DIR --logs DIR OLD.lua NEW.lua [--debug OUTDIR]

  --libs DIR    Ashita's addons/libs folder (common, chat and the string and table helpers
                load from here, so they behave as they do in the game).
  --logs DIR    A folder of chat logs from Ashita's logs addon, edited to write each line's chat
                mode first ("121 [hh:mm:ss] text"). Searched recursively for *.log; lines without
                a mode are skipped.
  OLD.lua       The version to compare against, e.g. from `git show <commit>:hush.lua`.
  NEW.lua       The version under test.
  --debug DIR   Also switch NEW's debug mode on (`/hush debug all`) for the every-filter run, with
                its records written under DIR, then print the start of the record and a count of
                its verdicts, and run a short spot check of the verdicts that run can't produce.
                Use an empty DIR: the full run's record is about 100 MB.

Every line runs with every filter on, then with each filter on alone. Yells (mode 11) also run in
several zones, since whether a yell is local depends on where the player stands. The player is
"Hugin". The two versions must hush exactly the same lines in every run.

Exit codes: 0 identical, 1 differences found, 2 usage error.
--]]

local libs, logs, debug_dir, files = nil, nil, nil, {}
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == '--libs' then i = i + 1; libs = arg[i]
    elseif a == '--logs' then i = i + 1; logs = arg[i]
    elseif a == '--debug' then i = i + 1; debug_dir = arg[i]
    else files[#files + 1] = a end
    i = i + 1
end
if not libs or not logs or #files ~= 2 then
    io.stderr:write('usage: luajit compare.lua --libs DIR --logs DIR OLD.lua NEW.lua [--debug OUTDIR]\n')
    os.exit(2)
end

package.path = libs .. '/?.lua;' .. libs .. '/?/init.lua;' .. package.path

-- Stand-ins for what Ashita provides in the game ------------------------------------------------

local PLAYER = 'Hugin'
local ZONE = 245 -- Lower Jeuno
local YELL_ZONES = { 100, 245, 249, 250, 50, 53 } -- West Ronfaure (no town), Lower Jeuno, Selbina, Kazham, Whitegate, Nashmau

local function unix(path) return (path:gsub('\\', '/')) end

local party = {
    GetMemberName = function () return PLAYER end,
    GetMemberZone = function () return ZONE end,
}
AshitaCore = {
    GetMemoryManager = function () return { GetParty = function () return party end } end,
    -- The logs addon already wrote the cleaned text, so auto-translate parsing is a no-op here.
    GetChatManager = function () return { ParseAutoTranslate = function (_, s) return s end } end,
    GetInstallPath = function () return debug_dir or '.' end,
    GetResourceManager = function () return { GetString = function (_, _, id) return 'Zone ' .. tostring(id) end } end,
}
AddonManager = {
    Count = function () return 2 end,
    Get = function (_, n) return ({ [0] = 'hush', [1] = 'fancychat' })[n] end,
    GetVersion = function (_, name) return name == 'hush' and 'test' or '1.0' end,
}

local handlers -- the events the version being loaded registers
ashita = {
    events = { register = function (event, _, fn) handlers[event] = fn end },
    fs = {
        exists = function (p) return os.rename(unix(p), unix(p)) ~= nil end,
        create_dir = function (p) return os.execute(("mkdir -p '%s'"):format(unix(p))) end,
    },
}
local real_open = io.open
---@diagnostic disable-next-line: duplicate-set-field
io.open = function (p, mode) return real_open(unix(p), mode) end

local loaded_settings
package.preload['imgui'] = function () return setmetatable({}, { __index = function () return function () end end }) end
package.preload['settings'] = function ()
    return {
        load = function (defaults)
            loaded_settings = {}
            for k, v in pairs(defaults) do loaded_settings[k] = v end
            return loaded_settings
        end,
        save = function () end,
        register = function () end,
    }
end

require('common')

local function load_version(path)
    handlers, loaded_settings = {}, nil
    addon = {}
    local chunk = assert(loadfile(path))
    chunk()
    assert(handlers.text_in, path .. ' registered no text_in handler')
    return { path = path, text_in = handlers.text_in, command = handlers.command, settings = loaded_settings }
end

local old = load_version(files[1])
local new = load_version(files[2])

-- The chat lines ------------------------------------------------------------------------------

local lines = {}
local p = assert(io.popen(("find '%s' -type f -name '*.log' | sort"):format(logs)))
for path in p:lines() do
    local f = assert(real_open(path, 'rb'))
    for raw in f:lines() do
        local m, text = raw:gsub('\r$', ''):match('^(%d+) %[%d%d:%d%d:%d%d%] (.*)$')
        if m then lines[#lines + 1] = { tonumber(m), text } end
    end
    f:close()
end
p:close()
if #lines == 0 then
    io.stderr:write('no mode-tagged lines under ' .. logs .. '\n')
    os.exit(2)
end

-- The runs ------------------------------------------------------------------------------------

local keys = {}
for k in pairs(old.settings) do keys[#keys + 1] = k end
table.sort(keys)

local function set_all(v, on)
    for _, k in ipairs(keys) do v.settings[k] = (on == true) or (on == k) end
end

local function hushes(v, mode, text)
    local e = { mode = mode, message = text, message_modified = text, blocked = false }
    v.text_in(e)
    return e.blocked
end

local runs = { { name = 'every filter', on = true } }
for _, k in ipairs(keys) do runs[#runs + 1] = { name = k, on = k } end

local differences, shown = 0, 0
print(('%d mode-tagged lines from %s'):format(#lines, logs))
print(('%-14s %10s %10s'):format('run', 'old hushes', 'new hushes'))
for n, run in ipairs(runs) do
    set_all(old, run.on); set_all(new, run.on)
    if n == 1 and debug_dir then
        assert(new.command, 'NEW registered no command handler')
        new.command({ command = '/hush debug all', blocked = false })
    end
    local counts = { 0, 0 }
    for _, l in ipairs(lines) do
        local zones = (l[1] == 11) and YELL_ZONES or { 245 }
        for _, z in ipairs(zones) do
            ZONE = z
            local a, b = hushes(old, l[1], l[2]), hushes(new, l[1], l[2])
            if a then counts[1] = counts[1] + 1 end
            if b then counts[2] = counts[2] + 1 end
            if a ~= b then
                differences = differences + 1
                if shown < 10 then
                    shown = shown + 1
                    print(('  DIFF [%s, zone %d] mode %d: old %s, new %s | %s'):format(run.name, z, l[1], tostring(a), tostring(b), l[2]))
                end
            end
        end
    end
    ZONE = 245
    if n == 1 and debug_dir then new.command({ command = '/hush debug off', blocked = false }) end
    print(('%-14s %10d %10d'):format(run.name, counts[1], counts[2]))
end

if debug_dir then
    local q = assert(io.popen(("find '%s' -type f -name '*.log' | sort | tail -1"):format(debug_dir)))
    local record = q:read('*l'); q:close()
    print('\ndebug record: ' .. tostring(record))
    if record then
        local tally, n = {}, 0
        for l in assert(real_open(record)):lines() do
            n = n + 1
            if n <= 25 then print('  ' .. l) end
            local verdict = l:match('^%[%d%d:%d%d:%d%d%] %[%d+%] *([^|]-) *|')
            if verdict then
                local word = verdict:match('^(%a[%a-]*)') or '(blank)'
                tally[word] = (tally[word] or 0) + 1
            end
        end
        print('verdicts:')
        for w, c in pairs(tally) do print(('  %-12s %d'):format(w, c)) end
    end

    -- Spot check: the verdicts the full run can't produce, with only "fish" on. Expected record
    -- lines: "shown: synth off", "shown", "hushed: fish", "pre-blocked; shown: synth off", then a
    -- "-- scope:" line and "pre-blocked" for the mode-36 line (skipped until every mode is on).
    print('\nspot check:')
    set_all(new, 'fish')
    os.execute('sleep 1') -- a new record name, one second on from the last
    local function feed(mode, text, pre)
        local e = { mode = mode, message = text, message_modified = text, blocked = pre or false }
        new.text_in(e)
        return e.blocked
    end
    new.command({ command = '/hush debug', blocked = false })
    feed(121, 'Mandy synthesized a bronze ingot.')
    feed(121, 'You find an earth crystal on the Goblin.')
    feed(142, 'Mandy caught a moat carp!')
    feed(121, 'Mandy synthesized a bronze ingot.', true)
    feed(36, 'Hugin defeats the Goblin.', true)
    new.command({ command = '/hush debug all', blocked = false })
    feed(36, 'Hugin defeats the Goblin.', true)
    new.command({ command = '/hush debug off', blocked = false })
    new.command({ command = '/hush debug off', blocked = false })
    local q2 = assert(io.popen(("find '%s' -type f -name '*.log' | sort | tail -1"):format(debug_dir)))
    local spot = q2:read('*l'); q2:close()
    for l in assert(real_open(spot)):lines() do print('  ' .. l) end
end

print(differences == 0 and '\nidentical' or ('\n%d differences'):format(differences))
os.exit(differences == 0 and 0 or 1)

-- Chronicle / Bestiary: the creatures of each land, told by someone who lives beside them (a player's idea, after
-- Diablo III's bestiary). A zone's notable groups (the Burning Blade, Zalazane's trolls, the Defias) and its beasts by
-- family (every colour of scorpid is one) have a few entries each, in the voice a local has for their own quests: the
-- first opens at this character's first kill of the group, the next after more kills. A new entry is offered as a note
-- once the fight is over; nothing plays unless you click Listen. The journal's Bestiary tab keeps them to hear, or
-- read, again, each creature with its model. A teller of one faction tells only that side. Kills are seen as the
-- famous rares see them (Rares.lua: your target dead when the fight ends, or a body you loot), each body counted once.
local _, ns = ...
local L = ns.L
local B = {}
ns.Bestiary = B

local counted, countedN = {}, 0 -- bodies counted already (dead as your target when the fight ends, then looted: one kill)
local waiting = {}              -- entries opened in a fight, or while another note was up: offered in turn
local flushing                  -- a look at the waiting entries is planned

local function data() return ns.Lore and ns.Lore.bestiary end

function B.Group(gid)
    local d = data()
    return d and d.groups and d.groups[gid]
end

function B.Key(gid, n) return ("beast:%s:%d"):format(gid, n) end

-- a group this character's side is told: a teller of one faction (Gryan Stoutmantle, Orgnil Soulscar) talks only to
-- that side, a neutral one (Hemet Nesingwary, the goblins) to both
function B.Mine(g)
    return g ~= nil and (not g.side or g.side == UnitFactionGroup("player"))
end

-- the groups a creature counts for: one, or one for each side (each told by its own people)
local function groupsOf(id)
    local d = data()
    local gids = d and d.npcs and id and d.npcs[id]
    if type(gids) == "table" then return gids end
    return gids and { gids } or {}
end

-- how many of a group this character has slain
function B.Kills(gid) return ((ns.char and ns.char.bestiary) or {})[gid] or 0 end

-- entry n of a group: open once this character has slain enough of them
function B.Unlocked(gid, n)
    local g = B.Group(gid)
    local need = g and g.need and g.need[n]
    return need ~= nil and B.Kills(gid) >= need
end

-- a zone's entries this character has opened, by group and in order; and how many the zone has in all
function B.ZoneEntries(zone)
    local out, total = {}, 0
    local d = data()
    for gid, g in pairs((d and d.groups) or {}) do
        if g.zone == zone and B.Mine(g) then
            for n = 1, #(g.need or {}) do
                total = total + 1
                if B.Unlocked(gid, n) then
                    out[#out + 1] = { gid = gid, n = n, name = g.name, who = g.who, text = g.text and g.text[n],
                        key = B.Key(gid, n) }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.n < b.n end)
    return out, total
end

-- the whole bestiary, for the journal's Bestiary page: every zone with the creatures this character has met there (slain
-- at least once: the entries opened, the kills, and how many the next entry needs), the others only counted, never named.
-- Only the groups told to this character's side. Zones with an opened entry first, then by name; a zone's creatures by
-- name.
local function bookGroup(book, byZone, gid, g)
    local z = byZone[g.zone]
    if not z then
        z = { zone = g.zone, groups = {}, found = 0, total = 0, unmet = 0, unmetNames = {} }
        byZone[g.zone] = z; book.zones[#book.zones + 1] = z
    end
    local kills = B.Kills(gid)
    local entries, nextNeed = {}, nil
    for n, need in ipairs(g.need or {}) do
        z.total, book.total = z.total + 1, book.total + 1
        if kills >= need then
            z.found, book.found = z.found + 1, book.found + 1
            entries[#entries + 1] = { n = n, key = B.Key(gid, n), text = g.text and g.text[n] }
        elseif not nextNeed then
            nextNeed = need
        end
    end
    if kills > 0 then
        book.met = book.met + 1
        z.groups[#z.groups + 1] = { gid = gid, name = g.name, who = g.who, kills = kills, entries = entries,
            nextNeed = nextNeed, total = #(g.need or {}) }
    else
        z.unmet = z.unmet + 1
        -- named only with Show what's left (a player on CurseForge: "And maybe for the Bestiary too?")
        z.unmetNames[#z.unmetNames + 1] = g.name
    end
end

function B.Book()
    local d = data()
    local zones, byZone = {}, {}
    local book = { zones = zones, found = 0, total = 0, met = 0 }
    for gid, g in pairs((d and d.groups) or {}) do
        if B.Mine(g) then bookGroup(book, byZone, gid, g) end
    end
    for _, z in ipairs(zones) do
        table.sort(z.groups, function(a, b) return a.name < b.name end)
        table.sort(z.unmetNames)
    end
    table.sort(zones, function(a, b)
        if (a.found > 0) ~= (b.found > 0) then return a.found > 0 end
        return a.zone < b.zone
    end)
    return book
end

local function fighting() return InCombatLockdown() or UnitAffectingCombat("player") end

local function show(gid, n)
    local g = B.Group(gid)
    if not (g and ns.Reminder and ns.Reminder.ShowStory) then return end
    local line = (n == 1 and L["Told by %s"] or L["More from %s"]):format(g.who or "")
    ns.Reminder.ShowStory((L["Bestiary: %s"]):format(g.name), g.text and g.text[n], { B.Key(gid, n) },
        function() ns.Journal.ShowBestiary(g.zone, gid) end, line, "bestiary")
end

-- the next waiting entry, once the fight is over and no other note is up (one note at a time: it would replace it)
local function flush()
    flushing = nil
    if #waiting == 0 or fighting() then return end -- the end of the fight looks again
    if not ns.settings.bestiary then wipe(waiting) return end -- turned off from a note: the journal has them
    if ns.Reminder and ns.Reminder.Busy and ns.Reminder.Busy() then
        flushing = true
        C_Timer.After(5, flush)
        return
    end
    local w = table.remove(waiting, 1)
    show(w[1], w[2])
    if #waiting > 0 then flushing = true; C_Timer.After(5, flush) end
end

local function offer(gid, n)
    if not ns.settings.bestiary then return end -- still opened: the journal has it
    waiting[#waiting + 1] = { gid, n }
    if not flushing then flush() end
end

-- a body of this npc lies dead, your kill (Rares.lua): one more of its group (the one told to your side), the same body
-- only once
function B.Killed(id, guid)
    local gids = groupsOf(id)
    if #gids == 0 or not ns.char then return end
    if guid then
        if counted[guid] then return end
        if countedN >= 500 then counted, countedN = {}, 0 end -- those bodies are long gone
        counted[guid], countedN = true, countedN + 1
    end
    for _, gid in ipairs(gids) do
        local g = B.Group(gid)
        if B.Mine(g) then
            ns.char.bestiary = ns.char.bestiary or {}
            local before = ns.char.bestiary[gid] or 0
            ns.char.bestiary[gid] = before + 1
            for n, need in ipairs(g.need or {}) do
                if before < need and before + 1 >= need then offer(gid, n) end
            end
        end
    end
end

if ns.Rares and ns.Rares.onKill then table.insert(ns.Rares.onKill, B.Killed) end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() C_Timer.After(1.5, flush) end) -- the fight is over: what opened during it
table.insert(ns.onLogin, function() pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED") end)

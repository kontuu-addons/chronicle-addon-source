-- Chronicle / Endings: a zone's epilogue once its story is done, and a dungeon's ending when its last boss falls.
-- Both are offered with a note (Listen / Journal), never played over the game uninvited.
local _, ns = ...
local L = ns.L
local E = {}
ns.Endings = E

local NEEDED = 0.8 -- share of a zone's story chapters to finish: side paths and pick-one paths need not all be done

local function mySide()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil, f
end

-- The chapters that make up a zone's story for this character: its faction's and the shared ones, without
-- gear, reputation or class chapters.
local function storyArcs(zone)
    local side = mySide()
    local out = {}
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        if a.zone == zone and not a.opt and not a.cls and (not a.side or a.side == side) then out[#out + 1] = a end
    end
    return out
end

-- How far this character is in a zone's story: finished chapters, chapters needed for the epilogue, and the total.
local function startedChapters()
    local started = {}
    for _, ch in ipairs(ns.Journal.BuildChapters()) do started[ch.key] = ch end
    return started
end

function E.ZoneProgress(zone, started)
    local arcs = storyArcs(zone)
    if #arcs < 2 then return 0, 0, #arcs end
    started = started or startedChapters()
    local done = 0
    for _, a in ipairs(arcs) do
        local ch = started["arc:" .. a.id]
        local last = a.quests and a.quests[#a.quests]
        -- finished: every quest of it, or its last step (chapters often hold quests from paths you did not take)
        if ch and (ch.done >= (ch.total or #ch.entries) or (last and ns.char.done[last])) then done = done + 1 end
    end
    return done, math.ceil(#arcs * NEEDED), #arcs
end

function E.EpilogueKey(zone)
    local _, faction = mySide()
    local key = faction and (zone .. "|" .. faction)
    return key and ns.Lore and ns.Lore.epilogue and ns.Lore.epilogue[key] and key or nil
end

function E.HasEpilogue(zone)
    return ns.char.epilogues and ns.char.epilogues[zone] ~= nil
end

-- The road each race's story takes through the world: the old way up from its home, zone by zone (thanks Alche).
local FORSAKEN = { "Tirisfal Glades", "Silverpine Forest", "Hillsbrad Foothills", "Alterac Mountains", "Arathi Highlands",
    "Badlands", "The Hinterlands", "Western Plaguelands", "Eastern Plaguelands" }
local DUROTAR = { "Durotar", "The Barrens", "Stonetalon Mountains", "Ashenvale", "Thousand Needles", "Desolace",
    "Dustwallow Marsh", "Feralas", "Tanaris", "Felwood", "Winterspring" }
local MULGORE = { "Mulgore", "The Barrens", "Stonetalon Mountains", "Thousand Needles", "Desolace", "Dustwallow Marsh",
    "Feralas", "Un'Goro Crater", "Felwood", "Winterspring" }
local ELWYNN = { "Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood", "Stranglethorn Vale", "Swamp of Sorrows",
    "The Hinterlands", "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands" }
local DUNMOROGH = { "Dun Morogh", "Loch Modan", "Wetlands", "Arathi Highlands", "Badlands", "Searing Gorge",
    "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands" }
local TELDRASSIL = { "Teldrassil", "Darkshore", "Ashenvale", "Stonetalon Mountains", "Desolace", "Feralas", "Felwood",
    "Winterspring" }
local ROUTES = { Scourge = FORSAKEN, Orc = DUROTAR, Troll = DUROTAR, Tauren = MULGORE, Human = ELWYNN,
    Dwarf = DUNMOROGH, Gnome = DUNMOROGH, NightElf = TELDRASSIL }
local LEVELS = {
    ["Tirisfal Glades"] = { 1, 10 }, ["Durotar"] = { 1, 10 }, ["Mulgore"] = { 1, 10 }, ["Elwynn Forest"] = { 1, 10 },
    ["Dun Morogh"] = { 1, 10 }, ["Teldrassil"] = { 1, 10 }, ["Silverpine Forest"] = { 10, 20 }, ["Westfall"] = { 10, 20 },
    ["Loch Modan"] = { 10, 20 }, ["Darkshore"] = { 10, 20 }, ["The Barrens"] = { 10, 25 },
    ["Redridge Mountains"] = { 15, 25 }, ["Stonetalon Mountains"] = { 15, 27 }, ["Ashenvale"] = { 18, 30 },
    ["Duskwood"] = { 18, 30 }, ["Hillsbrad Foothills"] = { 20, 30 }, ["Wetlands"] = { 20, 30 },
    ["Thousand Needles"] = { 25, 35 }, ["Alterac Mountains"] = { 30, 40 }, ["Arathi Highlands"] = { 30, 40 },
    ["Desolace"] = { 30, 40 }, ["Stranglethorn Vale"] = { 30, 45 }, ["Dustwallow Marsh"] = { 35, 45 },
    ["Badlands"] = { 35, 45 }, ["Swamp of Sorrows"] = { 35, 45 }, ["Feralas"] = { 40, 50 }, ["Tanaris"] = { 40, 50 },
    ["The Hinterlands"] = { 40, 50 }, ["Searing Gorge"] = { 43, 50 }, ["Felwood"] = { 48, 55 },
    ["Un'Goro Crater"] = { 48, 55 }, ["Burning Steppes"] = { 50, 58 }, ["Western Plaguelands"] = { 51, 58 },
    ["Eastern Plaguelands"] = { 53, 60 }, ["Winterspring"] = { 55, 60 },
}

local function route()
    local _, race = UnitRace("player")
    return race and ROUTES[race] or (UnitFactionGroup("player") == "Horde" and DUROTAR or ELWYNN)
end

-- "Levels 10-20" for a zone on a road
function E.LevelText(zone)
    local l = LEVELS[zone]
    return l and (L["Levels %d-%d"]):format(l[1], l[2]) or ""
end

-- The zones still ahead on this character's road: not seen through yet and not outgrown. after: only the ones
-- that come after this zone on the road (none when it isn't on it).
function E.RoadAhead(after, most)
    local lvl = UnitLevel("player") or 1
    local out, past = {}, after == nil
    for _, zone in ipairs(route()) do
        if past and not E.HasEpilogue(zone) and (LEVELS[zone] or { 0, 60 })[2] >= lvl then
            out[#out + 1] = zone
            if #out >= (most or 3) then break end
        end
        if zone == after then past = true end
    end
    return out
end

-- Check a zone; when its story is done for the first time, unlock the epilogue (and offer it, unless quiet).
function E.CheckZone(zone, quiet, started)
    if not zone or E.HasEpilogue(zone) then return false end
    local key = E.EpilogueKey(zone)
    if not key then return false end
    local done, needed = E.ZoneProgress(zone, started)
    if needed == 0 or done < needed then return false end
    ns.char.epilogues = ns.char.epilogues or {}
    ns.char.epilogues[zone] = time()
    if not quiet and ns.Reminder then
        -- and where the road goes on: the note says so, and its Journal button opens that zone's page
        local nextZone = E.RoadAhead(zone, 1)[1] or E.RoadAhead(nil, 1)[1]
        local line = nextZone and (L["The story continues in %s (%s)"]):format(ns.zoneLocal(nextZone), E.LevelText(nextZone))
        ns.Reminder.ShowStory((L["%s: the story is done"]):format(ns.zoneLocal(zone)), ns.Lore.epilogue[key], { "epi:" .. key },
            nextZone and function() ns.Journal.Open("area:" .. nextZone) end, line)
    end
    return true
end

-- the zone a finished quest's story belongs to
local function zoneOfQuest(id)
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        for _, q in ipairs(a.quests or {}) do if q == id then return a.zone end end
    end
end

-- ---------------------------------------------------------------- dungeons
-- ENCOUNTER_END gives the encounter's id and name. Lore bosses has every boss of every dungeon and raid by that id,
-- from the game's own table: where it is and its English name, whatever the client's language. A boss with a story
-- gets a word from the narrator the first time this character beats it (the user, 2026-11-07: "where is all the boss
-- lore ? and it doesnt talk about the boss after i kille them"); a dungeon (or a wing of it, "Dire Maul: West")
-- ends with its final boss.

-- a boss by its encounter id, and the id it is kept under (another difficulty's id points to the boss's own)
local function bossOf(id)
    local all = ns.Lore and ns.Lore.bosses
    local b = all and type(id) == "number" and all[id] or nil
    if b and b.a then id, b = b.a, all[b.a] end
    return b, id
end
E.BossOf = bossOf

local function wingOf(name, dungeon) return name == dungeon or name:sub(1, #dungeon + 2) == dungeon .. ": " end

-- the wing a boss ends, its ending and the boss as the ending knows it (names as the game's table spells them:
-- "C'thun")
local function dungeonEnding(dungeon, boss)
    local ends = ns.Lore and ns.Lore.dungeonEnd
    if not ends then return nil end
    boss = boss:lower()
    for name, bosses in pairs(ends) do
        if wingOf(name, dungeon) then
            for b, text in pairs(bosses) do
                if b:lower() == boss then return name, text, b end
            end
        end
    end
end

-- The game keeps a count of each dungeon's last boss killed (Statistics, on the character window: "Rath'mael Kills
-- (Ruins of Lordaeron)"), none of the other bosses (the user, 2026-11-07: "isnt that tracked in wow already?"). A
-- kill Chronicle didn't see, on another client language or before it was installed, still counts from there.
local function killedByStats(b)
    if not (b and b.s and GetStatistic) then return false end
    for _, s in ipairs(b.s) do
        local ok, n = pcall(GetStatistic, s)
        if ok and (tonumber(n) or 0) > 0 then return true end
    end
    return false
end

-- has this character beaten that boss: kept since boss lore came (1.1.3), the game's count of it, or the last boss of
-- a wing it finished
function E.Beaten(id)
    local b, main = bossOf(id)
    if not b then return false end
    if (ns.char.bosses and ns.char.bosses[main]) or killedByStats(b) then return true end
    for wing, t in pairs(ns.char.dungeonsDone or {}) do
        if t and wingOf(wing, b.d) and select(3, dungeonEnding(wing, b.n)) then return true end
    end
    return false
end

-- the bosses of a wing ("Dire Maul: West": those of the West), or of a whole dungeon that has no wings, by their ids
local function wingBosses(wing)
    local dungeon, part = wing:match("^(.-): (.+)$")
    dungeon = dungeon or wing
    local out = {}
    for id, b in pairs((ns.Lore and ns.Lore.bosses) or {}) do
        if b.d == dungeon and (part == nil or b.w == part) then out[#out + 1] = id end
    end
    return out
end

-- A wing finished before bosses were kept count of (or that only the game counts): its last boss is behind the others,
-- so they were beaten on the way (the user, 2026-11-07: "if they have killed the last boss, they should have killed the
-- other bosses aswel right?"). 0: when is not known; the first kill Chronicle sees still gets its note.
local function takeFinished(wing)
    ns.char.bosses = ns.char.bosses or {}
    for _, id in ipairs(wingBosses(wing)) do
        if ns.char.bosses[id] == nil then ns.char.bosses[id] = 0 end
    end
end

-- A wing whose last boss the game counts as killed, but Chronicle never saw it: finished, when is not known (0), with
-- all its bosses (the user: "if people get the update now, and they are high level they dont see the bosses they
-- already killed on lower levels"). A dungeon without wings whose one counted boss isn't the one its ending waits for
-- (Ragefire Chasm: the game counts Bazzalan, the story ends with Taragaman) is finished all the same; one with
-- several counted bosses (Shaper's Terrace) is left to the kills Chronicle sees.
local function finishedByStats()
    local all = ns.Lore and ns.Lore.bosses
    if not all then return end
    local ends, counted, winged = (ns.Lore.dungeonEnd or {}), {}, {}
    for name in pairs(ends) do
        local d = name:match("^(.-): ")
        if d then winged[d] = true end
    end
    for _, b in pairs(all) do
        if b.s and b.d then counted[b.d] = (counted[b.d] or 0) + 1 end
    end
    ns.char.dungeonsDone = ns.char.dungeonsDone or {}
    for _, b in pairs(all) do
        if b.s and b.d and killedByStats(b) then
            local wing = dungeonEnding(b.d, b.n)
            if not wing and not winged[b.d] and counted[b.d] == 1 then
                wing = b.d
            end
            if wing then
                if ends[wing] and not ns.char.dungeonsDone[wing] then ns.char.dungeonsDone[wing] = 0 end
                takeFinished(wing)
            end
        end
    end
end
E.FromStats = finishedByStats

local function onEncounterEnd(id, boss, success)
    if canaccessvalue and not (canaccessvalue(id) and canaccessvalue(boss) and canaccessvalue(success)) then return end
    if success ~= 1 or type(boss) ~= "string" then return end
    local inInstance = IsInInstance()
    if not inInstance then return end
    local b, main = bossOf(id)
    local dungeon = b and b.d or ns.zoneEN(ns.clean(GetRealZoneText()))
    if not dungeon then return end
    boss = b and b.n or boss
    -- the last boss a group killed in each dungeon, kept for /lore share: how we learn new dungeons' final bosses
    ns.db.lastBoss = ns.db.lastBoss or {}
    ns.db.lastBoss[dungeon] = boss
    local first = false
    if b then
        ns.char.bosses = ns.char.bosses or {}
        local had = ns.char.bosses[main]
        first = had == nil or had == 0 -- the first kill Chronicle sees (0: taken as beaten before it kept count)
        if first then ns.char.bosses[main] = time() end
    end
    local name, text, last = dungeonEnding(dungeon, boss)
    if name then
        ns.char.dungeonsDone = ns.char.dungeonsDone or {}
        ns.char.dungeonsDone[name] = time()
    end
    local lore = first and b.t and "boss:" .. main or nil -- who it was: only the first time
    if not (name or lore) or ns.settings.dungeonStory == false or not ns.Reminder then return end
    local page = function() ns.Journal.ShowDungeon(dungeon) end
    C_Timer.After(4, function()
        if name then
            -- the end: who the last one was (the first time, when it can be heard), then what it meant
            local keys = {}
            if lore and ns.Voice.Get(lore) then keys[1] = lore end
            keys[#keys + 1] = "dend:" .. name .. "|" .. last
            local title = (L["%s: the end"]):format((name:gsub("^([^:]+)", function(d) return ns.zoneLocal(d) end)))
            ns.Reminder.ShowStory(title, text, keys, page, nil, "dungeonStory")
        else
            ns.Reminder.ShowStory(boss, b.t, { lore }, page, nil, "dungeonStory")
        end
    end)
end

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "ENCOUNTER_END" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, ...)
    if not (ns.char and ns.Lore) then return end
    if event == "ENCOUNTER_END" then
        local id, boss, _, _, success = ...
        onEncounterEnd(id, boss, success)
    elseif event == "QUEST_TURNED_IN" then
        local id = ...
        -- after the recap has started, so the note does not cover the quest window's own business
        C_Timer.After(3, function() pcall(E.CheckZone, zoneOfQuest(id)) end)
    end
end)

-- Characters who finished a zone before this existed get its epilogue in the journal, without a note. Bosses are kept
-- count of from the first login with them: a wing finished before then has all its bosses, and so has one the game
-- counts as finished.
table.insert(ns.onLogin, function()
    ns.char.bossesSince = ns.char.bossesSince or time()
    for wing, t in pairs(ns.char.dungeonsDone or {}) do
        if t < ns.char.bossesSince then takeFinished(wing) end
    end
    C_Timer.After(10, function()
        pcall(finishedByStats)
        if not (ns.Lore and ns.Lore.epilogue) then return end
        local seen, started = {}, startedChapters()
        for _, a in ipairs(ns.Lore.arcs or {}) do
            if not seen[a.zone] then seen[a.zone] = true; pcall(E.CheckZone, a.zone, true, started) end
        end
    end)
end)

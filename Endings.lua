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
-- ENCOUNTER_END names the boss; a dungeon (or a wing of it, "Dire Maul: West") ends with a known final boss.
local function dungeonEnding(dungeon, boss)
    local ends = ns.Lore and ns.Lore.dungeonEnd
    if not ends then return nil end
    for name, bosses in pairs(ends) do
        if (name == dungeon or name:sub(1, #dungeon + 2) == dungeon .. ": ") and bosses[boss] then
            return name, bosses[boss]
        end
    end
end

local function onEncounterEnd(_, boss, _, _, success)
    if canaccessvalue and not canaccessvalue(boss) then return end
    if canaccessvalue and not canaccessvalue(success) then return end
    if success ~= 1 or type(boss) ~= "string" then return end
    local inInstance = IsInInstance()
    if not inInstance then return end
    local dungeon = ns.zoneEN(ns.clean(GetRealZoneText()))
    if not dungeon then return end
    -- the last boss a group killed in each dungeon, kept for /lore share: how we learn new dungeons' final bosses
    ns.db.lastBoss = ns.db.lastBoss or {}
    ns.db.lastBoss[dungeon] = boss
    local name, text = dungeonEnding(dungeon, boss)
    if not name then return end
    ns.char.dungeonsDone = ns.char.dungeonsDone or {}
    ns.char.dungeonsDone[name] = time()
    if ns.settings.zoneRecap ~= false and ns.Reminder then
        local title = (L["%s: the end"]):format((name:gsub("^([^:]+)", function(d) return ns.zoneLocal(d) end)))
        C_Timer.After(4, function() ns.Reminder.ShowStory(title, text, { "dend:" .. name .. "|" .. boss }) end)
    end
end

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "ENCOUNTER_END" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, ...)
    if not (ns.char and ns.Lore) then return end
    if event == "ENCOUNTER_END" then
        local _, boss, difficulty, size, success = ...
        onEncounterEnd(nil, boss, difficulty, size, success)
    elseif event == "QUEST_TURNED_IN" then
        local id = ...
        -- after the recap has started, so the note does not cover the quest window's own business
        C_Timer.After(3, function() pcall(E.CheckZone, zoneOfQuest(id)) end)
    end
end)

-- Characters who finished a zone before this existed get its epilogue in the journal, without a note.
table.insert(ns.onLogin, function()
    C_Timer.After(10, function()
        if not (ns.Lore and ns.Lore.epilogue) then return end
        local seen, started = {}, startedChapters()
        for _, a in ipairs(ns.Lore.arcs or {}) do
            if not seen[a.zone] then seen[a.zone] = true; pcall(E.CheckZone, a.zone, true, started) end
        end
    end)
end)

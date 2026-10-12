-- Chronicle / Capture: records quest text, who says it and where, and keeps the character's story journal.
-- Events are registered at load time (not at login) so this handler runs before auto-accept / auto turn-in
-- addons close the quest window and the text is gone.
local _, ns = ...
local clean = ns.clean
local ev = CreateFrame("Frame")

-- The NPC's body (a model file number): new WoW: Forever NPCs come without a race, and the model says which it is
-- ("character/tauren/female"), so their voice can fit. Read through a hidden model frame.
local probe
local function modelOf(unit)
    if not probe then
        local ok, f = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or not f then return nil end
        probe = f
        probe:SetSize(1, 1); probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100); probe:SetAlpha(0)
    end
    local ok = pcall(probe.SetUnit, probe, unit)
    if not ok or not probe.GetModelFileID then return nil end
    local ok2, id = pcall(probe.GetModelFileID, probe)
    return ok2 and clean(id) or nil
end

local function npcInfo()
    for _, unit in ipairs({ "questnpc", "npc" }) do
        -- a party member sharing a quest is "questnpc" too: never record players
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            local guid = clean(UnitGUID(unit))
            local kind, id
            if guid then
                local parts = { strsplit("-", guid) }
                kind, id = parts[1], tonumber(parts[6])
            end
            return {
                name = clean(UnitName(unit)),
                npcID = id,
                kind = kind,                         -- Creature, Vehicle, GameObject, ...
                sex = clean(UnitSex(unit)),          -- 1 unknown, 2 male, 3 female
                creature = clean(UnitCreatureType(unit)),
                model = modelOf(unit),
            }
        end
    end
end

local function where()
    local map = C_Map and C_Map.GetBestMapForUnit and clean(C_Map.GetBestMapForUnit("player"))
    local zone, sub = ns.zoneEN(clean(GetRealZoneText())), clean(GetSubZoneText())
    if zone == "" then zone = nil end   -- loading screens, some instances
    if sub == "" then sub = nil end
    return zone, sub, map
end

local function record(id)
    local q = ns.db.quests[id]
    if not q then
        q = { id = id, seen = time() }
        ns.db.quests[id] = q
    end
    return q
end

-- The client fills in the reader's name, class, race and gender. Remember who read it so the builder
-- can make the text neutral again.
local function reader()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    return { class = clean(class), race = clean(race), sex = clean(UnitSex("player")), name = clean(UnitName("player")) }
end

local function setText(q, key, text)
    text = clean(text)
    if type(text) == "string" and text ~= "" then
        q[key] = text
        q.by = q.by or {}
        q.by[key] = reader()
    end
end

local function setTitle(q, title)
    title = clean(title)
    if type(title) == "string" and title ~= "" then q.title = title end
end

local function currentQuestID()
    local id = clean(GetQuestID())
    if id and id > 0 then return id end
end

-- ---------------------------------------------------------------- who offers the new quests, and where
-- For the quest markers: an NPC's window lists the quests they offer (id and title) before you open any of them.
-- Only quests that are new in WoW: Forever are kept; classic ones ship with the addon.
local function recordOffer(id, title, level, npc)
    if not (ns.english and type(id) == "number" and id > 0 and ns.IsNew(id) and npc and npc.name) then return end
    -- the game only offers what this character can take: its map marker may show even without a known level
    if ns.char then
        ns.char.offered = ns.char.offered or {}
        ns.char.offered[id] = true
    end
    ns.db.offers = ns.db.offers or {}
    local o = ns.db.offers[id]
    if not o then
        local n = 0
        for _ in pairs(ns.db.offers) do n = n + 1 end
        if n >= 2000 then return end
        o = {}
        ns.db.offers[id] = o
    end
    local map = C_Map and C_Map.GetBestMapForUnit and clean(C_Map.GetBestMapForUnit("player"))
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    local info = map and C_Map.GetMapInfo(map)
    if pos and info then
        local x, y = pos:GetXY()
        o.zone, o.x, o.y = ns.zoneEN(info.name), math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
    end
    o.t = clean(title) or o.t
    o.lvl = (type(level) == "number" and level > 0) and level or o.lvl
    o.npc, o.npcID, o.side = npc.name, npc.npcID, UnitFactionGroup("player")
end

local function recordOffers(kind, npc)
    if kind == "gossip" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
        for _, q in ipairs(ok and list or {}) do recordOffer(q.questID, q.title, q.questLevel, npc) end
    elseif kind == "greeting" and GetNumAvailableQuests and GetAvailableQuestInfo then
        for i = 1, GetNumAvailableQuests() do
            local ok, _, _, _, _, id = pcall(GetAvailableQuestInfo, i)
            if ok then recordOffer(id, GetAvailableTitle and GetAvailableTitle(i), GetAvailableLevel and GetAvailableLevel(i), npc) end
        end
    end
end

-- ---------------------------------------------------------------- quest dialog pages
local function onDetail()
    local id = currentQuestID(); if not id then return end
    local q = record(id)
    setTitle(q, GetTitleText())
    setText(q, "detail", GetQuestText())
    setText(q, "objectives", GetObjectiveText())
    q.giver = npcInfo() or q.giver
    local zone, sub, map = where()
    if zone then q.zone, q.subzone, q.map = zone, sub, map or q.map end -- no zone (loading screen, instance): keep what was recorded
    pcall(recordOffer, id, q.title, nil, q.giver)
    ns.Voice.OnQuestPage(id, "detail", q.detail, q.giver and q.giver.sex == 3)
end

local function onProgress()
    local id = currentQuestID(); if not id then return end
    local q = record(id)
    setTitle(q, GetTitleText())
    setText(q, "progress", GetProgressText())
    q.ender = npcInfo() or q.ender
    ns.Voice.OnQuestPage(id, "progress", q.progress, q.ender and q.ender.sex == 3)
end

local function onComplete()
    local id = currentQuestID(); if not id then return end
    local q = record(id)
    setTitle(q, GetTitleText())
    setText(q, "complete", GetRewardText())
    q.ender = npcInfo() or q.ender
    ns.Voice.OnQuestPage(id, "complete", q.complete, q.ender and q.ender.sex == 3)
end

-- ---------------------------------------------------------------- greeting windows
-- The gossip window ("No other race on Azeroth has suffered...") or the quest greeting of an NPC with several quests.
-- a recorded greeting with a page no voiced line matches yet: still worth keeping and sharing
function ns.GreetingPending(id, g)
    if type(g) ~= "table" or type(g.text) ~= "string" then return false end
    if not ns.Voice.GreetingKey(id, g.text) then return true end
    for _, t in ipairs(g.more or {}) do
        if type(t) == "string" and not ns.Voice.GreetingKey(id, t) then return true end
    end
    return false
end

local prunedGreetings = false
local function onGreeting(kind)
    local text
    if kind == "gossip" then
        if C_GossipInfo and C_GossipInfo.GetText then
            local ok, t = pcall(C_GossipInfo.GetText)
            if ok then text = t end
        end
        if not text and GetGossipText then text = GetGossipText() end
    else
        text = GetGreetingText and GetGreetingText()
    end
    text = clean(text)
    local npc = npcInfo()
    if npc then pcall(recordOffers, kind, npc) end
    if not (npc and npc.npcID and type(text) == "string" and text ~= "") then return end
    local key = ns.Voice.GreetingKey(npc.npcID, text)
    local lore = ns.Lore or {}
    local unknownNPC = not (lore.npcs and npc.name and lore.npcs[npc.name])
    local newText = lore.greet and lore.greet[npc.npcID] ~= nil
    ns.db.greetings = ns.db.greetings or {}
    if not ns.english then
        -- another client language: every greeting is kept in its own table for /lore share (none has a voice in this
        -- language yet), the start of voices in German and French
        ns.db.loc = ns.db.loc or {}
        ns.db.loc.greetings = ns.db.loc.greetings or {}
        local g = ns.db.loc.greetings[npc.npcID] or {}
        g.name, g.sex, g.creature, g.kind = npc.name, npc.sex, npc.creature, npc.kind
        if not g.text or g.text == text then
            g.text = text
        else
            g.more = g.more or {}
            local have = false
            for _, t in ipairs(g.more) do if t == text then have = true end end
            if not have and #g.more < 5 then g.more[#g.more + 1] = text end
        end
        g.zone, g.by = where(), reader()
        ns.db.loc.greetings[npc.npcID] = g
        ns.Voice.OnGreeting(npc.npcID, key, text, npc.sex == 3)
        return
    end
    -- once per session, greetings that have a voice by now are let go: the limit below counts only the ones still
    -- waiting, so long-time recorders keep recording (Turak Runetotem's talent page was never kept; thanks Alche)
    if not prunedGreetings then
        prunedGreetings = true
        for id, g in pairs(ns.db.greetings) do
            if not ns.GreetingPending(id, g) then ns.db.greetings[id] = nil end
        end
    end
    local recorded = 0
    for _ in pairs(ns.db.greetings) do recorded = recorded + 1 end
    if not key and (unknownNPC or newText) and (ns.db.greetings[npc.npcID] or recorded < 400) then
        -- a greeting nobody has voiced yet (new NPC, or new text): keep it for /lore share and the next release
        local g = ns.db.greetings[npc.npcID] or {}
        g.name, g.sex, g.creature, g.kind = npc.name, npc.sex, npc.creature, npc.kind
        -- every page this NPC shows is kept: the welcome and the answers behind its chat options (the newest used to
        -- replace the rest, so only the last page someone saw ever got a voice)
        if not g.text or g.text == text then
            g.text = text
        else
            g.more = g.more or {}
            local have = false
            for _, t in ipairs(g.more) do if t == text then have = true end end
            if not have and #g.more < 5 then g.more[#g.more + 1] = text end
        end
        g.model = npc.model
        g.zone = where()
        g.by = reader()
        ns.db.greetings[npc.npcID] = g
    end
    ns.Voice.OnGreeting(npc.npcID, key, text, npc.sex == 3)
end

-- ---------------------------------------------------------------- journal
local function questTitle(id)
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
    return ok and clean(t) or nil
end

local function markDone(id, when)
    local c = ns.char
    if c.done[id] then return false end
    c.done[id] = true
    c.active[id] = nil
    local zone = where()
    c.journal[#c.journal + 1] = { id = id, t = when, zone = when and zone or nil }
    return true
end

-- Quests already in the log when the addon first sees them: take their text from the quest log.
local function backfillLog()
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not okN or not n then return end
    local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local header
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and info.isHeader then
            header = clean(info.title)
        elseif ok and info and info.questID and info.questID > 0 then
            local id = info.questID
            local q = record(id)
            setTitle(q, info.title)
            -- quest log headers are usually the zone, but can be a category (class, profession, "Camping")
            if header then q.category = header end
            if not ns.char.active[id] then ns.char.active[id] = time() end
            if not q.detail and C_QuestLog.SetSelectedQuest and GetQuestLogQuestText then
                C_QuestLog.SetSelectedQuest(id)
                local desc, obj = GetQuestLogQuestText()
                setText(q, "detail", desc)
                setText(q, "objectives", obj)
                q.fromLog = true
            end
        end
    end
    if prev and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(prev) end
end

-- Quests finished before the addon was installed still count toward the story. The client lists every
-- completed quest ID; hidden tracking flags are in there too, so only quests with a real title are kept.
local HISTORY_ZONE = "Before the journal"
local pendingTitles = {}

local function addHistory(id)
    local title = questTitle(id)
    if not title or title == "" then return false end
    local q = record(id)
    q.title = q.title or title
    q.history = true
    if markDone(id, nil) then
        ns.char.journal[#ns.char.journal].zone = q.zone or ns.LoreZone(id) or HISTORY_ZONE
    end
    return true
end

-- Some new Forever quests have one copy per starting zone ("The Adventurer", "Camping 101") sharing a single completed
-- flag, so finishing one marks them all. A copy actually done wins; otherwise the one in this character's
-- starting zone (or the first). Copies only known from the flag are forgotten.
local START_ZONE = { Human = "Elwynn Forest", Dwarf = "Dun Morogh", Gnome = "Dun Morogh", NightElf = "Teldrassil",
                     Orc = "Durotar", Troll = "Durotar", Scourge = "Tirisfal Glades", Tauren = "Mulgore" }

-- quests from chapters that belong to the other faction: Forever starting-zone quests share a completed flag
-- with their twin elsewhere, so the game reports them done for characters who never saw them
local foreign
local function foreignQuests()
    if foreign then return foreign end
    foreign = {}
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    if side == "" then return foreign end
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        if a.side and a.side ~= side then
            for _, id in ipairs(a.quests or {}) do foreign[id] = true end
        end
    end
    return foreign
end

local function dropTwins()
    local c = ns.char
    local home = START_ZONE[select(2, UnitRace("player")) or ""]
    local byTitle = {}
    for i, e in ipairs(c.journal) do
        local q = ns.db.quests[e.id]
        if q and q.title and ns.IsNew(e.id) then -- classic chains reuse titles on purpose ("The Missing Diplomat")
            local list = byTitle[q.title] or {}
            list[#list + 1] = i
            byTitle[q.title] = list
        end
    end
    local function flagOnly(i)
        local q = ns.db.quests[c.journal[i].id]
        return q and q.history
    end
    -- where a quest giver stands: the camping lessons share one chapter, but Kharanos, Brill and Goldshire each
    -- have their own copy
    local function zoneOf(i)
        local id = c.journal[i].id
        local at = ns.Map and ns.Map.QuestInfo(id)
        return (at and at.zone) or ns.LoreZone(id) or c.journal[i].zone
    end
    local drop = {}
    local other = foreignQuests()
    for i, e in ipairs(c.journal) do
        if other[e.id] and flagOnly(i) then drop[i] = true end
    end
    for _, list in pairs(byTitle) do
        if #list > 1 then
            local keep
            for _, i in ipairs(list) do
                if not flagOnly(i) then keep = keep or i end
            end
            if not keep then
                for _, i in ipairs(list) do
                    if c.journal[i].zone == home or zoneOf(i) == home then keep = keep or i end
                end
            end
            keep = keep or list[1]
            -- twins live in different starting zones; two quests with one title in the same zone are two parts of a
            -- chain ("Delicate Instruments" in Elwynn), both kept
            for _, i in ipairs(list) do
                if i ~= keep and flagOnly(i) and zoneOf(i) ~= zoneOf(keep) then drop[i] = true end
            end
        end
    end
    for i = #c.journal, 1, -1 do
        if drop[i] then
            c.twins = c.twins or {}
            c.twins[c.journal[i].id] = true -- still flagged by the game: don't add it again next login
            c.done[c.journal[i].id] = nil
            table.remove(c.journal, i)
        end
    end
end

local noTitle
local function scanCompleted()
    -- beta.14: older versions also dropped parts of a chain that share a title; forget those once so they come back
    if not ns.char.twinsV2 then ns.char.twins, ns.char.twinsV2 = nil, true end
    ns.db.noTitle = ns.db.noTitle or {}
    noTitle = ns.db.noTitle
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return end
    local ids = {}
    if C_QuestLog.GetAllCompletedQuestIDs then
        local ok, all = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(all) == "table" then ids = all end
    else
        for id in pairs(ns.db.quests) do ids[#ids + 1] = id end
        for id in pairs(ns.Lore.quests or {}) do ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        -- hidden tracking flags have no title: remembered account-wide so they are asked for only once
        if not ns.char.done[id] and not noTitle[id] and not (ns.char.twins or {})[id] and not foreignQuests()[id]
            and C_QuestLog.IsQuestFlaggedCompleted(id) then
            if not addHistory(id) and C_QuestLog.RequestLoadQuestByID then
                pendingTitles[id] = true
                C_QuestLog.RequestLoadQuestByID(id) -- answered by QUEST_DATA_LOAD_RESULT
            end
        end
    end
    dropTwins()
    -- drop "active" entries that are no longer in the log
    for id in pairs(ns.char.active) do
        local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
        if ok and not idx and not ns.char.done[id] then ns.char.active[id] = nil end
    end
end

local refreshTimer
local function refreshJournal()
    if ns.Journal and ns.Journal.Refresh then ns.Journal.Refresh() end
end

ev:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    if ns.settings.debug and event ~= "QUEST_DATA_LOAD_RESULT" then
        local id = GetQuestID and GetQuestID()
        ns.pr(("debug: %s (args: %s) GetQuestID=%s"):format(event, tostring((...)), tostring(id)))
    end
    if event == "GOSSIP_SHOW" then onGreeting("gossip")
    elseif event == "QUEST_GREETING" then onGreeting("greeting")
    elseif event == "QUEST_DETAIL" then onDetail()
    elseif event == "QUEST_PROGRESS" then onProgress()
    elseif event == "QUEST_COMPLETE" then onComplete()
    elseif event == "QUEST_FINISHED" then ns.Voice.OnQuestClosed()
    elseif event == "QUEST_ACCEPTED" then
        local id = ...
        if type(id) ~= "number" or id == 0 then id = select(2, ...) end
        if type(id) == "number" and id > 0 then
            local q = record(id)
            if not q.title then q.title = questTitle(id) end
            ns.char.active[id] = time()
            refreshJournal()
        end
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local id, ok = ...
        if pendingTitles[id] then
            pendingTitles[id] = nil
            if ok and addHistory(id) then
                if refreshTimer then refreshTimer:Cancel() end
                refreshTimer = C_Timer.NewTimer(0.5, function() dropTwins(); refreshJournal() end) -- these arrive in bursts
            elseif ns.db.noTitle then
                ns.db.noTitle[id] = true
            end
        end
    elseif event == "QUEST_REMOVED" then
        -- also fires for a hand-in: wait, then only an abandoned quest (not done, not flagged) leaves the active list
        -- (thanks Pylo)
        local id = ...
        if type(id) == "number" and ns.char.active[id] then
            C_Timer.After(1, function()
                if ns.char.done[id] then return end
                local ok, flagged = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
                if ok and flagged then return end
                ns.char.active[id] = nil
                refreshJournal()
            end)
        end
    elseif event == "QUEST_TURNED_IN" then
        local id = ...
        if type(id) == "number" and id > 0 then
            local q = record(id)
            if not q.title then q.title = questTitle(id) end
            if markDone(id, time()) then refreshJournal() end
            ns.Voice.OnQuestTurnedIn(id)
        end
    end
end)

for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL","QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

table.insert(ns.onLogin, function()
    -- the quest log and completion flags are not reliable right at login
    C_Timer.After(3, function()
        pcall(backfillLog)
        pcall(scanCompleted)
        refreshJournal()
    end)
end)

-- Chronicle / Scan (developer tool, off for players): asks the game for the title of every quest ID in the range
-- where WoW: Forever's new quests live, so the builder knows how many new quests exist and which still need
-- recording. Only titles (and objectives when the client has them): the spoken text still comes from playing.
-- Turned on by ChronicleDB.devScan = true. Slow on purpose, pauses in combat, resumes next session.
local _, ns = ...
local L = ns.L

local FIRST, LAST = 85000, 101000
local EVERY = 0.12        -- seconds between requests (~8 per second)

local state, ticker
local pending = {}
local classic

local function info(id)
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
    title = ok and ns.clean(title) or nil
    if not title or title == "" then return nil end
    local e = { t = title }
    if C_QuestLog.GetQuestDifficultyLevel then
        local okL, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
        if okL and type(lvl) == "number" and lvl > 0 then e.lvl = lvl end
    end
    if C_QuestLog.GetQuestObjectives then
        local okO, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if okO and type(objs) == "table" then
            local texts = {}
            for _, o in ipairs(objs) do if type(o.text) == "string" and o.text ~= "" then texts[#texts + 1] = o.text end end
            if #texts > 0 then e.obj = table.concat(texts, "\n") end
        end
    end
    return e
end

local function finish()
    if ticker then ticker:Cancel(); ticker = nil end
    local n = 0
    for _ in pairs(state.found) do n = n + 1 end
    state.done = true
    ns.pr((L["quest scan finished: %d quests found in %d-%d that were not in Classic."]):format(n, FIRST, LAST))
end

local function step()
    if InCombatLockdown() then return end
    local id = state.next
    if id > LAST then finish(); return end
    state.next = id + 1
    if classic[id] or state.found[id] then return end
    local e = info(id)
    if e then
        state.found[id] = e
    elseif C_QuestLog.RequestLoadQuestByID then
        pending[id] = true
        C_QuestLog.RequestLoadQuestByID(id) -- answered by QUEST_DATA_LOAD_RESULT
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, id, success)
    if not pending[id] then return end
    pending[id] = nil
    if success then
        local e = info(id)
        if e then state.found[id] = e end
    end
end)

-- Developer test: can this client list a zone's quests with map positions by itself (the modern engine can)?
-- Each function is tried on the zone you are in; the builder reads the results from ChronicleDB.probe.
local PROBES = {
    { "C_QuestLine.GetAvailableQuestLines", function(m)
        if C_QuestLine.RequestQuestLinesForMap then C_QuestLine.RequestQuestLinesForMap(m) end
        return C_QuestLine.GetAvailableQuestLines(m) end },
    { "C_QuestLog.GetQuestsOnMap", function(m) return C_QuestLog.GetQuestsOnMap(m) end },
    { "C_TaskQuest.GetQuestsOnMap", function(m) return C_TaskQuest.GetQuestsOnMap(m) end },
    { "C_QuestLine.GetForceVisibleQuests", function(m) return C_QuestLine.GetForceVisibleQuests(m) end },
}

local function probe()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = m and C_Map.GetMapInfo(m)
    if not mapInfo then return end
    ns.db.probe = ns.db.probe or {}
    local out = { map = m }
    local found = 0
    for _, p in ipairs(PROBES) do
        local ok, res = pcall(p[2], m)
        if not ok then
            out[p[1]] = "unavailable"
        elseif type(res) ~= "table" then
            out[p[1]] = "returned " .. type(res)
        else
            local sample = {}
            for i = 1, math.min(5, #res) do
                local r = res[i]
                if type(r) == "table" then
                    sample[i] = { id = r.questID or r.questLineID, name = r.questName or r.questLineName,
                                  x = r.x, y = r.y, lvl = r.questLevel }
                else sample[i] = r end
            end
            out[p[1]] = { count = #res, sample = sample }
            found = found + #res
        end
    end
    ns.db.probe[mapInfo.name] = out
    if ns.settings.debug then ns.pr(("debug: zone quest test in %s: %d results"):format(mapInfo.name, found)) end
end

local probeEv = CreateFrame("Frame")
probeEv:SetScript("OnEvent", function() C_Timer.After(3, function() pcall(probe) end) end)

table.insert(ns.onLogin, function()
    if ns.db.devScan then
        probeEv:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        C_Timer.After(8, function() pcall(probe) end)
    end
    if not (ns.db.devScan and C_QuestLog and C_QuestLog.GetTitleForQuestID) then return end
    local version, build = GetBuildInfo()
    local client = version .. "." .. build
    ns.db.scan = ns.db.scan or { found = {} }
    state = ns.db.scan
    state.found = state.found or {}
    if state.client ~= client then          -- new client build: quests may have been added, look again
        state.client, state.next, state.done = client, FIRST, nil
    end
    state.loc = GetLocale()
    if state.done then return end
    state.next = state.next or FIRST
    classic = {}
    for _, qid in ipairs((ns.Lore and ns.Lore.classic) or {}) do classic[qid] = true end
    pcall(ev.RegisterEvent, ev, "QUEST_DATA_LOAD_RESULT")
    ns.pr((L["quest scan running in the background (%d of %d IDs checked)."]):format(state.next - FIRST, LAST - FIRST + 1))
    C_Timer.After(20, function() ticker = C_Timer.NewTicker(EVERY, step) end) -- let the login rush settle first
end)

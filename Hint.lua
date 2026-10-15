-- Chronicle / Hint: for players who play with the map's quest objectives off. On request, one quest's objective
-- areas show on the map (the game's own), and everything is put back when the map or the quest closes. An option,
-- off by default. Right-click a quest in the quest log or the tracker, or the Hint button on the story so far.
local _, ns = ...
local L = ns.L
local H = {}
ns.Hint = H

local CVAR = "questPOI" -- the map's "Show quest objectives"

local function getCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

local function setCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, name, tostring(value)) end
end

-- what the hint changed, to put back: kept in the saved data too, so a /reload or a crash can't leave it changed
local active
local function restore()
    local a = active or (ns.db and ns.db.hintRestore)
    active = nil
    if ns.db then ns.db.hintRestore = nil end
    if not a then return end
    if a.poi ~= nil then setCVar(CVAR, a.poi) end
    if a.track ~= nil and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        pcall(C_SuperTrack.SetSuperTrackedQuestID, a.track)
    end
end
H.Restore = restore

-- is this quest's hint on right now (the button then says Hide hint)
function H.IsActive(questID) return active ~= nil and active.quest == questID end
table.insert(ns.onLogin, restore)

-- the map closing, or its quest page closing, ends the hint (watched, no hooks on the game's windows)
local watching
local function watch()
    if watching then return end
    watching = true
    local hosts = { WorldMapFrame, QuestMapFrame and QuestMapFrame.DetailsFrame }
    for _, host in ipairs(hosts) do
        if host then
            local layer = ns.Overlay(host)
            layer.onClose = function() if active then restore() end end
        end
    end
end

function H.Available(questID)
    return ns.settings.questHints and questID and C_QuestLog.GetLogIndexForQuestID
        and C_QuestLog.GetLogIndexForQuestID(questID) and QuestMapFrame_OpenToQuestDetails and true or false
end

function H.Show(questID)
    if not H.Available(questID) then return end
    if InCombatLockdown() then
        ns.pr(L["a hint opens the map: after the fight."])
        return
    end
    restore()
    local a = { quest = questID }
    if getCVar(CVAR) ~= "1" then
        a.poi = getCVar(CVAR) or "0"
        setCVar(CVAR, "1")
    end
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
        local ok, cur = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and cur ~= questID then
            a.track = cur or 0
            pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
        end
    end
    active = a
    ns.db.hintRestore = a
    watch()
    if not pcall(QuestMapFrame_OpenToQuestDetails, questID) then restore() end
end

-- "Hint" in the quest log's and the tracker's right-click menus
local function questOf(owner)
    local region, depth = owner, 0
    while region and depth < 6 do
        local id = region.questID
        if type(id) == "number" and id > 0 then return id end
        if region.GetQuestID then
            local ok, q = pcall(region.GetQuestID, region)
            if ok and type(q) == "number" and q > 0 then return q end
        end
        region = region.GetParent and region:GetParent() or nil
        depth = depth + 1
    end
end

table.insert(ns.onLogin, function()
    if not (Menu and Menu.ModifyMenu) then return end
    local function add(owner, root)
        local id = questOf(owner)
        if not H.Available(id) then return end
        root:CreateDivider()
        root:CreateButton(L["Hint"], function() H.Show(id) end)
    end
    pcall(Menu.ModifyMenu, "MENU_QUEST_MAP_LOG_TITLE", add)
    pcall(Menu.ModifyMenu, "MENU_QUEST_OBJECTIVE_TRACKER", add)
end)

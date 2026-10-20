-- Chronicle / Map: a book on the world map for each story chapter you have started, at its first quest giver.
-- Hover for the chapter and your progress; click to open it in the journal.
local _, ns = ...
local L = ns.L
local M = {}
ns.Map = M

local TEMPLATE = "ChronicleMapPinTemplate"

-- pin behaviour (the frame template is in MapPin.xml)
---@class ChronicleMapPinMixin: MapCanvasPinMixin
---@field Icon Texture  (parentKey in MapPin.xml)
---@field chapter table
ChronicleMapPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

-- Story books sit on the game's own area-marker layer. (A layer of our own meant writing into the world map's
-- level manager, which is the game's data: map pins could then be blocked in combat and blamed on us.)
local storyLevel = "PIN_FRAME_LEVEL_AREA_POI"

function ChronicleMapPinMixin:OnLoad()
    if self.UseFrameLevelType then self:UseFrameLevelType(storyLevel) end
    self:SetScalingLimits(1, 1.0, 1.2)
end

-- addon pins must not call the protected passthrough setter (blocked-action errors when the map opens in combat)
function ChronicleMapPinMixin:SetPassThroughButtons() end
function ChronicleMapPinMixin:CheckMouseButtonPassthrough() end

function ChronicleMapPinMixin:OnAcquired(chapter, x, y)
    self.chapter = chapter
    self:SetPosition(x, y)
    local done = chapter.done >= (chapter.total or #chapter.entries)
    self.Icon:SetDesaturated(done)
    self.Icon:SetAlpha(done and 0.7 or 1)
end

function ChronicleMapPinMixin:OnMouseEnter()
    local c = self.chapter
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.title)
    GameTooltip:AddLine((L["%d of %d quests"]):format(c.done, c.total or #c.entries), 1, 1, 1)
    GameTooltip:AddLine(L["Click to open in the journal"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ChronicleMapPinMixin:OnMouseLeave() GameTooltip:Hide() end

function ChronicleMapPinMixin:OnClick(button)
    if button and button ~= "LeftButton" then return end -- right-click stays the map's zoom-out
    ns.Journal.Open(self.chapter.key)
end

-- ---------------------------------------------------------------- optional quest markers
-- "!" where a quest giver has quests for you now (the game shows the "?" for hand-ins itself). Off by default, and
-- off whenever Questie runs (it already does this, with objectives too).
local QTEMPLATE = "ChronicleQuestPinTemplate"
---@class ChronicleQuestPinMixin: MapCanvasPinMixin
---@field Icon Texture  (parentKey in MapPin.xml)
---@field spot table
ChronicleQuestPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function ChronicleQuestPinMixin:OnLoad()
    if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    self:SetScalingLimits(1, 1.0, 1.2)
end
function ChronicleQuestPinMixin:SetPassThroughButtons() end
function ChronicleQuestPinMixin:CheckMouseButtonPassthrough() end

function ChronicleQuestPinMixin:OnAcquired(spot, x, y)
    self.spot = spot
    self:SetPosition(x, y)
    self.Icon:SetTexture(spot.turnin and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
end

function ChronicleQuestPinMixin:OnMouseEnter()
    local spot = self.spot
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(spot.who or (spot.turnin and L["Hand in here"] or L["Quests here"]))
    for _, q in ipairs(spot.quests) do
        local c = (q.lvl and q.lvl > 0 and GetQuestDifficultyColor) and GetQuestDifficultyColor(q.lvl) or { r = 1, g = 0.82, b = 0 }
        GameTooltip:AddLine((q.lvl and q.lvl > 0) and ("[%d] %s"):format(q.lvl, q.t) or q.t, c.r, c.g, c.b)
    end
    GameTooltip:AddLine(spot.turnin and L["Ready to hand in"] or L["Available to you"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function ChronicleQuestPinMixin:OnMouseLeave() GameTooltip:Hide() end

local decoded = {}
local function zoneData(zone)
    local d = decoded[zone]
    if d then return d end
    d = { givers = {}, ends = {} }
    local l = ns.Lore or {}
    for line in ((l.qmarks or {})[zone] or ""):gmatch("[^\n]+") do
        local id, lvl, min, races, classes, prev, x, y, t = strsplit("\t", line)
        d.givers[#d.givers + 1] = { id = tonumber(id), lvl = tonumber(lvl), min = tonumber(min), races = tonumber(races),
            classes = tonumber(classes), prev = tonumber(prev), x = tonumber(x), y = tonumber(y), t = t }
    end
    for line in ((l.qends or {})[zone] or ""):gmatch("[^\n]+") do
        local id, x, y = strsplit("\t", line)
        d.ends[tonumber(id)] = { x = tonumber(x), y = tonumber(y) }
    end
    decoded[zone] = d
    return d
end

local function flagged(id)
    if ns.char.done[id] then return true end
    local ok, d = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and d
end
local function inLog(id)
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and idx ~= nil
end
local function fits(mask, bitValue) return not mask or mask == 0 or bit.band(mask, bitValue) ~= 0 end

-- every quest the marker data knows, whatever the zone: level, limits, title and where its giver stands
local questIndex
-- quest -> its line in the marker data, and its zone; a quest's details are unpacked only when asked for, and kept
-- while in use (unpacking all 3,800 at once kept 2.6 MB of small tables for good)
local questZone
local questDecoded = setmetatable({}, { __mode = "v" })
function M.QuestInfo(id)
    if not questIndex then
        questIndex, questZone = {}, {}
        for zone, blob in pairs((ns.Lore and ns.Lore.qmarks) or {}) do
            for line in blob:gmatch("[^\n]+") do
                local qid = tonumber(line:match("^(%d+)\t"))
                if qid and not questIndex[qid] then questIndex[qid], questZone[qid] = line, zone end
            end
        end
    end
    local q = questDecoded[id]
    if q then return q end
    local line = questIndex[id]
    if not line then return nil end
    local _, lvl, min, races, classes, prev, x, y, t = strsplit("\t", line)
    q = { lvl = tonumber(lvl), min = tonumber(min), races = tonumber(races), classes = tonumber(classes),
        prev = tonumber(prev), x = tonumber(x), y = tonumber(y), t = t, zone = questZone[id] }
    questDecoded[id] = q
    return q
end

-- the map id of a zone by its English name (searched once over the world's zone maps)
local mapIDs
local function zoneMapID(zone)
    if not mapIDs then
        mapIDs = {}
        for _, root in ipairs({ 947, 1414, 1415, 12, 13 }) do -- Azeroth, Kalimdor, Eastern Kingdoms (old and new ids)
            local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, Enum.UIMapType.Zone, true)
            for _, info in ipairs(ok and kids or {}) do
                local en = ns.zoneEN(info.name)
                if en and not mapIDs[en] then mapIDs[en] = info.mapID end
            end
        end
    end
    return mapIDs[zone]
end

-- The way into Blackrock Mountain for a quest given inside it (a giver the world map cannot show): the game's own
-- dungeon entrance, on the Horde side from Searing Gorge, on the Alliance side from the Burning Steppes
local BLACKROCK = { ["Blackrock Depths"] = true, ["Blackrock Spire"] = true, ["Molten Core"] = true, ["Blackwing Lair"] = true }
function M.DungeonDoor(name)
    if not (BLACKROCK[name] and C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then return end
    local zone = UnitFactionGroup("player") == "Horde" and "Searing Gorge" or "Burning Steppes"
    local mapID = zoneMapID(zone)
    local ok, doors = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID or 0)
    local pick
    for _, d in ipairs(ok and doors or {}) do
        if d.position and (not pick or d.name == name) then pick = d end
    end
    if not pick then return end
    local x, y = pick.position:GetXY()
    return zone, x * 100, y * 100
end

-- A marker where a quest giver stands: TomTom's arrow when TomTom is there, else the game's own map pin with its
-- tracking arrow, else the coordinates in chat.
function M.Waypoint(zone, x, y, title)
    if not (zone and x and y) then return false end
    local mapID = zoneMapID(zone)
    local where = ("%s %.0f, %.0f"):format(ns.zoneLocal(zone), x, y)
    local tomtom = rawget(_G, "TomTom")
    if mapID and tomtom and tomtom.AddWaypoint then
        pcall(tomtom.AddWaypoint, tomtom, mapID, x / 100, y / 100, { title = title, persistent = false })
        ns.pr((L["marked on the map: %s (%s)"]):format(title or "", where))
        return true
    end
    if mapID and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        if ok then
            ns.pr((L["marked on the map: %s (%s)"]):format(title or "", where))
            return true
        end
    end
    ns.pr((L["%s: %s"]):format(title or "", where))
    return false
end

-- can this character ever take the quest (race and class; level comes with time)
function M.ForMe(id)
    local q = M.QuestInfo(id)
    if not q then return true end
    local raceBit = 2 ^ ((select(3, UnitRace("player")) or 1) - 1)
    local classBit = 2 ^ ((select(3, UnitClass("player")) or 1) - 1)
    return fits(q.races, raceBit) and fits(q.classes, classBit)
end

local function questieRunning()
    return C_AddOns.IsAddOnLoaded("Questie")
end

local function personName(id, which)
    local l = ns.Lore or {}
    local i = l[which] and l[which][id]
    return i and l.people and l.people[i]
end

-- Our pins are our own frames on the map's canvas, placed by us. Taking them from the map's pin pool
-- (map:AcquirePin) made addon code write a counter inside the game's pool; when the game later placed its own
-- quest markers in combat, it read that counter and was blocked ("SetPassThroughButtons", thanks to a player's
-- taint log). Same look and behaviour: the templates and their mixins, positioned and sized here.
local own, ownMap = {}, nil

-- placed on the canvas like the map's own art: they zoom with the map
local function place(pin, x, y)
    local canvas = ownMap and ownMap:GetCanvas()
    if not canvas then return end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
end

local function acquire(template, data, x, y)
    local canvas = ownMap and ownMap:GetCanvas()
    if not canvas then return end
    local list = own[template] or {}
    own[template] = list
    local pin
    for _, p in ipairs(list) do if not p:IsShown() then pin = p; break end end
    if not pin then
        pin = CreateFrame("Button", nil, canvas, template)
        pin.SetPosition = function(self, px, py) place(self, px, py) end
        pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnEnter", function(self) self:OnMouseEnter() end)
        pin:SetScript("OnLeave", function(self) self:OnMouseLeave() end)
        pin:SetScript("OnClick", function(self, button) if self.OnClick then self:OnClick(button) end end)
        list[#list + 1] = pin
    end
    -- above the map's own art and most of its markers (the game's layers reach about 2900 here)
    pin:SetFrameLevel(canvas:GetFrameLevel() + (template == QTEMPLATE and 2600 or 2500))
    pin:Show()
    ---@diagnostic disable-next-line: undefined-field
    pin:OnAcquired(data, x, y) -- from the template's mixin
    return pin
end

local function releaseAll()
    for _, list in pairs(own) do for _, pin in ipairs(list) do pin:Hide() end end
end

local function addQuestPins(map, zone)
    local level = UnitLevel("player") or 1
    local raceBit = 2 ^ ((select(3, UnitRace("player")) or 1) - 1)
    local classBit = 2 ^ ((select(3, UnitClass("player")) or 1) - 1)
    local d = zoneData(zone)
    local spots, order = {}, {}
    local function spot(x, y, turnin, who)
        local k = ("%s:%.0f:%.0f"):format(turnin and "t" or "g", x * 2, y * 2) -- one pin per NPC, not per quest
        if not spots[k] then
            spots[k] = { x = x, y = y, turnin = turnin, who = who, quests = {} }
            order[#order + 1] = k
        end
        return spots[k]
    end
    local seen = {}
    -- titles in the quest log or already handed in: WoW: Forever gives some quests in several copies (one per race
    -- or class), and taking one leaves the others on offer to nobody
    local taken = {}
    local okN, n = pcall(function() return C_QuestLog.GetNumQuestLogEntries() end)
    for i = 1, okN and tonumber(n) or 0 do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and info.title and not info.isHeader then taken[info.title:lower()] = true end
    end
    for id in pairs(ns.char.done or {}) do
        local qi = M.QuestInfo(id)
        if qi and type(qi.t) == "string" then taken[qi.t:lower()] = true end
    end
    local function consider(q)
        if not q.id or seen[q.id] then return end
        seen[q.id] = true
        if flagged(q.id) or inLog(q.id) then return end
        if type(q.t) == "string" and taken[q.t:lower()] then return end
        -- a new Forever quest nobody has seen the level of: it may need a higher level, an earlier quest or another
        -- class, so it only shows once the game has offered it to this character
        if not (q.lvl and q.lvl > 0) and ns.IsNew(q.id) and not (ns.char.offered or {})[q.id] then return end
        if q.min and q.min > level then return end
        if q.lvl and q.lvl > 0 and q.lvl < level - 7 then return end -- long outgrown: keeps the map calm
        if q.lvl and q.lvl > level + 5 then return end                -- far too hard for now (some have no real minimum)
        if not (fits(q.races, raceBit) and fits(q.classes, classBit)) then return end
        -- a profession's own quest ("Camping 101: Mining"): only for those who have it
        local prof = ns.Lore and ns.Lore.optional and ns.Lore.optional[q.id]
        if type(prof) ~= "string" then prof = type(q.t) == "string" and q.t:match("^Camping 101: (.+)$") end -- other copies of it
        if type(prof) == "string" and ns.Journal and ns.Journal.HasProfession and not ns.Journal.HasProfession(prof) then return end
        if q.prev and q.prev > 0 and not flagged(q.prev) then return end
        if q.prev and q.prev < 0 and not inLog(-q.prev) then return end
        table.insert(spot(q.x, q.y, false, personName(q.id, "giverOf")).quests, q)
    end
    for _, q in ipairs(d.givers) do consider(q) end
    -- new Forever quests this account found itself, before the next release ships them
    local side = UnitFactionGroup("player")
    for id, o in pairs(ns.db.offers or {}) do
        if o.zone == zone and o.x and (not o.side or o.side == side) then
            -- class letters ("Glyphic Parchment" is a mage's) only show for that class
            local letter = o.t and (ns.Lore.classLetters or {})[o.t:match("^(%S+)")]
            consider({ id = id, lvl = o.lvl, min = o.lvl and math.max(1, o.lvl - 4), classes = letter, x = o.x, y = o.y, t = o.t or "?" })
        end
    end
    -- (where to hand in a finished quest: the game's own map already shows a "?" there)
    for _, k in ipairs(order) do
        local s = spots[k]
        acquire(QTEMPLATE, s, s.x / 100, s.y / 100)
    end
end

-- ---------------------------------------------------------------- story map
-- Zone maps get a small panel with the zone's chapters and a book where a started chapter continues; continent
-- maps show how many chapters you have found in each zone. No spoilers: chapters you haven't started are only
-- counted, never named, and the next step names who to talk to, not the quest.
local NTEMPLATE = "ChronicleNextPinTemplate"
local READY, WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t", "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t"

local byZone
local function zoneArcs(zone)
    if not byZone then
        byZone = {}
        for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
            local z = a.zone or ""
            byZone[z] = byZone[z] or {}
            table.insert(byZone[z], a)
        end
    end
    return byZone[zone] or {}
end

-- this character's story in a zone: started chapters (from the journal) and how many more there are to find
local function startedChapters()
    local started = {}
    for _, ch in ipairs(ns.Journal.BuildChapters()) do started[ch.key] = ch end
    return started
end

local function zoneStory(zone, started)
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    local classBit = 2 ^ ((select(3, UnitClass("player")) or 1) - 1)
    started = started or startedChapters()
    local s = { zone = zone, chapters = {}, hidden = 0, done = 0 }
    for _, a in ipairs(zoneArcs(zone)) do
        local ch = started["arc:" .. a.id]
        if ch then
            s.chapters[#s.chapters + 1] = { ch = ch, arc = a }
            if ch.done >= (ch.total or #ch.entries) then s.done = s.done + 1 end
        elseif (not a.side or a.side == side) and (not a.cls or bit.band(a.cls, classBit) ~= 0)
            and ns.Journal.ArcForMyRace(a) then
            s.hidden = s.hidden + 1
            -- Show what's left: where each undiscovered chapter starts (lowest level first)
            -- (only what you can take now or soon: a level 55 chain in Brill isn't for a level 10 character)
            if ns.settings.showLeft then
                local first = ns.Journal.StillToDo(a.quests)[1]
                local need = first and (first.min and first.min > 0 and first.min or first.lvl) or 0
                if first and need <= (UnitLevel("player") or 1) + 2 then
                    s.starts = s.starts or {}; table.insert(s.starts, first)
                end
            end
        end
    end
    if s.starts then table.sort(s.starts, function(x, y) return (x.lvl or 99) < (y.lvl or 99) end) end
    if ns.settings.hideUnfound then s.hidden, s.starts = 0, nil end -- nothing about what isn't found yet
    s.total = #s.chapters + s.hidden
    return s
end

-- "? [12] Title  - Giver" lines for the undiscovered chapters' first quests
local function startLines(s, max)
    local out = {}
    for i, q in ipairs(s.starts or {}) do
        if i > max then
            out[#out + 1] = "|cffaaaaaa" .. (L["and %d more"]):format(#s.starts - max) .. "|r"
            break
        end
        local line, who = ns.Journal.ToDoLine(q)
        out[#out + 1] = "|cffffd100?|r " .. line .. (who and ("  |cffaaaaaa" .. q.giver .. "|r") or "")
    end
    return out
end

local function storyTooltip(owner, s, hint)
    if owner then GameTooltip:SetOwner(owner, "ANCHOR_RIGHT") end
    GameTooltip:AddLine(ns.zoneLocal(s.zone))
    for _, c in ipairs(s.chapters) do
        local total = c.ch.total or #c.ch.entries
        local finished = c.ch.done >= total
        GameTooltip:AddDoubleLine((finished and READY or WAITING) .. " " .. c.ch.title, ("%d/%d"):format(c.ch.done, total),
            1, 1, 1, 0.8, 0.8, 0.8)
    end
    if s.starts then
        GameTooltip:AddLine(L["Chapters to discover"], 0.6, 0.6, 0.6)
        for _, line in ipairs(startLines(s, 8)) do GameTooltip:AddLine(line, 1, 1, 1) end
    elseif s.hidden > 0 then
        GameTooltip:AddLine(s.hidden == 1 and L["1 chapter still to discover"] or (s.hidden .. L[" chapters still to discover"]), 0.6, 0.6, 0.6)
    end
    if hint then GameTooltip:AddLine(hint, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

---@class ChronicleNextPinMixin: MapCanvasPinMixin
---@field Icon Texture
---@field Glow Texture
---@field step table
ChronicleNextPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
function ChronicleNextPinMixin:OnLoad()
    if self.UseFrameLevelType then self:UseFrameLevelType(storyLevel) end
    self:SetScalingLimits(1, 1.0, 1.2)
end
function ChronicleNextPinMixin:SetPassThroughButtons() end
function ChronicleNextPinMixin:CheckMouseButtonPassthrough() end
function ChronicleNextPinMixin:OnAcquired(step, x, y)
    self.step = step
    self:SetPosition(x, y)
end
function ChronicleNextPinMixin:OnMouseEnter()
    local st = self.step
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["The story continues"])
    GameTooltip:AddLine(st.ch.title, 1, 1, 1)
    if st.who then GameTooltip:AddLine((L["Speak with %s"]):format(st.who), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(L["Click to open the chapter"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function ChronicleNextPinMixin:OnMouseLeave() GameTooltip:Hide() end
function ChronicleNextPinMixin:OnClick(button)
    if button and button ~= "LeftButton" then return end
    ns.Journal.Open(self.step.ch.key)
end

-- the next quest of each started, unfinished chapter: its giver, if it stands in this zone and you can take it now
local function addNextPins(map, s)
    local l = ns.Lore or {}
    for _, c in ipairs(s.chapters) do
        local state = {}
        for _, e in ipairs(c.ch.entries) do state[e.id] = e.state end
        local busy = false
        for _, e in ipairs(c.ch.entries) do if e.state == "active" then busy = true end end
        if not busy then
            for _, q in ipairs(c.arc.quests or {}) do
                if not state[q] and not flagged(q) then
                    local at = ns.StepAt(q)
                    if at and l.stepZones[at[1]] == s.zone then
                        acquire(NTEMPLATE, { ch = c.ch, who = personName(q, "giverOf") }, at[2] / 100, at[3] / 100)
                    end
                    break
                end
            end
        end
    end
end

-- continent maps: hover a zone to see its story (no labels cluttering the map)
local hover = CreateFrame("Frame")
hover:Hide()
local hoverZone, hoverWait = nil, 0
hover:SetScript("OnUpdate", function(self, elapsed)
    hoverWait = hoverWait - elapsed
    if hoverWait > 0 then return end
    hoverWait = 0.1
    local map = self.map
    if not (map and map:IsShown()) then self:Hide() return end
    local sc = map.ScrollContainer
    local zone, owner = nil, sc or map
    if sc and sc:IsMouseOver() and sc.GetNormalizedCursorPosition then
        local x, y = sc:GetNormalizedCursorPosition()
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, map:GetMapID(), x, y)
        if ok and info and info.mapID ~= map:GetMapID() then zone = ns.zoneEN(info.name) end
    end
    if zone == hoverZone then return end
    hoverZone = zone
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
    if not zone then return end
    if GameTooltip:IsShown() and GameTooltip:GetOwner() ~= owner then return end -- a pin's tooltip is showing
    local s = zoneStory(zone)
    if s.total == 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    storyTooltip(nil, s)
end)

local function watchHover(map)
    hover.map, hoverZone = map, nil
    hover:Show()
end

-- zone maps: a small panel in the corner with the zone's story
local panel, showPanel
local function storyPanel()
    if panel then return panel end
    local host = WorldMapFrame.ScrollContainer or WorldMapFrame
    local p = CreateFrame("Frame", nil, ns.Overlay(host), "BackdropTemplate")
    p:SetPoint("TOPLEFT", host, "TOPLEFT", 44, -8) -- right of the map's own corner button, never on it
    p:SetSize(250, 60)
    p:SetFrameStrata("HIGH")
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    p:SetBackdropColor(0.06, 0.05, 0.04, 0.85)
    p:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    -- the quest log's own dark background behind the text, where the client has it
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestLog-main-background") then
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("QuestLog-main-background"); bg:SetPoint("TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", -2, 2)
        p:SetBackdropColor(0, 0, 0, 0)
    end
    -- the new windows' diamond-metal border where the client has it: a little more room inside for it
    -- the quest log's own frame first (the same as the story-so-far page beside the log), else the diamond metal
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestLog-frame") then
        local rim = p:CreateTexture(nil, "ARTWORK", nil, -1)
        rim:SetAtlas("QuestLog-frame"); rim:SetPoint("TOPLEFT", -3, 3); rim:SetPoint("BOTTOMRIGHT", 3, -3)
        p.fancy = true
    else
        p.fancy = ns.FancyBorder(p) ~= nil
    end
    local pad = p.fancy and 5 or 0
    if p.fancy then p:SetBackdropBorderColor(0, 0, 0, 0) end
    -- a small +/- button folds the panel; clicking the title does the same
    p.fold = p:CreateTexture(nil, "OVERLAY")
    p.fold:SetSize(14, 14); p.fold:SetPoint("TOPLEFT", 8 + pad, -7 - pad)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("LEFT", p.fold, "RIGHT", 4, 0); p.title:SetPoint("RIGHT", p, "RIGHT", -8 - pad, 0)
    p.title:SetJustifyH("LEFT")
    local toggle = CreateFrame("Button", nil, p)
    toggle:SetPoint("TOPLEFT", p.fold, "TOPLEFT", -3, 3); toggle:SetPoint("BOTTOMRIGHT", p.title, "BOTTOMRIGHT", 4, -3)
    toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    toggle:GetHighlightTexture():ClearAllPoints(); toggle:GetHighlightTexture():SetAllPoints(p.fold)
    toggle:SetScript("OnClick", function()
        ns.db.storyPanelCollapsed = not ns.db.storyPanelCollapsed or nil
        if p.story then showPanel(p.story) end
    end)
    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.body:SetPoint("TOPLEFT", p.fold, "BOTTOMLEFT", 0, -5); p.body:SetPoint("RIGHT", -8 - pad, 0)
    p.body:SetJustifyH("LEFT"); p.body:SetSpacing(3)
    p.play = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.play:SetSize(104, 20); ns.FitButton(p.play); p.play:SetPoint("BOTTOMLEFT", 6 + pad, 6 + pad)
    p.play:SetScript("OnClick", function(b)
        if ns.Voice.Owner() == b then ns.Voice.Stop() else ns.Voice.PlayQueue(b.keys or {}, b) end
    end)
    p.open = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.open:SetSize(70, 20); ns.FitButton(p.open); p.open:SetPoint("LEFT", p.play, "RIGHT", 4, 0)
    p.open:SetText(L["Journal"])
    p.open:SetScript("OnClick", function(b) if b.key then ns.Journal.Open(b.key) end end)
    panel = p
    return p
end

local function plural(n, one, many) return n == 1 and ("1 " .. one) or (n .. " " .. many) end
local MAX_LINES = 7

function showPanel(s)
    local p = storyPanel()
    p.story = s
    local going, finished = {}, 0
    for _, c in ipairs(s.chapters) do
        local total = c.ch.total or #c.ch.entries
        if c.ch.done >= total then finished = finished + 1 else going[#going + 1] = c end
    end
    -- closest to done first
    table.sort(going, function(a, b)
        local fa = a.ch.done / math.max(1, a.ch.total or #a.ch.entries)
        local fb = b.ch.done / math.max(1, b.ch.total or #b.ch.entries)
        if fa ~= fb then return fa > fb end
        return a.ch.title < b.ch.title
    end)
    local collapsed = ns.db.storyPanelCollapsed
    p.fold:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    p.title:SetText((L["The story of %s"]):format(ns.zoneLocal(s.zone)))
    local lines = {}
    if collapsed then
        local bits = {}
        if #going > 0 then bits[#bits + 1] = #going .. L[" in progress"] end
        if finished > 0 then bits[#bits + 1] = finished .. L[" finished"] end
        if s.hidden > 0 then bits[#bits + 1] = s.hidden .. L[" to discover"] end
        lines[1] = "|cffaaaaaa" .. table.concat(bits, "  ·  ") .. "|r"
    else
        for i, c in ipairs(going) do
            if i > MAX_LINES then
                lines[#lines + 1] = "|cffaaaaaa" .. plural(#going - MAX_LINES, L["more chapter"], L["more chapters"]) .. L[" in the journal|r"]
                break
            end
            lines[#lines + 1] = (L["%s %s  |cffaaaaaa%d/%d|r"]):format(WAITING, c.ch.title, c.ch.done, c.ch.total or #c.ch.entries)
        end
        if finished > 0 then lines[#lines + 1] = READY .. " " .. plural(finished, L["chapter finished"], L["chapters finished"]) end
        if s.starts then
            lines[#lines + 1] = "|cff999999" .. L["Chapters to discover"] .. "|r"
            for _, line in ipairs(startLines(s, 5)) do lines[#lines + 1] = line end
        elseif s.hidden > 0 then
            lines[#lines + 1] = "|cff999999" .. plural(s.hidden, L["chapter"], L["chapters"]) .. L[" still to discover|r"]
        end
    end
    p.body:SetText(table.concat(lines, "\n"))
    local keys = ns.Journal.ZoneStoryKeys and ns.Journal.ZoneStoryKeys(s.zone) or {}
    p.play.keys = keys
    p.play:SetText(ns.Voice.Owner() == p.play and L["Stop"] or L["Play story"])
    p.play:SetEnabled(#keys > 0 or ns.Voice.Owner() == p.play)
    local first = going[1] or s.chapters[1]
    p.open.key = first and first.ch.key
    local buttons = not collapsed and #s.chapters > 0
    p.play:SetShown(buttons)
    p.open:SetShown(buttons and p.open.key ~= nil)
    p:SetHeight(p.title:GetStringHeight() + p.body:GetStringHeight() + (buttons and 46 or 20) + (p.fancy and 10 or 0))
    p:Show()
end

-- Voice.lua calls this when something starts or stops talking: keep the panel's Play/Stop button honest
function M.OnVoiceChanged()
    if panel and panel:IsShown() then
        local mine = ns.Voice.Owner() == panel.play
        panel.play:SetText(mine and L["Stop"] or L["Play story"])
        panel.play:SetEnabled(mine or #(panel.play.keys or {}) > 0)
    end
end

-- data provider: which chapters to show on the map being viewed
local provider

local function refresh(self)
    local map = self:GetMap()
    ownMap = map
    releaseAll()
    hover:Hide()
    if panel then panel:Hide() end
    if not (ns.settings and ns.char) then return end
    local info = C_Map.GetMapInfo(map:GetMapID())
    if not info then return end
    local zone = ns.zoneEN(info.name)
    -- the panel and the books are separate options: some want the list without the pins
    if (ns.settings.storyPanel ~= false or ns.settings.mapPins) and Enum and Enum.UIMapType then
        local ok, err = pcall(function()
            if info.mapType == Enum.UIMapType.Continent then
                if ns.settings.storyPanel ~= false then watchHover(map) end
            elseif info.mapType == Enum.UIMapType.Zone then
                local s = zoneStory(zone)
                if s.total > 0 then
                    if ns.settings.storyPanel ~= false then showPanel(s) end
                    if ns.settings.mapPins then addNextPins(map, s) end
                end
            end
        end)
        if not ok and ns.settings.debug then ns.pr("debug: story map: " .. tostring(err)) end
    end
    if ns.settings.questMarkers and not questieRunning() then
        local ok, err = pcall(addQuestPins, map, zone)
        if not ok and ns.settings.debug then ns.pr("debug: quest markers: " .. tostring(err)) end
    end
    if not ns.settings.mapPins then return end
    local pins = {}
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        if a.pin and a.pin[1] == zone then pins["arc:" .. a.id] = a.pin end
    end
    for _, ch in ipairs(ns.Journal.BuildChapters()) do
        local pin = pins[ch.key]
        if pin then acquire(TEMPLATE, ch, pin[2] / 100, pin[3] / 100) end
    end
end

-- the world map's own Map Filter menu: Chronicle's map options, added the way the game's menus allow addons to
table.insert(ns.onLogin, function()
    if not (Menu and Menu.ModifyMenu) then return end
    pcall(Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(_, root)
        if not (root and root.CreateCheckbox) then return end
        local function toggle(key, default)
            return function() if ns.settings[key] == nil then return default end return ns.settings[key] and true or false end,
                function()
                    local on = ns.settings[key]
                    if on == nil then on = default end
                    ns.settings[key] = not on
                    M.Refresh()
                end
        end
        root:CreateDivider()
        root:CreateTitle("Chronicle")
        local get, set = toggle("mapPins", true)
        root:CreateCheckbox(L["Story pins"], get, set)
        get, set = toggle("storyPanel", true)
        root:CreateCheckbox(L["Story panel"], get, set)
        get, set = toggle("questMarkers", false)
        root:CreateCheckbox(L["Quest givers (!)"], get, set)
    end)
end)

function M.Refresh()
    if provider and provider:GetMap() then refresh(provider) end
end

table.insert(ns.onLogin, function()
    if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RefreshAllData = refresh
    provider.RemoveAllData = function(self)
        releaseAll()
        if panel then panel:Hide() end
    end
    local ok, err = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider)
    if not ok then provider = nil; ns.pr(L["map pins are not available in this client: "] .. tostring(err)) end
end)

-- quests accepted, finished or handed in change the markers; the log updates in bursts, so wait a moment
local pendingRefresh
local qev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP" }) do pcall(qev.RegisterEvent, qev, e) end
qev:SetScript("OnEvent", function()
    if pendingRefresh or not (ns.settings and ns.settings.questMarkers) then return end
    pendingRefresh = true
    C_Timer.After(1, function()
        pendingRefresh = false
        if WorldMapFrame and WorldMapFrame:IsShown() then M.Refresh() end
    end)
end)

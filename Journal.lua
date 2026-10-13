-- Chronicle / Journal: "the story so far" (one chapter per story arc) and the people you have met.
-- Only quests you have done or are on are shown, and recaps are written per quest, so nothing is spoiled.
local _, ns = ...
local L = ns.L
local J = {}
ns.Journal = J

local W, H, LIST_W = 900, 580, 250
local frame, list, listScroll, page, pageScroll, search
local tab = "story"                -- "story", "people", "attune" or "dungeons"
local listRows, entryRows = {}, {}
local chapters, selected = {}, nil
local attuneList, dungeonList = {}, {}
-- tabs with their own list on the left (and their own selection)
local OWN_LIST = { attune = true, dungeons = true }

-- the game's soft click when picking something from a list (chapters, characters, zones)
local function click() if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end end
local people, selectedPerson = {}, nil
local filter = ""
local header, person = {}, {}

-- colors: dark leather frame, parchment page with ink-colored text
local INK, INK_TITLE, INK_SOFT = { 0.18, 0.11, 0.05 }, { 0.08, 0.05, 0.02 }, { 0.30, 0.21, 0.11 }
-- titles in the game's own parchment colour, the one its quest pages use (near-black, not our old red-brown)
if GetMaterialTextColors then
    local ok, _, title = pcall(GetMaterialTextColors, "Parchment")
    if ok and type(title) == "table" and title[1] then INK_TITLE = { title[1], title[2], title[3] } end
end
local GOLD = { 0.85, 0.68, 0.35 }
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_ACTIVE = "Interface\\GossipFrame\\ActiveQuestIcon"

-- ---------------------------------------------------------------- data
local function lore() return ns.Lore or { arcs = {}, quests = {} } end

local function questTitle(id)
    local q = ns.db.quests[id]
    if q and q.title then return q.title end
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
    return (ok and t) or (L["Quest %d"]):format(id)
end

-- starting zones of one race only: WoW: Forever gives each race's version of a quest the same number there
local RACE_ZONES = { ["Zephras Isle"] = "Skyborne" }

local function personOf(id, which)
    local l = lore()
    local q = ns.db.quests[id]
    local rec = q and q[which == "ender" and "ender" or "giver"]
    if rec and rec.name then return rec.name end
    -- the shipped giver or ender was recorded in another race's starting zone (Windshaper Boro for a tauren's
    -- Call of Earth): not someone this character has met
    local r = RACE_ZONES[ns.LoreZone and ns.LoreZone(id) or ""]
    if r and r ~= select(2, UnitRace("player")) then return nil end
    local map = l[which == "ender" and "enderOf" or "giverOf"]
    local i = map and map[id]
    return i and l.people and l.people[i] or nil
end

local function excerpt(text, n)
    if not text then return nil end
    text = text:gsub("\r", ""):gsub("\n+", " ")
    if #text <= n then return text end
    return (text:sub(1, n):match("^(.*)%s") or text:sub(1, n)) .. "..."
end

local function matches(...)
    if filter == "" then return true end
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if s and s:lower():find(filter, 1, true) then return true end
    end
    return false
end

local function flaggedDone(id)
    if ns.char.done[id] then return true end
    local ok, d = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and d or false
end

-- Show what's left (option): the quests of a chapter this character has not done or started yet and can take, in
-- the chapter's order, by name, level and giver. Never any story text.
-- a quest picked by profession ("Camping 101: Mining"): never missing, only shown once done
local function optional(id) return (lore().optional or {})[id] end

function J.StillToDo(quests)
    local out = {}
    for _, id in ipairs(quests or {}) do
        if not optional(id) and not flaggedDone(id) and not ns.char.active[id] and (not ns.Map or ns.Map.ForMe(id)) then
            local info = ns.Map and ns.Map.QuestInfo(id) or {}
            local title = (ns.db.quests[id] and ns.db.quests[id].title) or info.t or (lore().titles or {})[id]
            if not title then
                local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
                title = ok and t or nil
            end
            if title then
                out[#out + 1] = { id = id, title = title, lvl = info.lvl, min = info.min, giver = personOf(id, "giver"),
                    zone = info.zone, x = info.x, y = info.y }
            end
        end
    end
    return out
end

-- "[12] Title" with the level coloured like the quest log, and who gives it and where
function J.ToDoLine(q, withPlace)
    local lvl = ""
    if q.lvl and q.lvl > 0 then
        local c = GetQuestDifficultyColor and GetQuestDifficultyColor(q.lvl)
        lvl = c and ("|cff%02x%02x%02x[%d]|r "):format(c.r * 255, c.g * 255, c.b * 255, q.lvl) or ("[" .. q.lvl .. "] ")
    end
    local where = ""
    if withPlace and q.zone and q.x then where = (" (%s %.0f, %.0f)"):format(ns.zoneLocal(q.zone), q.x, q.y) end
    return lvl .. q.title, q.giver and ((L["Given by %s"]):format(q.giver) .. where) or nil
end

-- starting zones that belong to one race (the race's token from UnitRace)

-- is this chapter for this character's race at all
function J.ArcForMyRace(arc)
    local r = RACE_ZONES[arc.zone or ""]
    return not r or r == select(2, UnitRace("player"))
end

-- the professions this character has learned, as the game's skill line IDs (Cooking 185, Fishing 356, ...)
local SKILL_ID = { Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Herbalism = 182,
    Leatherworking = 165, Mining = 186, Skinning = 393, Tailoring = 197, Cooking = 185, ["First Aid"] = 129,
    Fishing = 356 }
local profCache, profAt
local function myProfessions()
    if profAt == GetTime() then return profCache end
    local have = {}
    if GetProfessions and GetProfessionInfo then
        for _, i in pairs({ GetProfessions() }) do
            local ok, _, _, _, _, _, _, line = pcall(GetProfessionInfo, i)
            if ok and line then have[line] = true end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then -- the classic skill list (names in English clients)
        for i = 1, GetNumSkillLines() do
            local name = GetSkillLineInfo(i)
            if name and SKILL_ID[name] then have[SKILL_ID[name]] = true end
        end
    end
    profCache, profAt = have, GetTime()
    return have
end

-- has this character learned this profession ("Mining")? An unknown name counts as yes.
function J.HasProfession(name)
    local id = SKILL_ID[name]
    return not id or myProfessions()[id] or false
end

-- a Class, Profession and Events chapter not yet started: shown only for this class, the professions this
-- character has, and for a holiday only while the game's calendar says it is on
function J.ArcForMe(arc)
    local classBit = 2 ^ ((select(3, UnitClass("player")) or 1) - 1)
    if arc.cls and bit.band(arc.cls, classBit) == 0 then return false end
    if arc.event and not (ns.Holiday and ns.Holiday.IsOn(arc.event)) then return false end
    if arc.prof and not myProfessions()[arc.prof] then return false end
    return J.ArcForMyRace(arc)
end

-- The chapters are built from every chapter in the lore (about 800), which the map and the journal ask for
-- several times each time they open: kept until something they depend on changes (quests done or taken, the zone
-- you're in, your professions, a holiday, the "show what's left" option).
local built = {}
local function signature(withLocked)
    local c = ns.char
    local active = 0
    for _ in pairs(c.active) do active = active + 1 end
    local profs = {}
    for id in pairs(myProfessions()) do profs[#profs + 1] = id end
    table.sort(profs)
    return table.concat({ #c.journal, active, tostring(withLocked), tostring(ns.settings.showLeft), tostring(ns.settings.hideUnfound),
        GetRealZoneText and GetRealZoneText() or "", table.concat(profs, ","),
        ns.Holiday and ns.Holiday.Signature and ns.Holiday.Signature() or "" }, "|")
end

function J.BuildChapters(withLocked)
    local sig = signature(withLocked)
    local cached = built[withLocked and true or false]
    if cached and cached.sig == sig then
        chapters = cached.out
        return cached.out
    end
    local c = ns.char
    local pos = {}
    for i, e in ipairs(c.journal) do pos[e.id] = i end
    local used, out = {}, {}
    local BIG = 1e9
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    local myRace = select(2, UnitRace("player"))
    local undiscovered = {}

    for _, arc in ipairs(lore().arcs or {}) do
        local ch = { key = "arc:" .. arc.id, title = arc.title, zone = arc.zone, intro = arc.intro, arc = arc,
            introKey = "arc:" .. arc.id, entries = {}, total = #(arc.quests or {}), order = BIG }
        -- the other faction's chapter: Forever starting-zone quests share a completed flag with their twin in
        -- another zone, so they can look done here without ever being played
        -- the same goes for a race's own starting zone (Zephras Isle is the Skyborne's): its quests can look done
        -- for another race through a twin's flag, so its chapters are only for that race
        local zoneRace = RACE_ZONES[arc.zone or ""]
        local foreign = (arc.side and side ~= "" and arc.side ~= side) or (zoneRace and zoneRace ~= myRace)
        if foreign then for _, id in ipairs(arc.quests or {}) do used[id] = true end end
        for _, id in ipairs(foreign and {} or arc.quests or {}) do
            local state = c.done[id] and "done" or (c.active[id] and "active") or nil
            if state then
                ch.entries[#ch.entries + 1] = { id = id, state = state }
                ch.order = math.min(ch.order, pos[id] or BIG - 1)
                used[id] = true
            end
        end
        -- the total counts the profession quests only when you have taken them
        for _, id in ipairs(foreign and {} or arc.quests or {}) do
            if optional(id) and not (c.done[id] or c.active[id]) then ch.total = ch.total - 1 end
        end
        if #ch.entries > 0 then
            out[#out + 1] = ch
        elseif withLocked and not foreign and J.ArcForMe(arc) then
            undiscovered[#undiscovered + 1] = ch
        end
    end

    -- Show what's left: chapters not found yet, in the zones this story has reached and the zone you're in. Only
    -- where they start; the chapter itself opens once you take that quest.
    if withLocked and ns.settings.showLeft and not ns.settings.hideUnfound then
        local zones = {}
        for _, ch in ipairs(out) do zones[ch.zone or ""] = true end
        local here = GetRealZoneText and ns.zoneEN(GetRealZoneText())
        if here then zones[here] = true end
        for _, ch in ipairs(undiscovered) do
            if zones[ch.zone or ""] then
                local start = J.StillToDo(ch.arc.quests)[1]
                if start then
                    ch.locked, ch.start, ch.title, ch.intro = true, start, L["Undiscovered chapter"], nil
                    ch.key = "new:" .. ch.arc.id
                    out[#out + 1] = ch
                end
            end
        end
    end

    -- quests no arc covers (new ones not written up yet): one chapter per zone, in the order they were done
    local byZone = {}
    local function add(id, state, fallbackZone)
        if used[id] then return end
        used[id] = true
        local q = ns.db.quests[id] or {}
        local zone = q.zone or ns.LoreZone(id) or q.category or fallbackZone or L["Unknown lands"]
        local ch = byZone[zone]
        if not ch then
            ch = { key = "zone:" .. zone, title = L["Other tales"], zone = zone, entries = {}, order = BIG }
            byZone[zone] = ch
            out[#out + 1] = ch
        end
        ch.entries[#ch.entries + 1] = { id = id, state = state }
        ch.total = #ch.entries
        ch.order = math.min(ch.order, pos[id] or BIG - 1)
    end
    for _, e in ipairs(c.journal) do add(e.id, "done", e.zone) end
    local act = {}
    for id in pairs(c.active) do act[#act + 1] = id end
    table.sort(act, function(a, b) return (c.active[a] or 0) < (c.active[b] or 0) end)
    for _, id in ipairs(act) do add(id, "active") end

    for _, ch in ipairs(out) do
        ch.done = 0
        for _, e in ipairs(ch.entries) do if e.state == "done" then ch.done = ch.done + 1 end end
    end
    -- one heading per zone: zones in the order your story reached them, chapters in order within each zone
    local zoneFirst = {}
    for _, ch in ipairs(out) do
        local z = ch.zone or ""
        zoneFirst[z] = math.min(zoneFirst[z] or BIG, ch.order)
    end
    table.sort(out, function(a, b)
        local za, zb = zoneFirst[a.zone or ""], zoneFirst[b.zone or ""]
        if za ~= zb then return za < zb end
        if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
        return a.order < b.order
    end)
    chapters = out
    built[withLocked and true or false] = { sig = sig, out = out }
    return out
end

-- everyone who gave you or took a quest, most recent first
local function buildPeople()
    local byName, order = {}, {}
    local function touch(name, id, state, rank)
        if not name then return end
        local p = byName[name]
        if not p then
            p = { name = name, list = {}, state = {}, rank = rank }
            byName[name] = p
            order[#order + 1] = p
        end
        p.rank = math.max(p.rank, rank)
        if not p.state[id] then p.state[id] = state; p.list[#p.list + 1] = id end
    end
    -- a quest recorded in another race's starting zone (a twin of this character's own, sharing its number):
    -- its giver there is not someone this character has met
    local myRace = select(2, UnitRace("player"))
    local function elsewhere(id)
        local q = ns.db.quests[id]
        local r = q and RACE_ZONES[q.zone or ""]
        return r and r ~= myRace
    end
    for i, e in ipairs(ns.char.journal) do
        if not elsewhere(e.id) then
            touch(personOf(e.id, "giver"), e.id, "done", i)
            touch(personOf(e.id, "ender"), e.id, "done", i)
        end
    end
    local n = #ns.char.journal
    for id in pairs(ns.char.active) do touch(personOf(id, "giver"), id, "active", n + 1) end
    table.sort(order, function(a, b) return a.rank > b.rank end)
    people = order
    return order
end

-- narrator recap for a chapter: arc intro, then the per-quest recaps of quests you finished
local function recapKeys(ch)
    local keys = {}
    if ch.introKey then keys[#keys + 1] = ch.introKey end
    for _, e in ipairs(ch.entries) do
        if e.state == "done" then keys[#keys + 1] = "sum:" .. e.id end
    end
    local any = false
    for _, k in ipairs(keys) do if ns.Voice.Get(k) then any = true; break end end
    if not any then -- nothing narrated yet: the NPC lines instead
        keys = {}
        for _, e in ipairs(ch.entries) do
            keys[#keys + 1] = ns.Voice.PageKey(e.id, "detail")
            if e.state == "done" then keys[#keys + 1] = "q" .. e.id .. ":complete" end
        end
    end
    return keys
end

-- the zone's whole story so far: each started chapter's intro and your finished quests' recaps, in order
local function zoneStoryKeys(zone)
    local keys = {}
    if ns.Voice.Get("zone:" .. zone) then keys[1] = "zone:" .. zone end -- the zone's own introduction first
    local epi = ns.Endings and ns.Endings.HasEpilogue(zone) and ns.Endings.EpilogueKey(zone)
    for _, c in ipairs(chapters) do
        if c.zone == zone then
            if c.introKey and ns.Voice.Get(c.introKey) then keys[#keys + 1] = c.introKey end
            for _, e in ipairs(c.entries) do
                if e.state == "done" and ns.Voice.Get("sum:" .. e.id) then keys[#keys + 1] = "sum:" .. e.id end
            end
        end
    end
    if epi and ns.Voice.Get("epi:" .. epi) then keys[#keys + 1] = "epi:" .. epi end -- and its ending, once earned
    return keys
end

-- the story map's "Play story" button (Map.lua)
function J.ZoneStoryKeys(zone)
    J.BuildChapters()
    return zoneStoryKeys(zone)
end

-- ---------------------------------------------------------------- widgets
local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 80, 20)
    ns.FitButton(b)
    b:SetText(text)
    return b
end

local function wheel(sf, step)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * step)))
    end)
end

-- a scroll frame with the game's thin modern scrollbar just outside its right edge (hidden while everything fits),
-- or the classic one on clients without it
local function scrollFrame(parent, step)
    local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if ok and sf and sf.ScrollBar then
        local sb = sf.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, 0); sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 0)
        if sb.SetHideIfUnscrollable then sb:SetHideIfUnscrollable(true) end
        return sf
    end
    if ok and sf then sf:Hide() end
    sf = CreateFrame("ScrollFrame", nil, parent)
    wheel(sf, step)
    return sf
end

-- titles get the faint shadow the game's quest titles have (it makes them read bold); other text none
local function ink(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
    if c == INK_TITLE then fs:SetShadowColor(0, 0, 0, 0.35); fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

local function text(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    if color then ink(fs, color) end
    return fs
end

-- left list: zone headers and chapter / person rows
local function getListRow(i)
    local r = listRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetSize(LIST_W - 22, 38)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.85, 0.5, 0.08)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.85, 0.68, 0.35, 0.2)
    r.title = text(r, "GameFontNormal"); r.title:SetPoint("TOPLEFT", 8, -5); r.title:SetPoint("RIGHT", -8, 0); r.title:SetWordWrap(false)
    r.sub = text(r, "GameFontDisableSmall"); r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3); r.sub:SetPoint("RIGHT", -8, 0); r.sub:SetWordWrap(false)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("BOTTOMLEFT", 8, 3); r.bar:SetPoint("BOTTOMRIGHT", -8, 3); r.bar:SetHeight(3)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); r.bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
    r.bar:SetMinMaxValues(0, 1)
    local bbg = r.bar:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(1, 1, 1, 0.07)
    r.head = text(r, "GameFontNormalSmall", GOLD); r.head:SetPoint("BOTTOMLEFT", 4, 4); r.head:SetWordWrap(false)
    -- the game's ornate header bar behind zone headings, and a darker band on every other Characters row
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-Character-Info-Title") then
        r.headBar = r:CreateTexture(nil, "BACKGROUND"); r.headBar:SetAtlas("UI-Character-Info-Title"); r.headBar:SetAllPoints()
        r.stripe = r:CreateTexture(nil, "BACKGROUND", nil, -2); r.stripe:SetAtlas("UI-Character-Info-Line-Bounce")
        r.stripe:SetAllPoints()
    end
    -- chapters as small cards in Forever's Progress Track style: a diamond with the quests done, a check when finished
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Legacy-Rewards-Tracker-Diamond") then
        r.card = r:CreateTexture(nil, "BACKGROUND", nil, -1); r.card:SetAllPoints(); r.card:SetColorTexture(1, 0.9, 0.7, 0.05)
        r.edge = r:CreateTexture(nil, "BACKGROUND"); r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(2)
        r.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
        r.diamond = r:CreateTexture(nil, "ARTWORK"); r.diamond:SetSize(30, 30); r.diamond:SetPoint("LEFT", 2, 1)
        r.count = text(r, "GameFontHighlightSmall"); r.count:SetPoint("CENTER", r.diamond, "CENTER", 0, 0)
        r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetAtlas("worldquest-tracker-checkmark"); r.check:SetSize(20, 18)
        r.check:SetPoint("TOPRIGHT", -6, -4)
        r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", 36, -5); r.title:SetPoint("RIGHT", -28, 0)
        r.bar:ClearAllPoints(); r.bar:SetPoint("BOTTOMLEFT", 36, 3); r.bar:SetPoint("BOTTOMRIGHT", -8, 3)
        -- hovering a chapter card says what the gem means
        r:SetScript("OnEnter", function(self)
            local ch = self.kind == "chapter" and self.chapter
            if not ch then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ch.title)
            if ch.locked then
                GameTooltip:AddLine((L["Starts with %s"]):format(ch.start.title), 1, 1, 1)
                if ch.start.giver then GameTooltip:AddLine((L["Given by %s"]):format(ch.start.giver), 0.8, 0.8, 0.8) end
            else
                local total = ch.total or #ch.entries
                GameTooltip:AddLine((L["%d of %d quests done"]):format(ch.done, total), 1, 1, 1)
                local going = #ch.entries - ch.done
                if ch.done >= total then
                    GameTooltip:AddLine(L["Finished"], 0.3, 0.9, 0.3)
                elseif going > 0 then
                    GameTooltip:AddLine(going .. L[" in progress"], 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- folding a zone: remember per character which zones are folded; an explicit choice beats the default
    local function fold(self)
        local c = ns.char.collapsed or {}
        ns.char.collapsed = c
        c[self.which] = c[self.which] or {}
        c[self.which][self.zone] = self.open
        J.Refresh()
    end
    -- the small +/- on a zone heading folds it, and so does the heading itself
    r.foldBtn = CreateFrame("Button", nil, r)
    r.foldBtn:SetSize(14, 14); r.foldBtn:SetPoint("LEFT", 8, 0)
    r.foldBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    r.foldBtn:SetScript("OnClick", function() click(); fold(r) end)
    r:SetScript("OnClick", function(self)
        click()
        if self.kind == "chapter" then J.Select(self.key) elseif self.kind == "person" then J.ShowPerson(self.key)
        elseif self.kind == "head" and self.zone then
            fold(self)
        end
    end)
    listRows[i] = r
    return r
end

local function setRowKind(r, kind)
    r.kind = kind
    local isHead = kind == "head"
    r.head:SetShown(isHead)
    r.foldBtn:SetShown(isHead)
    r.title:SetShown(not isHead); r.sub:SetShown(not isHead)
    r.bar:SetShown(kind == "chapter")
    if r.diamond then
        local card = kind == "chapter"
        r.card:SetShown(card); r.edge:SetShown(card); r.diamond:SetShown(card); r.count:SetShown(card); r.check:Hide()
        -- people rows keep the plain layout
        r.title:SetPoint("TOPLEFT", card and 36 or 8, -5)
    end
    if r.headBar then
        r.headBar:SetShown(isHead); r.stripe:Hide()
        r.head:ClearAllPoints()
        -- centred between the +/- button and the bar's right end, so long names never run under the button
        if isHead then r.head:SetPoint("LEFT", 26, 0); r.head:SetPoint("RIGHT", -26, 0); r.head:SetJustifyH("CENTER")
        else r.head:SetPoint("BOTTOMLEFT", 4, 4); r.head:SetJustifyH("LEFT") end
        r:SetHeight(isHead and 32 or 38)
        r:EnableMouse(true)
        return
    end
    r:SetHeight(isHead and 22 or 38)
    r:EnableMouse(true)
end

-- Zone groups in the left list fold open and shut. By default only the first (most recent) zone and the zone of
-- whatever is selected are open; while searching everything is open so no hit hides in a folded zone.
local function zoneOpen(which, zone, index, holdsSelection)
    if filter ~= "" then return true end
    local c = ns.char.collapsed and ns.char.collapsed[which]
    if c and c[zone] ~= nil then return not c[zone] end
    return index == 1 or holdsSelection
end

local function zoneHeader(h, which, zone, count, open)
    h.which, h.zone, h.open = which, zone, open
    h.sel:SetShown(which == "story" and selected == "area:" .. zone)
    h.foldBtn:Show()
    h.foldBtn:SetNormalTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    h.head:SetText((L["%s  |cff8a6d45(%d)|r"]):format(ns.zoneLocal(zone):upper(), count))
end

-- small tips about what the addon can do, shown one at a time under a chapter (Options: Tips in the journal)
local TIPS = {
    "Open the world map: the story map shows each zone's chapters, and Play story tells the whole zone from the start.",
    "Every NPC you have met is on the Characters tab, with a short bio. Click their name in a chapter to jump there.",
    "Sit down by a camp fire and the narrator can tell you a tale about the zone while you wait.",
    "You can bind Play or stop, Skip and the journal to keys or controller buttons: Key Bindings, AddOns, Chronicle.",
    "/lore welcome shows a zone's introduction again, and capital cities have one too.",
    "Finish most of a zone's story and its epilogue is added at the end of Play story.",
    "Select a quest in your quest log to see where it stands in its chapter.",
    "Found a new Forever quest with no voice? /lore share, then paste it on the Chronicle Discord, and it gets voiced in an update.",
}
local tipIndex = math.random(#TIPS)

-- a Play button: Stop when it is the one talking, otherwise start its own lines
local function toggle(b, play)
    if ns.Voice.Owner() == b then ns.Voice.Stop() else play() end
end

-- right page rows (story entries)
local function getEntryRow(i)
    local r = entryRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, page)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("TOPLEFT", 0, -1)
    r.title = text(r, "QuestTitleFont", INK_TITLE); r.title:SetPoint("TOPLEFT", 20, 0)
    r.who = CreateFrame("Button", nil, r)
    r.who:SetHeight(14); r.who:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.who.text = text(r.who, "GameFontNormalSmall", INK_SOFT); r.who.text:SetPoint("LEFT")
    r.who:SetScript("OnEnter", function(self) self.text:SetTextColor(INK_TITLE[1], INK_TITLE[2], INK_TITLE[3]) end)
    r.who:SetScript("OnLeave", function(self) ink(self.text, INK_SOFT) end)
    r.who:SetScript("OnClick", function(self) click(); if self.name then J.ShowPerson(self.name) end end)
    r.body = text(r, "QuestFont", INK); r.body:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -5); r.body:SetSpacing(2)
    r.play = button(r, L["Quest"], 64)
    r.recap = button(r, L["Recap"], 64)
    entryRows[i] = r
    return r
end

-- ---------------------------------------------------------------- render: story
local todoRows = {} -- Show what's left lines (see getTodoRow below)
local chronPool, chronUsed = {}, {} -- Your chronicle's boxes, cards and timeline pieces, by kind

local function hideAll()
    for _, r in ipairs(todoRows) do r:Hide() end
    for kind, pieces in pairs(chronPool) do
        for _, f in ipairs(pieces) do f:Hide() end
        chronUsed[kind] = 0
    end
    for _, r in ipairs(entryRows) do r:Hide() end
    for _, v in pairs(header) do if v.Hide then v:Hide() end end
    for _, v in pairs(person) do if type(v) == "table" and v.Hide then v:Hide() end end
    for _, r in ipairs(person.deal or {}) do r:Hide() end
end

-- Show what's left lines on the parchment: a missing quest (click: a marker at its giver on the map), or a quiet
-- label between them on the zone page
local function getTodoRow(i)
    local r = todoRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page)
    r.pin = r:CreateTexture(nil, "ARTWORK"); r.pin:SetSize(14, 14); r.pin:SetPoint("TOPLEFT", 0, -1)
    r.pin:SetTexture("Interface\\AddOns\\ForeverChronicle\\Media\\pin")
    r.title = text(r, "QuestFont", INK); r.title:SetPoint("TOPLEFT", 20, 0); r.title:SetJustifyH("LEFT")
    r.who = text(r, "GameFontNormalSmall", INK_SOFT); r.who:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
    r.who:SetJustifyH("LEFT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.55, 0.35, 0.1, 0.12)
    r:SetScript("OnClick", function(self)
        click()
        local q = self.quest
        if q and q.open then J.Open(q.open)
        elseif q and q.keys then
            if ns.Voice.Owner() == self then ns.Voice.Stop() else ns.Voice.PlayQueue(q.keys, self) end
        elseif q and ns.Map then ns.Map.Waypoint(q.zone, q.x, q.y, q.title) end
    end)
    r:SetScript("OnEnter", function(self)
        if not (self.quest and self.quest.x) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.quest.title, 1, 1, 1)
        GameTooltip:AddLine(self.quest.tip or L["Click to mark the quest giver on the map"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    todoRows[i] = r
    return r
end

-- lays out quests (or a label when q is a string) from row n on, from y down; returns the new y and next n
local function placeTodos(items, y, n, pw, x)
    x = x or 0
    for _, q in ipairs(items) do
        local r = getTodoRow(n)
        n = n + 1
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", page, "TOPLEFT", x, y); r:SetWidth(pw - 10 - x)
        r.title:SetWidth(pw - 34 - x); r.who:SetWidth(pw - 34 - x)
        r:SetFrameLevel(page:GetFrameLevel() + 5) -- above a chapter card it sits in
        if type(q) == "string" then
            r.quest = nil; r.pin:Hide(); r:EnableMouse(false)
            r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", 0, 0)
            r.title:SetFontObject("QuestTitleFont"); r.title:SetText(q); r.who:SetText("")
        else
            r.quest = q; r:EnableMouse(q.x ~= nil or q.open ~= nil or q.keys ~= nil)
            r.pin:SetTexture(q.icon or "Interface\\AddOns\\ForeverChronicle\\Media\\pin")
            r.pin:SetSize(q.icon and 16 or 14, q.icon and 16 or 14)
            r.pin:SetShown(q.x ~= nil or q.icon ~= nil)
            r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", 20, 0)
            r.title:SetFontObject("QuestFont")
            local line, who = J.ToDoLine(q, true)
            if q.from then
                who = q.from .. (q.x and (" (%s %.0f, %.0f)"):format(ns.zoneLocal(q.zone), q.x, q.y) or "")
            end
            if q.extra then who = (who and (who .. "\n") or "") .. q.extra end
            r.title:SetText(line); r.who:SetText(who or "")
        end
        ink(r.title, type(q) == "string" and INK_TITLE or INK)
        r:Show() -- shown before measuring: a new row's text reads 0 tall while hidden (its second line got no room)
        local h = r.title:GetStringHeight() + (r.who:GetText() ~= "" and (r.who:GetStringHeight() + 4) or 0) + 4
        r:SetHeight(h)
        y = y - h - 6
    end
    return y, n
end

-- the way to a zone's own page (Zone overview); for the Class, Profession and Events chapters it lists only what
-- applies to this character (J.ArcForMe)
local function showZoneLinks(zone)
    local on = zone and true
    header.zoneLink.zone, header.overview.zone = zone, zone
    header.zoneLink:SetShown(on and true or false); header.overview:SetShown(on and true or false)
end

-- the button at the top right of the page: Play recap on a chapter, Listen (or another label) elsewhere
-- "Tell my chronicle": how long it is and how far it has got, and (option) a pause after each chapter, with the
-- button turning into Continue (thanks Cav3dust)
local tell = { keys = nil, i = 0, waiting = false }

local function tellSeconds(keys, from)
    local total = 0
    for i = from or 1, #keys do
        local e = ns.Voice.Get(keys[i])
        total = total + (e and e.d or 0)
    end
    return total
end

local function minutes(seconds) return math.max(1, math.floor(seconds / 60 + 0.5)) end

function J.TellChronicle(b)
    if ns.Voice.Owner() == b then -- Stop
        ns.Voice.Stop()
        tell.keys, tell.i, tell.waiting = nil, 0, false
        J.OnVoiceChanged()
        return
    end
    if not tell.waiting then
        local keys = {}
        for _, k in ipairs(b.keys or {}) do if ns.Voice.Get(k) then keys[#keys + 1] = k end end
        if #keys == 0 then return end
        tell.keys, tell.i = keys, 0
    end
    tell.waiting = false
    if ns.settings.chroniclePause then
        tell.i = tell.i + 1
        ns.Voice.PlayQueue({ tell.keys[tell.i] }, b)
    else
        local rest = {}
        for i = tell.i + 1, #tell.keys do rest[#rest + 1] = tell.keys[i] end
        tell.i = #tell.keys
        ns.Voice.PlayQueue(rest, b)
    end
end

-- the line under the button: the length, or where it has got to
local function tellInfo()
    local fs = header.tellInfo
    if not (fs and fs:IsShown()) then return end
    local keys = tell.keys
    if keys and ns.Voice.Owner() == header.recap then
        local idx
        local playing = ns.Voice.PlayingKey()
        for i, k in ipairs(keys) do if k == playing then idx = i; break end end
        if idx then
            local e = ns.Voice.Get(playing)
            local left = tellSeconds(keys, idx + 1) + math.max(0, (e and e.d or 0) - (ns.Voice.PlayingFor() or 0))
            fs:SetText((L["Chapter %d of %d  ·  about %d min left"]):format(idx, #keys, minutes(left)))
            return
        end
    elseif keys and tell.waiting then
        fs:SetText((L["Paused after chapter %d of %d"]):format(tell.i, #keys))
        return
    end
    local mine = {}
    for _, k in ipairs(header.recap.keys or {}) do if ns.Voice.Get(k) then mine[#mine + 1] = k end end
    local count = #mine == 1 and L["1 chapter  ·  about %d min"]:format(minutes(tellSeconds(mine)))
        or (L["%d chapters  ·  about %d min"]):format(#mine, minutes(tellSeconds(mine)))
    fs:SetText(#mine > 0 and count or "")
end

local function listenButton(keys, label)
    header.recap.tell = nil
    header.recap.libraryToggle = nil
    header.recap.keys, header.recap.label = keys, label
    local any = false
    for _, k in ipairs(keys) do if ns.Voice.Get(k) then any = true; break end end
    header.recap.anyAudio = any
    header.recap:SetText(label)
    local fs = header.recap:GetFontString() -- wide enough for its label ("Tell my chronicle")
    header.recap:SetWidth(math.max(100, (fs and fs:GetStringWidth() or 0) + 28))
    header.recap:SetText(ns.Voice.Owner() == header.recap and L["Stop"] or label)
    header.recap:SetEnabled(true)
    header.recap:SetShown(any and not ns.settings.journalOnly)
end

local function renderChapter(ch)
    local pw = page:GetWidth()
    hideAll()
    for _, r in ipairs(todoRows) do r:Hide() end
    header.title:Show(); header.sub:Show(); header.intro:Show()
    if not ch then
        header.title:SetText(filter ~= "" and L["Nothing matches your search"] or L["Your story has not begun"])
        header.sub:SetText("")
        header.intro:SetText(filter ~= "" and "" or L["Accept or finish a quest and it will be written here."])
        page:SetHeight(120)
        return
    end
    if ch.locked then
        -- a chapter not found yet: only where it starts, nothing of its story
        header.title:SetText(ch.title)
        header.sub:SetText(ns.zoneLocal(ch.zone) or "")
        showZoneLinks(ch.zone)
        header.intro:SetWidth(pw - 10)
        header.intro:SetText(L["You haven't found this chapter yet. Take its first quest and it opens here."])
        local y = -(54 + header.intro:GetStringHeight() + 18)
        y = placeTodos({ L["Starts with"], ch.start }, y, 1, pw)
        page:SetHeight(-y + 20)
        return
    end
    header.title:SetText(ch.title)
    header.sub:SetText((L["%s  -  %d of %d quests"]):format(ns.zoneLocal(ch.zone) or "", ch.done, ch.total or #ch.entries))
    showZoneLinks(ch.zone)
    header.intro:SetWidth(pw - 10)
    header.intro:SetText(ch.intro or "")
    local voices = not ns.settings.journalOnly
    header.recap:SetShown(voices); header.rule:Show()
    header.recap.keys, header.recap.label = recapKeys(ch), nil
    header.recap:SetWidth(100)
    header.zone.keys = zoneStoryKeys(ch.zone)
    header.zone:SetShown(voices and #header.zone.keys > 1)
    local anyAudio = false
    for _, k in ipairs(header.recap.keys) do if ns.Voice.Get(k) then anyAudio = true; break end end
    header.recap.anyAudio = anyAudio

    local y = -(54 + ((ch.intro and ch.intro ~= "") and (header.intro:GetStringHeight() + 14) or 0))
    header.rule:ClearAllPoints()
    header.rule:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y + 6); header.rule:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    y = y - 8
    for i, e in ipairs(ch.entries) do
        local q, l = ns.db.quests[e.id] or {}, lore().quests[e.id] or {}
        local r = getEntryRow(i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y); r:SetWidth(pw)
        r.title:SetWidth(pw - 170); r.body:SetWidth(pw - 24)
        r.icon:SetTexture(e.state == "done" and ICON_DONE or ICON_ACTIVE)
        r.title:SetText(questTitle(e.id) .. (ns.IsNew(e.id) and L["  |cff2e8f86new in Forever|r"] or "")
            .. (e.state == "active" and L["  |cff8a6d45(in progress)|r"] or ""))

        local giver = personOf(e.id, "giver")
        r.who.name = giver
        r.who.text:SetText(giver and (L["Given by %s"]):format(giver) or "")
        r.who:SetWidth(math.max(10, r.who.text:GetStringWidth()))

        local body
        if e.state == "done" and l.summary then body = l.summary else body = excerpt(q.detail, 420) end
        body = body or (ns.Voice.Get("q" .. e.id .. ":detail") and L["Press Quest to hear the quest giver."] or L["No story written for this quest yet."])
        r.body:SetText(body)

        local qKey, sKey = ns.Voice.PageKey(e.id, "detail"), "sum:" .. e.id
        r.play:ClearAllPoints(); r.play:SetPoint("TOPRIGHT", r, "TOPRIGHT", -70, 2)
        r.recap:ClearAllPoints(); r.recap:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 2)
        r.play:SetShown(ns.Voice.Get(qKey) ~= nil)
        r.recap:SetShown(e.state == "done" and ns.Voice.Get(sKey) ~= nil)
        r.play:SetScript("OnClick", function(b) toggle(b, function() ns.Voice.Play(qKey, b) end) end)
        r.recap:SetScript("OnClick", function(b) toggle(b, function() ns.Voice.Play(sKey, b) end) end)

        local h = r.title:GetStringHeight() + 17 + r.body:GetStringHeight() + 8
        r:SetHeight(h); r:Show()
        y = y - h - 14
    end
    -- Show what's left: the chapter's quests still to do, by name, level and giver (no story)
    if ns.settings.showLeft and ch.arc then
        local left = J.StillToDo(ch.arc.quests)
        if #left > 0 then
            table.insert(left, 1, L["Still to do"])
            y = placeTodos(left, y - 2, 1, pw) - 8
        end
    end
    -- one quiet tip under the chapter, a different one each time the page is drawn
    if ns.settings.tips ~= false then
        tipIndex = tipIndex % #TIPS + 1
        header.tip:ClearAllPoints()
        header.tip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 4); header.tip:SetWidth(pw - 10)
        header.tip:SetText(L["Did you know?"] .. " " .. L[TIPS[tipIndex]])
        header.tip:Show()
        y = y - header.tip:GetStringHeight() - 12
    end
    page:SetHeight(-y + 20)
    J.OnVoiceChanged()
end

-- ---------------------------------------------------------------- render: a zone's page
-- Everything about one zone's story on one page: chapters finished, in progress and not found yet, and with Show
-- what's left the missing quests under each (click one: a marker at its giver).
-- Your chronicle's pieces: a pool per kind, taken in order on each render (hideAll puts them back)
local function chronGet(kind, make)
    chronUsed[kind] = (chronUsed[kind] or 0) + 1
    local pieces = chronPool[kind] or {}
    chronPool[kind] = pieces
    local f = pieces[chronUsed[kind]]
    if not f then f = make(); pieces[#pieces + 1] = f end
    f:ClearAllPoints(); f:Show()
    return f
end

-- a quiet box on the parchment: a faint wash and a thin brown rim; clicking it opens what it holds
local function chronBox()
    local f = CreateFrame("Button", nil, page)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.45, 0.28, 0.08, 0.10)
    local function edge(a, b, across)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.45, 0.30, 0.12, 0.55); t:SetPoint(a); t:SetPoint(b)
        if across then t:SetHeight(1) else t:SetWidth(1) end
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT"); edge("TOPRIGHT", "BOTTOMRIGHT")
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.55, 0.35, 0.1, 0.10)
    f:SetScript("OnClick", function(self) if self.key then click(); J.Open(self.key) end end)
    return f
end

local function chronBar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); b:SetStatusBarColor(0.62, 0.43, 0.14)
    b:SetMinMaxValues(0, 1); b:SetHeight(4)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.30, 0.20, 0.08, 0.20)
    return b
end

local function makeStat()
    local f = chronBox()
    f:EnableMouse(false)
    f.num = text(f, "GameFontNormalHuge", INK_TITLE); f.num:SetPoint("TOP", 0, -7); f.num:SetJustifyH("CENTER")
    f.label = text(f, "GameFontNormalSmall", INK_SOFT); f.label:SetPoint("BOTTOM", 0, 6); f.label:SetJustifyH("CENTER")
    return f
end

local function makeRoad()
    local f = chronBox()
    f.title = text(f, "QuestFont", INK_TITLE); f.title:SetPoint("TOPLEFT", 8, -7); f.title:SetPoint("RIGHT", -8, 0)
    f.title:SetWordWrap(false)
    f.sub = text(f, "GameFontNormalSmall", INK_SOFT); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.here = text(f, "GameFontNormalSmall", { 0.55, 0.30, 0.02 }); f.here:SetPoint("TOPRIGHT", -7, -8)
    f.here:SetText(L["Here now"])
    f.bar = chronBar(f); f.bar:SetPoint("BOTTOMLEFT", 8, 8); f.bar:SetPoint("BOTTOMRIGHT", -8, 8)
    f.count = text(f, "GameFontNormalSmall", INK_SOFT); f.count:SetPoint("BOTTOMLEFT", f.bar, "TOPLEFT", 0, 3)
    return f
end

local function makeMarker()
    local t = page:CreateTexture(nil, "ARTWORK")
    t:SetSize(20, 20)
    return t
end

local function makeLine()
    local t = page:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.45, 0.30, 0.12, 0.45); t:SetWidth(2)
    return t
end

-- a zone on the timeline: its name folds its chapters away (remembered per character), the link opens its page
local function makeZone()
    local f = CreateFrame("Button", nil, page)
    f.fold = f:CreateTexture(nil, "ARTWORK"); f.fold:SetSize(14, 14); f.fold:SetPoint("TOPLEFT", 0, -3)
    f.title = text(f, "QuestTitleFont", INK_TITLE); f.title:SetPoint("TOPLEFT", 18, 0)
    f.sub = text(f, "GameFontNormalSmall", INK_SOFT); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.55, 0.35, 0.1, 0.10)
    f:SetScript("OnClick", function(self)
        if not self.zone then return end
        click()
        ns.char.collapsed = ns.char.collapsed or {}
        ns.char.collapsed.chronicle = ns.char.collapsed.chronicle or {}
        ns.char.collapsed.chronicle[self.zone] = self.open -- open now: fold it
        J.Refresh()
    end)
    f.link = CreateFrame("Button", nil, f)
    f.link.label = text(f.link, "GameFontNormalSmall", { 0.55, 0.30, 0.02 }); f.link.label:SetPoint("RIGHT", 0, 0)
    f.link.label:SetText(L["Zone overview"])
    f.link:SetSize(f.link.label:GetStringWidth() + 4, 16); f.link:SetPoint("TOPRIGHT", -4, -3)
    local lhl = f.link:CreateTexture(nil, "HIGHLIGHT"); lhl:SetAllPoints(); lhl:SetColorTexture(0.55, 0.35, 0.1, 0.15)
    f.link:SetScript("OnClick", function(self) local z = self:GetParent().zone; if z then click(); J.Open("area:" .. z) end end)
    return f
end

local function makeChapter()
    local f = CreateFrame("Button", nil, page)
    f:SetHeight(20)
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(14, 14); f.icon:SetPoint("LEFT", 0, 0)
    f.count = text(f, "GameFontNormalSmall", INK_SOFT); f.count:SetPoint("RIGHT", -4, 0); f.count:SetJustifyH("RIGHT")
    f.bar = chronBar(f); f.bar:SetWidth(90); f.bar:SetPoint("RIGHT", f.count, "LEFT", -6, 0)
    f.title = text(f, "GameFontHighlight", INK); f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.title:SetWordWrap(false)
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.55, 0.35, 0.1, 0.10)
    f:SetScript("OnClick", function(self) if self.key then click(); J.Open(self.key) end end)
    return f
end

local function makeBadge()
    local f = chronBox()
    f:EnableMouse(true)
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(14, 14); f.icon:SetPoint("LEFT", 7, 0)
    f.icon:SetTexture(ICON_DONE)
    f.label = text(f, "GameFontHighlightSmall", INK); f.label:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
    f:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.label:GetText(), 1, 1, 1)
        GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8); GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function makeChapterCard()
    local f = chronBox()
    f:SetFrameLevel(page:GetFrameLevel() + 1)
    f.title = text(f, "QuestFont", INK_TITLE); f.title:SetPoint("TOPLEFT", 10, -8); f.title:SetWordWrap(false)
    f.count = text(f, "GameFontNormalSmall", INK_SOFT); f.count:SetPoint("TOPRIGHT", -10, -9); f.count:SetJustifyH("RIGHT")
    f.title:SetPoint("RIGHT", f.count, "LEFT", -8, 0)
    f.bar = chronBar(f); f.bar:SetPoint("TOPLEFT", 10, -28); f.bar:SetPoint("TOPRIGHT", -10, -28)
    -- only the card's head opens the chapter (and lights up): the quests inside have their own
    f:EnableMouse(false)
    f.head = CreateFrame("Button", nil, f)
    f.head:SetPoint("TOPLEFT"); f.head:SetPoint("TOPRIGHT"); f.head:SetHeight(36)
    local hl = f.head:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.55, 0.35, 0.1, 0.10)
    f.head:SetScript("OnClick", function() if f.key then click(); J.Open(f.key) end end)
    return f
end

local function renderZone(zone)
    local pw = page:GetWidth()
    local width = pw - 10
    hideAll()
    header.title:Show(); header.sub:Show(); header.intro:Show()
    header.title:SetText(ns.zoneLocal(zone))
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    local byKey = {}
    for _, ch in ipairs(chapters) do byKey[ch.key] = ch end
    local done, going, hidden = {}, {}, {}
    for _, arc in ipairs(lore().arcs or {}) do
        if arc.zone == zone and (not arc.side or side == "" or arc.side == side)
            and (byKey["arc:" .. arc.id] or J.ArcForMe(arc)) then
            local ch = byKey["arc:" .. arc.id]
            local left = J.StillToDo(arc.quests)
            if ch then
                local total = ch.total or #ch.entries
                if ch.done >= total then done[#done + 1] = ch
                else
                    -- the ones in your quest log first (Show what's left skips them), then what's left to pick up
                    local quests = {}
                    for _, e in ipairs(ch.entries) do
                        if e.state == "active" then
                            quests[#quests + 1] = { title = questTitle(e.id) or ("#" .. e.id), from = L["In your quest log"], open = ch.key }
                        end
                    end
                    for _, q in ipairs(left) do quests[#quests + 1] = q end
                    going[#going + 1] = { ch = ch, total = total, quests = quests }
                end
            elseif #left > 0 and not ns.settings.hideUnfound then
                -- not found yet: only where it starts, never its name or the rest
                hidden[#hidden + 1] = { quests = { left[1] } }
            end
        end
    end
    local levels = ns.Endings and ns.Endings.LevelText(zone) or ""
    local story = ns.Endings and ns.Endings.HasEpilogue(zone)
    header.sub:SetText(story and L["You have seen this story through"] or levels)
    header.intro:SetWidth(width)
    if #done + #going + #hidden == 0 then
        header.intro:SetText(L["No chapters known here yet."])
        page:SetHeight(120)
        return
    end
    if #going + #hidden == 0 then
        header.intro:SetText(L["Every chapter here is finished."])
    else
        header.intro:SetText(ns.settings.showLeft and L["Click a quest to mark its quest giver on the map."]
            or L["Turn on Show what's left in the options to see the missing quests and where to get them."])
    end
    local y, n = -(54 + header.intro:GetStringHeight() + 16), 1
    local GAP = 8

    -- the numbers, each in its own box
    local stats = { { #done, L["Finished"] }, { #going, L["In progress"] }, { #hidden, L["To discover"] } }
    if ns.settings.hideUnfound then stats[3] = nil end
    local bw = (width - GAP * (#stats - 1)) / #stats
    for i, st in ipairs(stats) do
        local b = chronGet("stat", makeStat)
        b:SetSize(bw, 50); b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (bw + GAP), y)
        b.num:SetText(tostring(st[1])); b.label:SetText(st[2])
    end
    y = y - 50 - 20

    -- chapters on the way: a card each, with the quests still to do inside it
    local function chapterCard(title, count, value, quests, key, dim)
        local c = chronGet("chapterCard", makeChapterCard)
        c:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y); c:SetWidth(width)
        c.key = key
        c.head:EnableMouse(key ~= nil)
        c.title:SetText(title); c.count:SetText(count or "")
        c.title:SetAlpha(dim and 0.6 or 1)
        c.bar:SetShown(value ~= nil); c.bar:SetValue(value or 0)
        local inner = y - (value and 38 or 30)
        if ns.settings.showLeft and #quests > 0 then inner, n = placeTodos(quests, inner, n, pw, 12) end
        c:SetHeight(y - inner + 4)
        y = inner - 4 - 10
    end
    if #going > 0 then
        y, n = placeTodos({ L["In progress"] }, y, n, pw)
        for _, g in ipairs(going) do
            chapterCard(g.ch.title, ("%d/%d"):format(g.ch.done, g.total), g.total > 0 and g.ch.done / g.total or 0,
                g.quests, g.ch.key)
        end
        y = y - 10
    end
    if #hidden > 0 then
        y, n = placeTodos({ L["To discover"] }, y, n, pw)
        for _, h in ipairs(hidden) do chapterCard(L["Undiscovered chapter"], nil, nil, h.quests, nil, true) end
        y = y - 10
    end

    -- finished chapters: a tick each (click: the chapter)
    if #done > 0 then
        y, n = placeTodos({ L["Finished"] }, y, n, pw)
        for _, ch in ipairs(done) do
            local r = chronGet("chapter", makeChapter)
            r:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y); r:SetWidth(width - 4)
            r.key = ch.key
            r.icon:SetTexture(ICON_DONE)
            r.title:SetText(ch.title)
            r.bar:Hide(); r.count:Hide()
            r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            y = y - 22
        end
    end
    y = y - 10
    -- books, plaques and letters found here: the ones you have read (click: hear it), the others only as a place
    local here = J.ZoneBooks(zone)
    J.booksAt = -y - 10
    if #here > 0 then
        local found, items, notes = 0, {}, 0
        for _, b in ipairs(here) do
            if b.found then
                found = found + 1
                items[#items + 1] = { title = b.title, from = L["Click to hear it"], keys = b.keys, icon = J.IconOf(b.title, b.x) }
            elseif not ns.settings.hideUnfound then
                if b.x then
                    items[#items + 1] = { title = L["Not found yet"], from = L["Lies here"], zone = zone, x = b.x, y = b.y,
                        tip = L["Click to mark it on the map"] }
                else
                    notes = notes + 1 -- letters have no place of their own: one line for all of them
                end
            end
        end
        if notes > 0 then
            items[#items + 1] = { title = notes == 1 and L["1 more note comes with a quest here"]
                or (L["%d more notes come with quests here"]):format(notes) }
        end
        if #items > 0 then
            y, n = placeTodos({ ns.settings.hideUnfound and ("%s  (%d)"):format(L["Books and notes"], found)
                or ("%s  (%d/%d)"):format(L["Books and notes"], found, #here) }, y, n, pw)
            y, n = placeTodos(items, y, n, pw)
            y = y - 10
        end
    end

    page:SetHeight(-y + 20)
end

-- ---------------------------------------------------------------- render: attunements
-- The quest chains that open the great dungeons and raids. The Attunements tab lists this faction's chains on the
-- left; the page shows one in full: what it opens, an introduction, and every step with its level, quest giver and
-- place (click: a marker at the giver) and what it asks.
local function attunements()
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    local out = {}
    for _, at in ipairs(lore().attunements or {}) do
        local hit = matches(at.title, at.intro)
        if hit and (not at.side or side == "" or at.side == side) then
            local done, nextId = 0, nil
            for _, id in ipairs(at.quests or {}) do
                local d = flaggedDone(id)
                for _, alt in ipairs((at.alts or {})[id] or {}) do d = d or flaggedDone(alt) end
                if d then done = done + 1 elseif not nextId then nextId = id end
            end
            out[#out + 1] = { at = at, key = "att:" .. at.id, title = at.title, done = done,
                total = #(at.quests or {}), nextId = nextId, entries = {} }
        end
    end
    return out
end

local DONE_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:-1|t "

local function renderAttunement(a)
    local pw = page:GetWidth()
    hideAll()
    header.title:Show(); header.sub:Show(); header.intro:Show()
    if not a then
        header.title:SetText(L["Attunements"]); header.sub:SetText(""); header.intro:SetText("")
        page:SetHeight(120)
        return
    end
    local at, titles = a.at, lore().titles or {}
    header.title:SetText(a.title)
    local first = (at.info or {})[at.quests[1]] or {}
    header.sub:SetText(not a.nextId and L["Attuned"]
        or a.total == 1 and (L["1 step  ·  from level %d"]):format(first.m or 0)
        or (L["%d of %d steps  ·  from level %d"]):format(a.done, a.total, first.m or 0))
    header.intro:SetWidth(pw - 10)
    header.intro:SetText(at.intro or "")
    listenButton({ "att:" .. at.id }, L["Listen"])
    local y, n = -(54 + header.intro:GetStringHeight() + 18), 1
    y, n = placeTodos({ L["The steps"] }, y, n, pw)
    local ahead, top = 0, 0
    for _, id in ipairs(at.quests or {}) do
        local info = (at.info or {})[id] or {}
        local where = ns.Map and ns.Map.QuestInfo(id) or {}
        local title = (ns.db.quests[id] and ns.db.quests[id].title) or titles[id] or where.t or "?"
        if not where.x and (info.p or info.d) then
            -- a giver inside a dungeon: its entrance (or a known spot outside)
            local p = info.p
            if not p and ns.Map then p = { ns.Map.DungeonDoor(info.d) } end
            p = p or {}
            where = { zone = p[1], x = p[2], y = p[3] }
        end
        local d = flaggedDone(id)
        for _, alt in ipairs((at.alts or {})[id] or {}) do d = d or flaggedDone(alt) end
        local state = d and DONE_ICON
            or (ns.char.active[id] and ("|cffd9a400" .. L["In progress: "] .. "|r"))
            or (id == a.nextId and ("|cff7a4b12" .. L["Next: "] .. "|r")) or ""
        if state == "" then
            -- a step still ahead: no name, giver or task (they would give the story away), only how far it goes
            ahead, top = ahead + 1, math.max(top, info.l or 0)
        else
            local giver = personOf(id, "giver")
            -- inside a dungeon and no way in on the map: at least say where they are
            if giver and info.d and not where.x then giver = giver .. (L[" (in %s)"]):format(info.d) end
            local q = { id = id, title = state .. title, lvl = info.l, giver = giver,
                from = info.i and info.d and (L["Begins with an item found in %s"]):format(info.d) or nil,
                zone = where.zone, x = where.x, y = where.y,
                -- what a step asks only once you have it: the next one would give the story away
                extra = (d or ns.char.active[id]) and info.o ~= "" and info.o or nil }
            y, n = placeTodos({ q }, y, n, pw)
        end
    end
    if ahead > 0 then
        y, n = placeTodos({ { title = "|cff7a6a55" .. (ahead == 1 and L["1 more step ahead"]
            or (L["%d more steps ahead"]):format(ahead)) .. (top > 0 and (L[", up to level %d"]):format(top) or "") .. "|r" } }, y, n, pw)
    end
    page:SetHeight(-y + 20)
end

-- Picking up the first step of an attunement: a note saying where the road leads, once per character
local attuneEv = CreateFrame("Frame")
attuneEv:RegisterEvent("QUEST_ACCEPTED")
attuneEv:SetScript("OnEvent", function(_, _, ...)
    local id = ...
    if type(id) ~= "number" or id == 0 then id = select(2, ...) end
    if type(id) ~= "number" or not (ns.char and ns.Reminder) then return end
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    for _, at in ipairs(lore().attunements or {}) do
        local first = (at.quests or {})[1]
        local hit = first == id
        for _, alt in ipairs((at.alts or {})[first or 0] or {}) do hit = hit or alt == id end
        if hit and (not at.side or at.side == side) then
            ns.char.attuneNoted = ns.char.attuneNoted or {}
            if ns.char.attuneNoted[at.id] then return end
            ns.char.attuneNoted[at.id] = time()
            C_Timer.After(2, function()
                ns.Reminder.ShowStory((L["The road to %s"]):format(at.title), at.intro or "", { "att:" .. at.id },
                    function() J.ShowAttunements(at.id) end)
            end)
            return
        end
    end
end)

-- ---------------------------------------------------------------- render: dungeons and raids
-- Every dungeon and raid with a story: its introduction, its chapters (click: open the chapter), and how its story
-- ends, once you have beaten its last boss (Endings.lua keeps when).
local RAIDS = { ["Molten Core"] = true, ["Onyxia's Lair"] = true, ["Blackwing Lair"] = true, ["Zul'Gurub"] = true,
    ["Ruins of Ahn'Qiraj"] = true, ["Ahn'Qiraj"] = true, ["Naxxramas"] = true }

-- the game's own level ranges for the original dungeons; new WoW: Forever ones take theirs from their quests
local LEVELS = { ["Ragefire Chasm"] = { 13, 18 }, ["Wailing Caverns"] = { 17, 24 }, ["The Deadmines"] = { 17, 26 },
    ["Shadowfang Keep"] = { 22, 30 }, ["Blackfathom Deeps"] = { 24, 32 }, ["The Stockade"] = { 24, 32 },
    ["Gnomeregan"] = { 29, 38 }, ["Razorfen Kraul"] = { 29, 38 }, ["Scarlet Monastery"] = { 34, 45 },
    ["Razorfen Downs"] = { 37, 46 }, ["Uldaman"] = { 41, 51 }, ["Zul'Farrak"] = { 44, 54 }, ["Maraudon"] = { 46, 55 },
    ["Sunken Temple"] = { 50, 56 }, ["Blackrock Depths"] = { 52, 60 }, ["Blackrock Spire"] = { 55, 60 },
    ["Dire Maul"] = { 55, 60 }, ["Stratholme"] = { 58, 60 }, ["Scholomance"] = { 58, 60 },
    -- new in WoW: Forever, by the levels of the quests found there so far
    ["Ruins of Lordaeron"] = { 21, 22 }, ["Excavation Site: Wetlands"] = { 31, 31 } }

local function wingOf(name, dungeon) return name == dungeon or name:sub(1, #dungeon + 2) == dungeon .. ": " end

local function dungeons()
    local lo = lore()
    local names, out = {}, {}
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    local byKey = {}
    for _, ch in ipairs(chapters) do byKey[ch.key] = ch end
    for name in pairs(lo.dungeonIntro or {}) do names[name] = true end
    for name in pairs(lo.dungeonEnd or {}) do names[name:match("^([^:]+)")] = true end
    for name in pairs(names) do
        local d = { name = name, key = "dng:" .. name, intro = (lo.dungeonIntro or {})[name], raid = RAIDS[name],
            chapters = {}, done = 0, total = 0 }
        for wing, t in pairs(ns.char.dungeonsDone or {}) do
            if wingOf(wing, name) then d.cleared = math.max(d.cleared or 0, t) end
        end
        -- all its chapters for this character: the ones begun with their progress, the others with where they start
        for _, a in ipairs(lo.arcs or {}) do
            if a.zone == name and not (a.side and side ~= "" and a.side ~= side) then
                local ch = byKey["arc:" .. a.id]
                if ch and not ch.locked then
                    d.chapters[#d.chapters + 1] = ch
                    d.done = d.done + ch.done
                    d.total = d.total + (ch.total or #ch.entries)
                elseif J.ArcForMe(a) and a.quests and a.quests[1] then
                    d.chapters[#d.chapters + 1] = { title = a.title, locked = true, first = a.quests[1] }
                    d.total = d.total + #a.quests
                end
            end
        end
        for _, a in ipairs(lo.arcs or {}) do -- its levels: those of its quests
            if a.zone == name then
                for _, q in ipairs(a.quests or {}) do
                    local info = ns.Map and ns.Map.QuestInfo(q)
                    local lv = info and info.lvl
                    if lv and lv > 0 then d.lo, d.hi = math.min(d.lo or lv, lv), math.max(d.hi or lv, lv) end
                end
            end
        end
        if LEVELS[name] then d.lo, d.hi = LEVELS[name][1], LEVELS[name][2] end
        if d.raid then d.lo, d.hi = 60, 60 end -- every raid is for level 60
        local hit = matches(name, ns.zoneLocal(name))
        for _, ch in ipairs(d.chapters) do hit = hit or matches(ch.title) end
        if hit then out[#out + 1] = d end
    end
    table.sort(out, function(a, b)
        if (a.lo or 99) ~= (b.lo or 99) then return (a.lo or 99) < (b.lo or 99) end
        return a.name < b.name
    end)
    return out
end

local function levels(d)
    local s = d.lo and (d.lo == d.hi and (L["Level %d"]):format(d.lo) or (L["Levels %d-%d"]):format(d.lo, d.hi)) or ""
    return s
end

local function renderDungeon(d)
    local pw = page:GetWidth()
    hideAll()
    header.title:Show(); header.sub:Show(); header.intro:Show()
    if not d then
        header.title:SetText(L["Dungeons & Raids"]); header.sub:SetText("")
        header.intro:SetText(filter ~= "" and L["Nothing matches your search"] or "")
        page:SetHeight(120)
        return
    end
    header.title:SetText(ns.zoneLocal(d.name))
    local sub = levels(d)
    if d.cleared then
        local when = (L["Cleared %s"]):format(date("%d %b %Y", d.cleared))
        sub = sub ~= "" and (sub .. "  ·  " .. when) or when
    end
    header.sub:SetText(sub)
    header.intro:SetWidth(pw - 10)
    header.intro:SetText(d.intro or "")
    -- how it ends: only the wings you have finished
    local ends = {}
    for wing, bosses in pairs(lore().dungeonEnd or {}) do
        if wingOf(wing, d.name) and (ns.char.dungeonsDone or {})[wing] then
            for boss, said in pairs(bosses) do ends[#ends + 1] = { wing = wing, boss = boss, text = said } end
        end
    end
    table.sort(ends, function(a, b) return a.wing < b.wing end)
    local keys = { d.key }
    for _, e in ipairs(ends) do keys[#keys + 1] = "dend:" .. e.wing .. "|" .. e.boss end
    listenButton(keys, L["Listen"])
    local y, n = -(54 + header.intro:GetStringHeight() + 18), 1
    if #d.chapters > 0 then
        y, n = placeTodos({ L["Chapters"] }, y, n, pw)
        for _, ch in ipairs(d.chapters) do
            local q
            if ch.locked then
                -- not found yet: where it starts (click: a marker at its quest giver)
                local w = ns.Map and ns.Map.QuestInfo(ch.first) or {}
                local start = (ns.db.quests[ch.first] and ns.db.quests[ch.first].title) or (lore().titles or {})[ch.first] or w.t
                local giver = personOf(ch.first, "giver")
                local from = start and (L["Starts with %s"]):format(start) or ""
                if giver then from = from .. "  ·  " .. (L["Given by %s"]):format(giver) end
                q = { title = "|cff8f8676" .. ch.title .. "|r", from = from, zone = w.zone, x = w.x, y = w.y }
            else
                q = { open = ch.key, title = ch.title, from = (L["%d of %d quests"]):format(ch.done, ch.total or #ch.entries) }
            end
            y, n = placeTodos({ q }, y, n, pw)
        end
    end
    y, n = placeTodos({ L["How it ends"] }, y, n, pw)
    if #ends > 0 then
        for _, e in ipairs(ends) do
            local wing = e.wing ~= d.name and ("|cff7a4b12" .. e.wing:match(": (.+)$") .. ":|r ") or ""
            y, n = placeTodos({ { title = wing .. e.text } }, y, n, pw)
        end
    else
        y, n = placeTodos({ { title = "|cff7a6a55" .. L["Defeat its last boss and the narrator tells how the story ends."] .. "|r" } }, y, n, pw)
    end
    page:SetHeight(-y + 20)
end

-- ---------------------------------------------------------------- render: your chronicle
-- This character's whole journey on one page: the zones in the order you came to them, the dungeons you cleared
-- and the attunements you finished. "Tell my chronicle": each zone's epilogue, or where it isn't done yet, the
-- recap of the last quest you finished there.
local HISTORY = "Before the journal"

local function journey()
    -- quests of a zone's own story: not camping, profession, class or holiday chapters (they say little of the road)
    local story = {}
    for _, a in ipairs(lore().arcs or {}) do
        if not (a.opt or a.cls or a.prof or a.event) then
            for _, id in ipairs(a.quests or {}) do story[id] = a.zone end
        end
    end
    local zones, byZone = {}, {}
    for _, e in ipairs(ns.char.journal or {}) do
        local q = ns.db.quests[e.id] or {}
        local z = story[e.id] or q.zone or ns.LoreZone(e.id) or e.zone
        if z and z ~= HISTORY and story[e.id] then
            local s = byZone[z]
            if not s then s = { zone = z, n = 0 }; byZone[z] = s; zones[#zones + 1] = s end
            s.n = s.n + 1
            s.first = s.first or e.t
        end
    end
    -- what the narrator tells of a zone not finished yet: one recap per chapter you finished there (its last quest),
    -- in the order you finished them; the camping lessons are left out, they tell nothing of the road
    for _, ch in ipairs(chapters) do
        local s = byZone[ch.zone or ""]
        local camping = ch.arc and (ch.arc.id:find("_adventurer$") or ch.arc.id:find("camping"))
        if s and not ch.locked and not camping and ch.done >= (ch.total or #ch.entries) and ch.done > 0 then
            local last
            for _, e in ipairs(ch.entries) do if e.state == "done" and ns.Voice.Get("sum:" .. e.id) then last = e.id end end
            if last then
                s.told = s.told or {}
                s.told[#s.told + 1] = { id = last, order = ch.order or 0 }
            end
        end
    end
    for _, s in ipairs(zones) do table.sort(s.told or {}, function(a, b) return a.order < b.order end) end
    return zones
end

-- ---------------------------------------------------------------- render: the library
-- Every book, letter and plaque this character has read, to hear again. The ones not found yet are only counted,
-- never named.
-- the books this character has read; /lore library preview pretends about a third were found (this session only,
-- nothing saved), to see the shelves full
local preview
function J.LibraryPreview()
    if preview then preview = nil else
        preview = {}
        for title in pairs((ns.Lore and ns.Lore.books) or {}) do
            if math.random() < 0.33 then preview[title] = time() - math.random(0, 86400 * 7) end
        end
    end
    if frame and frame:IsShown() then J.Refresh() end
    return preview ~= nil
end
local function libraryRead() return preview or (ns.char and ns.char.library) or {} end

function J.LibraryCount()
    local total, found = 0, 0
    local read = libraryRead()
    for title in pairs((ns.Lore and ns.Lore.books) or {}) do
        total = total + 1
        if read[title] then found = found + 1 end
    end
    return found, total
end

local function bookKeys(title)
    local keys = {}
    for _, item in ipairs(((ns.Lore and ns.Lore.books) or {})[title] or {}) do
        if ns.Voice.Get(item[1]) then keys[#keys + 1] = item[1] end
    end
    return keys
end

-- the books and plaques lying in a zone (the builder's list from Wowhead), found ones first, each once
function J.ZoneBooks(zone)
    local out, seen = {}, {}
    local read = libraryRead()
    for _, b in ipairs((((ns.Lore and ns.Lore.bookPlaces) or {})[zone]) or {}) do
        local title = b[1]
        if not seen[title] and ((ns.Lore and ns.Lore.books) or {})[title] then
            seen[title] = true
            out[#out + 1] = { title = title, x = b[2], y = b[3], found = read[title] and true or false, keys = bookKeys(title) }
        end
    end
    table.sort(out, function(a, b)
        if a.found ~= b.found then return a.found end
        return a.found and a.title < b.title or (not a.found and (a.y or 0) < (b.y or 0))
    end)
    return out
end

-- a series: "The Rebellion In Eldre'Thalas, Part 2" -> "The Rebellion In Eldre'Thalas", 2
local ROMAN = { I = 1, V = 5, X = 10, L = 50 }
---@param word string
---@return number?
local function numberOf(word)
    if word:match("^%d+$") then return tonumber(word) end
    local n, last = 0, 0
    for k = #word, 1, -1 do
        local v = ROMAN[word:sub(k, k)]
        if not v then return end
        if v < last then n = n - v else n = n + v; last = v end
    end
    return n > 0 and n or nil
end

-- "X, Part 2", "X - Chapter IV", "X - Page 14", "X (Day 87)": the series and where in it; whole chapters come before loose pages
-- series the game doesn't number the usual way
local NAMED = {
    ["The First Troll Legend"] = { "The Troll Legends", 1 }, ["The Second Troll Legend"] = { "The Troll Legends", 2 },
    ["The Third Troll Legend"] = { "The Troll Legends", 3 }, ["The Fourth Troll Legend"] = { "The Troll Legends", 4 },
    ["A Clue to Sander's Treasure"] = { "Sander's Treasure", 1 }, ["Another Clue to Sander's Treasure"] = { "Sander's Treasure", 2 },
    ["Final Clue to Sander's Treasure"] = { "Sander's Treasure", 3 },
    ["Secret Note #1"] = { "Secret Notes", 1 }, ["Secret Note #2"] = { "Secret Notes", 2 }, ["Secret Note #3"] = { "Secret Notes", 3 },
}

local function seriesOf(title)
    local named = NAMED[title]
    if named then return named[1], named[2] end
    local base, kind, word = title:match("^(.-),?%s+%-?%s*(%a+)%s+([%dIVXL]+)$")
    if not base then base, word = title:match("^(.-)%s+%(Day%s+(%d+)%)$"); kind = "day" end
    if not base then return end
    kind = kind:lower()
    if kind ~= "part" and kind ~= "volume" and kind ~= "chapter" and kind ~= "book" and kind ~= "page" and kind ~= "day" then return end
    local n = numberOf(word)
    if not n then return end
    return base, kind == "page" and 1000 + n or n
end

-- what a book looks like on the shelf
local ICON_BOOK, ICON_LETTER = "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Letter_15"
local ICON_PLAQUE, ICON_SCROLL = "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Scroll_03"
local function iconOf(title, object)
    local t = title:lower()
    if t:find("plaque") or t:find("monument") or t:find("memorial") or t:find("marker") or t:find("tablet")
        or t:find("grave") or t:find("tomb") then return ICON_PLAQUE end
    if t:find("letter") or t:find("note") or t:find("orders") or t:find("report") or t:find("instructions")
        or t:find("envelope") or t:find("message") then return ICON_LETTER end
    if t:find("map") or t:find("scroll") or t:find("page") or t:find("journal") then return ICON_SCROLL end
    return object and ICON_BOOK or ICON_LETTER
end
J.IconOf = iconOf

local function makeTile()
    local f = chronBox()
    f:SetHeight(58)
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(34, 34); f.icon:SetPoint("LEFT", 8, 0)
    local rim = f:CreateTexture(nil, "OVERLAY"); rim:SetSize(38, 38); rim:SetPoint("CENTER", f.icon, "CENTER")
    rim:SetTexture("Interface\\Buttons\\UI-Quickslot2"); rim:SetTexCoord(0.2, 0.8, 0.2, 0.8); rim:SetAlpha(0.6)
    f.title = text(f, "GameFontHighlight", INK_TITLE); f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 2)
    f.title:SetPoint("RIGHT", -8, 0); f.title:SetJustifyV("TOP"); f.title:SetWordWrap(true)
    f.title:SetHeight(28) -- a fixed two lines, so a reused tile never keeps an old one-line height
    if f.title.SetMaxLines then f.title:SetMaxLines(2) end
    f.sub = text(f, "GameFontNormalSmall", INK_SOFT); f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, -2)
    f.sub:SetPoint("RIGHT", -8, 0)
    f.bar = chronBar(f); f.bar:SetPoint("BOTTOMLEFT", 6, 4); f.bar:SetPoint("BOTTOMRIGHT", -6, 4); f.bar:SetHeight(3)
    f:SetScript("OnClick", function(self)
        if not self.keys or #self.keys == 0 then return end
        click()
        if ns.Voice.Owner() == self then ns.Voice.Stop() return end
        -- a series: choose where to start
        if self.parts and #self.parts > 1 and MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(self.series)
                root:CreateButton(L["From the start"], function() ns.Voice.PlayQueue(self.keys, self) end)
                for _, part in ipairs(self.parts) do
                    local label = part.title:sub(1, #self.series) == self.series and part.title:sub(#self.series + 1):gsub("^[%s,%-]+", "") or part.title
                    root:CreateButton(label ~= "" and label or part.title, function() ns.Voice.PlayQueue(bookKeys(part.title), self) end)
                end
            end)
            return
        end
        ns.Voice.PlayQueue(self.keys, self)
    end)
    -- the reading bar follows the voice
    f:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t < 0.25 then return end
        self.t = 0
        local mine = ns.Voice.Owner() == self
        self.bar:SetShown(mine)
        if mine then
            local key, at = ns.Voice.PlayingKey(), ns.Voice.PlayingFor() or 0
            local total, before = 0, 0
            for _, k in ipairs(self.keys or {}) do
                local e = ns.Voice.Get(k)
                local d = e and e.d or 0
                if key and k == key then before = total + math.min(at, d) end
                total = total + d
            end
            self.bar:SetValue(total > 0 and before / total or 0)
        end
    end)
    return f
end

-- ---- the bookcase: books as spines standing on wooden shelves, gaps where the ones not found yet will stand
local SPINES = { { 0.45, 0.12, 0.10 }, { 0.15, 0.30, 0.18 }, { 0.14, 0.22, 0.40 }, { 0.40, 0.26, 0.12 },
    { 0.30, 0.16, 0.35 }, { 0.12, 0.32, 0.32 }, { 0.50, 0.38, 0.16 }, { 0.22, 0.20, 0.18 } }
local PAPER = { { 0.82, 0.74, 0.56 }, { 0.72, 0.64, 0.48 }, { 0.86, 0.80, 0.66 }, { 0.66, 0.56, 0.40 } }
local function hashOf(str)
    local h = 7
    for i = 1, #str do h = (h * 31 + str:byte(i)) % 2147483647 end
    return h
end

-- a soft fall from one colour to another (the game's gradients), flat where the client has none
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function shade(t, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    t:SetTexture(WHITE)
    if t.SetGradient and CreateColor and pcall(t.SetGradient, t, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then
        return
    end
    t:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

local function makeSpine()
    local f = CreateFrame("Button", nil, page)
    f.body = f:CreateTexture(nil, "ARTWORK")
    f.body:SetAllPoints()
    f.tag = f:CreateTexture(nil, "ARTWORK", nil, 2); f.tag:SetHeight(11)
    f.tag:SetPoint("TOPLEFT", 2, -14); f.tag:SetPoint("TOPRIGHT", -2, -14)
    f.band1 = f:CreateTexture(nil, "ARTWORK", nil, 2); f.band1:SetHeight(2)
    f.band1:SetPoint("TOPLEFT", 1, -5); f.band1:SetPoint("TOPRIGHT", -1, -5); f.band1:SetColorTexture(0.86, 0.70, 0.36, 0.9)
    f.band2 = f:CreateTexture(nil, "ARTWORK", nil, 2); f.band2:SetHeight(2)
    f.band2:SetPoint("BOTTOMLEFT", 1, 5); f.band2:SetPoint("BOTTOMRIGHT", -1, 5); f.band2:SetColorTexture(0.86, 0.70, 0.36, 0.9)
    f.band3 = f:CreateTexture(nil, "ARTWORK", nil, 2); f.band3:SetHeight(1)
    f.band3:SetPoint("BOTTOMLEFT", 1, 9); f.band3:SetPoint("BOTTOMRIGHT", -1, 9); f.band3:SetColorTexture(0.86, 0.70, 0.36, 0.7)
    f.gem = f:CreateTexture(nil, "ARTWORK", nil, 3); f.gem:SetSize(3, 3); f.gem:SetPoint("CENTER", 0, -4)
    f.gem:SetColorTexture(0.95, 0.80, 0.40, 1)
    f.foot = f:CreateTexture(nil, "BACKGROUND"); f.foot:SetHeight(3)
    f.foot:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 1, 0); f.foot:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 3, 0)
    f.foot:SetColorTexture(0, 0, 0, 0.4)
    f.glow = f:CreateTexture(nil, "OVERLAY"); f.glow:SetAllPoints(); f.glow:SetColorTexture(1, 0.9, 0.6, 0.25)
    f.glow:SetBlendMode("ADD"); f.glow:Hide()
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.9, 0.6, 0.18); hl:SetBlendMode("ADD")
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.missing then
            GameTooltip:SetText(L["Not found yet"], 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText(self.title, 1, 1, 1)
            GameTooltip:AddLine(self.pages == 1 and L["1 page"] or (L["%d pages"]):format(self.pages or 0), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["Click to hear it"], 0.6, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function(self)
        if self.missing or not self.keys or #self.keys == 0 then return end
        click()
        if ns.Voice.Owner() == self then ns.Voice.Stop() else ns.Voice.PlayQueue(self.keys, self) end
    end)
    return f
end

local function makeWood()
    return page:CreateTexture(nil, "BORDER")
end

-- the brass name plate above a bookcase
local function makePlate()
    local f = CreateFrame("Frame", nil, page)
    f:SetHeight(22)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.rim = f:CreateTexture(nil, "BORDER"); f.rim:SetPoint("TOPLEFT", -1, 1); f.rim:SetPoint("BOTTOMRIGHT", 1, -1)
    f.rim:SetColorTexture(0.80, 0.62, 0.30, 1)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.text:SetPoint("CENTER", 0, 0)
    f.text:SetTextColor(0.98, 0.84, 0.48); f.text:SetShadowColor(0, 0, 0, 0.8); f.text:SetShadowOffset(1, -1)
    return f
end

local function wood(y, x, w, h, r1, g1, b1, r2, g2, b2)
    local t = chronGet("wood", makeWood)
    t:SetPoint("TOPLEFT", page, "TOPLEFT", x, y); t:SetSize(w, h)
    shade(t, "VERTICAL", r2, g2, b2, 1, r1, g1, b1, 1) -- VERTICAL goes bottom to top: r1 on top
    return t
end

-- one bookcase: a name plate, the found books in order (a little wider or narrower each), then the gaps
local function bookcase(y, width, title, spines, missing, letters)
    local plate = chronGet("plate", makePlate)
    plate.text:SetText(title)
    plate:SetWidth(plate.text:GetStringWidth() + 28)
    plate:SetPoint("TOP", page, "TOPLEFT", width / 2, y)
    plate.bg:SetColorTexture(0.20, 0.12, 0.05, 1) -- dark wood, gold letters
    y = y - 28
    local rowH = letters and 62 or 86
    local inner = width - 20
    -- lay the books out first: each its own width, wrapping to the next shelf
    local rows, x, row = { {} }, 0, 1
    local function place(item, w)
        if x + w > inner and x > 0 then row = row + 1; rows[row] = {}; x = 0 end
        rows[row][#rows[row] + 1] = { item = item, x = x, w = w }
        x = x + w + 2
    end
    for _, sp in ipairs(spines) do place(sp, sp.w) end
    for _ = 1, missing do place(false, letters and 9 or 13) end
    local caseH = #rows * (rowH + 12) + 6
    -- the case: a top board, its back wall, sides, a plank under every shelf and a base
    wood(y, -2, width + 4, 8, 0.46, 0.29, 0.12, 0.28, 0.16, 0.06)
    local back = wood(y - 8, 0, width, caseH, 0.10, 0.06, 0.02, 0.22, 0.13, 0.05)
    back:SetAlpha(0.85)
    wood(y - 8, 0, 8, caseH, 0.42, 0.26, 0.11, 0.30, 0.18, 0.07)
    wood(y - 8, width - 8, 8, caseH, 0.42, 0.26, 0.11, 0.30, 0.18, 0.07)
    for r = 1, #rows do
        local py = y - 8 - r * (rowH + 12) + 4
        wood(py, 0, width, 8, 0.56, 0.37, 0.16, 0.34, 0.21, 0.08)
    end
    wood(y - 8 - caseH, -2, width + 4, 6, 0.30, 0.18, 0.07, 0.18, 0.10, 0.04)
    -- the books
    for r, items in ipairs(rows) do
        local base = y - 8 - r * (rowH + 12) + 4
        for _, it in ipairs(items) do
            local sp = it.item
            local f = chronGet("spine", makeSpine)
            local playing = sp and ns.Voice.Owner() == f
            local h = sp and sp.h or (rowH - 16)
            f:SetSize(it.w, h)
            f:SetPoint("BOTTOMLEFT", page, "TOPLEFT", 10 + it.x, base + (playing and 8 or 0))
            f.missing = not sp
            if sp then
                local c = sp.color
                f.title, f.pages, f.keys = sp.title, sp.pages, sp.keys
                shade(f.body, "HORIZONTAL", math.min(1, c[1] * 1.35), math.min(1, c[2] * 1.35), math.min(1, c[3] * 1.35), 1,
                    c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1)
                local style = sp.style
                f.band1:SetShown(not letters); f.band2:SetShown(not letters)
                f.band3:SetShown(not letters and style % 3 == 0)
                f.tag:SetShown(not letters and style % 2 == 0)
                if f.tag:IsShown() then shade(f.tag, "VERTICAL", 0.72, 0.64, 0.46, 1, 0.88, 0.80, 0.62, 1) end
                f.gem:SetShown(not letters and style % 5 == 1)
                f.foot:Show(); f:SetAlpha(1)
            else
                shade(f.body, "HORIZONTAL", 0.07, 0.04, 0.01, 0.55, 0.03, 0.02, 0.0, 0.55) -- an empty slot
                f.band1:Hide(); f.band2:Hide(); f.band3:Hide(); f.tag:Hide(); f.gem:Hide(); f.foot:Hide()
                f:SetAlpha(0.75)
            end
            f.glow:SetShown(playing and true or false)
        end
    end
    return y - 8 - caseH - 22
end

local function renderLibrary()
    local pw = page:GetWidth()
    local width = pw - 10
    hideAll()
    header.title:Show(); header.sub:Show(); header.intro:Show()
    header.title:SetText(L["Library"])
    local books = (ns.Lore and ns.Lore.books) or {}
    local objects = (ns.Lore and ns.Lore.bookObjects) or {}
    local read = libraryRead()
    local found, total = J.LibraryCount()
    header.sub:SetText(ns.settings.hideUnfound and (L["%d found"]):format(found) or (L["%d of %d found"]):format(found, total))
    header.intro:SetWidth(width)
    header.intro:SetText(found > 0 and L["Every book, letter and plaque you have read. Click one to hear it again."]
        or L["Open a book, a letter or a plaque and it goes on your shelf here, to hear again whenever you like."])
    local y, n = -(54 + header.intro:GetStringHeight() + 16), 1
    local GAP = 8

    -- the shelf entries: a book on its own, or a series with the parts found so far, in order
    local seriesTotal = {}
    for title in pairs(books) do
        local base = seriesOf(title)
        if base then seriesTotal[base] = (seriesTotal[base] or 0) + 1 end
    end
    local entries, byBase, pages, seriesFound = {}, {}, 0, 0
    for title, items in pairs(books) do
        if read[title] then
            pages = pages + #items
            local base, part = seriesOf(title)
            if base and seriesTotal[base] > 1 then
                local e = byBase[base]
                if not e then
                    e = { title = base, parts = {}, object = objects[title], t = 0, series = true }
                    byBase[base] = e; entries[#entries + 1] = e; seriesFound = seriesFound + 1
                end
                e.parts[#e.parts + 1] = { part = part, title = title }
                e.t = math.max(e.t, read[title])
            else
                entries[#entries + 1] = { title = title, object = objects[title], t = read[title], pages = #items }
            end
        end
    end
    for _, e in ipairs(entries) do
        if e.series then
            table.sort(e.parts, function(a, b) return a.part < b.part end)
            e.keys, e.pages = {}, 0
            for _, p in ipairs(e.parts) do
                for _, k in ipairs(bookKeys(p.title)) do e.keys[#e.keys + 1] = k end
                e.pages = e.pages + #(books[p.title] or {})
            end
        else
            e.keys = bookKeys(e.title)
        end
    end

    -- the numbers, each in its own box
    local stats = { { found, L["Found"] }, { pages, L["Pages to hear"] }, { seriesFound, L["Series"] }, { total - found, L["Still to find"] } }
    if ns.settings.hideUnfound then stats[4] = nil end
    local bw = (width - GAP * (#stats - 1)) / #stats
    for k, st in ipairs(stats) do
        local b = chronGet("stat", makeStat)
        b:SetSize(bw, 50); b:SetPoint("TOPLEFT", page, "TOPLEFT", (k - 1) * (bw + GAP), y)
        b.num:SetText(tostring(st[1])); b.label:SetText(st[2])
    end
    y = y - 50 - 20

    -- the view: the bookcase, or tiles (the button at the top right switches)
    header.recap.tell, header.recap.keys = nil, {}
    header.recap.libraryToggle = true
    local asShelves = (ns.settings.libraryView or "shelves") == "shelves"
    header.recap:SetText(asShelves and L["Show as tiles"] or L["Show as shelves"])
    local fs = header.recap:GetFontString()
    header.recap:SetWidth(math.max(100, (fs and fs:GetStringWidth() or 0) + 28))
    header.recap:SetEnabled(true); header.recap:Show()
    if asShelves then
        for _, sh in ipairs({ { L["Found in the world"], true }, { L["Letters and notes"], false } }) do
            local spines, all, have = {}, 0, 0
            for title in pairs(books) do
                if (objects[title] and true or false) == sh[2] then
                    all = all + 1
                    if read[title] then have = have + 1 end
                end
            end
            local mine = {}
            for _, e in ipairs(entries) do if (e.object and true or false) == sh[2] then mine[#mine + 1] = e end end
            table.sort(mine, function(a, b) return a.title < b.title end)
            for _, e in ipairs(mine) do
                local colors = sh[2] and SPINES or PAPER
                local color = colors[hashOf(e.title) % #colors + 1]
                local parts = e.series and e.parts or { { title = e.title } }
                for _, part in ipairs(parts) do -- a series stands together, in one colour
                    local hh = hashOf(part.title)
                    spines[#spines + 1] = { title = part.title, pages = #(books[part.title] or {}), keys = bookKeys(part.title),
                        color = color, style = hh % 30,
                        w = sh[2] and (11 + hh % 6) or (8 + hh % 3),
                        h = (sh[2] and 56 or 38) + hh % (sh[2] and 24 or 16) }
                end
            end
            if ns.settings.hideUnfound then
                y = bookcase(y, width, ("%s  ·  %d"):format(sh[1], have), spines, 0, not sh[2])
            else
                y = bookcase(y, width, ("%s  ·  %d / %d"):format(sh[1], have, all), spines, all - have, not sh[2])
            end
        end
        page:SetHeight(-y + 20)
        return
    end

    -- tiles, three to a row
    local cw = (width - GAP * 2) / 3
    local function tiles(items)
        local col = 0
        for _, e in ipairs(items) do
            local t = chronGet("tile", makeTile)
            t:SetSize(cw, 58); t:SetPoint("TOPLEFT", page, "TOPLEFT", col * (cw + GAP), y)
            t:SetAlpha(1); t:EnableMouse(true)
            t.keys = e.keys
            t.parts, t.series = e.series and e.parts or nil, e.series and e.title or nil
            t.icon:SetTexture(e.icon or iconOf(e.title, e.object)); t.icon:SetDesaturated(e.missing and true or false)
            t.title:SetText(e.title)
            local playing = ns.Voice.Owner() == t
            if e.missing then
                t.sub:SetText(e.sub); t:SetAlpha(0.55); t:EnableMouse(false)
            elseif playing then
                t.sub:SetText(L["Reading..."])
            elseif e.series then
                t.sub:SetText((L["Part %d of %d found"]):format(#e.parts, seriesTotal[e.title] or #e.parts))
            else
                t.sub:SetText(e.pages == 1 and L["1 page"] or (L["%d pages"]):format(e.pages or 0))
            end
            col = col + 1
            if col == 3 then col = 0; y = y - 58 - GAP end
        end
        if col > 0 then y = y - 58 - GAP end
    end

    -- last read: the three newest
    if #entries > 3 then
        table.sort(entries, function(a, b) return (a.t or 0) > (b.t or 0) end)
        y, n = placeTodos({ L["Last read"] }, y, n, pw)
        tiles({ entries[1], entries[2], entries[3] })
        y = y - 10
    end

    -- the shelves
    local shelves = {
        { L["Found in the world"], true },
        { L["Letters and notes"], false },
    }
    for _, sh in ipairs(shelves) do
        local items, have, all = {}, 0, 0
        for title in pairs(books) do
            if (objects[title] and true or false) == sh[2] then
                all = all + 1
                if read[title] then have = have + 1 end
            end
        end
        for _, e in ipairs(entries) do if (e.object and true or false) == sh[2] then items[#items + 1] = e end end
        table.sort(items, function(a, b) return a.title < b.title end)
        y, n = placeTodos({ ns.settings.hideUnfound and ("%s  (%d)"):format(sh[1], have) or ("%s  (%d/%d)"):format(sh[1], have, all) }, y, n, pw)
        if all - have > 0 and not ns.settings.hideUnfound then
            items[#items + 1] = { title = L["Still on the shelves"], missing = true, icon = sh[2] and ICON_BOOK or ICON_LETTER,
                                sub = (L["%d more to find"]):format(all - have) }
        end
        tiles(items)
        y = y - 10
    end
    page:SetHeight(-y + 20)
end

local function renderChronicle()
    local pw = page:GetWidth()
    local width = pw - 10
    hideAll()
    header.title:Show(); header.sub:Show(); header.intro:Show()
    local me = ns.clean(UnitName("player")) or ""
    header.title:SetText((L["The chronicle of %s"]):format(me))
    local zones = journey()
    local began
    for _, e in ipairs(ns.char.journal or {}) do if e.t then began = e.t; break end end
    local chaptersDone = 0
    for _, ch in ipairs(chapters) do
        if not ch.locked and ch.done > 0 and ch.done >= (ch.total or #ch.entries) then chaptersDone = chaptersDone + 1 end
    end
    local bits = { ("%s %s, " .. L["level %d"]):format(UnitRace("player") or "", UnitClass("player") or "", UnitLevel("player") or 1) }
    if began then bits[#bits + 1] = (L["since %s"]):format(date("%d %b %Y", began)) end
    header.sub:SetText(table.concat(bits, "  ·  "))
    local epi = ns.char.epilogues or {}
    local finished = 0
    for _, s in ipairs(zones) do if epi[s.zone] then finished = finished + 1 end end
    header.intro:SetWidth(pw - 10)
    if #zones == 0 then
        header.intro:SetText(L["Your story has not begun"])
    else
        local intro = (L["Your story began in %s. Since then you have finished %d quests in %d places."])
            :format(ns.zoneLocal(zones[1].zone), #ns.char.journal, #zones)
        -- a zone's whole story (its epilogue) only once there is one to tell of
        if finished > 0 then intro = intro .. " " .. (L["You have seen the story through in %d of them."]):format(finished) end
        header.intro:SetText(intro)
    end
    local keys = {}
    for _, s in ipairs(zones) do
        local ek = epi[s.zone] and ns.Endings and ns.Endings.EpilogueKey(s.zone)
        if ek and ns.Voice.Get("epi:" .. ek) then keys[#keys + 1] = "epi:" .. ek
        else
            for _, t in ipairs(s.told or {}) do keys[#keys + 1] = "sum:" .. t.id end
        end
    end
    listenButton(keys, L["Tell my chronicle"])
    header.recap.tell = true
    header.tellInfo:Show()
    tellInfo()
    if tell.waiting and ns.Voice.Owner() ~= header.recap then
        header.recap:SetText((L["Continue (%d/%d)"]):format(tell.i + 1, #tell.keys))
    end
    local y, n = -(54 + header.intro:GetStringHeight() + 16), 1
    local GAP = 8

    -- the numbers, each in its own box
    local stats = { { #ns.char.journal, L["Quests"] }, { chaptersDone, L["Chapters finished"] },
        { #people, L["People met"] }, { finished, L["Stories seen through"] } }
    local bw = (width - GAP * (#stats - 1)) / #stats
    for i, st in ipairs(stats) do
        local b = chronGet("stat", makeStat)
        b:SetSize(bw, 50); b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (bw + GAP), y)
        b.num:SetText(tostring(st[1])); b.label:SetText(st[2])
    end
    y = y - 50 - 20

    -- the next zones on your race's road, as cards: levels, chapters done, and where you are now
    local ahead = (ns.Endings and not ns.settings.hideUnfound) and ns.Endings.RoadAhead(nil, 3) or {}
    if #ahead > 0 then
        y, n = placeTodos({ L["The road ahead"] }, y, n, pw)
        local here = ns.zoneEN and ns.zoneEN(GetRealZoneText() or "")
        local cw = (width - GAP * 2) / 3
        for i, zone in ipairs(ahead) do
            local c = chronGet("road", makeRoad)
            c:SetSize(cw, 62); c:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (cw + GAP), y)
            c.key = "area:" .. zone
            c.title:SetText(ns.zoneLocal(zone)); c.sub:SetText(ns.Endings.LevelText(zone))
            c.here:SetShown(zone == here)
            c.title:SetPoint("RIGHT", c.here:IsShown() and -(c.here:GetStringWidth() + 12) or -8, 0)
            local done, _, total = ns.Endings.ZoneProgress(zone)
            c.bar:SetValue(total > 0 and done / total or 0)
            c.count:SetText(total > 0 and (L["%d of %d chapters"]):format(done, total) or "")
        end
        y = y - 62 - 20
    end

    -- where you have been: a line down the page, a gem per zone (bright once its story is seen through), and its
    -- chapters under it: a tick when finished, a small bar while under way
    if #zones > 0 then
        y, n = placeTodos({ L["Where you have been"] }, y, n, pw)
        local gems = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Legacy-Rewards-Tracker-Diamond") ~= nil
        for zi, s in ipairs(zones) do
            local top = y
            local m = chronGet("marker", makeMarker)
            m:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y + 1)
            if gems then
                m:SetAtlas(epi[s.zone] and "Legacy-Rewards-Tracker-Diamond" or "Legacy-Rewards-Tracker-Diamond-Disable")
            else
                m:SetTexture(epi[s.zone] and ICON_DONE or ICON_ACTIVE)
            end
            local mine, finishedHere = {}, 0
            for _, ch in ipairs(chapters) do
                if ch.zone == s.zone and not ch.locked and #ch.entries > 0 then
                    mine[#mine + 1] = ch
                    if ch.done >= (ch.total or #ch.entries) then finishedHere = finishedHere + 1 end
                end
            end
            table.sort(mine, function(a, b) return (a.order or 0) < (b.order or 0) end)
            -- folded or open: as chosen, else only the zone you were in last is open
            local folded = ns.char.collapsed and ns.char.collapsed.chronicle
            local open
            if folded and folded[s.zone] ~= nil then open = not folded[s.zone] else open = zi == #zones end
            local from = (L["%d quests"]):format(s.n)
            if not open and #mine > 0 then from = from .. "  ·  " .. (L["%d of %d chapters"]):format(finishedHere, #mine) end
            if epi[s.zone] then from = from .. "  ·  " .. (L["story done %s"]):format(date("%d %b %Y", epi[s.zone])) end
            local z = chronGet("zone", makeZone)
            z:SetPoint("TOPLEFT", page, "TOPLEFT", 30, y); z:SetWidth(width - 30)
            z.zone, z.open = s.zone, open
            z.fold:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            z.title:SetText(ns.zoneLocal(s.zone)); z.sub:SetText(from)
            z:SetHeight(z.title:GetStringHeight() + z.sub:GetStringHeight() + 4)
            y = y - z:GetHeight() - 6
            for _, ch in ipairs(open and mine or {}) do
                local total = ch.total or #ch.entries
                local done = ch.done >= total
                local r = chronGet("chapter", makeChapter)
                r:SetPoint("TOPLEFT", page, "TOPLEFT", 34, y); r:SetWidth(width - 34)
                r.key = ch.key
                r.icon:SetTexture(done and ICON_DONE or ICON_ACTIVE)
                r.title:SetText(ch.title)
                r.bar:SetShown(not done); r.count:SetShown(not done)
                if not done then r.bar:SetValue(total > 0 and ch.done / total or 0); r.count:SetText(ch.done .. "/" .. total) end
                r.title:SetPoint("RIGHT", done and r or r.bar, done and "RIGHT" or "LEFT", -8, 0)
                y = y - 22
            end
            y = y - 14
            -- the line on to the next zone's gem
            if zi < #zones then
                local ln = chronGet("line", makeLine)
                ln:SetPoint("TOPLEFT", page, "TOPLEFT", 11, top - 19)
                ln:SetHeight(math.max(1, (top - 19) - (y + 1)))
            end
        end
    end

    -- dungeons cleared and attunements finished: small badges in rows
    local function badges(title, items)
        if #items == 0 then return end
        y, n = placeTodos({ title }, y, n, pw)
        local x = 0
        for _, it in ipairs(items) do
            local b = chronGet("badge", makeBadge)
            b.label:SetText(it.text); b.tip = it.tip
            local w = b.label:GetStringWidth() + 34
            if x > 0 and x + w > width then x = 0; y = y - 30 end
            b:SetSize(w, 24); b:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
            x = x + w + 6
        end
        y = y - 24 - 20
    end
    local cleared = {}
    for wing, t in pairs(ns.char.dungeonsDone or {}) do cleared[#cleared + 1] = { wing = wing, t = t } end
    table.sort(cleared, function(a, b) return a.t < b.t end)
    local items = {}
    for _, c in ipairs(cleared) do
        local name = c.wing:gsub("^([^:]+)", function(d) return ns.zoneLocal(d) end)
        items[#items + 1] = { text = name, tip = (L["Cleared %s"]):format(date("%d %b %Y", c.t)) }
    end
    badges(L["Dungeons & Raids"], items)
    items = {}
    for _, a in ipairs(attunements()) do if not a.nextId then items[#items + 1] = { text = a.title, tip = L["Attuned"] } end end
    badges(L["Attunements"], items)
    page:SetHeight(-y + 20)
end

-- ---------------------------------------------------------------- render: people
function J.ShowPerson(name)
    if tab ~= "people" then J.SetTab("people", true) end
    selectedPerson = name
    J.Refresh()
end

local function renderPerson(p)
    local pw = page:GetWidth()
    hideAll()
    if not p then
        header.title:Show(); header.title:SetText(filter ~= "" and L["Nobody matches your search"] or L["You have not met anyone yet"])
        page:SetHeight(120)
        return
    end
    local info = (lore().npcs or {})[p.name] or {}
    person.window:Show()
    local m = person.model
    pcall(m.ClearModel, m)
    local ok = false
    if info.d then ok = pcall(m.SetDisplayInfo, m, info.d) end
    if not ok and info.id then ok = pcall(m.SetCreature, m, info.id) end
    m:SetShown(ok)
    person.hint:SetShown(ok)
    person.talkUntil = nil
    if ok then
        m.zoom = 0.35
        pcall(m.SetPortraitZoom, m, m.zoom); pcall(m.SetCamDistanceScale, m, 1.1); pcall(m.SetFacing, m, 0)
    end

    person.name:Show(); person.name:SetText(p.name)
    person.title:Show()
    local bits = {}
    if info.t then bits[#bits + 1] = "<" .. info.t .. ">" end
    if info.r then bits[#bits + 1] = info.r end
    person.title:SetText(table.concat(bits, "   "))

    -- "Hear them": their greeting if one is voiced, else a line from a quest they gave or took
    local firstKey
    for _, item in ipairs((info.id and ns.Greetings(info.id)) or {}) do
        if ns.Voice.Get(item[1]) then firstKey = item[1]; break end
    end

    -- where you know them from, and what you did for them
    local zones, seen = {}, {}
    for _, id in ipairs(p.list) do
        local z = (ns.db.quests[id] or {}).zone or ns.LoreZone(id)
        if z and not seen[z] then seen[z] = true; zones[#zones + 1] = ns.zoneLocal(z) end
        for _, kind in ipairs({ "detail", "complete", "progress" }) do
            local k = "q" .. id .. ":" .. kind
            if not firstKey and ns.Voice.Get(k) and (kind == "detail" and personOf(id, "giver") == p.name or kind ~= "detail" and personOf(id, "ender") == p.name) then
                firstKey = k
            end
        end
    end
    person.where:Show(); person.where:SetText(#zones > 0 and (L["Met in %s"]):format(table.concat(zones, ", ")) or "")
    person.bio:Show(); person.bio:SetWidth(pw - 210); person.bio:SetText(info.b or "")
    person.hear:SetShown(firstKey ~= nil)
    person.hear.key = firstKey
    -- the narrator's word on them (their bio), when it has a voice
    local bioKey = info.id and info.b and ("bio:" .. info.id) or nil
    local voiced = bioKey and ns.Voice.Get(bioKey) and not ns.settings.journalOnly
    person.about.key = bioKey
    person.about:SetShown(voiced and true or false)
    person.about:SetText(ns.Voice.Owner() == person.about and L["Stop"] or L["Who are they?"])
    person.about:ClearAllPoints()
    if firstKey then person.about:SetPoint("LEFT", person.hear, "RIGHT", 6, 0)
    else person.about:SetPoint("TOPLEFT", person.where, "BOTTOMLEFT", 0, -8) end
    person.dealings:Show()

    -- one clickable line per quest: opens its chapter in the story
    for _, r in ipairs(person.deal) do r:Hide() end
    local prev, extra = person.dealings, 0
    for i, id in ipairs(p.list) do
        local r = person.deal[i]
        if not r then
            r = CreateFrame("Button", nil, page)
            r:SetHeight(18)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12); r.icon:SetPoint("TOPLEFT", 0, -3)
            r.text = text(r, "QuestFont", INK); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.role = text(r, "GameFontNormalSmall", INK_SOFT); r.role:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
            r:SetScript("OnEnter", function(self) ink(self.text, INK_TITLE) end)
            r:SetScript("OnLeave", function(self) ink(self.text, INK) end)
            r:SetScript("OnClick", function(self)
                click()
                for _, c in ipairs(chapters) do
                    for _, e in ipairs(c.entries) do
                        if e.id == self.id then J.SetTab("story", true); J.Select(c.key); return end
                    end
                end
            end)
            person.deal[i] = r
        end
        r.id = id
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -8 or -2); r:SetWidth(pw - 210)
        r.icon:SetTexture(p.state[id] == "done" and ICON_DONE or ICON_ACTIVE)
        r.text:SetText(questTitle(id))
        local gave, took = personOf(id, "giver") == p.name, personOf(id, "ender") == p.name
        r.role:SetText(gave and took and L["gave you this, and you reported back"] or gave and L["gave you this"]
            or took and L["you reported back"] or "")
        -- a long quest name: the note goes under it instead of off the page
        r.role:ClearAllPoints()
        if r.text:GetStringWidth() + r.role:GetStringWidth() + 26 > pw - 210 then
            r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
            r.role:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
            r:SetHeight(34)
        else
            r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.role:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
            r:SetHeight(18)
        end
        r:Show()
        prev = r
        extra = extra + r:GetHeight() - 18
    end
    page:SetHeight(math.max(270, 150 + person.bio:GetStringHeight() + 20 * #p.list + extra + 30))
end

-- ---------------------------------------------------------------- render: list
local function card(r, key, title, sub, done, total, finished)
    r.key = key
    r.title:SetText(title)
    r.sub:SetText(sub)
    r.bar:SetValue(total > 0 and done / total or (finished and 1 or 0))
    r.sel:SetShown(key == selected)
    if r.diamond then
        r.diamond:SetAtlas((done == 0 and not finished) and "Legacy-Rewards-Tracker-Diamond-Disable" or "Legacy-Rewards-Tracker-Diamond")
        r.count:SetText(tostring(done))
        r.check:SetShown(finished and true or false)
        r.chapter = { title = title, done = done, total = total, entries = {} }
        r.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
    end
end

local function renderList()
    for _, r in ipairs(listRows) do r:Hide() end
    local y, n = 0, 0
    local function row(kind)
        n = n + 1
        local r = getListRow(n)
        setRowKind(r, kind)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
        y = y - r:GetHeight() - 2
        r:Show()
        return r
    end
    if tab == "story" then
        -- your chronicle: the whole journey, above the chapters
        if filter == "" and #ns.char.journal > 0 then
            local r = row("chapter")
            local lvl = UnitLevel("player") or 1
            card(r, "chronicle", L["Your chronicle"], (L["Level %d"]):format(lvl), 0, 0, false)
            r.bar:SetValue(lvl / 60)
            if r.diamond then r.count:SetText(""); r.diamond:SetAtlas("Legacy-Rewards-Tracker-Diamond"); r.chapter = nil end
        end
        -- the Library: every book, letter and plaque this character has read (thanks Alche)
        if filter == "" then
            local found, total = J.LibraryCount()
            if total > 0 then
                local r = row("chapter")
                card(r, "library", L["Library"], ns.settings.hideUnfound and (L["%d found"]):format(found)
                    or (L["%d of %d found"]):format(found, total), found, total, false)
                r.bar:SetValue(found / total)
                r.bar:SetShown(not ns.settings.hideUnfound) -- the bar would tell how many there are
                if r.diamond then r.count:SetText(tostring(found)); r.chapter = nil end
            end
        end
        -- chapters arrive grouped by zone; collect the runs first so each header knows its count
        local runs = {}
        for _, ch in ipairs(chapters) do
            if ch.visible then
                local zone = ch.zone or L["Elsewhere"]
                local last = runs[#runs]
                if not last or last.zone ~= zone then last = { zone = zone, list = {} }; runs[#runs + 1] = last end
                last.list[#last.list + 1] = ch
            end
        end
        for i, run in ipairs(runs) do
            local holds = false
            for _, ch in ipairs(run.list) do if ch.key == selected then holds = true end end
            local open = zoneOpen("story", run.zone, i, holds)
            zoneHeader(row("head"), "story", run.zone, #run.list, open)
            if open then
                for _, ch in ipairs(run.list) do
                    local r = row("chapter")
                    r.key = ch.key
                    if ch.locked then
                        r.title:SetText("|cff8f8676" .. ch.title .. "|r")
                        r.sub:SetText((L["Starts with %s"]):format(ch.start.title))
                        r.bar:SetValue(0)
                    else
                        r.title:SetText(ch.title)
                        local going = #ch.entries > ch.done and ("  ·  " .. (#ch.entries - ch.done) .. L[" in progress"]) or ""
                        if r.diamond then
                            -- the diamond already says how many are done: the line gives the total
                            r.sub:SetText((L["of %d quests"]):format(ch.total or #ch.entries) .. going)
                        else
                            r.sub:SetText((L["%d / %d quests%s"]):format(ch.done, ch.total or #ch.entries,
                                #ch.entries > ch.done and ("  -  " .. (#ch.entries - ch.done) .. L[" in progress"]) or ""))
                        end
                        r.bar:SetValue(ch.done / math.max(ch.total or #ch.entries, 1))
                    end
                    r.sel:SetShown(ch.key == selected)
                    if r.diamond then
                        local total = ch.total or #ch.entries
                        local finished = not ch.locked and ch.done >= total
                        -- a status gem: grey before the first quest is done, gold on the way, a check when finished
                        r.diamond:SetAtlas((ch.locked or ch.done == 0) and "Legacy-Rewards-Tracker-Diamond-Disable"
                            or "Legacy-Rewards-Tracker-Diamond")
                        r.count:SetText(ch.locked and "?" or tostring(ch.done))
                        r.check:SetShown(finished)
                        r.chapter = ch
                        r.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], ch.locked and 0.15 or 0.5)
                    end
                end
                -- the zone's books and notes, for collectors: how many found (click: the zone page, at its books)
                if filter == "" then
                    local here = J.ZoneBooks(run.zone)
                    local found = 0
                    for _, b in ipairs(here) do if b.found then found = found + 1 end end
                    if #here > 0 and (found > 0 or not ns.settings.hideUnfound) then
                        local r = row("chapter")
                        card(r, "books:" .. run.zone, L["Books and notes"], ns.settings.hideUnfound and (L["%d found"]):format(found)
                            or (L["%d of %d found"]):format(found, #here), found, #here, found == #here)
                        r.bar:SetShown(not ns.settings.hideUnfound)
                        if r.diamond then r.chapter = nil end
                    end
                end
            end
        end
    elseif tab == "dungeons" then
        -- dungeons, then raids, each under a heading that folds like a zone's
        for _, group in ipairs({ { "Dungeons", false }, { "Raids", true } }) do
            local inGroup = {}
            for _, d in ipairs(dungeonList or {}) do if (d.raid or false) == group[2] then inGroup[#inGroup + 1] = d end end
            if #inGroup > 0 then
                local holds = false
                for _, d in ipairs(inGroup) do holds = holds or d.key == selected end
                local open = zoneOpen("dungeons", group[1], 1, holds)
                zoneHeader(row("head"), "dungeons", group[1], #inGroup, open)
                if open then
                    for _, d in ipairs(inGroup) do
                        card(row("chapter"), d.key, ns.zoneLocal(d.name), levels(d), d.done, d.total, d.cleared ~= nil)
                    end
                end
            end
        end
    elseif tab == "attune" then
        for _, a in ipairs(attuneList or {}) do
            local r = row("chapter")
            r.key = a.key
            r.title:SetText(a.title)
            local total = math.max(a.total, 1)
            if r.diamond then
                r.sub:SetText(not a.nextId and L["Attuned"] or a.total == 1 and L["1 step"] or (L["of %d steps"]):format(a.total))
                r.diamond:SetAtlas(a.done == 0 and "Legacy-Rewards-Tracker-Diamond-Disable" or "Legacy-Rewards-Tracker-Diamond")
                r.count:SetText(tostring(a.done))
                r.check:SetShown(not a.nextId)
                r.chapter = a
                r.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
            else
                r.sub:SetText((L["%d / %d steps"]):format(a.done, a.total))
            end
            r.bar:SetValue(a.done / total)
            r.sel:SetShown(a.key == selected)
        end
    else
        -- grouped by where you met them; zones in the order of your most recent dealings there
        local groups, order = {}, {}
        for _, p in ipairs(people) do
            if p.visible then
                local met = p.list[1] and ns.db.quests[p.list[1]] and ns.db.quests[p.list[1]].zone
                met = met or (p.list[1] and ns.LoreZone(p.list[1])) or L["Elsewhere"]
                if not groups[met] then groups[met] = {}; order[#order + 1] = met end
                table.insert(groups[met], p)
            end
        end
        for i, zone in ipairs(order) do
            local holds = false
            for _, p in ipairs(groups[zone]) do if p.name == selectedPerson then holds = true end end
            local open = zoneOpen("people", zone, i, holds)
            zoneHeader(row("head"), "people", zone, #groups[zone], open)
            for j, p in ipairs(open and groups[zone] or {}) do
                local r = row("person")
                r.key = p.name
                if r.stripe then r.stripe:SetShown(j % 2 == 0) end
                r.title:SetText(p.name)
                local info = (lore().npcs or {})[p.name] or {}
                local count = #p.list
                r.sub:SetText(info.t and ("<" .. info.t .. ">") or info.r
                    or (count == 1 and L["1 quest"] or (L["%d quests"]):format(count)))
                r.sel:SetShown(p.name == selectedPerson)
            end
        end
    end
    list:SetHeight(-y + 4)
end

-- ---------------------------------------------------------------- refresh / selection
local function applyFilter()
    for _, ch in ipairs(chapters) do
        local hit = matches(ch.title, ch.zone, ns.zoneLocal(ch.zone))
        if not hit and ch.locked then hit = matches(ch.start.title, ch.start.giver) end
        if not hit then
            for _, e in ipairs(ch.entries) do
                if matches(questTitle(e.id), personOf(e.id, "giver")) then hit = true; break end
            end
        end
        ch.visible = hit
    end
    for _, p in ipairs(people) do
        local info = (lore().npcs or {})[p.name] or {}
        p.visible = matches(p.name, info.t, info.r)
    end
end

local function findChapter(key)
    for _, c in ipairs(chapters) do if c.key == key and c.visible then return c end end
end

local function findPerson(name)
    for _, p in ipairs(people) do if p.name == name and p.visible then return p end end
end

-- the pages you came through on the Story tab, for the Back button (the latest last)
local history = {}
local function remember(key)
    if tab == "story" and selected and key ~= selected then
        history[#history + 1] = selected
        if #history > 30 then table.remove(history, 1) end
    end
end

local function showBack()
    local b = header.back
    if not b then return end
    b:ClearAllPoints()
    if header.recap:IsShown() then b:SetPoint("TOPRIGHT", header.recap, "TOPLEFT", -4, 0)
    else b:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0) end
    b:SetShown(tab == "story" and #history > 0)
end

function J.Refresh()
    if not frame or not frame:IsShown() then return end
    J.BuildChapters(true)
    buildPeople()
    applyFilter()
    if tab == "attune" then
        attuneList = attunements()
        local pick
        for _, a in ipairs(attuneList) do if a.key == selected then pick = a end end
        if not pick then pick = attuneList[1]; selected = pick and pick.key end
        renderList(); renderAttunement(pick)
        return
    elseif tab == "dungeons" then
        dungeonList = dungeons()
        local pick
        for _, d in ipairs(dungeonList) do if d.key == selected then pick = d end end
        if not pick then -- the first one for your level
            local lvl = UnitLevel("player") or 1
            for _, d in ipairs(dungeonList) do if not pick and (d.hi or 0) >= lvl then pick = d end end
            pick = pick or dungeonList[1]
            selected = pick and pick.key
        end
        renderList(); renderDungeon(pick)
        return
    elseif tab == "story" and selected == "chronicle" then
        renderList(); renderChronicle(); showBack()
    elseif tab == "story" and selected == "library" then
        renderList(); renderLibrary(); showBack()
    elseif tab == "story" and selected and selected:match("^area:") then
        renderList(); renderZone(selected:sub(6)); showBack()
    elseif tab == "story" and selected and selected:match("^books:") then
        renderList(); renderZone(selected:sub(7)); showBack()
    elseif tab == "story" then
        local ch = findChapter(selected)
        if not ch then
            for i = #chapters, 1, -1 do if chapters[i].visible and not chapters[i].locked then ch = chapters[i]; break end end
            selected = ch and ch.key
        end
        renderList(); renderChapter(ch); showBack()
    else
        local p = findPerson(selectedPerson)
        if not p then
            for _, x in ipairs(people) do if x.visible then p = x; break end end
            selectedPerson = p and p.name
        end
        renderList(); renderPerson(p)
    end
end

function J.Back()
    local key = table.remove(history)
    if not key then return end
    selected = key
    J.Refresh()
    pageScroll:SetVerticalScroll(0)
end

---@param key string?
function J.Select(key)
    remember(key)
    selected = key
    J.Refresh()
    pageScroll:SetVerticalScroll(0)
    if key and key:match("^books:") then -- down to the zone's books, once the page knows its height
        C_Timer.After(0, function()
            pageScroll:SetVerticalScroll(math.max(0, math.min(pageScroll:GetVerticalScrollRange(), J.booksAt or 0)))
        end)
    end
end

-- the Options and Share tabs show their page in place of the list and the parchment
local function panes()
    return {
        options = { host = frame.optionsHost, tab = frame.optionsTab, embed = function(h) return ns.Options.Embed(h) end,
                    unembed = function(h) ns.Options.Unembed(h) end },
        share = { host = frame.shareHost, tab = frame.shareTab, embed = function(h) return ns.Share.Embed(h) end },
    }
end

function J.SetTab(which, keepSelection)
    local all = panes()
    local p = all[which]
    local shown = p and p.host and p.embed(p.host)
    if p and not shown then
        -- nothing to share, or no page to show here: the old ways
        if which == "options" and ns.Options.Open() then frame:Hide() end
        return
    end
    for name, q in pairs(all) do
        if q.host then
            local on = name == which
            q.host:SetShown(on)
            if q.tab then q.tab:SetEnabled(not on) end
            if not on and q.unembed then q.unembed(q.host) end
        end
    end
    search:SetShown(not shown); listScroll:SetShown(not shown); frame.paper:SetShown(not shown)
    if shown then
        frame.tabStory:SetEnabled(true); frame.tabPeople:SetEnabled(true); frame.tabAttune:SetEnabled(true)
        frame.tabDungeons:SetEnabled(true)
        return
    end
    if which ~= tab and (OWN_LIST[which] or OWN_LIST[tab]) then selected = nil end
    tab = which
    frame.tabStory:SetEnabled(which ~= "story")
    frame.tabPeople:SetEnabled(which ~= "people")
    frame.tabAttune:SetEnabled(which ~= "attune")
    frame.tabDungeons:SetEnabled(which ~= "dungeons")
    listScroll:SetVerticalScroll(0); pageScroll:SetVerticalScroll(0)
    if not keepSelection then J.Refresh() end
end

function J.OnVoiceChanged()
    if tell.keys and not ns.Voice.IsPlaying() then -- the chronicle stopped: after a chapter (pause), or at its end
        if ns.settings.chroniclePause and tell.i < #tell.keys then tell.waiting = true
        else tell.keys, tell.i, tell.waiting = nil, 0, false end
    end
    if not (frame and frame:IsShown() and header.recap) then return end
    if tab == "story" and selected == "library" then J.Refresh() return end -- its rows say Stop while they play
    local by = ns.Voice.Owner()
    header.recap:SetText(by == header.recap and L["Stop"] or header.recap.label or L["Play recap"])
    if header.recap.tell and tell.waiting and by ~= header.recap then
        header.recap:SetText((L["Continue (%d/%d)"]):format(tell.i + 1, #tell.keys))
    end
    tellInfo()
    header.recap:SetEnabled(header.recap.anyAudio or by == header.recap)
    header.zone:SetText(by == header.zone and L["Stop"] or L["Play zone story"])
    if person.about then person.about:SetText(by == person.about and L["Stop"] or L["Who are they?"]) end
    for _, r in ipairs(entryRows) do
        r.play:SetText(by == r.play and L["Stop"] or L["Quest"])
        r.recap:SetText(by == r.recap and L["Stop"] or L["Recap"])
    end
end

-- ---------------------------------------------------------------- frame
-- Forever's own window style (the game's portrait frame: gold metal border, round portrait, side tabs), when this
-- client has it; otherwise the plain dark frame Chronicle had before.
local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- a square tab on the window's right edge, like the Friends and Progress Track windows
local function sideTab(parent, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(55, 55)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAtlas("common-sidetab"); b.bg:SetSize(55, 60); b.bg:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(34, 34); b.icon:SetPoint("CENTER", -2, 0)
    b.icon:SetTexture(icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.sel = b:CreateTexture(nil, "OVERLAY"); b.sel:SetAtlas("common-sidetab-selected"); b.sel:SetSize(55, 60); b.sel:SetPoint("CENTER")
    b.sel:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAtlas("common-sidetab-hover"); hl:SetSize(55, 60); hl:SetPoint("CENTER")
    b:SetScript("OnClick", function() if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end onClick() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- J.SetTab calls SetEnabled(false) on the tab that is open: show it selected instead of greying it out
    function b:SetEnabled(on) self.sel:SetShown(not on); self.icon:SetDesaturated(false) end
    return b
end

local function create()
    local styled = hasAtlas("common-sidetab") and hasAtlas("UI-Frame-PortraitMetal-CornerTopLeft")
        and pcall(function() frame = CreateFrame("Frame", "ChronicleJournalFrame", UIParent, "PortraitFrameTemplate") end)
        and frame and frame.NineSlice ~= nil
    if styled then
        frame:SetSize(W, H)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("HIGH")
        -- the dark rock background and the streaks along the top, like the game's own windows
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetPoint("TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", -2, 2)
        bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
        bg:SetHorizTile(true); bg:SetVertTile(true)
        local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        streaks:SetAtlas("_UI-Frame-TopTileStreaks", true)
        streaks:SetPoint("TOPLEFT", 2, -21); streaks:SetPoint("TOPRIGHT", -2, -21); streaks:SetHorizTile(true)
        pcall(frame.SetTitle, frame, "Chronicle")
        pcall(frame.SetPortraitToAsset, frame, "Interface\\Icons\\INV_Misc_Book_09")
    else
        if frame then frame:Hide() end
        frame = CreateFrame("Frame", "ChronicleJournalFrame", UIParent, "BackdropTemplate")
        frame:SetSize(W, H)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("HIGH")
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        frame:SetBackdropColor(0.1, 0.07, 0.05, 0.98)
        frame:SetBackdropBorderColor(0.45, 0.33, 0.16, 1)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26); icon:SetPoint("TOPLEFT", 12, -9); icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        local t = text(frame, "GameFontNormalLarge"); t:SetPoint("LEFT", icon, "RIGHT", 8, 0); t:SetText("Chronicle")
        frame.titleText = t
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ChronicleJournalFrame") -- Escape closes it
    -- in front when opened or clicked, like the game's own windows (the story-so-far page beside the map sits high
    -- in the same layer and used to cover it)
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
    -- the game's own open and close sounds (the same as the Adventure Guide), however it opens or closes
    if SOUNDKIT then
        frame:HookScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
        frame:HookScript("OnHide", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end)
    end

    local openOptions = function() if ns.Options.Open() then frame:Hide() end end -- the settings window opens behind ours
    if styled then
        -- side tabs: the two pages, then a gap, then options and sharing
        frame.tabStory = sideTab(frame, "Interface\\Icons\\INV_Scroll_03", L["The Story"], function() J.SetTab("story") end)
        frame.tabStory:SetPoint("TOPLEFT", frame, "TOPRIGHT", -3, -40)
        frame.tabPeople = sideTab(frame, "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", L["Characters"],
            function() J.SetTab("people") end)
        frame.tabPeople:SetPoint("TOPLEFT", frame.tabStory, "BOTTOMLEFT", 0, -4)
        frame.tabAttune = sideTab(frame, "Interface\\Icons\\INV_Misc_Key_14", L["Attunements"], function() J.ShowAttunements() end)
        frame.tabAttune:SetPoint("TOPLEFT", frame.tabPeople, "BOTTOMLEFT", 0, -4)
        frame.tabDungeons = sideTab(frame, "Interface\\Icons\\INV_Misc_Head_Dragon_Black", L["Dungeons & Raids"],
            function() J.SetTab("dungeons") end)
        frame.tabDungeons:SetPoint("TOPLEFT", frame.tabAttune, "BOTTOMLEFT", 0, -4)
        local options = sideTab(frame, "Interface\\Icons\\Trade_Engineering", L["Options"], function() J.SetTab("options") end)
        frame.optionsTab = options
        -- where the options page shows inside the journal
        frame.optionsHost = CreateFrame("Frame", nil, frame)
        frame.optionsHost:SetPoint("TOPLEFT", 70, -40); frame.optionsHost:SetPoint("BOTTOMRIGHT", -14, 12)
        frame.optionsHost:Hide()
        -- closing the journal on its Options tab: next time it opens on the story again
        frame:HookScript("OnHide", function()
            if frame.optionsHost:IsShown() or (frame.shareHost and frame.shareHost:IsShown()) then J.SetTab(tab, true) end
        end)
        options:SetPoint("TOPLEFT", frame.tabDungeons, "BOTTOMLEFT", 0, -22)
        local share = sideTab(frame, "Interface\\Icons\\INV_Letter_15", L["Share recordings"], function() J.SetTab("share") end)
        share:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -4)
        frame.shareTab = share
        frame.shareHost = CreateFrame("Frame", nil, frame)
        frame.shareHost:SetPoint("TOPLEFT", 70, -40); frame.shareHost:SetPoint("BOTTOMRIGHT", -14, 12)
        frame.shareHost:Hide()
    else
        frame.tabStory = button(frame, L["The Story"], 100); frame.tabStory:SetPoint("LEFT", frame.titleText, "RIGHT", 24, 0)
        frame.tabStory:SetScript("OnClick", function() J.SetTab("story") end)
        frame.tabPeople = button(frame, L["Characters"], 100); frame.tabPeople:SetPoint("LEFT", frame.tabStory, "RIGHT", 4, 0)
        frame.tabPeople:SetScript("OnClick", function() J.SetTab("people") end)
        frame.tabAttune = button(frame, L["Attunements"], 100); frame.tabAttune:SetPoint("LEFT", frame.tabPeople, "RIGHT", 4, 0)
        frame.tabAttune:SetScript("OnClick", function() J.SetTab("attune") end)
        frame.tabDungeons = button(frame, L["Dungeons & Raids"], 120); frame.tabDungeons:SetPoint("LEFT", frame.tabAttune, "RIGHT", 4, 0)
        frame.tabDungeons:SetScript("OnClick", function() J.SetTab("dungeons") end)
        local share = button(frame, L["Share recordings"], 130)
        share:SetPoint("TOPRIGHT", -36, -12)
        share:SetScript("OnClick", function() ns.Share.Open() end)
        local options = button(frame, L["Options"], 80)
        options:SetPoint("RIGHT", share, "LEFT", -4, 0)
        options:SetScript("OnClick", openOptions)
    end

    -- search (below the round portrait in the new style)
    local topY = styled and -66 or -50
    search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(LIST_W - 26, 20); search:SetPoint("TOPLEFT", 20, topY); search:SetAutoFocus(false)
    search.hint = text(search, "GameFontDisableSmall"); search.hint:SetPoint("LEFT", 4, 0); search.hint:SetText(L["Search quests, people, places"])
    search:SetScript("OnTextChanged", function(self)
        filter = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        self.hint:SetShown(self:GetText() == "")
        J.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- left list
    listScroll = scrollFrame(frame, 60)
    listScroll:SetPoint("TOPLEFT", 12, topY - 28); listScroll:SetPoint("BOTTOMLEFT", 12, 12); listScroll:SetWidth(LIST_W - 22)
    list = CreateFrame("Frame", nil, listScroll); list:SetSize(LIST_W - 22, 10)
    listScroll:SetScrollChild(list)

    -- parchment page
    local paper = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.paper = paper
    paper:SetPoint("TOPLEFT", LIST_W + 10, styled and -32 or -46); paper:SetPoint("BOTTOMRIGHT", -12, 12)
    paper:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    paper:SetBackdropColor(0.9, 0.84, 0.7, 1)
    paper:SetBackdropBorderColor(0.45, 0.33, 0.16, 1)
    local tex = paper:CreateTexture(nil, "BORDER")
    tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
    -- WoW: Forever's spellbook paper where the client has it (the spellbook stretches the same page across both
    -- halves; thanks Cav3dust), else the quest log's old parchment
    local spellbook = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("spellbook-Page-Right-C60")
    if spellbook and spellbook.file then
        -- the page's top strip is the book's dark edge: cut off, so the chapter title sits on paper
        local b = spellbook
        tex:SetTexture(b.file)
        -- and a little off the left, the shadow of the book's spine
        tex:SetTexCoord(b.leftTexCoord + (b.rightTexCoord - b.leftTexCoord) * 0.06, b.rightTexCoord,
            b.topTexCoord + (b.bottomTexCoord - b.topTexCoord) * 0.09, b.bottomTexCoord)
        tex:ClearAllPoints(); tex:SetAllPoints(paper)
        -- a faint warm light over it: the spellbook paper is darker than the parchment the text was made for
        local glow = paper:CreateTexture(nil, "BORDER", nil, 1)
        glow:SetAllPoints(paper); glow:SetColorTexture(1, 0.92, 0.75, 0.10); glow:SetBlendMode("ADD")
        paper:SetBackdropColor(0, 0, 0, 0); paper:SetBackdropBorderColor(0, 0, 0, 0)
    elseif tex:SetTexture("Interface\\QuestFrame\\QuestBG") then tex:SetTexCoord(0, 0.586, 0, 0.65); tex:SetAlpha(0.85) else tex:Hide() end

    pageScroll = scrollFrame(paper, 50)
    pageScroll:SetPoint("TOPLEFT", 22, -18); pageScroll:SetPoint("BOTTOMRIGHT", -30, 14) -- the scrollbar on flat paper, off the curled edge
    page = CreateFrame("Frame", nil, pageScroll); page:SetSize(W - LIST_W - 74, 10)
    pageScroll:SetScrollChild(page)

    frame:SetScale(tonumber(ns.settings.journalScale) or 1)

    -- a resize grip in the bottom right corner: drag it and the journal grows or shrinks as you go (its top left
    -- corner stays where it is). The same size as the options' Journal size slider.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4); grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(self)
        local sc = frame:GetScale()
        self.left, self.top = frame:GetLeft() * sc, frame:GetTop() * sc -- in the screen's (UIParent's) units
        self:SetScript("OnUpdate", function(g)
            local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
            local v = math.max(0.8, math.min(1.3, (cx - g.left) / W))
            frame:SetScale(v)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.left / v, g.top / v)
            ns.settings.journalScale = v
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if ns.Options and ns.Options.Refresh then pcall(ns.Options.Refresh) end -- the slider shows the new size
    end)

    -- story header
    header.title = text(page, "QuestTitleFont", INK_TITLE); header.title:SetPoint("TOPLEFT", 0, 0); header.title:SetPoint("RIGHT", -110, 0)
    header.sub = text(page, "GameFontNormalSmall", INK_SOFT); header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -5)
    -- the zone line under a chapter's title opens the zone's page (everything about its story, and what's left)
    header.zoneLink = CreateFrame("Button", nil, page)
    header.zoneLink:SetPoint("TOPLEFT", header.sub, "TOPLEFT", -2, 2); header.zoneLink:SetPoint("BOTTOMRIGHT", header.sub, "BOTTOMRIGHT", 2, -2)
    header.zoneLink:SetScript("OnEnter", function(self)
        ink(header.sub, INK_TITLE)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine((L["Everything about %s's story"]):format(ns.zoneLocal(self.zone) or ""), 1, 1, 1)
        GameTooltip:Show()
    end)
    header.zoneLink:SetScript("OnLeave", function() ink(header.sub, INK_SOFT); GameTooltip:Hide() end)
    header.zoneLink:SetScript("OnClick", function(self) click(); if self.zone then J.Select("area:" .. self.zone) end end)
    header.intro = text(page, "QuestFont", INK); header.intro:SetPoint("TOPLEFT", 0, -50); header.intro:SetSpacing(3)
    header.recap = button(page, L["Play recap"], 100); header.recap:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    header.recap:SetScript("OnClick", function(self)
        if self.tell then click(); J.TellChronicle(self) return end
        if self.libraryToggle then
            click()
            ns.settings.libraryView = (ns.settings.libraryView or "shelves") == "shelves" and "tiles" or "shelves"
            J.Refresh()
            return
        end
        toggle(self, function() ns.Voice.PlayQueue(self.keys or {}, self) end)
    end)
    header.zone = button(page, L["Play zone story"], 120); header.zone:SetPoint("TOPRIGHT", header.recap, "BOTTOMRIGHT", 0, -4)
    header.zone:SetScript("OnClick", function(self)
        toggle(self, function() ns.Voice.PlayQueue(self.keys or {}, self) end)
    end)
    -- the same page behind a button beside Play zone story, easier to find than the grey line
    header.overview = button(page, L["Zone overview"], 120)
    header.overview:SetPoint("RIGHT", header.zone, "LEFT", -4, 0)
    header.overview:SetScript("OnClick", function(self) if self.zone then J.Select("area:" .. self.zone) end end)
    header.overview:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine((L["Everything about %s's story"]):format(ns.zoneLocal(self.zone) or ""), 1, 1, 1)
        GameTooltip:Show()
    end)
    header.overview:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.tellInfo = text(page, "GameFontNormalSmall", INK_SOFT); header.tellInfo:SetJustifyH("RIGHT")
    header.tellInfo:SetPoint("TOPRIGHT", header.recap, "BOTTOMRIGHT", -2, -4)
    local ticker = CreateFrame("Frame", nil, page)
    ticker:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t > 0.5 then self.t = 0; tellInfo() end
    end)
    header.back = button(page, L["Back"], 70)
    header.back:SetScript("OnClick", function() click(); J.Back() end)
    header.tip = text(page, "GameFontDisableSmall"); header.tip:SetJustifyH("LEFT")
    header.left = text(page, "QuestFont", INK); header.left:SetJustifyH("LEFT"); header.left:SetSpacing(3)
    header.rule = page:CreateTexture(nil, "ARTWORK"); header.rule:SetHeight(1); header.rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.5)

    -- character page
    person.window = CreateFrame("Frame", nil, page, "BackdropTemplate")
    person.window:SetSize(180, 240); person.window:SetPoint("TOPLEFT", 0, 0)
    person.window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    person.window:SetBackdropColor(0.05, 0.04, 0.04, 1)
    person.window:SetBackdropBorderColor(0.45, 0.33, 0.16, 1)
    person.model = CreateFrame("PlayerModel", nil, person.window)
    person.model:SetPoint("TOPLEFT", 1, -1); person.model:SetPoint("BOTTOMRIGHT", -1, 1)
    person.name = text(page, "QuestTitleFont", INK_TITLE); person.name:SetPoint("TOPLEFT", person.window, "TOPRIGHT", 16, 0)
    person.title = text(page, "GameFontNormalSmall", INK_SOFT); person.title:SetPoint("TOPLEFT", person.name, "BOTTOMLEFT", 0, -5)
    person.where = text(page, "GameFontNormalSmall", INK_SOFT); person.where:SetPoint("TOPLEFT", person.title, "BOTTOMLEFT", 0, -4)
    person.hear = button(page, L["Hear them"], 90); person.hear:SetPoint("TOPLEFT", person.where, "BOTTOMLEFT", 0, -8)
    person.hear:SetScript("OnClick", function(self)
        if not self.key then return end
        if ns.Voice.IsPlaying() and ns.Voice.PlayingKey() == self.key then ns.Voice.Stop(); return end
        if ns.Voice.Play(self.key) then
            -- the model talks while they speak, then goes back to standing
            local m, e = person.model, ns.Voice.Get(self.key)
            pcall(m.SetAnimation, m, 60)
            person.talkUntil = GetTime() + ((e and e.d) or 3)
        end
    end)
    person.about = button(page, L["Who are they?"], 110); person.about:SetPoint("LEFT", person.hear, "RIGHT", 6, 0)
    person.about:SetScript("OnClick", function(self)
        toggle(self, function() ns.Voice.PlayQueue({ self.key }, self) end)
    end)
    person.bio = text(page, "QuestFont", INK); person.bio:SetPoint("TOPLEFT", person.hear, "BOTTOMLEFT", 0, -10); person.bio:SetSpacing(3)
    person.dealings = text(page, "QuestTitleFont", INK_TITLE); person.dealings:SetPoint("TOPLEFT", person.bio, "BOTTOMLEFT", 0, -16)
    person.dealings:SetText(L["Your dealings"])
    person.deal = {}

    -- the model: a soft backdrop, drag to turn, scroll to zoom
    local glow = person.window:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetColorTexture(1, 1, 1, 1)
    local top, bottom = { 0.16, 0.13, 0.10, 1 }, { 0.03, 0.025, 0.02, 1 }
    if CreateColor then pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top))) end
    person.hint = text(page, "GameFontDisableSmall"); person.hint:SetPoint("TOP", person.window, "BOTTOM", 0, -4)
    person.hint:SetText(L["Drag to turn  -  scroll to zoom"])
    local m = person.model
    m:EnableMouse(true); m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self) self.dragX, self.dragFacing = GetCursorPosition(), self:GetFacing() or 0 end)
    m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    m:SetScript("OnMouseWheel", function(self, d)
        self.zoom = math.max(0, math.min(0.9, (self.zoom or 0.35) + d * 0.1))
        pcall(self.SetPortraitZoom, self, self.zoom)
    end)
    m:SetScript("OnUpdate", function(self)
        if self.dragX then
            local x = GetCursorPosition()
            self:SetFacing(self.dragFacing + (x - self.dragX) / 80)
        end
        if person.talkUntil and GetTime() > person.talkUntil then
            person.talkUntil = nil
            pcall(self.SetAnimation, self, 0)
        end
    end)

    frame.tabStory:SetEnabled(false)
    frame:Hide()
end

-- The chapter for where you are: one in this zone with a quest in progress, else the latest one in this zone.
local function chapterHere()
    local zone = GetRealZoneText and ns.zoneEN(GetRealZoneText())
    if not zone or zone == "" then return nil end
    local best
    for _, c in ipairs(chapters) do
        if c.zone == zone then
            for _, e in ipairs(c.entries) do
                if e.state == "active" then return c.key end
            end
            best = c.key
        end
    end
    return best
end

-- Open the journal on a given chapter (map pins, reminders).
function J.Open(key)
    if not frame then create() end
    remember(key)
    frame:Show()
    if tab ~= "story" then J.SetTab("story", true) end
    selected = key
    J.Refresh()
    pageScroll:SetVerticalScroll(0)
end

-- Open the journal on the Attunements tab, on one attunement when given (the note when its road begins).
function J.ShowAttunements(id)
    if not frame then create() end
    frame:Show()
    J.SetTab("attune", true)
    if id then selected = "att:" .. id end
    J.Refresh()
    pageScroll:SetVerticalScroll(0)
end

-- the journal's size (the options' slider). Applied once the slider rests: the options can sit inside the journal,
-- and resizing it under the mouse while dragging or scrolling made the slider jump.
local scaleTimer
function J.SetScale(v)
    ns.settings.journalScale = v
    if scaleTimer then scaleTimer:Cancel() end
    scaleTimer = C_Timer.NewTimer(0.5, function()
        scaleTimer = nil
        if frame then frame:SetScale(tonumber(ns.settings.journalScale) or 1) end
    end)
end

function J.Toggle()
    if not frame then create() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        J.BuildChapters()
        if tab == "story" then selected = chapterHere() or selected end
        J.Refresh()
    end
end

-- /lore share and the share nudge: the Share tab of the journal in the new style (false: use the old window)
function J.ShowShare()
    if not frame then create() end
    if not frame.shareHost then return false end
    frame:Show()
    J.SetTab("share")
    return frame.shareHost:IsShown()
end

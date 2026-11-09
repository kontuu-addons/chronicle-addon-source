-- Chronicle / Reminder: "Previously in <zone>" when you return to a zone after a while away.
-- Offers the narrator's recaps of the last quests you finished there. Nothing plays unless you click Listen.
local _, ns = ...
local L = ns.L
local R = {}
ns.Reminder = R

-- seconds away before a zone counts as "returning": a day (it was half an hour, and the note came after every trip to
-- town or a dungeon; the user: "Noone forgets that quick")
local AWAY = 24 * 60 * 60
local SHOW_FOR = 25    -- seconds the toast stays up (longer while the mouse is over it)
local toast

-- Each kind of note by its box in the options (Options.lua), the one its "Don't show these" unticks
local OPTION = {
    zoneRecap = "\"Previously in...\" reminders", zoneIntro = "Welcome to new zones",
    flightStory = "The story on flights", bestiary = "Bestiary", campfire = "By the fire",
    levelMilestones = "Level milestones", shareNudge = "Remind me to share new quests",
    -- a dungeon's notes have their own box: under "Previously in...", turning that off hid them too, so nothing was
    -- said after a dungeon's last boss (the user, 2026-11-07: "it doesnt talk about the boss after i kille them")
    dungeonStory = "Dungeon stories",
}

-- "Don't show these" (the user, 2026-11-06: people click away the notes, "Previously in" and the bestiary's): that kind
-- of note is off, and the chat says where to turn it back on. What the notes offered stays in the journal.
function R.TurnOff(kind)
    if not OPTION[kind] then return end
    if ns.Options and ns.Options.Set then ns.Options.Set(kind, false) else ns.settings[kind] = false end
    ns.pr((L["these notes are off now. To get them back, tick \"%s\" in /lore options."]):format(L[OPTION[kind]]))
end

-- The link in a note's foot (the note is a strip taller while it shows); t.kind says what it turns off.
function R.AddOffLink(t)
    local b = CreateFrame("Button", nil, t)
    b:SetNormalFontObject("GameFontDisableSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetText(L["Don't show these"])
    local fs = b:GetFontString()
    b:SetSize(math.max(80, (fs and fs:GetStringWidth() or 0) + 6), 14)
    b:SetPoint("BOTTOMRIGHT", -10, 5)
    b:SetScript("OnClick", function() t:Hide(); R.TurnOff(t.kind) end)
    t.off = b
    return b
end

-- A note's Listen and History wait their turn after whoever is talking and the lines already waiting; they used to cut
-- the line off and throw the waiting ones away (domino1919 on CurseForge: "it deletes the queue and plays"). With
-- nothing talking, or the voices paused, they play at once.
local function listen(keys)
    if not ns.Voice.IsPlaying() then return ns.Voice.PlayQueue(keys) end
    for _, k in ipairs(keys) do ns.Voice.Enqueue(k) end
end

local function questZone(id, e)
    local q = ns.db.quests[id] or {}
    return q.zone or ns.LoreZone(id) or e.zone
end

-- Recap keys for the last few quests you finished in this zone, oldest first.
local function recentRecaps(zone, max)
    local keys, titles = {}, {}
    local j = ns.char.journal
    for i = #j, 1, -1 do
        local e = j[i]
        if questZone(e.id, e) == zone and ns.Voice.Get("sum:" .. e.id) then
            table.insert(keys, 1, "sum:" .. e.id)
            local q = ns.db.quests[e.id]
            table.insert(titles, 1, q and q.title or nil)
            if #keys >= max then break end
        end
    end
    return keys, titles
end

local function getToast()
    if toast then toast.open = nil; toast.history:Hide(); return toast end
    local t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    t:SetSize(340, 74)
    -- drag it anywhere; right-click puts it back at the top of the screen (thanks alche)
    local function place()
        local pos = ns.settings.reminderPos
        t:ClearAllPoints()
        if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" then
            t:SetPoint("TOP", UIParent, "BOTTOMLEFT", pos[1], pos[2])
        else
            t:SetPoint("TOP", UIParent, "TOP", 0, -140)
        end
    end
    place()
    t:SetMovable(true); t:SetClampedToScreen(true); t:EnableMouse(true); t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", t.StartMoving)
    t:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, top = self:GetCenter(), self:GetTop()
        ns.settings.reminderPos = { x, top }
        place()
    end)
    t:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.settings.reminderPos = nil; place() end
    end)
    t:SetFrameStrata("MEDIUM")
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    t:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    t:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    t:EnableMouse(true)

    local icon = t:CreateTexture(nil, "ARTWORK")
    -- from the top, so a note with "Don't show these" grows only at its foot
    icon:SetSize(40, 40); icon:SetPoint("TOPLEFT", 10, -17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0); t.title:SetPoint("RIGHT", -28, 0); t.title:SetJustifyH("LEFT")
    t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3); t.sub:SetPoint("RIGHT", -12, 0)
    t.sub:SetJustifyH("LEFT"); t.sub:SetWordWrap(false)

    t.listen = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    t.listen:SetSize(80, 20); ns.FitButton(t.listen); t.listen:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -4)
    t.listen:SetText(L["Listen"])
    t.listen:SetScript("OnClick", function() listen(t.keys or {}); t:Hide() end)
    t.journal = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    t.journal:SetSize(80, 20); ns.FitButton(t.journal); t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    t.journal:SetText(L["Journal"])
    t.journal:SetScript("OnClick", function()
        t:Hide()
        if t.open then t.open() else ns.Journal.Toggle() end
    end)
    -- zone welcomes: the zone's longer history, for those who want all the lore (only shown when it is voiced)
    t.history = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    t.history:SetSize(80, 20); ns.FitButton(t.history); t.history:SetPoint("LEFT", t.journal, "RIGHT", 6, 0)
    t.history:SetText(L["History"])
    t.history:SetScript("OnClick", function() listen({ t.historyKey }); t:Hide() end)
    t.history:Hide()
    local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 0, 0)
    R.AddOffLink(t)

    t:SetScript("OnUpdate", function(self)
        if self:IsMouseOver() then self.hideAt = GetTime() + 5 end
        if GetTime() > (self.hideAt or 0) then self:Hide() end
    end)
    -- zone welcomes: the whole intro on hover (the toast only has room for its start)
    t:SetScript("OnEnter", function(self)
        if not self.full then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.title:GetText())
        GameTooltip:AddLine(self.full, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:Hide()
    toast = t
    return t
end

-- a note is up (the bestiary waits for it to go: a new note would take its place)
function R.Busy() return toast ~= nil and toast:IsShown() end

-- Up it goes for secs, with "Don't show these" in its foot when its kind of note has a box in the options.
local function present(t, kind, secs)
    kind = OPTION[kind] and kind or nil
    t.kind = kind
    t.off:SetShown(kind ~= nil)
    t:SetHeight(kind and 88 or 74)
    t.hideAt = GetTime() + secs
    t:Show()
    return true
end

-- The story chapters begun in a zone: the ones still under way, in the order you began them (as the journal has
-- them), and how many are finished.
local function chaptersHere(zone)
    local going, finished = {}, 0
    local all = ns.Journal and ns.Journal.BuildChapters and ns.Journal.BuildChapters() or {}
    for _, ch in ipairs(all) do
        if ch.arc and ch.zone == zone and #ch.entries > 0 then
            if ch.done >= (ch.total or #ch.entries) then finished = finished + 1 else going[#going + 1] = ch end
        end
    end
    return going, finished
end

-- Where you are in each chapter under way: its introduction, then the recap of the last step you finished in it.
-- Back after days away, the last three quests' recaps said little about the zone's story (Heybarbaruiva: "more of
-- an overview of my progress in the zone's main story so far"). At most three chapters: the ones you did something
-- in last, told in the order you began them.
local MAX_TOLD = 3
local function storySoFar(going)
    local at, when = {}, {}
    for i, e in ipairs(ns.char.journal) do at[e.id], when[e.id] = i, e.t or 0 end
    local told = going
    if #going > MAX_TOLD then
        local busy = {}
        for i, ch in ipairs(going) do
            local last = 0 -- a step finished, or a quest of it taken
            for _, e in ipairs(ch.entries) do
                local t = (e.state == "done" and when[e.id]) or (ns.char.active and ns.char.active[e.id]) or 0
                if t > last then last = t end
            end
            busy[i] = { ch = ch, i = i, t = last }
        end
        table.sort(busy, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.i > b.i end)
        local keep = {}
        for i = 1, MAX_TOLD do keep[busy[i].ch] = true end
        told = {}
        for _, ch in ipairs(going) do if keep[ch] then told[#told + 1] = ch end end
    end
    local keys = {}
    for _, ch in ipairs(told) do
        if ch.introKey and ns.Voice.Get(ch.introKey) then keys[#keys + 1] = ch.introKey end
        local last
        for _, e in ipairs(ch.entries) do
            if e.state == "done" and (at[e.id] or 0) >= (last and at[last] or 0) then last = e.id end
        end
        if last and ns.Voice.Get("sum:" .. last) then keys[#keys + 1] = "sum:" .. last end
    end
    return keys
end

function R.Show(zone)
    local going, finished = chaptersHere(zone)
    local keys, titles = {}, {}
    if #going > 0 then keys = storySoFar(going) end
    if #keys == 0 then keys, titles = recentRecaps(zone, 3) end
    if #going == 0 and #keys == 0 then return false end
    local t = getToast()
    t.keys = keys
    -- Journal: the zone's page, every chapter there with how far you are and what's left
    t.open = function() ns.Journal.Open("area:" .. zone) end
    local voiced = #keys > 0 and not ns.settings.journalOnly
    t.listen:SetShown(voiced)
    t.journal:ClearAllPoints()
    if voiced then t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    else t.journal:SetPoint("TOPLEFT", t.sub, "BOTTOMLEFT", -2, -6) end
    t.title:SetText((L["Previously in %s"]):format(ns.zoneLocal(zone)))
    if #going > 0 then
        -- "Chapters: 2 in progress  ·  3 finished"; hover: each one under way and how far you are in it
        local bits = { #going .. L[" in progress"] }
        if finished > 0 then bits[2] = finished .. L[" finished"] end
        t.sub:SetText(L["Chapters"] .. ": " .. table.concat(bits, "  ·  "))
        local lines = {}
        for _, ch in ipairs(going) do
            lines[#lines + 1] = ("%s  |cffaaaaaa%d/%d|r"):format(ch.title, ch.done, ch.total or #ch.entries)
        end
        if finished > 0 then
            lines[#lines + 1] = "|cffaaaaaa" .. finished .. " " .. (finished == 1 and L["chapter finished"] or L["chapters finished"]) .. "|r"
        end
        t.full = table.concat(lines, "\n")
    else
        t.full = nil
        local last = titles[#titles]
        t.sub:SetText(last and (L["Last: %s"]):format(last) or (L["%d recaps"]):format(#keys))
    end
    return present(t, "zoneRecap", SHOW_FOR)
end

-- A story moment worth its own note: a zone's epilogue, a dungeon's ending. Listen plays keys; hover shows text.
-- open: what the Journal button opens (default: the journal as it was). line: shown in place of the text's start.
-- kind: the setting this note comes under (it gets "Don't show these"), when it has a box in the options.
function R.ShowStory(title, text, keys, open, line, kind)
    local t = getToast()
    t.keys, t.full, t.open = keys, text, open
    local voiced = keys[1] and ns.Voice.Get(keys[1]) ~= nil and not ns.settings.journalOnly
    t.listen:SetShown(voiced)
    t.journal:ClearAllPoints()
    if voiced then t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    else t.journal:SetPoint("TOPLEFT", t.sub, "BOTTOMLEFT", -2, -6) end
    t.title:SetText(title)
    t.sub:SetText(line or text or "")
    return present(t, kind, SHOW_FOR * 2)
end

-- Entering a dungeon or raid: offer its welcome and the narrator's chapter intros for it (once per visit).
local announced = {}
function R.ShowDungeon(zone)
    local intro = ns.Lore and ns.Lore.dungeonIntro and ns.Lore.dungeonIntro[zone]
    if intro then
        local keys = { "dng:" .. zone }
        for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
            if a.zone == zone and ns.Voice.Get("arc:" .. a.id) and #keys < 3 then keys[#keys + 1] = "arc:" .. a.id end
        end
        return R.ShowStory((L["Entering %s"]):format(ns.zoneLocal(zone)), intro, keys,
            function() ns.Journal.ShowDungeon(zone) end, nil, "dungeonStory")
    end
    local keys, first = {}, nil
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        if a.zone == zone and ns.Voice.Get("arc:" .. a.id) then
            keys[#keys + 1] = "arc:" .. a.id
            first = first or a.title
            if #keys >= 2 then break end
        end
    end
    if #keys == 0 then return false end
    local t = getToast()
    t.keys, t.full = keys, nil
    t.listen:Show()
    t.journal:ClearAllPoints(); t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    t.title:SetText((L["Entering %s"]):format(ns.zoneLocal(zone)))
    t.sub:SetText(first or "")
    return present(t, "dungeonStory", SHOW_FOR)
end

-- First time in a zone: the narrator's short introduction to it (nothing plays unless you click Listen).
-- asked: /lore welcome, so no "Don't show these" on it.
function R.ShowWelcome(zone, asked)
    local text = ns.Lore and ns.Lore.zoneIntro and ns.Lore.zoneIntro[zone]
    if not text then return false end
    local t = getToast()
    local key = "zone:" .. zone
    t.keys, t.full = { key }, text
    -- the zone's own page, where this welcome stays to read again (it was gone once closed; thanks emmaloui)
    t.open = function() ns.Journal.Open("area:" .. zone) end
    local voiced = ns.Voice.Get(key) ~= nil and not ns.settings.journalOnly
    t.listen:SetShown(voiced)
    t.journal:ClearAllPoints()
    if voiced then
        t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    else
        t.journal:SetPoint("TOPLEFT", t.sub, "BOTTOMLEFT", -2, -6)
    end
    t.historyKey = "hist:" .. zone
    t.history:SetShown(voiced and ns.Voice.Get(t.historyKey) ~= nil)
    t.title:SetText((L["Welcome to %s"]):format(ns.zoneLocal(zone)))
    t.sub:SetText(text)
    return present(t, not asked and "zoneIntro" or nil, SHOW_FOR)
end

-- Taking a flight: the story so far in the zone you're flying to, or its welcome if you haven't started there.
function R.ShowFlight(zone)
    if not zone then return false end
    local keys, titles = recentRecaps(zone, 3)
    local t
    if #keys > 0 then
        t = getToast()
        t.keys, t.full = keys, nil
        t.listen:Show()
        t.journal:ClearAllPoints(); t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
        local last = titles[#titles]
        t.sub:SetText(last and (L["Last: %s"]):format(last) or (L["%d recaps"]):format(#keys))
    elseif R.ShowWelcome(zone) then
        t = toast -- as the welcome set it up (getToast again cleared its Journal button's page and its History)
    else
        return false
    end
    t.title:SetText((L["Flying to %s"]):format(ns.zoneLocal(zone)))
    return present(t, "flightStory", SHOW_FOR)
end

local ev -- created below; onZone waits for the end of a fight on it

local function onZone()
    local zone = GetRealZoneText and ns.zoneEN(ns.clean(GetRealZoneText()))
    if not zone or zone == "" or not ns.char then return end
    if UnitOnTaxi("player") then return end -- flying over a zone isn't visiting it; landing checks again
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then
        if ns.settings.dungeonStory ~= false and not announced[zone] then
            announced[zone] = true
            R.ShowDungeon(zone)
        end
        return
    end
    announced = {} -- leaving resets, so the next run gets the offer again
    -- not in combat: mark the zone as seen only when the welcome could really show, else it is lost for good (thanks Pylo)
    if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED") return end
    ns.char.zoneSeen = ns.char.zoneSeen or {}
    local last = ns.char.zoneSeen[zone]
    ns.char.zoneSeen[zone] = time()
    if not last and ns.settings.zoneIntro then
        R.ShowWelcome(zone)
    elseif ns.settings.zoneRecap and last and time() - last > AWAY then
        R.Show(zone)
    end
end

ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end -- the fight is over: look at the zone again
    C_Timer.After(2, onZone)
end)
table.insert(ns.onLogin, function()
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("PLAYER_CONTROL_GAINED")
    C_Timer.After(6, onZone) -- logging back in after a break counts as returning too
end)

-- keep "last seen" fresh while you stay in a zone, so a long session there is not "away"
C_Timer.NewTicker(300, function()
    local zone = GetRealZoneText and ns.zoneEN(ns.clean(GetRealZoneText()))
    -- only a zone already seen: a new one must still get its welcome (and a zone flown over isn't seen)
    if zone and zone ~= "" and ns.char and ns.char.zoneSeen and ns.char.zoneSeen[zone] and not UnitOnTaxi("player") then
        ns.char.zoneSeen[zone] = time()
    end
end)

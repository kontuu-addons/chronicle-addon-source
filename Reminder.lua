-- Chronicle / Reminder: "Previously in <zone>" when you return to a zone after a while away.
-- Offers the narrator's recaps of the last quests you finished there. Nothing plays unless you click Listen.
local _, ns = ...
local L = ns.L
local R = {}
ns.Reminder = R

local AWAY = 30 * 60   -- seconds away before a zone counts as "returning"
local SHOW_FOR = 25    -- seconds the toast stays up (longer while the mouse is over it)
local toast

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
    if toast then toast.open = nil; return toast end
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
    icon:SetSize(40, 40); icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0); t.title:SetPoint("RIGHT", -28, 0); t.title:SetJustifyH("LEFT")
    t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3); t.sub:SetPoint("RIGHT", -12, 0)
    t.sub:SetJustifyH("LEFT"); t.sub:SetWordWrap(false)

    t.listen = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    t.listen:SetSize(80, 20); ns.FitButton(t.listen); t.listen:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -4)
    t.listen:SetText(L["Listen"])
    t.listen:SetScript("OnClick", function() ns.Voice.PlayQueue(t.keys or {}); t:Hide() end)
    t.journal = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    t.journal:SetSize(80, 20); ns.FitButton(t.journal); t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    t.journal:SetText(L["Journal"])
    t.journal:SetScript("OnClick", function()
        t:Hide()
        if t.open then t.open() else ns.Journal.Toggle() end
    end)
    local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 0, 0)

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

function R.Show(zone)
    local keys, titles = recentRecaps(zone, 3)
    if #keys == 0 then return false end
    local t = getToast()
    t.keys, t.full = keys, nil
    t.listen:Show()
    t.journal:ClearAllPoints(); t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    t.title:SetText((L["Previously in %s"]):format(ns.zoneLocal(zone)))
    local last = titles[#titles]
    t.sub:SetText(last and (L["Last: %s"]):format(last) or (L["%d recaps"]):format(#keys))
    t.hideAt = GetTime() + SHOW_FOR
    t:Show()
    return true
end

-- A story moment worth its own note: a zone's epilogue, a dungeon's ending. Listen plays keys; hover shows text.
-- open: what the Journal button opens (default: the journal as it was). line: shown in place of the text's start.
function R.ShowStory(title, text, keys, open, line)
    local t = getToast()
    t.keys, t.full, t.open = keys, text, open
    local voiced = keys[1] and ns.Voice.Get(keys[1]) ~= nil and not ns.settings.journalOnly
    t.listen:SetShown(voiced)
    t.journal:ClearAllPoints()
    if voiced then t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    else t.journal:SetPoint("TOPLEFT", t.sub, "BOTTOMLEFT", -2, -6) end
    t.title:SetText(title)
    t.sub:SetText(line or text or "")
    t.hideAt = GetTime() + SHOW_FOR * 2
    t:Show()
    return true
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
        return R.ShowStory((L["Entering %s"]):format(ns.zoneLocal(zone)), intro, keys)
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
    t.hideAt = GetTime() + SHOW_FOR
    t:Show()
    return true
end

-- First time in a zone: the narrator's short introduction to it (nothing plays unless you click Listen).
function R.ShowWelcome(zone)
    local text = ns.Lore and ns.Lore.zoneIntro and ns.Lore.zoneIntro[zone]
    if not text then return false end
    local t = getToast()
    local key = "zone:" .. zone
    t.keys, t.full = { key }, text
    local voiced = ns.Voice.Get(key) ~= nil and not ns.settings.journalOnly
    t.listen:SetShown(voiced)
    t.journal:ClearAllPoints()
    if voiced then
        t.journal:SetPoint("LEFT", t.listen, "RIGHT", 6, 0)
    else
        t.journal:SetPoint("TOPLEFT", t.sub, "BOTTOMLEFT", -2, -6)
    end
    t.title:SetText((L["Welcome to %s"]):format(ns.zoneLocal(zone)))
    t.sub:SetText(text)
    t.hideAt = GetTime() + SHOW_FOR
    t:Show()
    return true
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
        t = getToast()
    else
        return false
    end
    t.title:SetText((L["Flying to %s"]):format(ns.zoneLocal(zone)))
    t.hideAt = GetTime() + SHOW_FOR
    t:Show()
    return true
end

local ev -- created below; onZone waits for the end of a fight on it

local function onZone()
    local zone = GetRealZoneText and ns.zoneEN(ns.clean(GetRealZoneText()))
    if not zone or zone == "" or not ns.char then return end
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then
        if ns.settings.zoneRecap and not announced[zone] then
            announced[zone] = true
            R.ShowDungeon(zone)
        end
        return
    end
    announced = {} -- leaving resets, so the next run gets the offer again
    -- not in combat: mark the zone as seen only when the welcome could really show, else it is lost for good
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
    C_Timer.After(6, onZone) -- logging back in after a break counts as returning too
end)

-- keep "last seen" fresh while you stay in a zone, so a long session there is not "away"
C_Timer.NewTicker(300, function()
    local zone = GetRealZoneText and ns.zoneEN(ns.clean(GetRealZoneText()))
    -- only a zone already seen: a new one must still get its welcome
    if zone and zone ~= "" and ns.char and ns.char.zoneSeen and ns.char.zoneSeen[zone] then ns.char.zoneSeen[zone] = time() end
end)

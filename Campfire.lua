-- Chronicle / Campfire: sit by a camp fire (WoW: Forever's camping) and a small window counts down the minute until
-- the camp's benefits arrive, offers a campfire tale for the zone while you wait, and then shows what the camp gave.
local _, ns = ...
local L = ns.L
local C = {}
ns.Campfire = C

-- English names; the spell IDs are learned the first time they are seen, so other client languages work after that
local WAITING, BENEFITS, RESTED, NEARBY = "Welcoming Campfire", "Camp Benefits", "Boosted Rest", "Campfire Nearby"
local invitedOff = {} -- zones where the invitation was waved away this session
-- camp objects you hovered over at this fire (the game does not say what a camp holds until the minute is up)
local OBJECTS = { "Camp Chair", "Camp Tent", "Tent", "Fish Bowl", "Lodestone", "Mana Well", "Sharpening Wheel",
    "Faction Banner", "Incense Candle", "Reagent Bot", "First Aid Kit" }
local seenHere, seenOrder = {}, {}
local SHOW_BENEFITS = 10 -- seconds the window shows what the camp gave

local win, lastWaiting, lastExpires

-- aura timings can be hidden from addons (in combat): nil then, and the window simply leaves them out
local function safe(v)
    if v == nil or (canaccessvalue and not canaccessvalue(v)) then return nil end
    return v
end

local function auras()
    local out, i = {}, 1
    while i <= 40 do
        local a
        -- in combat the game locks buff data for addons and reading it throws an error: pcall, and the ticker
        -- doesn't ask in combat at all (a camp is never a fight)
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            a = ok and data or nil
        elseif UnitAura then
            local ok, name, _, _, _, duration, expires, _, _, _, id = pcall(UnitAura, "player", i, "HELPFUL")
            a = ok and name and { name = name, duration = duration, expirationTime = expires, spellId = id } or nil
        end
        if not a then break end
        -- a plain copy with only what the game lets addons read (hidden values become nil), so comparing them is safe
        out[#out + 1] = { name = safe(a.name), spellId = safe(a.spellId), duration = safe(a.duration),
                          expirationTime = safe(a.expirationTime), sourceUnit = safe(a.sourceUnit), index = i, raw = a }
        i = i + 1
    end
    return out
end

-- the camp aura we are after: by its learned spell ID, or by its English name (and then learn the ID)
local function find(name)
    ns.db.campSpells = ns.db.campSpells or {}
    -- known from the beta, so every client language works from the first fire
    ns.db.campSpells[WAITING] = ns.db.campSpells[WAITING] or 1289723 -- (the beta also uses 1229739 for it)
    ns.db.campSpells[BENEFITS] = ns.db.campSpells[BENEFITS] or 1229741
    ns.db.campSpells[NEARBY] = ns.db.campSpells[NEARBY] or 1283391
    local id = ns.db.campSpells[name]
    -- the cheap way first: is the camp buff there at all? (reading every buff twice a second made garbage)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if get and id then
        local ok, a = pcall(get, id)
        local ok2, b = false, nil
        if name == WAITING then ok2, b = pcall(get, 1229739) end
        if not ((ok and a) or (ok2 and b)) then return nil end
    end
    for _, a in ipairs(auras()) do
        local readable = not canaccessvalue or (canaccessvalue(a.name) and canaccessvalue(a.spellId))
        local ok = readable and ((id and a.spellId == id) or (name == WAITING and a.spellId == 1229739) or (a.name == name))
        if ok then
            if a.spellId and not id then ns.db.campSpells[name] = a.spellId end
            return a
        end
    end
end

-- the benefits as the buff's own tooltip lists them ("Tent: ...", "Camp Chair: ...")
local function benefitText(a)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnitBuff then
        local ok, data = pcall(C_TooltipInfo.GetUnitBuff, "player", a.index, "HELPFUL")
        for i, line in ipairs(ok and data and data.lines or {}) do
            if i > 1 and line.leftText and line.leftText ~= "" then lines[#lines + 1] = line.leftText end
        end
    end
    -- one effect per line ("Fish Bowl: All stats increased by 8%."): drop the heading and the time left
    local out = {}
    for _, block in ipairs(lines) do
        block = block:gsub("|n", "\n") -- the game's own line breaks
        for t in block:gmatch("[^\r\n]+") do
            t = t:gsub("^%s+", ""):gsub("%s+$", "")
            -- an effect is "Name: what it does"; skip the heading, the time left and anything without a colon
            if t:find(":", 1, true) and not t:find(":$") and not t:lower():find("remaining", 1, true) then out[#out + 1] = t end
        end
    end
    return table.concat(out, "\n")
end

-- the tale for this zone: its voice key when voiced, and its text (shown in the window until the voice exists)
local function taleKey()
    local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    local text = zone and ns.Lore and ns.Lore.campfire and ns.Lore.campfire[zone]
    if not text then return nil, zone end
    local key = "tale:" .. zone
    return key, zone, ns.Voice.Get(key) ~= nil, text
end

-- Chronicle hiding the window itself (not you closing it)
local function hideWin(w)
    if not w then return end
    w.byUs = true; w:Hide(); w.byUs = nil
end

local function create()
    local f = CreateFrame("Frame", "ChronicleCampfireFrame", UIParent, "BackdropTemplate")
    ns.PadClose("ChronicleCampfireFrame") -- with a controller, its back button (Escape) closes it
    f:SetSize(260, 92)
    local pos = ns.settings.campfirePos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    f:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.settings.campfirePos = { p, rp, x, y }
    end)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1); f.title:SetPoint("RIGHT", -28, 0); f.title:SetJustifyH("LEFT")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4); f.sub:SetPoint("RIGHT", -12, 0)
    f.sub:SetJustifyH("LEFT"); f.sub:SetSpacing(2)
    f.story = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.story:SetSize(120, 20); ns.FitButton(f.story); f.story:SetPoint("BOTTOMLEFT", 10, 10)
    f.story:SetText(L["Tell me a story"])
    f.story:SetScript("OnClick", function(b)
        if ns.Voice.Owner() == b then ns.Voice.Stop(); return end
        local key, zone, voiced, text = taleKey()
        if not key then return end
        ns.char.tales = ns.char.tales or {}
        ns.char.tales[zone] = time()
        if voiced then ns.Voice.Play(key, b); return end
        -- not voiced yet: read it in the window
        f.reading = true
        f:SetWidth(380) -- a wider page to read on
        f.sub:SetText(text)
        f.story:Hide(); f.later:Hide()
        f:SetHeight(f.title:GetStringHeight() + f.sub:GetStringHeight() + 34)
    end)
    f.later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.later:SetSize(80, 20); ns.FitButton(f.later); f.later:SetPoint("LEFT", f.story, "RIGHT", 6, 0)
    f.later:SetText(L["Not now"])
    f.later:SetScript("OnClick", function() f.dismissed = true; f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        if f.reading then
            -- closing the tale goes back to the countdown
            f.reading = nil
            f:SetWidth(260)
            local w = find(WAITING)
            if w then C.ShowWaiting(w) else hideWin(f) end
            return
        end
        if f.inviting then local _, zone = taleKey(); if zone then invitedOff[zone] = true end; f.inviting = nil end
        f.dismissed = true; f:Hide()
    end)
    f:Hide()
    -- closed any other way than by Chronicle itself (Escape, a controller's back button) counts like the X: it stays
    -- closed until you sit down again, instead of popping straight back up while you stand by the fire
    f:SetScript("OnHide", function(self)
        if self.byUs then return end
        if self.inviting then local _, zone = taleKey(); if zone then invitedOff[zone] = true end; self.inviting = nil end
        self.dismissed = true
    end)
    return f
end

-- not dragged anywhere: sit above the speaker window while it is up, so the two never cover each other
local hooked
local function place()
    if not win or ns.settings.campfirePos then return end
    local head = _G.ChronicleTalkingHead
    if head and not hooked then
        hooked = true
        head:HookScript("OnShow", place); head:HookScript("OnHide", place)
    end
    win:ClearAllPoints()
    if head and head:IsShown() then win:SetPoint("BOTTOM", head, "TOP", 0, 8)
    else win:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
end

local function fit()
    place()
    local buttons = win.story:IsShown()
    win:SetHeight(math.max(buttons and 92 or 56,
        win.title:GetStringHeight() + win.sub:GetStringHeight() + (buttons and 52 or 30)))
end

-- waiting for the minute to pass: the countdown, and a tale if there is one for this zone
local function showWaiting(a)
    win = win or create()
    if win.dismissed then return end -- closed: stays closed until you sit down again
    if win.reading then return end   -- reading a tale: leave the page as it is
    local key = taleKey()
    win.title:SetText(L["By the fire"])
    win.story:SetShown(key ~= nil)
    win.later:SetShown(key ~= nil)
    win.story:SetText(ns.Voice.Owner() == win.story and L["Stop"] or L["Tell me a story"])
    local left = math.max(0, math.floor((safe(a.expirationTime) or GetTime()) - GetTime() + 0.5))
    local text = (L["The camp's benefits in %d s"]):format(left)
    -- still enjoying an earlier camp: show what is active and for how long
    local old = find(BENEFITS)
    if old then
        local active = benefitText(old)
        local mins = math.floor(((safe(old.expirationTime) or GetTime()) - GetTime()) / 60 + 0.5)
        if active ~= "" then
            text = text .. "\n\n" .. (L["Active now (%d min left):"]):format(mins) .. "\n" .. active
        end
    end
    if #seenOrder > 0 then
        text = text .. "\n\n" .. L["At this camp:"] .. " " .. table.concat(seenOrder, ", ")
    else
        -- a quiet hint until the first object is found
        text = text .. "\n\n|cff8a8a8a" .. L["Hover over the camp objects to see them here."] .. "|r"
    end
    -- the tent's rested experience is once an hour
    local rest = find(RESTED)
    local restUntil = rest and safe(rest.expirationTime)
    if restUntil then
        text = text .. "\n\n" .. (L["Tent rest: again in %d min"]):format(math.floor((restUntil - GetTime()) / 60 + 0.5))
    end
    win.sub:SetText(text)
    fit()
    win:Show()
end

C.ShowWaiting = function(a) showWaiting(a) end

local function showBenefits(a)
    win = win or create()
    local text = benefitText(a)
    if text == "" then hideWin(win); return end
    win.title:SetText(L["Camp benefits"])
    win.reading = nil
    win:SetWidth(260)
    win.sub:SetText(text)
    -- a tale that is still being told keeps its Stop button
    local telling = ns.Voice.Owner() == win.story
    win.story:SetShown(telling); win.later:SetShown(false)
    fit()
    win:Show()
    win.hideAt = GetTime() + SHOW_BENEFITS
end

-- near a fire, not sitting: an invitation, only while this zone has a tale this character has not heard yet
local function showInvite()
    local key, zone = taleKey()
    if not key or invitedOff[zone] or (ns.char.tales and ns.char.tales[zone]) then
        if win and win.inviting then win.inviting = nil; hideWin(win) end
        return
    end
    win = win or create()
    if win.dismissed and not win.inviting then return end
    win.inviting = true
    win.dismissed = nil
    win.title:SetText(L["A campfire nearby"])
    win.sub:SetText((L["Sit down for a while, and hear a tale of %s."]):format(ns.zoneLocal(zone)))
    win.story:Hide(); win.later:Hide()
    win:SetWidth(260)
    fit()
    win:Show()
end

local function atFire() return find(NEARBY) or find(WAITING) end

-- the tooltip of a world object (not a unit) under the mouse: a camp object when it is one we know
local function noteHovered()
    if not GameTooltip:IsShown() or UnitExists("mouseover") then return end
    local line = _G.GameTooltipTextLeft1
    local name = line and line:GetText()
    if not name or (canaccessvalue and not canaccessvalue(name)) then return end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if seenHere[name] then return end
    for _, o in ipairs(OBJECTS) do
        if name == o then
            seenHere[name] = true
            seenOrder[#seenOrder + 1] = name
            return
        end
    end
end

local ticker = CreateFrame("Frame")
local wait = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - elapsed
    if wait > 0 then return end
    wait = 0.5
    if not (ns.char and ns.settings and ns.settings.campfire) then return end
    if InCombatLockdown() or UnitAffectingCombat("player") then return end
    if atFire() then noteHovered() end
    local w = find(WAITING)
    if w then
        -- a new countdown (sitting down again, also on a chair while the last one still ran) opens the window anew
        local exp = safe(w.expirationTime)
        local restarted = exp and lastExpires and math.abs(exp - lastExpires) > 2
        if not lastWaiting or restarted then
            if win then win.dismissed = nil; win.reading = nil; win.inviting = nil; win:SetWidth(260) end
        end
        lastExpires = exp or lastExpires
        lastWaiting = GetTime()
        showWaiting(w)
        return
    end
    -- the countdown just ended: show what the camp gave (once), then let the window go
    if lastWaiting and GetTime() - lastWaiting < 3 then
        local b = find(BENEFITS)
        -- only a freshly granted buff (an hour long, just started), not one left over from an earlier camp
        local dur, exp = b and safe(b.duration), b and safe(b.expirationTime)
        local fresh = dur and exp and dur > 0 and (exp - GetTime()) > dur - 10
        if fresh and not (win and win.dismissed) then showBenefits(b); lastWaiting = nil; return end
    elseif lastWaiting then
        lastWaiting = nil -- stood up before the minute was over
        if win and ns.Voice.Owner() ~= win.story then hideWin(win) end
    end
    if not lastWaiting and not find(NEARBY) and #seenOrder > 0 then seenHere, seenOrder = {}, {} end -- left the fire
    -- not sitting: invite when a fire is near, and drop the invitation when it is not
    if not lastWaiting and not (win and win.hideAt) then
        if find(NEARBY) then showInvite() elseif win and win.inviting then win.inviting = nil; hideWin(win) end
    end
    if win and win.hideAt and GetTime() > win.hideAt and ns.Voice.Owner() ~= win.story then
        win.hideAt = nil
        hideWin(win)
    end
end)

function C.OnVoiceChanged()
    if win and win:IsShown() and win.story:IsShown() then
        win.story:SetText(ns.Voice.Owner() == win.story and L["Stop"] or L["Tell me a story"])
    end
end

-- /lore campdebug: everything the camp auras carry, to see whether the game says more than the tooltip does
function C.Debug()
    local list = auras()
    ns.pr(("campdebug: %d buffs"):format(#list))
    for _, a in ipairs(list) do
        ns.pr(("  %s (%s)"):format(tostring(a.name), tostring(a.spellId)))
    end
    for _, a in ipairs(list) do
        local n = a.name
        if n == WAITING or n == BENEFITS or n == RESTED then
            ns.pr(('%s id=%s dur=%s source=%s'):format(tostring(n), tostring(a.spellId), tostring(a.duration), tostring(a.sourceUnit)))
            for k, v in pairs(a.raw or a) do
                if type(v) == 'table' then
                    local parts = {}
                    for i, x in pairs(v) do parts[#parts + 1] = tostring(i) .. '=' .. tostring(x) end
                    ns.pr(('  %s: %s'):format(tostring(k), table.concat(parts, ', ')))
                end
            end
        end
    end
end

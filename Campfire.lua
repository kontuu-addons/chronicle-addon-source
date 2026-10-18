-- Chronicle / Campfire: sit down by a camp fire (WoW: Forever's camping) and the narrator tells the zone's campfire
-- tale in the speaker window, once per character. Near a fire whose zone has a tale you haven't heard, a short note
-- says so. The countdown and the camp's benefits are the game's own buffs.
local _, ns = ...
local L = ns.L
local C = {}
ns.Campfire = C

local SITTING = { 1289723, 1229739 } -- "Welcoming Campfire", while you sit and wait for the camp's benefits
local NEARBY = { 1283391 }            -- "Campfire Nearby", while you're close to a camp fire
local DELAY = 3 -- seconds seated before the tale starts, so a quick sit-down doesn't start a story
local HINT_AGAIN = 300 -- shortcut: one fire can't be told from another, so the note waits 5 min before showing again

local function has(ids, name)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for _, id in ipairs(get and ids or {}) do
        local ok, a = pcall(get, id)
        if ok and a ~= nil then return true end
    end
    -- shortcut: English clients only, for when the beta changes a spell ID; add the new ID above then
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not byName then return false end
    local ok, a = pcall(byName, "player", name, "HELPFUL")
    return ok and a ~= nil
end

local function sitting() return has(SITTING, "Welcoming Campfire") end
local function nearby() return has(NEARBY, "Campfire Nearby") end

-- the tale of the zone you're in, when there is one this character hasn't heard yet
local function unheardTale()
    local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    local key = zone and "tale:" .. zone
    if not key or (ns.char.tales and ns.char.tales[zone]) or not ns.Voice.Get(key) then return nil end
    return key, zone
end

local seated, pending, near, hint, hintAgain

local function tell()
    pending = nil
    if not (seated and ns.settings.campfire) or ns.settings.journalOnly then return end
    if InCombatLockdown() or ns.Voice.Paused() then return end -- paused: the tale waits for the next sit-down
    local key, zone = unheardTale()
    if not key then return end
    ns.Voice.Enqueue(key) -- after whoever is talking now; Voice marks it heard once it starts
end

-- the note, in the game's zone name style: above the zone name, fading in and out on its own
local function showHint(zone)
    if not hint then
        hint = CreateFrame("Frame", nil, UIParent)
        hint:SetSize(512, 80); hint:SetFrameStrata("LOW")
        -- right above the game's zone name, so the two never cover each other
        if _G.ZoneTextFrame then hint:SetPoint("BOTTOM", _G.ZoneTextFrame, "TOP", 0, -30) else hint:SetPoint("TOP", 0, -20) end
        hint.title = hint:CreateFontString(nil, "ARTWORK", "SubZoneTextFont")
        hint.title:SetPoint("TOP"); hint.title:SetTextColor(1, 0.82, 0)
        hint.sub = hint:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
        hint.sub:SetPoint("TOP", hint.title, "BOTTOM", 0, -6)
        hint.fade = hint:CreateAnimationGroup()
        hint.fade:SetToFinalAlpha(true)
        local fadeIn = hint.fade:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.6); fadeIn:SetOrder(1)
        local fadeOut = hint.fade:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetStartDelay(4); fadeOut:SetDuration(1.5); fadeOut:SetOrder(2)
        hint.fade:SetScript("OnFinished", function() hint:Hide() end)
    end
    hint.title:SetText(L["A campfire nearby"])
    hint.sub:SetText((L["Sit down for a while, and hear a tale of %s."]):format(ns.zoneLocal(zone)))
    hint.fade:Stop(); hint:SetAlpha(0); hint:Show(); hint.fade:Play()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" or not (ns.char and ns.settings and ns.settings.campfire) or InCombatLockdown() then return end
    local now = sitting()
    if now and not seated and not pending then
        pending = true
        C_Timer.After(DELAY, tell)
    end
    seated = now
    if seated and hint and hint:IsShown() then hint:Hide() end -- sat down: the note did its job
    local close = nearby()
    if close and not near and not seated and GetTime() > (hintAgain or 0) and not ns.settings.journalOnly then
        local _, zone = unheardTale()
        if zone then
            hintAgain = GetTime() + HINT_AGAIN
            showHint(zone)
        end
    end
    near = close
end)
table.insert(ns.onLogin, function() ev:RegisterEvent("UNIT_AURA") end)

-- /lore campdebug: every buff by name and spell ID, to find the camp's new IDs when the beta changes them
function C.Debug()
    local i = 1
    while C_UnitAuras and C_UnitAuras.GetAuraDataByIndex do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not (ok and a) then break end
        ns.pr(("  %s (%s)"):format(tostring(a.name), tostring(a.spellId)))
        i = i + 1
    end
    ns.pr(("campdebug: %d buffs, near a fire: %s, sitting by it: %s"):format(i - 1, tostring(nearby()), tostring(sitting())))
end

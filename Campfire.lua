-- Chronicle / Campfire: sit down by a camp fire (WoW: Forever's camping) and the narrator tells the zone's campfire
-- tale in the speaker window, once per character. The countdown and the camp's benefits are the game's own buffs.
local _, ns = ...
local C = {}
ns.Campfire = C

-- "Welcoming Campfire", the buff while you sit and wait for the camp's benefits (the beta uses both IDs)
local SITTING = { 1289723, 1229739 }
local DELAY = 3 -- seconds seated before the tale starts, so a quick sit-down doesn't start a story

local function sitting()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for _, id in ipairs(get and SITTING or {}) do
        local ok, a = pcall(get, id)
        if ok and a ~= nil then return true end
    end
    -- shortcut: English clients only, for when the beta changes the spell ID; add the new ID to SITTING then
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not byName then return false end
    local ok, a = pcall(byName, "player", "Welcoming Campfire", "HELPFUL")
    return ok and a ~= nil
end

local seated, pending

local function tell()
    pending = nil
    if not (seated and ns.settings.campfire) or ns.settings.journalOnly then return end
    if InCombatLockdown() or ns.Voice.Paused() then return end -- paused: the tale waits for the next sit-down
    local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    local key = zone and "tale:" .. zone
    if not key or (ns.char.tales and ns.char.tales[zone]) or not ns.Voice.Get(key) then return end
    ns.Voice.Enqueue(key) -- after whoever is talking now; Voice marks it heard once it starts
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
    ns.pr(("campdebug: %d buffs, sitting by a fire: %s"):format(i - 1, tostring(sitting())))
end

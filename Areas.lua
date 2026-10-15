-- Chronicle / Areas: the first time a character walks into a named place inside a zone (Bloodhoof Village, Red Rocks),
-- the narrator says a line or two about it (thanks Lukey_Q). Only when nobody else is talking; a place passed while
-- someone talks gets its turn the next time. Places without a line yet are kept for /lore share.
local _, ns = ...

local function onArea()
    if not (ns.char and ns.settings and ns.settings.areaIntros) or ns.settings.journalOnly then return end
    if InCombatLockdown() or IsInInstance() then return end
    local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    local place = ns.clean(GetSubZoneText())
    if not (zone and zone ~= "" and place and place ~= "" and place ~= zone) then return end
    local key = "area:" .. zone .. ":" .. place
    ns.char.areaSeen = ns.char.areaSeen or {}
    if ns.char.areaSeen[key] then return end
    if not ns.Voice.Get(key) then
        if ns.english then -- no line yet: the place's name and zone go out with /lore share
            ns.db.areas = ns.db.areas or {}
            ns.db.areas[zone] = ns.db.areas[zone] or {}
            ns.db.areas[zone][place] = true
        end
        return
    end
    if ns.Voice.IsPlaying() then return end
    ns.char.areaSeen[key] = time()
    ns.Voice.Play(key)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() C_Timer.After(1.5, onArea) end)
table.insert(ns.onLogin, function()
    ev:RegisterEvent("ZONE_CHANGED")
    ev:RegisterEvent("ZONE_CHANGED_INDOORS")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
end)

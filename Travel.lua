-- Chronicle / Travel: the quiet moments between the action.
-- On a flight: the story so far in the zone you're flying to (or its welcome), offered as a toast.
-- Running back as a ghost, or casting a fishing line: now and then the narrator says a short line. All can be turned
-- off in the options.
local _, ns = ...
local T = {}
ns.Travel = T

local GHOST_COOLDOWN = 15 * 60 -- seconds between ghost lines
local GHOST_CHANCE = 0.6       -- not every death
local FISH_COOLDOWN = 15 * 60  -- seconds between fishing lines
local FISH_CHANCE = 1 / 3      -- not every cast
local FISHING_ICON = 136245    -- Trade_Fishing: the same in every client language, and for every rank of Fishing
local destination              -- the flight node picked on the taxi map

-- "Sentinel Hill, Westfall" -> "Westfall"; "Stormwind, Elwynn" -> "Stormwind City". Node names are written in the
-- client's language; ns.zoneEN turns a local zone name into the English one the story data uses.
local function nodeZone(name)
    local l = ns.Lore
    if not (name and l) then return nil end
    local known = {}
    for _, z in ipairs(l.zoneNames or {}) do known[z] = true end
    for z in pairs(l.zoneIntro or {}) do known[z] = true end
    for part in name:gmatch("[^,]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        local z = ns.zoneEN(part) or part
        if known[z] then return z end
        for k in pairs(known) do
            if k:sub(1, #z) == z then return k end -- "Elwynn" -> "Elwynn Forest", "Stranglethorn" -> "Stranglethorn Vale"
        end
    end
end

hooksecurefunc("TakeTaxiNode", function(slot)
    local ok, name = pcall(TaxiNodeName, slot)
    destination = ok and ns.clean(name) or nil
end)

local function onFlight()
    if not (ns.settings.flightStory and destination and UnitOnTaxi("player")) then return end
    local zone = nodeZone(destination)
    destination = nil
    if zone and ns.Reminder then ns.Reminder.ShowFlight(zone) end
end

local function onGhost()
    if not (ns.settings.ghostQuips and not ns.settings.journalOnly and UnitIsGhost("player")) then return end
    local lines = ns.Lore and ns.Lore.ghost
    if not lines or #lines == 0 or ns.Voice.IsPlaying() or ns.Voice.Paused() then return end
    ns.char.ghost = ns.char.ghost or { at = 0, recent = {} }
    local g = ns.char.ghost
    if time() - (g.at or 0) < GHOST_COOLDOWN or math.random() > GHOST_CHANCE then return end
    local recent = {}
    for _, i in ipairs(g.recent) do recent[i] = true end
    local pool = {}
    for i = 1, #lines do
        if not recent[i] and ns.Voice.Get("ghost:" .. i) then pool[#pool + 1] = i end
    end
    if #pool == 0 then return end
    local i = pool[math.random(#pool)]
    g.at = time()
    table.insert(g.recent, i)
    while #g.recent > math.min(8, #lines - 1) do table.remove(g.recent, 1) end
    ns.Voice.Play("ghost:" .. i)
end

-- the channel just started is Fishing (any rank): told by its icon, which no client language changes
local function isFishing(spellID)
    if type(spellID) ~= "number" or (canaccessvalue and not canaccessvalue(spellID)) then return false end
    local ok, icon
    if C_Spell and C_Spell.GetSpellTexture then
        ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
    elseif GetSpellInfo then
        ok, icon = pcall(function() return select(3, GetSpellInfo(spellID)) end)
    end
    if not ok or icon == nil or (canaccessvalue and not canaccessvalue(icon)) then return false end
    return icon == FISHING_ICON or (type(icon) == "string" and icon:lower():find("trade_fishing", 1, true) ~= nil)
end

local function onFishing()
    if not (ns.settings.fishingLines and not ns.settings.journalOnly) then return end
    local lines = ns.Lore and ns.Lore.fishing
    if not lines or #lines == 0 or ns.Voice.IsPlaying() or ns.Voice.Paused() then return end
    ns.char.fishing = ns.char.fishing or { at = 0, recent = {} }
    local f = ns.char.fishing
    if time() - (f.at or 0) < FISH_COOLDOWN or math.random() > FISH_CHANCE then return end
    local recent = {}
    for _, i in ipairs(f.recent) do recent[i] = true end
    local pool = {}
    for i = 1, #lines do
        if not recent[i] and ns.Voice.Get("fish:" .. i) then pool[#pool + 1] = i end
    end
    if #pool == 0 then return end
    local i = pool[math.random(#pool)]
    f.at = time()
    table.insert(f.recent, i)
    while #f.recent > math.min(10, #lines - 1) do table.remove(f.recent, 1) end
    ns.Voice.Play("fish:" .. i)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_CONTROL_LOST" then
        C_Timer.After(1.5, onFlight) -- UnitOnTaxi turns true a moment after take-off
    elseif event == "PLAYER_ALIVE" then
        C_Timer.After(8, onGhost) -- fires when you release your spirit; a few seconds in, once you are on your way back
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        if unit == "player" and isFishing(spellID) then C_Timer.After(2, onFishing) end -- once the bobber has landed
    end
end)
table.insert(ns.onLogin, function()
    ev:RegisterEvent("PLAYER_CONTROL_LOST")
    ev:RegisterEvent("PLAYER_ALIVE")
    if ev.RegisterUnitEvent then
        pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_START", "player")
    else
        pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_CHANNEL_START")
    end
end)

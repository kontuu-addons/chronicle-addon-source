-- Chronicle / Travel: the quiet moments between the action.
-- On a flight: the story so far in the zone you're flying to (or its welcome), offered as a toast.
-- Running back as a ghost: now and then the narrator says a short line. Both can be turned off in the options.
local _, ns = ...
local T = {}
ns.Travel = T

local GHOST_COOLDOWN = 15 * 60 -- seconds between ghost lines
local GHOST_CHANCE = 0.6       -- not every death
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
    if not lines or #lines == 0 or ns.Voice.IsPlaying() then return end
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

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        C_Timer.After(1.5, onFlight) -- UnitOnTaxi turns true a moment after take-off
    elseif event == "PLAYER_ALIVE" then
        C_Timer.After(8, onGhost) -- fires when you release your spirit; a few seconds in, once you are on your way back
    end
end)
table.insert(ns.onLogin, function()
    ev:RegisterEvent("PLAYER_CONTROL_LOST")
    ev:RegisterEvent("PLAYER_ALIVE")
end)

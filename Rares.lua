-- Chronicle / Rares: the first time this character slays one of the famous rares that have a real story (Ghost
-- Howl, Varo'then's Ghost, Duggan Wildhammer...), the narrator tells it once the fight is over. Once per character;
-- the zone's page in the journal keeps it to hear again. Rares in the open world fire no boss event, so the kill is
-- seen from your target lying dead when the fight ends (and not someone else's kill), or from looting the body.
local _, ns = ...
local R = {}
ns.Rares = R

local pending -- slain while still fighting something else: told when the fight is over

-- "Creature-0-1234-0-12-3056-0000A1B2C3" -> 3056
local function npcID(guid)
    if type(guid) ~= "string" or (canaccessvalue and not canaccessvalue(guid)) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end
R.NpcID = npcID

local function fighting() return InCombatLockdown() or UnitAffectingCombat("player") end

local function tell(key)
    if fighting() then pending = key; return end
    ns.Voice.Enqueue(key)
end

-- a famous rare is dead and this character had a part in it
function R.Slain(id)
    local rare = id and ns.Lore and ns.Lore.rares and ns.Lore.rares[id]
    if not rare or not ns.char then return end
    ns.char.rares = ns.char.rares or {}
    if ns.char.rares[id] then return end -- once per character
    ns.char.rares[id] = time()
    if not ns.settings.rareLines or ns.settings.journalOnly then return end
    local key = "rare:" .. id
    if ns.Voice.Get(key) then tell(key) end
end

-- the unit lies dead, and it was not someone else's kill
local function checkDead(unit)
    local ok, there = pcall(UnitExists, unit)
    if not (ok and there) then return end
    local okDead, dead = pcall(UnitIsDead, unit)
    if not (okDead and dead == true) then return end
    if UnitIsTapDenied then
        local okTap, denied = pcall(UnitIsTapDenied, unit)
        if okTap and denied == true then return end
    end
    local okGuid, guid = pcall(UnitGUID, unit)
    if okGuid then R.Slain(npcID(guid)) end
end

local function onLoot()
    if not (GetNumLootItems and GetLootSourceInfo) then return end
    local okN, n = pcall(GetNumLootItems)
    for i = 1, (okN and type(n) == "number" and n or 0) do
        local ok, guid = pcall(GetLootSourceInfo, i)
        if ok then R.Slain(npcID(guid)) end
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        checkDead("target")
        if pending then
            local key = pending
            pending = nil
            C_Timer.After(1, function() ns.Voice.Enqueue(key) end) -- a breath after the fight
        end
    elseif event == "LOOT_OPENED" then
        onLoot()
        checkDead("target")
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not fighting() then checkDead("target") end -- clicking the body after the fight
    end
end)
table.insert(ns.onLogin, function()
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "LOOT_OPENED", "PLAYER_TARGET_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
end)

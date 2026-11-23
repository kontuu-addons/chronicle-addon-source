-- Chronicle: Locale
-- Interface text in the player's language, and zone names that work on every client.
local _, ns = ...

-- ---------------------------------------------------------------- zones
-- The story data is keyed by English zone names, but the game reports zones in the client's language
-- ("Forêt d'Elwynn"). Each zone has the same map ID in every language, so the names are matched through it.
local ZONES = {
    [1411] = "Durotar", [1412] = "Mulgore", [1413] = "The Barrens", [1416] = "Alterac Mountains", [1417] = "Arathi Highlands",
    [1418] = "Badlands", [1419] = "Blasted Lands", [1420] = "Tirisfal Glades", [1421] = "Silverpine Forest", [1422] = "Western Plaguelands",
    [1423] = "Eastern Plaguelands", [1424] = "Hillsbrad Foothills", [1425] = "The Hinterlands", [1426] = "Dun Morogh", [1427] = "Searing Gorge",
    [1428] = "Burning Steppes", [1429] = "Elwynn Forest", [1430] = "Deadwind Pass", [1431] = "Duskwood", [1432] = "Loch Modan",
    [1433] = "Redridge Mountains", [1434] = "Stranglethorn Vale", [1435] = "Swamp of Sorrows", [1436] = "Westfall", [1437] = "Wetlands",
    [1438] = "Teldrassil", [1439] = "Darkshore", [1440] = "Ashenvale", [1441] = "Thousand Needles", [1442] = "Stonetalon Mountains",
    [1443] = "Desolace", [1444] = "Feralas", [1445] = "Dustwallow Marsh", [1446] = "Tanaris", [1447] = "Azshara",
    [1448] = "Felwood", [1449] = "Un'Goro Crater", [1450] = "Moonglade", [1451] = "Silithus", [1452] = "Winterspring",
    [1453] = "Stormwind City", [1454] = "Orgrimmar", [1455] = "Ironforge", [1456] = "Thunder Bluff", [1457] = "Darnassus",
    [1458] = "Undercity", [2482] = "Mount Hyjal", [2521] = "Zephras Isle", [2548] = "Riverglades", [2652] = "Shen'dralas",
    [2665] = "Zephras Isle",
}
-- dungeons, raids and battlegrounds by instance ID (GetRealZoneText(id) gives their name in the client's language)
local INSTANCES = {
    [389] = "Ragefire Chasm", [43] = "Wailing Caverns", [36] = "The Deadmines", [33] = "Shadowfang Keep",
    [48] = "Blackfathom Deeps", [34] = "The Stockade", [90] = "Gnomeregan", [47] = "Razorfen Kraul",
    [189] = "Scarlet Monastery", [129] = "Razorfen Downs", [70] = "Uldaman", [209] = "Zul'Farrak", [349] = "Maraudon",
    [109] = "Sunken Temple", [230] = "Blackrock Depths", [229] = "Blackrock Spire", [429] = "Dire Maul",
    [289] = "Scholomance", [329] = "Stratholme", [409] = "Molten Core", [249] = "Onyxia's Lair", [469] = "Blackwing Lair",
    [309] = "Zul'Gurub", [509] = "Ruins of Ahn'Qiraj", [531] = "Ahn'Qiraj", [533] = "Naxxramas", [369] = "Deeprun Tram",
    [30] = "Alterac Valley", [489] = "Warsong Gulch", [529] = "Arathi Basin",
}

local LOCALE = GetLocale and GetLocale() or "enUS"
local ENGLISH = (LOCALE == "enUS" or LOCALE == "enGB")
local toEN, toLocal

local function build()
    toEN, toLocal = {}, {}
    if not (C_Map and C_Map.GetMapInfo) then return end
    for id, en in pairs(ZONES) do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            toEN[info.name] = en
            toLocal[en] = toLocal[en] or info.name
        end
    end
    for id, en in pairs(INSTANCES) do
        local ok, name = pcall(GetRealZoneText, id)
        if ok and name and name ~= "" then
            toEN[name] = en
            toLocal[en] = toLocal[en] or name
        end
    end
    if next(toEN) == nil then toEN, toLocal = nil, nil end -- map data not ready yet: try again next time
end

-- the English zone name for a map ID, the same on every client (nil for maps that aren't one of the zones)
function ns.zoneOfMap(map)
    return map and ZONES[map]
end

-- true for a zone, dungeon or raid name as the story data spells it
local KNOWN = {}
for _, t in ipairs({ ZONES, INSTANCES }) do for _, en in pairs(t) do KNOWN[en] = true end end
function ns.zoneKnown(name)
    return KNOWN[name] == true
end

-- the English name the story data uses, for a zone name the game gave us
function ns.zoneEN(name)
    if ENGLISH or not name or name == "" then return name end
    if not toEN then build() end
    return toEN and toEN[name] or name
end

-- the zone's name in the player's language, for display (journal groups that aren't zones come from the translations)
function ns.zoneLocal(name)
    if ENGLISH or not name or name == "" then return name end
    if not toLocal then build() end
    return toLocal and toLocal[name] or rawget(ns.L, name) or name
end

-- ---------------------------------------------------------------- interface text
-- L["English text"] returns the translation for this client, or the English text itself.
-- The translations live in Locales\<locale>.lua, which only fill in L on their own client.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.locale = LOCALE

-- A date for display. The game's date() has English month names only, so other languages get the numeric form.
function ns.Date(t)
    if ENGLISH then return date("%d %b %Y", t) end
    return date(LOCALE == "deDE" and "%d.%m.%Y" or "%d/%m/%Y", t)
end

-- ---------------------------------------------------------------- the story texts in the player's language
-- Recaps, chapters, bios, the Bestiary and the rest in Spanish, French or German come in an addon of their own per
-- language (ForeverChronicle_esES, _frFR, _deDE), loaded only on that client; Latin American Spanish takes the Spanish
-- one (thanks david for asking). Its texts are laid over the English ones they translate, which stay wherever nothing
-- is translated yet. Keys (zones, ids, names) never change: only the texts shown.
local LANGUAGE = { esES = "esES", esMX = "esES", frFR = "frFR", deDE = "deDE" }

function ns.LoadLanguage()
    local lang = LANGUAGE[LOCALE]
    if not lang or ns.language then return end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "ForeverChronicle_" .. lang) end
end

-- one table's texts over the English: only keys the English has, text for text, and only the given fields
local function over(dst, src, fields)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "string" and type(dst[k]) == "string" and (not fields or fields[k]) then dst[k] = v end
    end
end
local TEXTS, RARE, CHARACTER = { title = true, intro = true, text = true }, { name = true, text = true }, { t = true, b = true }

function ns.ApplyLanguage(locale, t)
    local lore = ns.Lore
    if LANGUAGE[LOCALE] ~= locale or type(lore) ~= "table" or type(t) ~= "table" then return false end
    for _, key in ipairs({ "zoneIntro", "epilogue", "history", "campfire", "dungeonIntro", "levels", "ghost", "fishing",
                           "titles" }) do
        over(lore[key], t[key])
    end
    for key, list in pairs(t.campfireMore or {}) do over((lore.campfireMore or {})[key], list) end
    for key, ends in pairs(t.dungeonEnd or {}) do over((lore.dungeonEnd or {})[key], ends) end
    for id, s in pairs(t.quests or {}) do
        local q = lore.quests and lore.quests[id]
        if q and type(q.summary) == "string" and type(s) == "string" then q.summary = s end
    end
    for _, name in ipairs({ "arcs", "legends", "peoples" }) do
        local src = t[name]
        for _, e in ipairs(src and lore[name] or {}) do over(e, src[e.id], TEXTS) end
    end
    for name, e in pairs(t.npcs or {}) do over((lore.npcs or {})[name], e, CHARACTER) end
    if type(t.races) == "table" then
        for _, e in pairs(lore.npcs or {}) do
            if type(e) == "table" and e.r and t.races[e.r] then e.r = t.races[e.r] end
        end
    end
    for id, r in pairs(t.rares or {}) do over((lore.rares or {})[id], r, RARE) end
    local groups = lore.bestiary and lore.bestiary.groups
    for id, g in pairs(t.bestiary or {}) do
        local dst = groups and groups[id]
        if type(dst) == "table" and type(g) == "table" then
            over(dst, g, { name = true })
            over(dst.text, g.text)
        end
    end
    ns.language = locale
    return true
end

-- Buttons are sized for the English labels; in other languages they grow to fit their text.
function ns.FitButton(b)
    if ENGLISH or not b then return b end
    local base
    hooksecurefunc(b, "SetText", function(self)
        base = base or self:GetWidth()
        local fs = self:GetFontString()
        if fs then self:SetWidth(math.max(base, fs:GetStringWidth() + 20)) end
    end)
    return b
end

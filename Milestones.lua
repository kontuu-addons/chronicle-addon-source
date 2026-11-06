-- Chronicle / Milestones: every 10th level, a short word from the narrator and the zones where new stories open up
-- for your level and faction (ones you haven't started). Offered as a toast; nothing plays unless you click Listen.
local _, ns = ...
local L = ns.L

-- zone levels, who quests there (A, H or both) and the land (E the Eastern Kingdoms, K Kalimdor), as in the original
-- game
local ZONES = {
    { "Westfall", 10, 20, "A", "E" }, { "Loch Modan", 10, 20, "A", "E" }, { "Darkshore", 10, 20, "A", "K" },
    { "The Barrens", 10, 25, "H", "K" }, { "Silverpine Forest", 10, 20, "H", "E" },
    { "Redridge Mountains", 15, 25, "A", "E" }, { "Stonetalon Mountains", 15, 27, "AH", "K" },
    { "Duskwood", 18, 30, "A", "E" }, { "Ashenvale", 18, 30, "AH", "K" }, { "Wetlands", 20, 30, "A", "E" },
    { "Hillsbrad Foothills", 20, 30, "AH", "E" }, { "Thousand Needles", 25, 35, "AH", "K" },
    { "Arathi Highlands", 30, 40, "AH", "E" }, { "Alterac Mountains", 30, 40, "AH", "E" },
    { "Desolace", 30, 40, "AH", "K" }, { "Stranglethorn Vale", 30, 45, "AH", "E" }, { "Badlands", 35, 45, "AH", "E" },
    { "Swamp of Sorrows", 35, 45, "AH", "E" }, { "Dustwallow Marsh", 35, 45, "AH", "K" },
    { "Feralas", 40, 50, "AH", "K" }, { "Tanaris", 40, 50, "AH", "K" }, { "The Hinterlands", 40, 50, "AH", "E" },
    { "Searing Gorge", 43, 50, "AH", "E" }, { "Azshara", 45, 55, "AH", "K" }, { "Blasted Lands", 45, 55, "AH", "E" },
    { "Un'Goro Crater", 48, 55, "AH", "K" }, { "Felwood", 48, 55, "AH", "K" },
    { "Burning Steppes", 50, 58, "AH", "E" }, { "Western Plaguelands", 51, 58, "AH", "E" },
    { "Winterspring", 55, 60, "AH", "K" }, { "Eastern Plaguelands", 53, 60, "AH", "E" }, { "Silithus", 55, 60, "AH", "K" },
}

-- the land a race starts in: its zones come first (a Forsaken was offered the Barrens before Silverpine Forest)
local HOME = { Human = "E", Dwarf = "E", Gnome = "E", Scourge = "E", NightElf = "K", Orc = "K", Troll = "K", Tauren = "K" }
-- races with a narrator's line of their own where the side's doesn't fit them (the Horde's sends you to the Barrens
-- at 10, to Ashenvale at 20; the Forsaken's road runs through Silverpine and Hillsbrad)
local OWN = { Scourge = "Forsaken" }

-- zones where this character has already done a quest
local function startedZones()
    local seen = {}
    for _, e in ipairs(ns.char.journal or {}) do
        local q = ns.db.quests[e.id] or {}
        local z = q.zone or ns.LoreZone(e.id) or e.zone
        if z then seen[z] = true end
    end
    return seen
end

local function suggestions(level, side, home)
    local seen, near, far = startedZones(), {}, {}
    for _, z in ipairs(ZONES) do
        local name, low, high, who, land = z[1], z[2], z[3], z[4], z[5]
        if who:find(side, 1, true) and low <= level + 2 and high > level and not seen[name] then
            local list = (not home or land == home) and near or far
            list[#list + 1] = ns.zoneLocal(name)
        end
    end
    for _, name in ipairs(far) do near[#near + 1] = name end
    return { unpack(near, 1, math.min(3, #near)) }
end

local function onLevel(level)
    if not ns.settings.levelMilestones or level % 10 ~= 0 then return end
    local faction = UnitFactionGroup("player")
    local side = faction == "Horde" and "H" or "A"
    local _, race = UnitRace("player")
    race = ns.clean(race)
    local key = ("lvl:%d|%s"):format(level, faction == "Horde" and "Horde" or "Alliance")
    local own = race and OWN[race] and ("lvl:%d|%s"):format(level, OWN[race])
    -- their own line when it has a voice (or neither has one: Journal only), so old voice packs keep the side's
    if own and ns.Voice.Subtitle(own) and (ns.Voice.Get(own) or not ns.Voice.Get(key)) then key = own end
    local line = ns.Voice.Subtitle(key)
    local zones = level < 60 and suggestions(level, side, race and HOME[race]) or {}
    local text = #zones > 0 and (L["New stories at your level: %s"]):format(table.concat(zones, ", ")) or line
    if not text or not ns.Reminder then return end
    ns.Reminder.ShowStory((L["Level %d"]):format(level), text, { key }, nil, nil, "levelMilestones")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, level) C_Timer.After(3, function() onLevel(tonumber(level) or 0) end) end)
table.insert(ns.onLogin, function() ev:RegisterEvent("PLAYER_LEVEL_UP") end)

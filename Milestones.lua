-- Chronicle / Milestones: every 10th level, a short word from the narrator and the zones where new stories open up
-- for your level and faction (ones you haven't started). Offered as a toast; nothing plays unless you click Listen.
local _, ns = ...
local L = ns.L

-- zone levels and who quests there (A, H or both), as in the original game
local ZONES = {
    { "Westfall", 10, 20, "A" }, { "Loch Modan", 10, 20, "A" }, { "Darkshore", 10, 20, "A" },
    { "The Barrens", 10, 25, "H" }, { "Silverpine Forest", 10, 20, "H" },
    { "Redridge Mountains", 15, 25, "A" }, { "Stonetalon Mountains", 15, 27, "AH" },
    { "Duskwood", 18, 30, "A" }, { "Ashenvale", 18, 30, "AH" }, { "Wetlands", 20, 30, "A" },
    { "Hillsbrad Foothills", 20, 30, "AH" }, { "Thousand Needles", 25, 35, "AH" },
    { "Arathi Highlands", 30, 40, "AH" }, { "Alterac Mountains", 30, 40, "AH" }, { "Desolace", 30, 40, "AH" },
    { "Stranglethorn Vale", 30, 45, "AH" }, { "Badlands", 35, 45, "AH" }, { "Swamp of Sorrows", 35, 45, "AH" },
    { "Dustwallow Marsh", 35, 45, "AH" }, { "Feralas", 40, 50, "AH" }, { "Tanaris", 40, 50, "AH" },
    { "The Hinterlands", 40, 50, "AH" }, { "Searing Gorge", 43, 50, "AH" }, { "Azshara", 45, 55, "AH" },
    { "Blasted Lands", 45, 55, "AH" }, { "Un'Goro Crater", 48, 55, "AH" }, { "Felwood", 48, 55, "AH" },
    { "Burning Steppes", 50, 58, "AH" }, { "Western Plaguelands", 51, 58, "AH" }, { "Winterspring", 55, 60, "AH" },
    { "Eastern Plaguelands", 53, 60, "AH" }, { "Silithus", 55, 60, "AH" },
}

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

local function suggestions(level, side)
    local seen, out = startedZones(), {}
    for _, z in ipairs(ZONES) do
        local name, low, high, who = z[1], z[2], z[3], z[4]
        if who:find(side, 1, true) and low <= level + 2 and high > level and not seen[name] then
            out[#out + 1] = ns.zoneLocal(name)
            if #out >= 3 then break end
        end
    end
    return out
end

local function onLevel(level)
    if not ns.settings.levelMilestones or level % 10 ~= 0 then return end
    local faction = UnitFactionGroup("player")
    local side = faction == "Horde" and "H" or "A"
    local key = ("lvl:%d|%s"):format(level, faction == "Horde" and "Horde" or "Alliance")
    local line = ns.Voice.Subtitle(key)
    local zones = level < 60 and suggestions(level, side) or {}
    local text = #zones > 0 and (L["New stories at your level: %s"]):format(table.concat(zones, ", ")) or line
    if not text or not ns.Reminder then return end
    ns.Reminder.ShowStory((L["Level %d"]):format(level), text, { key })
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, level) C_Timer.After(3, function() onLevel(tonumber(level) or 0) end) end)
table.insert(ns.onLogin, function() ev:RegisterEvent("PLAYER_LEVEL_UP") end)

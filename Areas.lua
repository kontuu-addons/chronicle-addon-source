-- Chronicle / Areas: the first time a character walks into a named place inside a zone (Bloodhoof Village, Red Rocks),
-- the narrator says a line or two about it (thanks Lukey_Q). Only when nobody else is talking; a place passed while
-- someone talks gets its turn the next time. Places without a line yet are kept for /lore share.
local _, ns = ...

-- WoW: Forever renamed a few places since their line was written under the old name: the game's name -> ours (thanks
-- AstroCat: Crusader's Outpost in Tirisfal never told its line, so the land's Places could never be complete)
local RENAMED = { ["Tirisfal Glades:Crusader's Outpost"] = "Crusader Outpost" }

-- The land you're in as the map has it, walked up to the zone.
local function mapZone()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local id = C_Map.GetBestMapForUnit("player")
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 8 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == ZONE then return info.name end
        id = info.parentMapID
    end
end

-- Where you are: the zone and the named place in it. A few of WoW: Forever's buildings are named places the game calls
-- a zone of their own, with no subzone: inside Crusader's Outpost the zone is "Crusader's Outpost", only the minimap
-- says where you are, and only its name changes on the way in (thanks AstroCat, who found it in the game; the name is
-- the building's, WMOAreaTable, not a subzone's). Then the land comes from the map, the place from the minimap.
local function here()
    local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    local place = ns.clean(GetSubZoneText())
    if place == "" then
        local land = mapZone()
        land = land and ns.zoneEN(ns.clean(land))
        if land and land ~= "" and land ~= zone then
            local mini = ns.clean(GetMinimapZoneText and GetMinimapZoneText() or "")
            place = mini ~= "" and mini or ns.clean(GetRealZoneText())
            zone = land
        end
    end
    return zone, place
end

local function onArea()
    if not (ns.char and ns.settings) or ns.settings.journalOnly then return end
    -- on a flight the places only pass below: they wait until you go there yourself (thanks tranced93)
    if InCombatLockdown() or IsInInstance() or UnitOnTaxi("player") then return end
    local zone, place = here()
    if not (zone and zone ~= "" and place and place ~= "" and place ~= zone) then return end
    place = RENAMED[zone .. ":" .. place] or place
    local key = "area:" .. zone .. ":" .. place
    if not ns.Voice.Get(key) and place:find("'s ", 1, true) then -- renamed with a possessive, as that one was
        local plain = "area:" .. zone .. ":" .. (place:gsub("'s ", " "))
        if ns.Voice.Get(plain) then key = plain end
    end
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
    -- with the place intros off (another addon tells the places, AstroCat), the place still goes into the journal's
    -- Places, quietly, to hear from there
    if not ns.settings.areaIntros then ns.char.areaSeen[key] = time() return end
    if ns.Voice.IsPlaying() or ns.Voice.Paused() then return end
    ns.char.areaSeen[key] = time()
    ns.Voice.Play(key)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() C_Timer.After(1.5, function() ns.AfterCutscene(onArea) end) end)
table.insert(ns.onLogin, function()
    ev:RegisterEvent("ZONE_CHANGED")
    ev:RegisterEvent("ZONE_CHANGED_INDOORS")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("PLAYER_CONTROL_GAINED") -- landing: the place you land in is yours now
    pcall(ev.RegisterEvent, ev, "MINIMAP_ZONE_CHANGED") -- walking into such a building changes only the minimap's name
end)

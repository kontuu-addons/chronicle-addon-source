-- Chronicle / Speech: NPCs saying things out loud in the world (speech bubbles, yells, whispers).
-- Only plays when nothing else is talking, and the same line from the same NPC waits a while before repeating.
-- Lines nobody has voiced yet (new NPCs) are recorded for /lore share.
local _, ns = ...
local S = {}
ns.Speech = S

local REPEAT_AFTER = 120 -- seconds before the same line may play again
local lastPlayed = {}

local function norm(s)
    return " " .. s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%a]+", " ") .. " "
end

function S.Key(speaker, text)
    local list = ns.Lore and ns.Lore.speech and ns.Lore.speech[speaker]
    if not list then return nil end
    local shown = norm(text)
    for _, item in ipairs(list) do
        if shown:find(" " .. item[2] .. " ", 1, true) then return item[1] end
    end
end

local function record(speaker, text)
    ns.db.speech = ns.db.speech or {}
    if not ns.db.speech[speaker] then
        local n = 0
        for _ in pairs(ns.db.speech) do n = n + 1 end
        if n >= 200 then return end -- enough NPCs to voice in the next release; keeps saved data small
    end
    local r = ns.db.speech[speaker] or { texts = {} }
    for _, t in ipairs(r.texts) do if t == text then return end end
    if #r.texts >= 12 then return end -- enough to voice an NPC; avoids filling saved data with combat spam
    r.texts[#r.texts + 1] = text
    r.zone = ns.zoneEN(ns.clean(GetRealZoneText()))
    for _, unit in ipairs({ "target", "mouseover", "npc" }) do
        if UnitExists(unit) and ns.clean(UnitName(unit)) == speaker then
            r.npc = { sex = ns.clean(UnitSex(unit)), creature = ns.clean(UnitCreatureType(unit)) }
            break
        end
    end
    local _, class = UnitClass("player")
    r.by = { class = ns.clean(class), name = ns.clean(UnitName("player")) }
    ns.db.speech[speaker] = r
end

local ev = CreateFrame("Frame")
-- lines the game already shows in a chat bubble over the speaker (said or yelled, bubbles on): the speaker window
-- leaves the words out for these, so they are not on screen twice
local bubbled = {}
function S.Bubbled(key) return key and bubbled[key] or false end

-- an NPC thanking a player by name ("Thank you for the spores, Darnok."): the name becomes $N before the line is
-- kept for sharing, the same token the game data uses, so the voice says "adventurer" and fits every player
local function withoutNames(text, target)
    local function swap(n)
        if type(n) == "string" and #n > 1 then text = text:gsub("%f[%a]" .. n:gsub("%p", "%%%0") .. "%f[%A]", "$N") end
    end
    swap(ns.clean(target)) -- may be nil: no one targeted
    swap(ns.clean(UnitName("player")))
    return text
end

-- the one speaking, if they're on screen as your target, mouseover, focus or a nameplate: whether a man or a woman
-- (guards and some enemies come as both, with a voice for each)
local function speakerSexOf(guid)
    if not guid or (canaccessvalue and not canaccessvalue(guid)) then return nil end
    local units = { "target", "mouseover", "focus" }
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate.namePlateUnitToken then units[#units + 1] = plate.namePlateUnitToken end
        end
    end
    for _, unit in ipairs(units) do
        local ok, same = pcall(function() return UnitGUID(unit) == guid end)
        if ok and same then
            local ok2, sex = pcall(UnitSex, unit)
            if ok2 and not (canaccessvalue and not canaccessvalue(sex)) then return sex end
        end
    end
end

ev:SetScript("OnEvent", function(_, event, text, speaker, _, _, target, _, _, _, _, _, _, guid)
    if not (ns.db and ns.settings.worldSpeech) then return end
    text, speaker = ns.clean(text), ns.clean(speaker)
    if type(text) ~= "string" or type(speaker) ~= "string" or text == "" then return end
    local key = S.Key(speaker, text)
    if ns.settings.debug then ns.pr(("debug: %s says -> %s"):format(speaker, key or "no match")) end
    if not key then
        record(speaker, withoutNames(text, target))
        return
    end
    if not ns.Voice.Get(key) or ns.Voice.IsPlaying() then return end -- never talk over quests and recaps
    if lastPlayed[key] and GetTime() - lastPlayed[key] < REPEAT_AFTER then return end
    lastPlayed[key] = GetTime()
    bubbled[key] = (event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL")
        and GetCVarBool and GetCVarBool("chatBubbles") or false
    ns.Voice.SetText(key, text)
    ns.Voice.SetSpeakerSex(speakerSexOf(guid))
    ns.Voice.Play(key)
    ns.Voice.SetSpeakerSex(nil)
end)
for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_RAID_BOSS_WHISPER" }) do
    pcall(ev.RegisterEvent, ev, e)
end

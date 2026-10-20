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
    local units = { "target", "mouseover", "focus", "targettarget", "softenemy", "softinteract", "pettarget",
        "party1target", "party2target", "party3target", "party4target" }
    if UnitTokenFromGUID then -- the game's own lookup, when it knows the speaker as a unit
        local ok, token = pcall(UnitTokenFromGUID, guid)
        if ok and type(token) == "string" then table.insert(units, 1, token) end
    end
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
    -- not on screen (often in a fight): a man or a woman by the speaker's own id, so a pack of thugs doesn't all
    -- shout in the voice the data lists first, and each one keeps the same voice (thanks Lukey_Q)
    local ok, last = pcall(function() return tonumber(guid:sub(-1), 16) end)
    if ok and last then return last % 2 == 0 and 2 or 3, true end
    return math.random(2, 3), true
end

-- chatter that came while other chatter was talking: played after it, if still fresh (10 seconds)
local waiting = {}
local function sayNow(said)
    bubbled[said.key] = said.bubbled
    ns.Voice.SetText(said.key, said.text)
    ns.Voice.SetSpeakerSex(said.sex)
    ns.Voice.Play(said.key)
    ns.Voice.SetSpeakerSex(nil)
end
local queueWatch = CreateFrame("Frame")
local queueWait = 0
queueWatch:SetScript("OnUpdate", function(_, dt)
    queueWait = queueWait - dt
    if queueWait > 0 or #waiting == 0 then return end
    queueWait = 0.2
    if ns.Voice.IsPlaying() or ns.Voice.Paused() then return end
    local said = table.remove(waiting, 1)
    if said and GetTime() - said.at < 10 then sayNow(said) end
end)

ev:SetScript("OnEvent", function(_, event, text, speaker, _, _, target, _, _, _, _, _, _, guid)
    if not (ns.db and ns.settings.worldSpeech) or ns.InCutscene() then return end
    text, speaker = ns.clean(text), ns.clean(speaker)
    if type(text) ~= "string" or type(speaker) ~= "string" or text == "" then return end
    local key = S.Key(speaker, text)
    if ns.settings.debug then ns.pr(("debug: %s says -> %s"):format(speaker, key or "no match")) end
    if not key then
        record(speaker, withoutNames(text, target))
        return
    end
    if not ns.Voice.Get(key) then return end
    if lastPlayed[key] and GetTime() - lastPlayed[key] < REPEAT_AFTER then return end
    local sex, guessed = speakerSexOf(guid)
    -- option: someone who comes as a man or a woman, and the addon can't see which one this is: stay quiet
    if guessed and ns.settings.mixedSure and (ns.audio[key .. ":m"] or ns.audio[key .. ":w"]) then return end
    lastPlayed[key] = GetTime()
    local said = {
        key = key, text = text, sex = sex, at = GetTime(),
        bubbled = (event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL")
            and GetCVarBool and GetCVarBool("chatBubbles") or false,
    }
    if ns.Voice.Paused() then return end -- you paused to talk: the chatter around you doesn't break in
    if ns.Voice.IsPlaying() then
        -- never over quests and recaps; but an answer to someone still talking waits its turn (the Stormwind
        -- kids and their dolly answer each other; the reply used to be lost, thanks Azona)
        local k = ns.Voice.PlayingKey() or ""
        if (k:sub(1, 4) == "say:" or k:sub(1, 5) == "sayr:") and #waiting < 3 then waiting[#waiting + 1] = said end
        return
    end
    sayNow(said)
end)
for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_RAID_BOSS_WHISPER" }) do
    pcall(ev.RegisterEvent, ev, e)
end

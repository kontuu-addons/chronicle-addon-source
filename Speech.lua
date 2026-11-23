-- Chronicle / Speech: NPCs saying things out loud in the world (speech bubbles, yells, whispers).
-- Only plays when nothing else is talking, and the same line from the same NPC waits a while before repeating.
-- Lines nobody has voiced yet (new NPCs) are recorded for /lore share.
local _, ns = ...
local L = ns.L
local S = {}
ns.Speech = S

local REPEAT_AFTER = 120 -- seconds before the same line may play again
local lastPlayed = {}

-- Nobody hears the Stormwind Crier: his announcement came round every minute and a half, all day (thanks Hedge), and
-- once every ten minutes was still too much (the user, 2026-11-23: "remove storwind guy for everyone"). His lines
-- aren't kept for /lore share either. Not every crier: Darkshire's and Southshore's tell an attack in steps, minutes
-- apart, and the scene needs every one of them
local SILENT = { ["Stormwind Crier"] = true }

local function norm(s)
    return " " .. s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%a]+", " ") .. " "
end

function S.Key(speaker, text)
    local speech = ns.Lore and ns.Lore.speech
    if not speech then return nil end
    local shown = norm(text)
    local function find(list)
        for _, item in ipairs(list or {}) do
            -- a line in a language you don't know plays only with that option on (Voice.Tongue)
            if shown:find(" " .. item[2] .. " ", 1, true) then return ns.Voice.Tongue(item[1]) end
        end
    end
    -- a warlock's imp has a random name of its own: its lines are found by their words, whatever it is called (only
    -- imps of a name someone had shared spoke; thanks Donkeyman)
    return find(speech[speaker]) or find(speech["*pet"])
end

-- what a release has voiced by now is let go: /lore share sends only what still waits, not the same lines every time,
-- and the limit below counts only the speakers still waiting (thanks WildflowerWonder)
function S.LetGoVoiced()
    for speaker, r in pairs(ns.db.speech or {}) do
        local left = {}
        for _, t in ipairs(type(r) == "table" and r.texts or {}) do
            local key = S.Key(speaker, t)
            if not (key and ns.Voice.Get(key)) then left[#left + 1] = t end
        end
        if #left == 0 then ns.db.speech[speaker] = nil else r.texts = left end
    end
end

local letGo = false
local function record(speaker, text)
    if not ns.english then return end -- other languages can't be voiced, and Share never sends them: don't fill the saved data
    ns.db.speech = ns.db.speech or {}
    if not letGo then letGo = true; S.LetGoVoiced() end -- once a session
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
local function readableSex(unit)
    local ok, sex = pcall(UnitSex, unit)
    if ok and type(sex) == "number" and not (canaccessvalue and not canaccessvalue(sex)) then return sex end
end

local function speakerSexOf(guid, speaker)
    local units = { "target", "mouseover", "focus", "targettarget", "softenemy", "softinteract", "pettarget",
        "party1target", "party2target", "party3target", "party4target" }
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate.namePlateUnitToken then units[#units + 1] = plate.namePlateUnitToken end
        end
    end
    local known = type(guid) == "string" and not (canaccessvalue and not canaccessvalue(guid))
    local hidden = not known -- the game kept the ids from us (in a fight), so units can't be told apart by them
    if known then
        if UnitTokenFromGUID then -- the game's own lookup, when it knows the speaker as a unit
            local ok, token = pcall(UnitTokenFromGUID, guid)
            if ok and type(token) == "string" then table.insert(units, 1, token) end
        end
        for _, unit in ipairs(units) do
            local ok, readable, same = pcall(function()
                local g = UnitGUID(unit)
                if g == nil then return true, false end
                if canaccessvalue and not canaccessvalue(g) then return false, false end
                return true, g == guid
            end)
            if not (ok and readable) then
                hidden = true
            elseif same then
                local sex = readableSex(unit)
                if sex then return sex end
            end
        end
    end
    -- with the ids hidden (the Scarlet Zealots' battle cries all came in the woman's voice, the one the data lists
    -- first): the units on screen with the speaker's name. One sex among them is the answer; with both, the one
    -- that has you as its target. (With the ids readable and no match, the speaker isn't on screen: no name check,
    -- another one of the same name would answer for them.)
    if hidden then
        local sexes, onMe = {}, {}
        for _, unit in ipairs(units) do
            local ok, same = pcall(function() return ns.clean(UnitName(unit)) == speaker end)
            local sex = ok and same and readableSex(unit)
            if sex == 2 or sex == 3 then
                sexes[sex] = true
                local ok2, mine = pcall(UnitIsUnit, unit .. "target", "player")
                if ok2 and (not canaccessvalue or canaccessvalue(mine)) then
                    if mine then onMe[sex] = true end
                end
            end
        end
        local function onlyOne(t)
            local found
            for s in pairs(t) do
                if found then return nil end
                found = s
            end
            return found
        end
        local sex = onlyOne(onMe) or onlyOne(sexes)
        if sex then return sex end
    end
    -- not on screen (often in a fight): a man or a woman by the speaker's own id, so a pack of thugs doesn't all
    -- shout in the voice the data lists first, and each one keeps the same voice (thanks Lukey_Q)
    if known then
        local ok, last = pcall(function() return tonumber(guid:sub(-1), 16) end)
        if ok and last then return last % 2 == 0 and 2 or 3, true end
    end
    return math.random(2, 3), true
end

-- chatter that came while other chatter was talking: played after it, if still fresh (10 seconds)
local waiting = {}

-- a quest just taken or handed in: what is said around you in the next half minute is the quest's own scene (the one
-- you handed it to answering, someone else stepping in, the campfire talk of The Great Outdoors), so it waits for
-- the quest's voice instead of being lost under it. Whoever spoke in it stays part of it for two minutes, so a longer
-- scene keeps its lines (thanks Peter)
local STORY, SCENE = 30, 120
local storyUntil, inScene = 0, {}
local questEv = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN" }) do pcall(questEv.RegisterEvent, questEv, e) end
questEv:SetScript("OnEvent", function() storyUntil = GetTime() + STORY end)

-- NPCs the player muted (their portrait's right-click menu, /lore mute): what they say in the world stays silent, on
-- every character, until unmuted. By name, so one muted guard is every guard of that name. Their quests and greetings
-- still play: those you open yourself (thanks Hedge)
local lastSpeaker, nowSaid -- the last NPC heard in the world, and their line that started last

function S.Muted(name)
    return type(name) == "string" and ns.db ~= nil and type(ns.db.muted) == "table" and ns.db.muted[name] == true
end

function S.SetMuted(name, on)
    if type(name) ~= "string" or name == "" then return end
    if on then
        ns.db.muted = type(ns.db.muted) == "table" and ns.db.muted or {}
        ns.db.muted[name] = true
        -- their line playing now stops, and the ones waiting their turn go
        if nowSaid and nowSaid.speaker == name and ns.Voice.PlayingKey() == nowSaid.key then ns.Voice.Stop() end
        for i = #waiting, 1, -1 do
            if waiting[i].speaker == name then table.remove(waiting, i) end
        end
    elseif type(ns.db.muted) == "table" then
        ns.db.muted[name] = nil
        if next(ns.db.muted) == nil then ns.db.muted = nil end
    end
end

function S.MutedNames()
    local names = {}
    for name in pairs(ns.db and type(ns.db.muted) == "table" and ns.db.muted or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function S.UnmuteAll() ns.db.muted = nil end

function S.LastSpeaker() return lastSpeaker end

local function mutedNote(name)
    ns.pr((L["%s muted: what they say in the world stays silent. Right-click their portrait again or type /lore unmute to hear them."]):format(name))
end

-- the portrait menu's entry: mute, or unmute when muted
function S.Toggle(name)
    if S.Muted(name) then
        S.SetMuted(name, false)
        ns.pr((L["%s can be heard again."]):format(name))
    else
        S.SetMuted(name, true)
        mutedNote(name)
    end
end

-- a name typed after /lore mute or /lore unmute, matched whatever its capitals: an NPC with world lines, one muted,
-- the last one heard, or your target
local function named(text, among)
    local want = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1"):lower()
    for _, name in ipairs(among) do
        if type(name) == "string" and name:lower() == want then return name end
    end
end

local function speakers()
    local all = S.MutedNames()
    all[#all + 1] = lastSpeaker
    local ok, target = pcall(UnitName, "target")
    if ok and type(target) == "string" and not (canaccessvalue and not canaccessvalue(target)) then
        all[#all + 1] = ns.clean(target)
    end
    for name in pairs(ns.Lore and ns.Lore.speech or {}) do
        if name ~= "*pet" then all[#all + 1] = name end
    end
    return all
end

-- /lore mute [name]: the NPC who talked last in the world, or the one named
function S.MuteCommand(arg)
    local name
    if arg and arg:find("%S") then
        name = named(arg, speakers())
        if not name then
            ns.pr((L["no NPC called %s talks in the world in Chronicle."]):format(arg))
            return
        end
    else
        name = lastSpeaker
        if not name then
            ns.pr(L["nobody has talked yet. Type /lore mute right after an NPC talks, or right-click their portrait."])
            return
        end
    end
    if S.Muted(name) then
        ns.pr((L["%s is already muted."]):format(name))
        return
    end
    S.SetMuted(name, true)
    mutedNote(name)
end

-- /lore unmute [name]: the one named, or everyone
function S.UnmuteCommand(arg)
    local names = S.MutedNames()
    if #names == 0 then
        ns.pr(L["nobody is muted."])
        return
    end
    if arg and arg:find("%S") then
        local name = named(arg, names)
        if not name then
            ns.pr((L["%s isn't muted."]):format(arg))
            return
        end
        S.SetMuted(name, false)
        ns.pr((L["%s can be heard again."]):format(name))
        return
    end
    S.UnmuteAll()
    ns.pr((L["everyone can be heard again: %s."]):format(table.concat(names, ", ")))
end

local function sayNow(said)
    if S.Muted(said.speaker) then return end -- muted while it waited its turn
    lastSpeaker, nowSaid = said.speaker, said
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
    if said and GetTime() - said.at < (said.own and 60 or 10) then sayNow(said) end
end)

ev:SetScript("OnEvent", function(_, event, text, speaker, _, _, target, _, _, _, _, _, _, guid)
    if not (ns.db and ns.settings.worldSpeech) or ns.InCutscene() then return end
    text, speaker = ns.clean(text), ns.clean(speaker)
    if type(text) ~= "string" or type(speaker) ~= "string" or text == "" then return end
    if SILENT[speaker] then return end
    local key = S.Key(speaker, text)
    if ns.settings.debug then ns.pr(("debug: %s says -> %s"):format(speaker, key or "no match")) end
    if not key then
        record(speaker, withoutNames(text, target))
        return
    end
    if not ns.Voice.Get(key) then return end
    if S.Muted(speaker) then
        if ns.settings.debug then ns.pr(("debug: %s is muted"):format(speaker)) end
        return
    end
    if lastPlayed[key] and GetTime() - lastPlayed[key] < REPEAT_AFTER then return end
    local sex, guessed = speakerSexOf(guid, speaker)
    if ns.settings.debug then
        ns.pr(("debug: %s is %s%s"):format(speaker, sex == 2 and "a man" or sex == 3 and "a woman" or "?",
            guessed and " (a guess)" or ""))
    end
    -- option: someone who comes as a man or a woman, and the addon can't see which one this is: stay quiet
    if guessed and ns.settings.mixedSure and (ns.audio[key .. ":m"] or ns.audio[key .. ":w"]) then return end
    lastPlayed[key] = GetTime()
    local said = {
        key = key, text = text, sex = sex, at = GetTime(), speaker = speaker,
        bubbled = (event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL")
            and GetCVarBool and GetCVarBool("chatBubbles") or false,
    }
    local t = GetTime()
    if t <= storyUntil then inScene[speaker] = t + SCENE end
    if ns.Voice.Paused() then return end -- you paused to talk: the chatter around you doesn't break in
    if ns.Voice.IsPlaying() then
        -- never over quests and recaps; but an answer to someone still talking waits its turn (the Stormwind
        -- kids and their dolly answer each other; the reply used to be lost, thanks Azona). And a quest's scene
        -- (above), or the one whose quest page is playing, waits too, longer and more of it
        local k = ns.Voice.PlayingKey() or ""
        local now = ns.Voice.Get(k)
        said.own = (inScene[speaker] or 0) >= t or (now ~= nil and now.w == speaker)
        local chatter = k:sub(1, 4) == "say:" or k:sub(1, 5) == "sayr:"
        if (said.own and #waiting < 8) or (chatter and #waiting < 3) then waiting[#waiting + 1] = said end
        return
    end
    sayNow(said)
end)
for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_RAID_BOSS_WHISPER" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- Right-click the target's portrait (or the focus's, or your pet's): "Mute voice", or "Unmute voice" for one muted.
-- Only for an NPC Chronicle has world lines for, on an English client (the only one their words are matched on), with
-- "NPCs talking in the world" on and a voice pack installed. Added the way the game lets addons add to its menus (run
-- through secureexecuterange, as the quest log's Hint); the game can't take an addition back, so it goes in once, at
-- login, and looks each time the menu opens whether it has anything to show (thanks Hedge)
local MENUS = { MENU_UNIT_TARGET = "target", MENU_UNIT_FOCUS = "focus", MENU_UNIT_PET = "pet" }

function S.MenuName(unit)
    if not (ns.english and ns.settings.worldSpeech and not ns.settings.journalOnly) then return nil end
    if next(ns.audio) == nil then return nil end -- no voice pack: nothing to mute
    if type(unit) ~= "string" or not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    local name = UnitName(unit)
    if type(name) ~= "string" or (canaccessvalue and not canaccessvalue(name)) then return nil end
    name = ns.clean(name)
    if SILENT[name] then return nil end -- never heard: nothing to mute
    local speech = ns.Lore and ns.Lore.speech or {}
    if S.Muted(name) or speech[name] then return name end
    -- a warlock's imp: a name of its own, its lines found by their words
    if speech["*pet"] and UnitCreatureFamily then
        local ok, family = pcall(UnitCreatureFamily, unit)
        if not ok or type(family) ~= "string" or (canaccessvalue and not canaccessvalue(family)) then return nil end
        if family == "Imp" then return name end
    end
end

table.insert(ns.onLogin, function()
    if not (Menu and Menu.ModifyMenu) then return end
    for tag, default in pairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, context)
            local unit = type(context) == "table" and context.unit or default
            local ok, name = pcall(S.MenuName, unit)
            if not (ok and name and root and root.CreateButton) then return end
            root:CreateDivider()
            root:CreateTitle("Chronicle")
            root:CreateButton(S.Muted(name) and L["Unmute voice"] or L["Mute voice"], function() S.Toggle(name) end)
        end)
    end
end)

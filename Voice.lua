-- Chronicle / Voice: plays the pre-rendered voiceover registered by the ForeverChronicle_<Kalimdor|EasternKingdoms|Adventures> packs.
-- Keys: "q<id>:detail", "q<id>:progress", "q<id>:complete" (NPC lines), "sum:<id>" and "arc:<id>" (narrator recaps).
local _, ns = ...
local L = ns.L
local V = {}
ns.Voice = V

local handle, timer, queue
local warned = false

local function clearTimer()
    if timer then timer:Cancel(); timer = nil end
end

-- Guards, grunts, townsfolk and some enemies come as men and women under one NPC: their lines are also recorded
-- in the other voice (key .. ":w" a woman's, key .. ":m" a man's), played when the one speaking is that sex: the
-- NPC you're talking to, or for speech in the world the speaker World speech found on screen (V.SetSpeakerSex).
local speakerSex
function V.SetSpeakerSex(sex) speakerSex = sex end

local function sexOf(unit)
    if not UnitExists(unit) then return nil end
    local ok, sex = pcall(UnitSex, unit)
    if not ok or (canaccessvalue and not canaccessvalue(sex)) then return nil end
    return sex
end

function V.Get(key)
    if not key or ns.settings.journalOnly then return nil end -- journal only: every line counts as unvoiced
    local sex = speakerSex or sexOf("npc")
    local other = (sex == 3 and ":w") or (sex == 2 and ":m") or nil
    if other then
        local e = (ns.female and ns.audio[key .. ":f" .. other]) or ns.audio[key .. other]
        if e then return e end
    end
    return (ns.female and ns.audio[key .. ":f"]) or ns.audio[key]
end

function V.IsPlaying() return handle ~= nil end

-- The button that started what is playing, so only that one turns into Stop.
local owner
function V.Owner() return handle and owner or nil end

-- Subtitles: the text of a line, for the talking head. Recaps and chapter intros come from the lore data,
-- quest lines from the text recorded when the quest window opened, the rest from what was on screen.
local shownText = {}
function V.SetText(key, text) shownText[key] = text end

function V.Subtitle(key)
    if not key then return nil end
    if shownText[key] then return shownText[key] end
    local l = ns.Lore or {}
    local id = key:match("^sum:(%d+)")
    if id then return l.quests and l.quests[tonumber(id)] and l.quests[tonumber(id)].summary end
    local zone = key:match("^zone:(.+)")
    if zone then return l.zoneIntro and l.zoneIntro[zone] end
    local tale = key:match("^tale:(.+)")
    if tale then return l.campfire and l.campfire[tale] end
    local lvl = key:match("^lvl:(.+)")
    if lvl then return l.levels and l.levels[lvl] end
    local ghost = tonumber(key:match("^ghost:(%d+)$") or "")
    if ghost then return l.ghost and l.ghost[ghost] end
    local epi = key:match("^epi:(.+)")
    if epi then return l.epilogue and l.epilogue[epi] end
    local dng = key:match("^dng:(.+)")
    if dng then return l.dungeonIntro and l.dungeonIntro[dng] end
    local bio = tonumber(key:match("^bio:(%d+)$") or "")
    if bio then
        for _, e in pairs(l.npcs or {}) do if e.id == bio then return e.b end end
        return nil
    end
    local att = key:match("^att:(.+)")
    if att then
        for _, a in ipairs(l.attunements or {}) do if a.id == att then return a.intro end end
        return nil
    end
    local dname, boss = key:match("^dend:(.+)|(.+)$")
    if dname then return l.dungeonEnd and l.dungeonEnd[dname] and l.dungeonEnd[dname][boss] end
    local arc = key:match("^arc:(.+)")
    if arc then
        for _, a in ipairs(l.arcs or {}) do if a.id == arc then return a.intro end end
        return nil
    end
    local qid, kind = key:match("^q(%d+):(%a+)")
    if qid then
        local q = ns.db.quests[tonumber(qid)]
        return q and q[kind]
    end
    -- greetings and chatter: their words come with the voice pack
    local e = ns.audio and ns.audio[key]
    if e and type(e.x) == "string" then return e.x end
end

-- ---------------------------------------------------------------- who is speaking (TalkingHead.lua draws it)
local function showBar(entry, key)
    -- NPCs talking in the world already have the game's speech bubble; a window popping up for every chatter line is noise
    if key and key:sub(1, 4) == "say:" then return end
    -- Immersion's talk box already shows the NPC and the text of quest pages and greetings
    local npcLine = key and (key:match("^q%d") or key:sub(1, 4) == "gos:" or key:sub(1, 3) == "qg:")
    if npcLine and ns.ExternalDialogShown and ns.ExternalDialogShown() then return end
    if ns.settings.speaker and ns.TalkingHead then
        local ok, err = pcall(ns.TalkingHead.Show, entry, key)
        if not ok and ns.settings.debug then ns.pr("debug: talking head error: " .. tostring(err)) end
    end
end

-- Alt-tab: the game mutes everything in the background unless its Sound in Background is on. While Chronicle
-- talks, it switches that on (option "Keep talking when alt-tabbed"), and back off as soon as it is quiet again, so
-- a line goes on while you're away and nothing has to be guessed or replayed. Remembered in the saved data, so a
-- crash in the middle of a line can't leave it on.
local BG = "Sound_EnableSoundWhenGameIsInBG"

local function holdBackground()
    if not ns.settings.bgVoices or (ns.db and ns.db.bgHeld) or GetCVarBool(BG) then return end
    if pcall(SetCVar, BG, "1") and ns.db then ns.db.bgHeld = true end
end

local function releaseBackground()
    if not (ns.db and ns.db.bgHeld) then return end
    ns.db.bgHeld = nil
    pcall(SetCVar, BG, "0")
end
V.ReleaseBackground = releaseBackground

table.insert(ns.onLogin, releaseBackground)

-- Ducking (option, on by default): while Chronicle talks, music and ambience go down to a third of where you set
-- them, and fade back up when it is quiet again. Your own levels are kept in the saved data until then, so a crash
-- mid-line puts them back at the next login. A level you changed yourself in the meantime is left as you set it.
local DUCK = { "Sound_MusicVolume", "Sound_AmbienceVolume" }

-- The sound channel the voices play on (option, Dialog by default; thanks AstroCat): its name for PlaySoundFile,
-- its volume and on/off settings, and its name in the game's Audio options
local CHANNELS = {
    Dialog = { vol = "Sound_DialogVolume", on = "Sound_EnableDialog", name = "Dialog" },
    SFX = { vol = "Sound_SFXVolume", on = "Sound_EnableSFX", name = "Sound Effects" },
    Master = { vol = "Sound_MasterVolume", on = "Sound_EnableAllSound", name = "Master" },
    Music = { vol = "Sound_MusicVolume", on = "Sound_EnableMusic", name = "Music" },
    Ambience = { vol = "Sound_AmbienceVolume", on = "Sound_EnableAmbience", name = "Ambience" },
}
V.CHANNEL_ORDER = { "Dialog", "SFX", "Master", "Music", "Ambience" }
---@return string id, table channel
function V.Channel()
    local c = tostring(ns.settings and ns.settings.channel or "Dialog")
    if not CHANNELS[c] then c = "Dialog" end
    return c, CHANNELS[c]
end
local function channelOff()
    local _, ch = V.Channel()
    local function off(cvar) local v = GetCVar and GetCVar(cvar) return v ~= nil and tonumber(v) == 0 end
    return off("Sound_EnableAllSound") or off(ch.on)
end
local function channelOffMessage(first)
    local id, ch = V.Channel()
    if id == "Dialog" then
        return first and L["could not play a voice line: the game's Dialog sound is switched off (System > Audio > Dialog)."]
            or L["the voices are silent: the game's Dialog sound is switched off (System > Audio > Dialog)."]
    end
    return (L["the voices are silent: the game's %s sound is switched off (System > Audio)."]):format(L[ch.name])
end
local DUCK_TO = 0.35
local duckFade

local function holdDuck()
    if not (ns.settings.duck and ns.db) or ns.settings.journalOnly then return end
    if duckFade then duckFade:Cancel(); duckFade = nil end
    local saved = ns.db.duckSaved
    if not saved then
        saved = {}
        for _, cv in ipairs(DUCK) do saved[cv] = tonumber(GetCVar(cv)) end
        ns.db.duckSaved = saved
    end
    local _, ch = V.Channel()
    for _, cv in ipairs(DUCK) do -- never the channel Chronicle itself plays on
        if saved[cv] and cv ~= ch.vol then pcall(SetCVar, cv, saved[cv] * DUCK_TO) end
    end
end

local function releaseDuck(now)
    local saved = ns.db and ns.db.duckSaved
    if not saved then return end
    if duckFade then duckFade:Cancel(); duckFade = nil end
    local mine = {} -- the levels still where Chronicle put them (not changed by hand while it talked)
    for _, cv in ipairs(DUCK) do
        local cur = tonumber(GetCVar(cv))
        if saved[cv] and cur and math.abs(cur - saved[cv] * DUCK_TO) < 0.02 then mine[#mine + 1] = cv end
    end
    local step, steps = 0, now and 1 or 8
    local function tick()
        step = step + 1
        local f = DUCK_TO + (1 - DUCK_TO) * step / steps
        for _, cv in ipairs(mine) do pcall(SetCVar, cv, saved[cv] * f) end
        if step >= steps then
            if duckFade then duckFade:Cancel(); duckFade = nil end
            ns.db.duckSaved = nil
        end
    end
    if now then tick() else duckFade = C_Timer.NewTicker(0.08, tick, steps) end
end
V.ReleaseDuck = releaseDuck

table.insert(ns.onLogin, function() releaseDuck(true) end)

local paused -- Pause: the line that was talking and the ones waiting after it, for Resume

-- Refresh anything that shows play/stop state.
local function changed()
    if not handle and ns.TalkingHead then pcall(paused and ns.TalkingHead.ShowPaused or ns.TalkingHead.Hide) end
    if not handle then
        C_Timer.After(1, function()
            if handle then return end
            if V.ReleaseBackground then V.ReleaseBackground() end
            if V.ReleaseDuck then V.ReleaseDuck() end
        end)
    end
    if V.UpdateQuestButton then V.UpdateQuestButton() end
    if ns.Books and ns.Books.Update then ns.Books.Update() end
    if ns.Journal and ns.Journal.OnVoiceChanged then ns.Journal.OnVoiceChanged() end
    if ns.Map and ns.Map.OnVoiceChanged then ns.Map.OnVoiceChanged() end
    if ns.Campfire and ns.Campfire.OnVoiceChanged then ns.Campfire.OnVoiceChanged() end
end

local ttsActive = false

local function stopSound()
    clearTimer()
    if handle then StopSound(handle, 400); handle = nil end
    if ns.db then ns.db.playing = nil end
    if ttsActive then
        ttsActive = false
        if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
    end
    changed()
end

-- ---------------------------------------------------------------- stand-in voice
-- Lines nobody has recorded yet can be read by the game's built-in text-to-speech (off by default: it sounds
-- robotic). A proper voice replaces it once the line is recorded and rendered.
local function ttsVoiceID(female)
    local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
    if not ok or type(voices) ~= "table" or #voices == 0 then return nil end
    local want = female and { "zira", "hazel", "susan", "female" } or { "david", "george", "mark", "male" }
    for _, v in ipairs(voices) do
        local n = (v.name or ""):lower()
        for _, w in ipairs(want) do
            if n:find(w, 1, true) and not (not female and n:find("female", 1, true)) then return v.voiceID end
        end
    end
    return voices[1].voiceID
end

function V.Speak(text, female)
    if ns.settings.journalOnly or not (text and text ~= "" and C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local id = ttsVoiceID(female)
    if not id then return false end
    stopSound()
    queue = nil
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\r\n]+", " ")
    -- the call changed between client versions; try the newer form, then the older one
    local ok = pcall(C_VoiceChat.SpeakText, id, text, 0, 100, true)
    if not ok and Enum and Enum.VoiceTtsDestination then
        ---@diagnostic disable-next-line: type-mismatch
        ok = pcall(C_VoiceChat.SpeakText, id, text, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
    end
    ttsActive = ok
    if ns.settings.debug then ns.pr("debug: stand-in voice " .. (ok and "speaking" or "not available in this client")) end
    return ok
end

function V.Stop()
    queue, paused = nil, nil
    stopSound()
end

local playNext
local playingKey
local lastKey -- the last line that played, for Replay

local startedTime = 0
local function start(entry, key)
    paused = nil -- something new is talking: the paused line is let go
    stopSound()
    playingKey = key
    lastKey = key or lastKey
    startedTime = GetTime()
    if ns.char and ns.char.heard and key and (key:match("^q%d") or key:sub(1, 4) == "book") then ns.char.heard[key] = true end
    holdBackground()
    holdDuck()
    local willPlay, h = PlaySoundFile("Interface\\AddOns\\" .. entry.p .. "\\Audio\\" .. entry.f, (V.Channel()))
    if ns.settings.debug then
        ns.pr(("debug: play %s -> %s"):format(entry.f, willPlay and "playing" or "FAILED (file not loaded by the game, or Dialog sound muted)"))
    end
    if not willPlay then
        if not warned then
            warned = true
            -- say which of the two it is: a sound channel switched off, or a voice file the game can't find
            if channelOff() then
                ns.pr(channelOffMessage(true))
            else
                local pack = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(entry.p, "Title") or entry.p
                ns.pr((L["could not play %s: the game can't find the file. Restart the game after installing or updating voice packs. If that doesn't help, reinstall %s."]):format(entry.f, pack))
            end
        end
        return false
    end
    handle = h
    ns.db.playing = h -- a /reload keeps the sound going; the next login stops it
    showBar(entry, key)
    timer = C_Timer.NewTimer((entry.d or 5) + 0.35, function()
        handle, timer = nil, nil
        ns.db.playing = nil
        if queue then playNext() end
        if not handle then changed() end -- the last line in the queue ended: close the speaker window
    end)
    changed()
    return true
end

playNext = function()
    while queue and #queue > 0 do
        local key = table.remove(queue, 1)
        local entry = V.Get(key)
        if entry and start(entry, key) then return end
    end
    queue = nil
end

-- The talking head's X: skip to the next line waiting in the queue, or stop if nothing is waiting.
function V.Skip()
    if queue and #queue > 0 then
        stopSound()
        playNext()
        if not handle then changed() end
    else
        V.Stop()
    end
end

-- Pause: the game can't hold a sound halfway, so the line stops and is kept, with everything waiting after it.
-- Resume plays it again from its start and carries on with the rest (thanks Rhiload). Talking to someone or
-- opening a quest in between lets the pause go; chatter around you and place lines wait until you resume.
function V.Pause()
    if not (handle and playingKey) then return false end
    local keys = { playingKey }
    for _, k in ipairs(queue or {}) do keys[#keys + 1] = k end
    paused = { keys = keys, owner = owner }
    queue = nil
    stopSound()
    return true
end

function V.Paused() return paused ~= nil end

function V.Resume()
    local p = paused
    if not p then return false end
    paused = nil
    if not V.PlayQueue(p.keys, p.owner) then changed() return false end
    return true
end

-- Play the last line again (the speaker window's replay button, /lore replay). False when nothing has played yet.
function V.Replay()
    if not lastKey or not V.Get(lastKey) then return false end
    return V.Play(lastKey)
end

-- The options' Test button: a short narrator line, the welcome of the zone you're in if it has one. Says why when
-- nothing can play.
local TEST_KEYS = { "zone:Elwynn Forest", "zone:Durotar", "zone:Tirisfal Glades", "zone:Dun Morogh", "zone:Mulgore",
    "zone:Teldrassil", "zone:Westfall", "zone:The Barrens" }
function V.Test()
    if ns.settings.journalOnly then ns.pr(L["voices are off: Journal only is on."]); return false end
    local here = ns.zoneEN and ns.zoneEN(GetRealZoneText() or "")
    local key = here and V.Get("zone:" .. here) and "zone:" .. here
    if not key then for _, k in ipairs(TEST_KEYS) do if V.Get(k) then key = k; break end end end
    if not key then ns.pr(L["no voice found to test: are the voice packs installed and turned on?"]); return false end
    warned = false -- say why if it doesn't play, even when that was said before
    return V.Play(key)
end

-- Play one line. Returns false when there is no recording for it.
function V.Play(key, by)
    local entry = V.Get(key)
    if not entry then return false end
    queue = nil
    owner = by
    return start(entry, key)
end

-- Play after whatever is talking now (or right away if nothing is).
-- seconds since the current line started (DialogueUI: a "stop" right after a page change is the page change itself)
function V.PlayingFor() return handle and (GetTime() - startedTime) or nil end

-- is this line already waiting its turn?
function V.Waiting(key)
    for _, k in ipairs(queue or {}) do if k == key then return true end end
    return false
end

function V.Enqueue(key)
    if not V.Get(key) then return false end
    if paused then -- a recap after a turn-in, a book: after the paused lines
        paused.keys[#paused.keys + 1] = key
        return true
    end
    if handle then
        queue = queue or {}
        queue[#queue + 1] = key
        return true
    end
    return V.Play(key)
end

-- The narrator's recap once a quest is handed in, after the NPC has finished speaking.
local RACE_SLUG = { Scourge = "Undead", NightElf = "NightElf" }
local lastReaction

-- Your own character's short line after a turn-in (about half the time, never the same line twice in a row).
local function reactionKey()
    local _, race = UnitRace("player")
    local slug = RACE_SLUG[race] or race
    local sex = UnitSex("player") == 3 and 3 or 2
    if not slug or math.random() > 0.5 then return nil end
    local options = {}
    for n = 1, 6 do
        local k = ("react:%s:%d:%d"):format(slug, sex, n)
        if k ~= lastReaction and V.Get(k) then options[#options + 1] = k end
    end
    if #options == 0 then return nil end
    lastReaction = options[math.random(#options)]
    return lastReaction
end

function V.OnQuestTurnedIn(questID)
    C_Timer.After(0.2, function()
        if ns.settings.reactions then
            local k = reactionKey()
            if k then V.Enqueue(k) end
        end
        if ns.settings.recapAfterTurnIn then V.Enqueue("sum:" .. questID) end
    end)
end

-- Play several lines back to back (chapter recaps).
function V.PlayQueue(keys, by)
    stopSound()
    owner = by
    queue = {}
    for _, k in ipairs(keys) do if V.Get(k) then queue[#queue + 1] = k end end
    if #queue == 0 then queue = nil; return false end
    playNext()
    return true
end

function V.PlayingKey() return handle and playingKey or nil end
function V.LastKey() return playingKey end

-- ---------------------------------------------------------------- greetings
-- Which voiced greeting is on screen: each variant ships a short phrase (Data\Lore.lua "greet") that is
-- matched against the window text, so a line only plays when it is really the one being shown.
local function norm(s)
    return " " .. s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%a]+", " ") .. " "
end

function V.GreetingKey(npcID, text)
    local list = ns.Greetings(npcID)
    if not list then return nil end
    local shown = norm(text)
    for _, item in ipairs(list) do
        local phrase = item[2]
        if phrase:sub(1, 1) == "=" then
            -- a short greeting, matched whole: "=hail *" is "Hail, paladin!" ("*" = the name, race or class the
            -- game filled in)
            local pattern = phrase:sub(2):gsub("%*", "%%a[%%a ]-")
            if shown:match("^ *" .. pattern .. " *$") then return item[1] end
        elseif shown:find(" " .. phrase .. " ", 1, true) then
            return item[1]
        end
    end
end

local function isGreeting(key) return key and (key:sub(1, 4) == "gos:" or key:sub(1, 3) == "qg:") end

-- With the game's own greetings audible, the first line of a new conversation waits until the NPC's
-- "Greetings" is over instead of talking over it. Walking away before then cancels it.
local GAME_GREETING = 1.5
local lastGUID, ended, endTime = nil, false, 0
local function npcGUID()
    local g = UnitGUID("npc") -- nil for quests from items: no game greeting then
    if g and canaccessvalue and not canaccessvalue(g) then return nil end
    return g
end
local function afterGameGreeting(fn)
    local guid = npcGUID()
    if guid and canaccessvalue and not canaccessvalue(guid) then guid = nil end -- (npcGUID already does; the checker wants it here)
    -- gossip closing into a quest page (same frame) is still the same conversation
    local fresh = guid and (guid ~= lastGUID or (ended and GetTime() - endTime > 0.5))
    lastGUID, ended = guid, false
    if not fresh or (ns.GreetingsMuted and ns.GreetingsMuted()) or ns.settings.journalOnly then return fn() end
    C_Timer.After(GAME_GREETING, function()
        local now = npcGUID()
        if now and canaccessvalue and not canaccessvalue(now) then now = nil end
        if now == guid then fn() end
    end)
end
local closeEv = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED" }) do pcall(closeEv.RegisterEvent, closeEv, e) end
closeEv:SetScript("OnEvent", function()
    ended, endTime = true, GetTime()
    -- a greeting still waiting its turn belongs to a conversation that is over: it would play long after (the wind
    -- rider master greeting you in Thunder Bluff), so it goes, and greets you next time instead (thanks Alche)
    for i = #(queue or {}), 1, -1 do
        if isGreeting(queue[i]) then
            ns.char.greeted[queue[i]] = nil
            table.remove(queue, i)
        end
    end
end)

local onGreeting
function V.OnGreeting(...)
    local args = { ... }
    afterGameGreeting(function() onGreeting(unpack(args, 1, 4)) end)
end

function onGreeting(npcID, key, text, female)
    local entry = key and V.Get(key)
    if ns.settings.debug then
        ns.pr(("debug: greeting from npc %s -> %s"):format(tostring(npcID),
            key and (entry and (key .. " found in " .. entry.p) or (key .. " matched but not voiced yet")) or "no matching voiced greeting"))
    end
    if not ns.settings.greetings then return end
    if not entry then
        if ns.settings.ttsFallback and text then
            local k = "tts:gos:" .. tostring(npcID)
            local last = ns.char.greeted[k]
            if not last or time() - last >= (ns.settings.greetCooldown or 10) * 60 then
                ns.char.greeted[k] = time()
                V.Speak(text, female)
            end
        end
        return
    end
    -- greetings come back after a cooldown (like an NPC greeting you again when you return later),
    -- instead of the once-only rule for quest lines. 0 minutes = every time.
    local last = ns.char.greeted[key]
    local wait = (ns.settings.greetCooldown or 10) * 60
    if last and time() - last < wait then
        if ns.settings.debug then ns.pr(("debug: greeting on cooldown, %d s left"):format(wait - (time() - last))) end
        return
    end
    -- a greeting never cuts anyone off: it waits for whoever is talking. Only the newest greeting waits.
    local now = V.PlayingKey()
    if now == key then return end
    ns.char.greeted[key] = time()
    if text then V.SetText(key, text) end
    if not now then V.Play(key) return end
    if queue then
        for i = #queue, 1, -1 do if isGreeting(queue[i]) then table.remove(queue, i) end end
    end
    V.Enqueue(key)
end

-- Called by Capture when a quest dialog page opens. If someone is still talking, the line waits its turn.
-- Lines this character already heard are skipped; the Listen buttons always replay.
local onQuestPage
function V.OnQuestPage(...)
    local args = { ... }
    afterGameGreeting(function() onQuestPage(unpack(args, 1, 4)) end)
end

-- Some quests are handed out by more than one NPC (Report to Gryan Stoutmantle: Farmer Saldean and Marshal
-- Dughan). The line is voiced by one of them; when another known character is talking, play their own
-- recording if a release has one, otherwise stay silent rather than speak in the wrong voice, and keep the
-- NPC for /lore share so the next release can voice it.
local function otherSpeakerKey(questID, kind, key)
    local entry = V.Get(key)
    if not (ns.english and entry and entry.w and entry.w ~= "" and entry.w ~= "Narrator") then return key end
    local guid, shown = npcGUID(), UnitName("npc")
    if not (guid and shown) or (canaccessvalue and not canaccessvalue(shown)) or shown == entry.w then return key end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    local npcID = tonumber(id)
    local people = ns.Lore and ns.Lore.people
    local known = false
    for _, n in ipairs(people or {}) do if n == shown then known = true; break end end
    if unitType ~= "Creature" or not npcID or not known then return key end -- a renamed NPC, an object, a player
    local alt = ("%s:n%d"):format(key, npcID)
    if V.Get(alt) then return alt end
    ns.db.otherGivers = ns.db.otherGivers or {}
    local o = ns.db.otherGivers[questID] or {}
    o[kind] = { name = shown, npcID = npcID, sex = UnitSex("npc") }
    ns.db.otherGivers[questID] = o
    if ns.settings.debug then ns.pr(("debug: %s is voiced by %s, not %s: silent"):format(key, entry.w, shown)) end
    return nil
end

-- A page that reads differently for some characters ("Hail, young warrior..." for warriors, "Though you are not a
-- warrior..." for everyone else) has a recording for each version: the one whose words are on screen
local PAGE_TEXT = { detail = "GetQuestText", progress = "GetProgressText", complete = "GetRewardText" }
local function versionKey(questID, kind, key, text)
    local want = ns.TextCheck(questID)
    if not (key and want and want[kind:sub(1, 1) .. "2"] and ns.Share and ns.Share.TextCheck) then return key end
    if not text then
        local get = _G[PAGE_TEXT[kind] or ""]
        if get then
            local ok, t = pcall(get)
            text = ok and t or nil
        end
    end
    if type(text) ~= "string" or (canaccessvalue and not canaccessvalue(text)) then return key end
    local h = ns.Share.TextCheck(text, { name = ns.clean(UnitName("player")) })
    for i = 2, 5 do
        local check = want[kind:sub(1, 1) .. i]
        if not check then break end
        local alt = "q" .. questID .. ":" .. kind .. ":v" .. i
        if h == check and V.Get(alt) then return alt end
    end
    return key
end

-- A quest page played from the journal or the quest log: the version you were given, by the text you recorded
function V.PageKey(questID, kind)
    local q = ns.db and ns.db.quests[questID]
    return versionKey(questID, kind, "q" .. questID .. ":" .. kind, q and q[kind] or "")
end

-- The key for a quest page, with the right speaker when several NPCs give it (nil: stay silent). For DialogueUI.
function V.QuestKey(questID, kind)
    return versionKey(questID, kind, otherSpeakerKey(questID, kind, "q" .. questID .. ":" .. kind))
end

function onQuestPage(questID, kind, text, female)
    local key = versionKey(questID, kind, otherSpeakerKey(questID, kind, "q" .. questID .. ":" .. kind), text)
    local silenced = not key
    local entry = key and V.Get(key)
    key = key or ("q" .. questID .. ":" .. kind)
    ns.lastQuestID = questID
    ns.lastKey = not silenced and key or nil -- no Play button with someone else's voice behind it
    if ns.settings.debug then
        ns.pr(("debug: %s page, quest %s -> %s %s"):format(kind, tostring(questID), key,
            entry and ("found in " .. entry.p) or "NOT in any voice pack"))
        if entry and not ns.settings.voice then ns.pr("debug: voice is turned off (/lore voice)") end
        if entry and ns.settings.skipHeard and ns.char.heard[key] then ns.pr("debug: skipped, already heard (option: don't repeat lines)") end
    end
    if ns.settings.voice and entry then
        local heard = ns.char.heard
        if handle and playingKey == key then
            -- the same page event fired twice: keep talking, don't restart
        elseif not (ns.settings.skipHeard and heard[key]) then
            local now = playingKey and handle and V.Get(playingKey)
            -- nobody is cut off: whoever is talking finishes first, and every page you open waits its turn, in
            -- order (several quests picked up in a row all get their voice; the speaker window's X skips ahead).
            -- A line counts as heard once it has really started (start below), not while it is still waiting.
            if now and playingKey ~= key then
                local waiting = false
                for _, k in ipairs(queue or {}) do if k == key then waiting = true end end
                if not waiting then V.Enqueue(key) end
            else
                V.Play(key)
            end
        end
    elseif ns.settings.voice and ns.settings.ttsFallback and text then
        local heard = ns.char.heard
        if not (ns.settings.skipHeard and heard["tts:" .. key]) then
            heard["tts:" .. key] = true
            V.Speak(text, female)
        end
    end
    if not entry and not silenced and ns.PackHint then ns.PackHint(questID) end
    V.UpdateQuestButton()
end

function V.OnQuestClosed()
    -- only NPC lines stop with the window; the narrator's recap after a turn-in keeps going
    local k = V.PlayingKey()
    if ns.settings.stopOnClose and k and k:sub(1, 1) == "q" then
        local pending = queue
        V.Stop()
        if pending and #pending > 0 then V.PlayQueue(pending) end
    end
end

-- ---------------------------------------------------------------- play/stop button on the quest window
local btn, marker, recapBtn, listenTab, recapTab
local ICON_LISTEN, ICON_STOP = "Interface\\Icons\\Ability_Warrior_BattleShout", "Interface\\Icons\\Spell_Holy_Silence"
-- the quest window's Listen, as a button or a side tab, while it is on screen (the tour's tip points at it)
function V.ListenButton()
    if btn and btn:IsVisible() then return btn end
    if listenTab and listenTab:IsVisible() then return listenTab end
end

function V.UpdateQuestButton()
    if not btn then return end
    local has = ns.lastKey and V.Get(ns.lastKey)
    local tabs = ns.settings.questTabs and listenTab ~= nil -- option: tabs on the window's side instead of buttons in it
    btn:SetShown(has and not tabs and true or false)
    btn:SetText(handle and L["Stop"] or L["Listen"])
    if listenTab then
        listenTab:SetShown(has and tabs and true or false)
        listenTab.icon:SetTexture(handle and ICON_STOP or ICON_LISTEN)
    end
    -- Recap: the story so far in this quest's chapter, as the panel beside the quest log tells it (the last step you
    -- finished, or the chapter's introduction); handy when handing in a quest whose start you've forgotten
    local rkey
    if recapBtn and ns.lastQuestID and ns.StoryLog and not ns.settings.journalOnly then
        local arc, step = ns.StoryLog.ChapterOf(ns.lastQuestID)
        if arc then
            local _, k = ns.StoryLog.StorySoFar(arc, step)
            if k and V.Get(k) then rkey = k; recapBtn.chapter = arc.title; if recapTab then recapTab.chapter = arc.title end end
        end
    end
    if recapBtn then
        recapBtn.key = rkey
        recapBtn:SetShown(rkey and not tabs and true or false)
        recapBtn:SetText(owner == recapBtn and handle and L["Stop"] or L["Recap"])
    end
    if recapTab then
        recapTab.key = rkey
        recapTab:SetShown(rkey and tabs and true or false)
        recapTab.icon:SetTexture(owner == recapTab and handle and ICON_STOP or "Interface\\Icons\\INV_Misc_Book_09")
        recapTab:ClearAllPoints()
        if has then recapTab:SetPoint("TOPLEFT", listenTab, "BOTTOMLEFT", 0, -4)
        else recapTab:SetPoint("TOPLEFT", listenTab, "TOPLEFT", 0, 0) end
    end
    -- "New in WoW: Forever" for quests that were not in Classic, and whether it has a voice yet
    local new = ns.settings.newMarker and ns.lastQuestID and ns.IsNew(ns.lastQuestID)
    marker:SetShown(new and true or false)
    if new then
        -- next to the Listen button, or where it would be; never behind the portrait on the left
        marker:ClearAllPoints()
        if has and not tabs then marker:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        else marker:SetPoint("RIGHT", QuestFrame, "TOPRIGHT", -30, -40) end
        marker:SetText(has and L["New in WoW: Forever"] or L["New in WoW: Forever  |cff9d9d9d· voice coming soon|r"])
    end
end

table.insert(ns.onLogin, function()
    if ns.db.playing then StopSound(ns.db.playing, 400); ns.db.playing = nil end
end)

table.insert(ns.onLogin, function()
    if not QuestFrame then return end
    local layer = ns.Overlay(QuestFrame)
    btn = CreateFrame("Button", nil, layer, "UIPanelButtonTemplate")
    btn:SetSize(70, 20); ns.FitButton(btn)
    -- where it sits: the top right of the quest window, or where you moved it (shift-drag; it overlapped other
    -- addons' buttons, thanks AstroCat). The Recap button and the "New in WoW: Forever" note go along.
    local function place()
        local pos = ns.settings.questBtnPos
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", pos and pos[1] or -30, pos and pos[2] or -30)
    end
    place()
    btn:SetMovable(true); btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self.moving = true; self:StartMoving() end end)
    btn:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = nil
        self:StopMovingOrSizing()
        local s = self:GetEffectiveScale() / QuestFrame:GetEffectiveScale()
        ns.settings.questBtnPos = { math.floor(self:GetRight() * s - QuestFrame:GetRight() + 0.5),
            math.floor(self:GetTop() * s - QuestFrame:GetTop() + 0.5) }
        place()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(handle and L["Stop"] or L["Listen"])
        GameTooltip:AddLine(L["Shift-drag to move it, shift-right-click to put it back"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn.text = btn:GetFontString()
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if IsShiftKeyDown() then ns.settings.questBtnPos = nil; place() end
            return
        end
        if handle then V.Stop() elseif ns.lastKey then V.Play(ns.lastKey) end
        V.UpdateQuestButton()
    end)
    btn:Hide()
    recapBtn = CreateFrame("Button", nil, layer, "UIPanelButtonTemplate")
    recapBtn:SetSize(70, 20); ns.FitButton(recapBtn)
    recapBtn:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    recapBtn:SetScript("OnClick", function(self)
        if owner == self and handle then V.Stop() elseif self.key then V.Play(self.key, self) end
        V.UpdateQuestButton()
    end)
    recapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["The story so far"])
        if self.chapter then GameTooltip:AddLine(self.chapter, 1, 1, 1) end
        GameTooltip:Show()
    end)
    recapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    recapBtn:Hide()
    -- the same two as tabs on the window's right side, like the journal's (option "Side tabs on the quest window")
    local function sideTab(icon, onClick, tip)
        local b = CreateFrame("Button", nil, layer)
        b:SetSize(48, 48)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        if not (b.bg.SetAtlas and pcall(b.bg.SetAtlas, b.bg, "common-sidetab")) then
            b.bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        end
        b.bg:SetSize(48, 52); b.bg:SetPoint("CENTER")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("CENTER", -2, 0)
        b.icon:SetTexture(icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD"); hl:SetPoint("TOPLEFT", b.icon, -2, 2); hl:SetPoint("BOTTOMRIGHT", b.icon, 2, -2)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); tip(self); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        return b
    end
    listenTab = sideTab(ICON_LISTEN, function()
        if handle then V.Stop() elseif ns.lastKey then V.Play(ns.lastKey) end
        V.UpdateQuestButton()
    end, function() GameTooltip:AddLine(handle and L["Stop"] or L["Listen"], 1, 1, 1) end)
    -- just outside the window's right edge: the classic quest window's art ends about 30 pixels inside its frame
    local modern = QuestFrame.NineSlice or QuestFrame.PortraitContainer
    listenTab:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", modern and -3 or -33, -60)
    recapTab = sideTab("Interface\\Icons\\INV_Misc_Book_09", function(self)
        if owner == self and handle then V.Stop() elseif self.key then V.Play(self.key, self) end
        V.UpdateQuestButton()
    end, function(self)
        GameTooltip:AddLine(L["Recap"], 1, 1, 1)
        GameTooltip:AddLine(L["The story so far"])
        if self.chapter then GameTooltip:AddLine(self.chapter, 1, 1, 1) end
    end)
    marker = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marker:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    marker:SetTextColor(0.35, 0.85, 0.8) -- teal, like the WoW: Forever logo
    marker:Hide()
    layer.onClose = function() ns.lastQuestID = nil; marker:Hide() end
end)

-- ---------------------------------------------------------------- "Listen" in the quest log
-- Replays the quest giver's words for the selected quest. The client may use the classic quest log
-- (QuestLogFrame) or the retail map-based one (QuestMapFrame); a button is added to whichever exists.
local function selectedQuestID()
    local id = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    if (not id or id == 0) and GetQuestLogSelection and GetQuestLogTitle then
        local idx = GetQuestLogSelection()
        if idx and idx > 0 then id = select(8, GetQuestLogTitle(idx)) end
    end
    return (id and id > 0) and id or nil
end

local function logButton(parent, point, x, y, id)
    local b = CreateFrame("Button", nil, ns.Overlay(parent), "UIPanelButtonTemplate")
    b:SetSize(70, 20); ns.FitButton(b)
    -- where it sits, or where you moved it with shift-drag (saved per quest log, like the quest window's)
    local function place()
        local pos = ns.settings.logBtnPos and ns.settings.logBtnPos[id]
        b:ClearAllPoints()
        if pos then b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pos[1], pos[2]) else b:SetPoint(point, parent, point, x, y) end
    end
    place()
    b:SetMovable(true); b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self.moving = true; self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = nil
        self:StopMovingOrSizing()
        local sc = self:GetEffectiveScale() / parent:GetEffectiveScale()
        ns.settings.logBtnPos = ns.settings.logBtnPos or {}
        ns.settings.logBtnPos[id] = { math.floor(self:GetRight() * sc - parent:GetRight() + 0.5),
            math.floor(self:GetTop() * sc - parent:GetTop() + 0.5) }
        place()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((handle and playingKey == self.key) and L["Stop"] or L["Listen"])
        GameTooltip:AddLine(L["Shift-drag to move it, shift-right-click to put it back"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if IsShiftKeyDown() and ns.settings.logBtnPos then ns.settings.logBtnPos[id] = nil; place() end
            return
        end
        if handle and playingKey == self.key then V.Stop() elseif self.key then V.Play(self.key) end
    end)
    local elapsed = 0
    b:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local qid = selectedQuestID()
        self.key = qid and V.PageKey(qid, "detail") or nil
        local has = self.key and V.Get(self.key)
        self:SetAlpha(has and 1 or 0)
        self:EnableMouse(has and true or false)
        self:SetText((handle and playingKey == self.key) and L["Stop"] or L["Listen"])
    end)
end

table.insert(ns.onLogin, function()
    if QuestLogFrame then logButton(QuestLogFrame, "TOPRIGHT", -44, -44, "log") end
    if QuestLogDetailFrame then logButton(QuestLogDetailFrame, "TOPRIGHT", -44, -44, "detail") end
    -- inside the details page, level with its Back button: above it sat on the map's full-screen button
    if QuestMapFrame and QuestMapFrame.DetailsFrame then logButton(QuestMapFrame.DetailsFrame, "TOPRIGHT", -28, -12, "map") end
end)

-- The voices play on the game's Dialog channel: switched off, Chronicle is silent and nothing says why. Say it once
-- at login (thanks Kryx).
table.insert(ns.onLogin, function()
    C_Timer.After(8, function()
        if not ns.settings.voice or ns.settings.journalOnly then return end
        if channelOff() then
            warned = true -- no second message when the first line can't play
            ns.pr(channelOffMessage(false))
        end
    end)
end)

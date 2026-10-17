-- Chronicle core: saved data, settings, module hooks, /lore.
-- WoW: Forever (Retail-style API, Interface 16001).
local ADDON, ns = ...
local L = ns.L
ns.path = "Interface\\AddOns\\" .. ADDON .. "\\"
ns.onLogin = {}

-- Key bindings (Bindings.xml), so the voices and the journal work from a controller or a keyboard key.
BINDING_HEADER_CHRONICLE = "Chronicle"
BINDING_NAME_CHRONICLE_PLAYSTOP = L["Play, pause or resume the voice"]
BINDING_NAME_CHRONICLE_SKIP = L["Skip to the next line"]
BINDING_NAME_CHRONICLE_JOURNAL = L["Open the journal"]
_G.ChronicleBinding_PlayStop = function()
    local V = ns.Voice
    if not V then return end
    if V.Paused() then V.Resume() return end
    if V.IsPlaying() then V.Pause() return end
    local key = V.LastKey() or ns.lastKey -- the last line heard, or the quest window's line
    if key then V.Play(key) end
end
-- Playing with a controller: its back button is Escape, so Chronicle's small windows close with it then. Only while a
-- gamepad is on: with mouse and keyboard, Escape goes straight to the game menu as before.
local padFrames = {}
local function padOn()
    if GetCVar and GetCVar("GamePadEnable") ~= "1" then return false end
    local ok, ids = pcall(function() return C_GamePad and C_GamePad.GetAllDeviceIDs and C_GamePad.GetAllDeviceIDs() end)
    return not (ok and type(ids) == "table" and #ids == 0) -- no list to ask: trust the setting
end
ns.PadOn = padOn
local function updatePadClose()
    local on = padOn()
    for name in pairs(padFrames) do
        local at
        for i, n in ipairs(UISpecialFrames) do if n == name then at = i end end
        if on and not at then tinsert(UISpecialFrames, name) elseif not on and at then table.remove(UISpecialFrames, at) end
    end
end
function ns.PadClose(name)
    padFrames[name] = true
    updatePadClose()
end
local padWatch = CreateFrame("Frame")
for _, e in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "CVAR_UPDATE", "PLAYER_LOGIN" }) do
    pcall(padWatch.RegisterEvent, padWatch, e)
end
padWatch:SetScript("OnEvent", updatePadClose)

-- Skip: the next line; with nothing playing it closes the speaker window (no mouse needed on a controller)
_G.ChronicleBinding_Skip = function()
    if ns.Voice and ns.Voice.Paused() then ns.Voice.Stop(); if ns.TalkingHead then ns.TalkingHead.Hide(true) end
    elseif ns.Voice and ns.Voice.IsPlaying() then ns.Voice.Skip()
    elseif ns.TalkingHead then ns.TalkingHead.Hide(true) end
end
_G.ChronicleBinding_Journal = function() if ns.Journal then ns.Journal.Toggle() end end

-- The minimap's addon compartment (the TOC names these): left-click the journal, right-click the options.
_G.Chronicle_OnAddonCompartmentClick = function(_, button)
    if button == "RightButton" then
        if ns.Options then ns.Options.Open() end
    elseif ns.Journal then
        ns.Journal.Toggle()
    end
end
_G.Chronicle_OnAddonCompartmentEnter = function(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("Chronicle")
    GameTooltip:AddLine(L["Left-click: the story so far"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:Show()
end
_G.Chronicle_OnAddonCompartmentLeave = function() GameTooltip:Hide() end

local DEFAULTS = {
    journalOnly = false, -- no voices at all, just the journal (works without the voice packs)
    voice = true,        -- play recorded voiceover when a quest dialog opens
    bgVoices = true,     -- while Chronicle talks, the game's Sound in Background is on (alt-tab keeps the line going)
    duck = true,         -- music and ambience go down while Chronicle talks (thanks Alche)
    questHints = false,
    hideUnfound = false, -- no counts, gaps or pins for what this character hasn't found yet (thanks AstroCat)  -- Hint for one quest's objectives on the map (for playing with objectives off)
    chroniclePause = false, -- "Tell my chronicle" stops after each chapter until you press Continue
    journalScale = 1,    -- the journal's size
    stopOnClose = false, -- keep talking after the quest window closes (works with auto-accept addons)
    speaker = true,      -- show the "now speaking" bar
    lockSpeaker = false, -- the speaker window can't be dragged
    speakerBg = 1,       -- how strong the speaker window's background is (0 = only the words)
    recapAfterTurnIn = true, -- narrator reads the story recap after you hand in a quest
    minimap = true,      -- minimap button
    minimapFree = false, -- the button anywhere on the screen instead of on the minimap edge
    zoneRecap = true,    -- "Previously in <zone>" when returning to a zone
    zoneIntro = true,    -- "Welcome to <zone>" the first time you enter a zone
    areaIntros = true,   -- a line about a named place in a zone (Bloodhoof Village) the first time you enter it
    skipHeard = true,    -- don't auto-play a line this character has already heard
    greetings = true,    -- voice NPC greetings (gossip window / quest greeting)
    greetCooldown = 10,  -- minutes before the same greeting plays again (0 = every time)
    ttsFallback = false, -- read lines nobody has voiced yet with the game's built-in text-to-speech
    newMarker = true,    -- "New in WoW: Forever" on the quest window
    books = true,        -- the narrator reads books, letters and plaques
    reactions = false,   -- your own character says a short line after some turn-ins (off by default)
    mapPins = true,      -- story chapters on the world map (the books)
    storyPanel = true,   -- the zone's story panel on the world map, and the chapter count on continents
    showLeft = false,    -- quests still to do and where undiscovered chapters start (journal, map)
    logStory = true,     -- "The story so far" beside the quest log
    campfire = true,     -- "By the fire": camp countdown, a campfire tale, and the camp's benefits
    tips = true,         -- one small "Did you know?" under a journal chapter
    bigSubtitles = false, -- larger subtitle text in the speaker window
    checkVoices = false, -- Good / Bad buttons in the speaker window, for players who help check the voices
    flightStory = true,  -- on a flight: the story so far in the zone you're flying to
    ghostQuips = true,   -- running back as a ghost: now and then a short line from the narrator
    levelMilestones = true, -- every 10th level: a word from the narrator and where new stories open up
    muteGameGreetings = true, -- silence the game's own "Greetings"/"Farewell" NPC voices so they don't talk over ours
    questMarkers = false, -- "!" at quest givers with quests for you, "?" where to hand in (off when Questie runs)
    mixedSure = false,   -- NPCs that come as men and women: quiet when the speaker can't be seen (else a guess)
    worldSpeech = true,  -- NPCs speaking out loud in the world (speech bubbles, yells)
    subtitles = true,    -- show the text of what is being said in the talking head
    partySync = true,    -- swap unvoiced recordings with party members who also run Chronicle
    shareNudge = true,   -- after a turn-in, offer to share new quests that have no voice yet
}
ns.DEFAULTS = DEFAULTS

function ns.pr(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd9b36cChronicle|r: " .. tostring(msg)) end

-- True for quests that were not in original Classic: new in WoW: Forever.
local classicSet
function ns.IsNew(id)
    if not classicSet then
        classicSet = {}
        for _, qid in ipairs((ns.Lore and ns.Lore.classic) or {}) do classicSet[qid] = true end
    end
    return id and next(classicSet) ~= nil and not classicSet[id]
end

-- Zone of a quest according to the shipped lore data (covers every classic quest, even ones never recorded).
function ns.LoreZone(id)
    local l = ns.Lore
    local i = l and l.zoneOf and l.zoneOf[id]
    return i and l.zoneNames[i] or nil
end

-- ---------------------------------------------------------------- voice packs
-- Three voice addons (ForeverChronicle_Kalimdor, _EasternKingdoms, _Adventures) load after this one and register
-- their lines, with each zone's audio in its own sub-folder:
--   LibStub("Chronicle-1.0"):RegisterPack("ForeverChronicle_Kalimdor", { ["q354:detail"] = { "Durotar\\q354_detail.ogg", 21.4, "Coleman Farthing" }, ... })
-- Keys ending in ":f" are the variant for female characters (lines that say brother/sister etc.).
ns.audio, ns.packs = {}, {}
local function registerPack(folder, lines)
    if type(folder) ~= "string" or type(lines) ~= "table" then return end
    local n = 0
    -- each line stays the pack's own small table { file, seconds, who, words }; e.f, e.d, e.w, e.x and e.p read
    -- it through one shared lookup per pack (a copy per line cost about 9 MB for 31,000 lines)
    local FIELDS = { f = 1, d = 2, w = 3, x = 4, s = 5 } -- s: who speaks when, in a line with more than one voice
    local view = { __index = function(t, k) if k == "p" then return folder end local i = FIELDS[k] return i and rawget(t, i) end }
    for key, e in pairs(lines) do
        if type(e) == "table" and type(e[1]) == "string" then
            ns.audio[key] = setmetatable(e, view)
            n = n + 1
        end
    end
    ns.packs[#ns.packs + 1] = { folder = folder, lines = n }
end

-- The voice packs register through LibStub: LibStub("Chronicle-1.0"):RegisterPack(folder, lines)
local api = LibStub:NewLibrary("Chronicle-1.0", 1)
if api then
    function api:RegisterPack(folder, lines) registerPack(folder, lines) end
end
-- Voice packs from before 1.0.0-beta.7 call this global instead. It goes once everyone has the new packs.
_G.ChronicleRegisterPack = registerPack

-- Unit and quest APIs can hand back secret values in restricted contexts; never store those.
function ns.clean(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The game's diamond-metal border (as around Forever's new windows) on one of our frames, drawn over its edges
-- and leaving its inside alone. Returns the border, or nil where the client has no such border (old look stays).
function ns.FancyBorder(f)
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-Frame-DiamondMetal-CornerTopLeft")) then
        return nil
    end
    local ok, b = pcall(CreateFrame, "Frame", nil, f, "DialogBorderNoCenterTemplate")
    if not (ok and b) then return nil end
    -- the border's metal sits a little inside its frame: spread it out so it covers the whole background
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 6); b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 6, -6)
    b:SetFrameLevel(f:GetFrameLevel() + 5)
    b:EnableMouse(false)
    return b
end

-- A layer of our own over a Blizzard window, for Chronicle's buttons on it. Buttons made as children of a
-- Blizzard window get picked up by the game's gamepad mode when it scans that window, which taints its code
-- and blocks protected calls ("tried to call SetPreferredGamepadInteractTarget"). Hooking the window's OnShow
-- did the same: our code then ran inside the game's own, just before it made that call. So nothing of ours
-- touches the window at all: one watcher of our own looks every tenth of a second whether it is open, and
-- shows the layer (same place, drawn just above it) or hides it.
local layers = {}
-- the layer sits one strata above its window: a "toplevel" window (the book's) is raised over everything at its own
-- strata when it opens or is clicked, which covered the layer (the Listen button only showed as the book closed)
local ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }
local watch = CreateFrame("Frame")
local wait = 0
watch:SetScript("OnUpdate", function(_, dt)
    wait = wait - dt
    if wait > 0 then return end
    wait = 0.1
    for o, target in pairs(layers) do
        local open = target:IsVisible()
        if open and not o:IsShown() then
            local strata = target:GetFrameStrata()
            o:SetFrameStrata(ABOVE[strata] or strata)
            o:SetFrameLevel(target:GetFrameLevel() + 50)
            o:Show()
            if o.onOpen then o.onOpen() end
        elseif not open and o:IsShown() then
            o:Hide()
            if o.onClose then o.onClose() end
        end
    end
end)

function ns.Overlay(target)
    local o = CreateFrame("Frame", nil, UIParent)
    o:SetAllPoints(target)
    o:Hide()
    layers[o] = target
    return o
end

-- Lore data kept as short strings (one per quest or NPC instead of a table each): unpacked here when needed.
-- An older Lore.lua with tables still reads the same.
function ns.TextCheck(questID)
    local v = ns.Lore and ns.Lore.textcheck and ns.Lore.textcheck[questID]
    if type(v) ~= "string" then return v end
    local t = {}
    for k, n in v:gmatch("(%w+)=(%d+)") do t[k] = tonumber(n) end
    return t
end

local greetCache = setmetatable({}, { __mode = "v" })
function ns.Greetings(npcID)
    local v = ns.Lore and ns.Lore.greet and ns.Lore.greet[npcID]
    if type(v) ~= "string" then return v end
    local list = greetCache[npcID]
    if list then return list end
    list = {}
    for key, phrase in v:gmatch("([^\t\n]+)\t([^\n]*)") do list[#list + 1] = { key, phrase } end
    greetCache[npcID] = list
    return list
end

function ns.StepAt(questID)
    local v = ns.Lore and ns.Lore.stepAt and ns.Lore.stepAt[questID]
    if type(v) ~= "string" then return v end
    local step, x, y = v:match("^(%d+),([%d.]+),([%d.]+)$")
    return step and { tonumber(step), tonumber(x), tonumber(y) } or nil
end

local function applyDefaults(t, d)
    for k, v in pairs(d) do if t[k] == nil then t[k] = v end end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        ns.svLoaded = (ChronicleDB ~= nil)
        ChronicleDB = ChronicleDB or {}
        local db = ChronicleDB
        db.version = db.version or 1  -- future migrations compare against this
        db.quests = db.quests or {}   -- [questID] = captured text, giver, zone (shared by all characters)
        db.chars = db.chars or {}     -- character names, so the voice tool can swap them out of spoken text
        db.settings = db.settings or {}
        db.uiprobe = nil -- a developer's look at the UI, read from the file after the session: not kept in memory
        applyDefaults(db.settings, DEFAULTS)
        -- 0.1 stored quest log headers as the zone; real captures also have a map ID
        for _, q in pairs(db.quests) do
            if q.fromLog and q.zone and not q.map then q.category, q.zone = q.category or q.zone, nil end
        end

        ChronicleCharDB = ChronicleCharDB or {}
        local c = ChronicleCharDB
        c.journal = c.journal or {}   -- ordered list of { id, t, zone } turn-ins
        c.done = c.done or {}         -- [questID] = true
        c.active = c.active or {}     -- [questID] = accepted time
        c.heard = c.heard or {}       -- [voice key] = true, lines already played automatically
        c.greeted = c.greeted or {}   -- [greeting key] = time it last played (for the greeting cooldown)

        ns.db, ns.char, ns.settings = db, c, db.settings
    elseif event == "PLAYER_LOGIN" then
        local name = ns.clean(UnitName("player"))
        if name then ns.db.chars[name] = true end
        ns.female = (UnitSex("player") == 3)
        local loc = GetLocale and GetLocale() or "enUS"
        ns.english = (loc == "enUS" or loc == "enGB")
        for _, fn in ipairs(ns.onLogin) do fn() end

        -- other voice addons would talk over Chronicle: say so once, leave the choice to the player
        local isLoaded = C_AddOns.IsAddOnLoaded
        local others = {}
        for _, other in ipairs({ "VoiceOver", "VoiceOverForever", "SpokenQuests", "ForeverVoiceover", "ForeverTTS",
                                "ChattyLittleNpc", "AI_VoiceOver", "AIQuestVoices" }) do
            if isLoaded and isLoaded(other) then others[#others + 1] = other end
        end
        if #others > 0 and not ns.db.warnedOthers then
            ns.db.warnedOthers = true
            ns.pr((L["also running: %s. Two voice addons may speak at the same time; you can turn one off in the AddOns list."]):format(table.concat(others, ", ")))
        end

        -- "Chronicle: Story Journal" on CurseForge is this addon without the voice packs (its TOC says
        -- X-Edition: journal): it starts as a journal only, once, and never asks for the packs
        ns.journalEdition = (C_AddOns.GetAddOnMetadata(ADDON, "X-Edition") == "journal")
        if ns.journalEdition and not ns.db.editionDefaults then
            ns.db.editionDefaults = true
            ns.settings.journalOnly = true
            ns.ApplyGreetingMute()
        elseif not ns.journalEdition and ns.db.editionDefaults then
            -- the full addon after the Story Journal (both keep the same saved settings): the journal edition's
            -- "Journal only" would keep every voice off and every Play button grey. Voices back on, once (thanks Ziggo)
            ns.db.editionDefaults = nil
            if ns.settings.journalOnly then
                ns.settings.journalOnly = false
                ns.ApplyGreetingMute()
                C_Timer.After(6, function()
                    ns.pr(L["the voices are on again (the Story Journal edition had switched them off). Options > Journal only turns them off."])
                end)
            end
        end

        -- your character's own lines after a turn-in were too much for most: off for everyone once, on for whoever
        -- turns them back on under Options
        if not ns.db.reactionsOffOnce then
            ns.db.reactionsOffOnce = true
            ns.settings.reactions = false
        end

        -- the voices and the story texts are English: on other clients Chronicle starts as a journal only, once
        if not ns.english and not ns.journalEdition and not ns.db.localeDefaults then
            ns.db.localeDefaults = true
            ns.settings.journalOnly = true
            ns.ApplyGreetingMute()
            ns.pr(L["the voices are in English, so they start turned off on your game language. The journal and the map work as usual. To hear the voices, untick \"Journal only\" under Options."])
        end

        local voiced = 0
        for _ in pairs(ns.audio) do voiced = voiced + 1 end
        local version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
        if not ns.db.welcomed then
            -- first time on this account: what it is, and what it shares
            ns.db.welcomed = true
            if ns.journalEdition and #ns.packs == 0 then
                ns.pr(L["welcome! Your story is kept in the journal: |cffffd100/lore|r or the minimap book. The quests you do are sorted into chapters with short recaps, and the world map shows where your story continues."])
            else
                ns.pr((L["welcome! NPCs now speak their quests, and your story is kept in the journal: |cffffd100/lore|r or the minimap book. %d voice lines installed."]):format(voiced))
            end
            ns.pr(L["Options: Esc > Options > AddOns > Chronicle. With party members who also run Chronicle, text of new quests without a voice yet is swapped automatically so it can be voiced (turn off under \"Share recordings with my party\")."])
        elseif ns.db.lastVersion ~= version and #ns.packs > 0 then
            ns.pr((L["updated to %s: %d voice lines from %d packs. /lore to open."]):format(version, voiced, #ns.packs))
        end
        ns.db.lastVersion = version
        if C_Timer then C_Timer.After(6, ns.PackPopup) else ns.PackPopup() end
    end
end)

-- Popup at login while a voice pack is missing or turned off, until it's fixed or dismissed.
local PACKS = { { "ForeverChronicle_Kalimdor", "Voices of Kalimdor" },
    { "ForeverChronicle_EasternKingdoms", "Voices of the Eastern Kingdoms" },
    { "ForeverChronicle_Adventures", "Books & Adventures" } }

local function packState(folder)
    for _, p in ipairs(ns.packs) do if p.folder == folder then return "loaded" end end
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local ok, _, _, _, _, reason = pcall(info, folder)
    if ok and reason == "MISSING" then return "missing" end
    return ok and "off" or "missing"
end

function ns.PackPopup()
    if ns.settings.journalOnly or (ns.journalEdition and #ns.packs == 0) then return end
    local missing, off, sig = {}, {}, {}
    for _, p in ipairs(PACKS) do
        local s = packState(p[1])
        if s == "missing" then missing[#missing + 1] = "|cffffd100" .. p[2] .. "|r" end
        if s == "off" then off[#off + 1] = "|cffffd100" .. p[2] .. "|r" end
        if s ~= "loaded" then sig[#sig + 1] = p[1] .. s end
    end
    if #sig == 0 then ns.db.packPopupOff = nil return end
    sig = table.concat(sig, ",")
    if ns.db.packPopupOff == sig then return end -- the player asked not to be reminded about exactly this

    local text = (#ns.packs == 0) and L["Chronicle has no voices yet."] or L["Some of Chronicle's voices are missing."]
    if #missing > 0 then
        text = text .. L["\n\nThe voices are separate downloads. In the CurseForge app, search for |cffffd100Chronicle|r and install:\n\n"]
            .. table.concat(missing, "\n") .. L["\n\nThen restart the game."]
    end
    if #off > 0 then
        text = text .. L["\n\nTurned off in the AddOns list (character select screen):\n\n"] .. table.concat(off, "\n")
    end
    StaticPopupDialogs.CHRONICLE_PACKS = {
        text = text,
        button1 = OKAY,
        button2 = L["Don't remind me"],
        button3 = L["Journal only"],
        OnCancel = function(_, _, reason) if reason == "clicked" then ns.db.packPopupOff = sig end end,
        OnAlt = function() ns.SetJournalOnly(true) end,
        -- with a controller, its back button (Esc) closes it without counting as "don't remind"
        timeout = 0, whileDead = true, hideOnEscape = padOn(), noCancelOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("CHRONICLE_PACKS")
end

-- The game's own NPC greeting and farewell voices (Data\Greetings.lua) would talk over Chronicle's lines.
local greetingsMuted = false
function ns.ApplyGreetingMute()
    -- only while Chronicle voices greetings itself: with its greetings off, the game's own clips come back
    local want = ns.settings.muteGameGreetings and ns.settings.greetings and not ns.settings.journalOnly
    if want == greetingsMuted or not (MuteSoundFile and UnmuteSoundFile and ns.GreetingSounds) then return end
    local fn = want and MuteSoundFile or UnmuteSoundFile
    for _, fid in ipairs(ns.GreetingSounds) do pcall(fn, fid) end
    greetingsMuted = want and true or false
end
table.insert(ns.onLogin, function() ns.ApplyGreetingMute() end)
function ns.GreetingsMuted() return greetingsMuted end

-- Journal only: no voices, no talking head, no voice pack reminders; the journal, recaps text and map stay.
function ns.SetJournalOnly(on)
    ns.settings.journalOnly = on and true or false
    if on and ns.Voice then ns.Voice.Stop() end
    ns.ApplyGreetingMute()
    if ns.Voice and ns.Voice.UpdateQuestButton then ns.Voice.UpdateQuestButton() end
    if ns.Journal and ns.Journal.Refresh then pcall(ns.Journal.Refresh) end -- hides or shows the Listen buttons
    ns.pr(on and L["journal only: voices are off. Turn them back on under Options (the button in the journal)."]
        or L["voices are on again."])
end

-- Once per voice pack: a quest has no voice because the pack for its zone is switched off or missing.
local KALIMDOR = { ["Ashenvale"] = 1, ["Azshara"] = 1, ["Darkshore"] = 1, ["Darnassus"] = 1, ["Desolace"] = 1,
    ["Durotar"] = 1, ["Dustwallow Marsh"] = 1, ["Felwood"] = 1, ["Feralas"] = 1, ["Moonglade"] = 1, ["Mulgore"] = 1,
    ["Orgrimmar"] = 1, ["Silithus"] = 1, ["Stonetalon Mountains"] = 1, ["Tanaris"] = 1, ["Teldrassil"] = 1,
    ["The Barrens"] = 1, ["Thousand Needles"] = 1, ["Thunder Bluff"] = 1, ["Un'Goro Crater"] = 1, ["Winterspring"] = 1 }
local PACK_TITLE = { ForeverChronicle_Kalimdor = L["Voices of Kalimdor"],
    ForeverChronicle_EasternKingdoms = L["Voices of the Eastern Kingdoms"], ForeverChronicle_Adventures = L["Books & Adventures"] }
local hinted = {}
function ns.PackHint(questID)
    local zone = ns.LoreZone(questID)
    if not zone or ns.settings.journalOnly then return end
    -- Zephras Isle and Stormwind City live in Books & Adventures since beta.14 (the Eastern Kingdoms pack got too big)
    local folder = KALIMDOR[zone] and "ForeverChronicle_Kalimdor"
        or (zone == "Zephras Isle" or zone == "Stormwind City") and "ForeverChronicle_Adventures"
        or "ForeverChronicle_EasternKingdoms"
    if hinted[folder] then return end
    hinted[folder] = true
    for _, p in ipairs(ns.packs) do if p.folder == folder then return end end -- loaded: the line just isn't voiced yet
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    local ok, there = pcall(exists or function() return nil end, folder)
    if ok and there then
        ns.pr((L["voice for %s is in \"Chronicle - %s\", which is turned off in the AddOns list."]):format(zone, PACK_TITLE[folder]))
    elseif ok and there == false then
        ns.pr((L["voice for %s needs \"Chronicle - %s\". Install it, then restart the game."]):format(zone, PACK_TITLE[folder]))
    end
end

-- ---------------------------------------------------------------- checking the voices
-- ns.db.checks[key] = "good" or "bad" for every line someone has listened to on purpose (account-wide).
-- Bad lines also go into ns.db.reports, which /lore share sends in.
-- reason: one of the Bad button's fixed choices (voice, high, low, mood, word, text), or nil with a note of your own
function ns.Report(key, note, reason)
    ns.db.reports = ns.db.reports or {}
    table.insert(ns.db.reports, { key = key, note = (note and note ~= "") and note or nil, reason = reason, t = time() })
end

function ns.MarkLine(key, verdict, note, reason)
    if not key then return end
    ns.db.checks = ns.db.checks or {}
    ns.db.checks[key] = verdict
    if verdict == "bad" then
        ns.Report(key, note, reason)
    elseif ns.db.reports then -- marked good after all: drop the earlier report
        for i = #ns.db.reports, 1, -1 do
            if ns.db.reports[i].key == key then table.remove(ns.db.reports, i) end
        end
    end
end

-- How many of a zone's lines are checked: the voice files of a zone sit in a folder named after it.
local function checkStats(zone)
    local folder = zone and zone:gsub("[%s'%-]", ""):lower()
    local total, good, bad = 0, 0, 0
    local checks = ns.db.checks or {}
    for key, e in pairs(ns.audio) do
        local dir = e.f:match("^([^\\]+)\\")
        if not folder or (dir and dir:lower() == folder) then
            total = total + 1
            if checks[key] == "good" then good = good + 1 elseif checks[key] == "bad" then bad = bad + 1 end
        end
    end
    return total, good, bad
end

-- ---------------------------------------------------------------- slash
local toggles = {
    voice = L["voiceover on quest dialogs"],
    stoponclose = L["stop voice when the quest window closes"],
    debug = L["debug messages in chat (quest events and voice lookups)"],
}
local keyFor = { voice = "voice", stoponclose = "stopOnClose", debug = "debug" }

SLASH_CHRONICLE1 = "/lore"
SLASH_CHRONICLE2 = "/chronicle"
SlashCmdList.CHRONICLE = function(msg)
    local cmd = (msg or ""):match("^(%S*)"):lower()
    if cmd == "" then
        ns.Journal.Toggle()
    elseif cmd == "uiprobe" then
        -- developer tool: the window under the mouse, every frame and texture in it, saved for the builder to read
        -- (/reload afterwards writes it to the SavedVariables file)
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        local f = foci and foci[1]
        if not f then ns.pr("uiprobe: nothing under the mouse") return end
        local top, under = f, {}
        while top:GetParent() and top:GetParent() ~= UIParent do
            under[#under + 1] = select(2, pcall(top.GetDebugName, top)) or "?"
            top = top:GetParent()
        end
        local out, n = { under = under, top = select(2, pcall(top.GetDebugName, top)) }, 0
        local function info(r, depth)
            if n >= 600 then return end
            n = n + 1
            local e = { d = depth, name = select(2, pcall(r.GetDebugName, r)), type = r:GetObjectType() }
            pcall(function() e.w, e.h = math.floor(r:GetWidth() + 0.5), math.floor(r:GetHeight() + 0.5) end)
            if e.type == "Texture" then
                pcall(function() e.atlas = r:GetAtlas() end)
                pcall(function() e.file = r:GetTexture() end)
                pcall(function() e.coord = { r:GetTexCoord() } end)
                pcall(function() e.layer = r:GetDrawLayer() end)
            elseif e.type == "FontString" then
                pcall(function() e.font = { r:GetFont() }; e.text = r:GetText() end)
            end
            pcall(function() e.shown = r:IsShown() end)
            out[#out + 1] = e
            if r.GetRegions then for _, x in ipairs({ r:GetRegions() }) do info(x, depth + 1) end end
            if r.GetChildren then for _, x in ipairs({ r:GetChildren() }) do info(x, depth + 1) end end
        end
        info(top, 0)
        ns.db.uiprobe = ns.db.uiprobe or {}
        if #ns.db.uiprobe >= 20 then table.remove(ns.db.uiprobe, 1) end -- a developer's tool: the last few only
        table.insert(ns.db.uiprobe, out)
        ns.pr(("uiprobe: saved %s (%d parts). /reload to write it out."):format(tostring(out.top), n))
    elseif cmd == "campdebug" then
        local ok, err = pcall(ns.Campfire and ns.Campfire.Debug or error, "campfire module not loaded")
        if not ok then ns.pr("campdebug failed: " .. tostring(err)) end
    elseif cmd == "stop" then
        ns.Voice.Stop()
    elseif cmd == "library" and (msg or ""):lower():find("preview", 1, true) then
        ns.pr(ns.Journal.LibraryPreview() and "library preview on: about a third of the books shown as found (nothing is saved). /lore library preview again turns it off."
            or "library preview off.")
    elseif cmd == "replay" then
        if not ns.Voice.Replay() then ns.pr(L["nothing to replay yet."]) end
    elseif cmd == "report" then
        local key = ns.Voice.LastKey()
        if not key then
            ns.pr(L["nothing has played yet. Use /lore report right after a line that sounds wrong."])
        else
            local note = (msg or ""):match("^%S+%s+(.+)$")
            ns.MarkLine(key, "bad", note)
            local e = ns.Voice.Get(key)
            ns.pr((L["reported %s%s. Thanks, it gets fixed in the next build."]):format(e and e.w and (L["%s's line"]):format(e.w) or key,
                note and (" (" .. note .. ")") or ""))
        end
    elseif cmd == "welcome" or cmd == "zone" then
        local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
        if not (ns.Reminder and ns.Reminder.ShowWelcome(zone)) then ns.pr((L["no introduction for %s yet."]):format(tostring(ns.zoneLocal(zone)))) end
    elseif cmd == "checks" then
        local zone = ns.zoneEN(ns.clean(GetRealZoneText()))
        local total, good, bad = checkStats(zone)
        if total > 0 then
            ns.pr((L["%s: %d of %d lines checked (%d good, %d bad)"]):format(ns.zoneLocal(zone), good + bad, total, good, bad))
        end
        total, good, bad = checkStats(nil)
        ns.pr((L["all zones: %d of %d lines checked (%d good, %d bad)"]):format(good + bad, total, good, bad))
        if not ns.settings.checkVoices then
            ns.pr(L["turn on \"Help check the voices\" in the options to get Good and Bad buttons in the speaker window."])
        end
    elseif cmd == "share" then
        ns.Share.Open()
    elseif cmd == "tour" then
        ns.Tour.Start()
    elseif cmd == "options" or cmd == "config" then
        ns.Options.Open()
    elseif toggles[cmd] then
        local k = keyFor[cmd]
        ns.settings[k] = not ns.settings[k]
        ns.pr(toggles[cmd] .. ": " .. (ns.settings[k] and L["|cff44ff44on|r"] or L["|cffff4444off|r"]))
    elseif cmd == "status" then
        local n, missing = 0, 0
        for id, q in pairs(ns.db.quests) do
            n = n + 1
            if q.detail and not ns.audio["q" .. id .. ":detail"] then missing = missing + 1 end
        end
        ns.pr((L["saved data loaded at login: %s"]):format(ns.svLoaded and "yes" or "no"))
        ns.pr((L["%d quests recorded, %d of them not voiced yet, %d completed on this character"]):format(n, missing, #ns.char.journal))
        for _, p in ipairs(ns.packs) do ns.pr((L["  %s: %d lines"]):format(p.folder, p.lines)) end
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            ns.pr((L["memory: %.1f MB"]):format((GetAddOnMemoryUsage(ADDON) or 0) / 1024))
        end
        for cmdName, label in pairs(toggles) do
            ns.pr(("%-12s %s  (%s)"):format(cmdName, ns.settings[keyFor[cmdName]] and L["|cff44ff44on|r"] or L["|cffff4444off|r"], label))
        end
    else
        ns.pr(L["/lore  open the journal"])
        ns.pr(L["/lore stop  stop talking"])
        ns.pr(L["/lore share  send in quests that have no voiceover yet"])
        ns.pr(L["/lore report [what's wrong]  flag the last line (a name said wrong, a bad voice)"])
        ns.pr(L["/lore checks  how many voice lines you have checked here"])
        ns.pr(L["/lore options  settings (voice, volume, alt-tab sound)"])
        ns.pr(L["/lore voice | stoponclose  toggle settings"])
        ns.pr(L["/lore status  what has been recorded and voiced"])
        ns.pr(L["/lore tour  a short tour of Chronicle"])
    end
end

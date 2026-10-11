-- Chronicle / API: a small public playback API for other addons, on the library the voice packs already use.
--
--   local C = LibStub and LibStub("Chronicle-1.0", true)
--   if C and C.apiVersion then C:Play(C:QuestKeys(questID)) end
--
-- Chronicle decides what may play: only lines this character has earned (no recaps of quests not done yet, no
-- epilogue before the zone's story is done, nothing from the other faction), and only lines that have a voice.
-- Texts and voices stay in Chronicle; other addons only ask Chronicle to play them.
local _, ns = ...
local L = ns.L
local api = LibStub and LibStub("Chronicle-1.0", true)
if not api then return end

api.apiVersion = 3

local function completed(id)
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and done or false
end

local function onQuest(id)
    if C_QuestLog.IsOnQuest then
        local ok, on = pcall(C_QuestLog.IsOnQuest, id)
        if ok and on then return true end
    end
    return GetQuestLogIndexByID and (GetQuestLogIndexByID(id) or 0) > 0 or false
end

local function arcZone(id)
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do if a.id == id then return a.zone end end
end

-- may this character hear this line? (spoilers, faction, earned endings)
local function allowed(key)
    if type(key) ~= "string" or not ns.Voice.Get(key) then return false end
    local qid = tonumber(key:match("^q(%d+):"))
    if qid then return onQuest(qid) or completed(qid) end
    local sum = tonumber(key:match("^sum:(%d+)$"))
    if sum then return completed(sum) end
    local arc = key:match("^arc:(.+)$")
    if arc then
        for _, k in ipairs(ns.Journal.ZoneStoryKeys(arcZone(arc) or "")) do if k == key then return true end end
        return false
    end
    local epi = key:match("^epi:(.+)$")
    if epi then
        local zone = epi:match("^(.-)|")
        return ns.Endings and ns.Endings.HasEpilogue(zone) and ns.Endings.EpilogueKey(zone) == epi or false
    end
    local dungeon, boss = key:match("^dend:(.+)|(.+)$")
    if dungeon then return ns.db.lastBoss and ns.db.lastBoss[dungeon] == boss or false end
    return true -- greetings, books, zone welcomes, dungeon welcomes, campfire tales: nothing to spoil
end

local function filter(keys)
    local out = {}
    for _, k in ipairs(keys or {}) do if allowed(k) then out[#out + 1] = k end end
    return out
end

--- Play a key or a list of keys, in order. Keys this character may not hear are skipped. Returns how many will play.
function api:Play(keys)
    if ns.settings.journalOnly then return 0 end
    local list = filter(type(keys) == "table" and keys or { keys })
    if #list == 0 then return 0 end
    ns.Voice.PlayQueue(list, api)
    return #list
end

--- A line's words and how long it plays (seconds), to show the text in time with the voice. nil for a line this
--- character may not hear yet. The words are the ones on screen: the player's own name where the game used it.
function api:LineText(key)
    if not allowed(key) then return nil end
    local entry = ns.Voice.Get(key)
    local text = ns.Voice.Subtitle(key)
    if type(text) ~= "string" or text == "" then return nil end
    return text, entry and entry.d or nil
end

--- Hold the speaker window against your frame while it is open: point, relativePoint, x, y as in SetPoint
--- (DockSpeaker(frame, "TOPLEFT", 10, -10) uses the same point on both). Back to the player's place when your
--- frame hides or you call UndockSpeaker. Returns true when docked.
function api:DockSpeaker(frame, point, relPoint, x, y)
    if type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
    return ns.TalkingHead and ns.TalkingHead.Dock(frame, point, relPoint, x, y) or false
end

function api:UndockSpeaker()
    if ns.TalkingHead then ns.TalkingHead.Undock() end
end

function api:Stop() ns.Voice.Stop() end
function api:IsPlaying() return ns.Voice.IsPlaying() end
function api:PlayingKey() return ns.Voice.PlayingKey() end

--- A quest's lines this character may hear: the giver's text, progress, turn-in and (once done) the narrator's recap.
function api:QuestKeys(questID)
    local id = tonumber(questID)
    if not id then return {} end
    local keys = {}
    for _, kind in ipairs({ "detail", "progress", "complete" }) do
        local k = ns.Voice.QuestKey(id, kind)
        if k then keys[#keys + 1] = k end
    end
    keys[#keys + 1] = "sum:" .. id
    return filter(keys)
end

--- A zone's story so far, as the story map's Play story tells it (introduction, chapters, recaps, epilogue once earned).
function api:ZoneStoryKeys(zone)
    if type(zone) ~= "string" then return {} end
    return filter(ns.Journal.ZoneStoryKeys(zone))
end

--- A dungeon's welcome, and its ending once this account has beaten its last boss.
function api:DungeonKeys(dungeon)
    if type(dungeon) ~= "string" then return {} end
    local keys = { "dng:" .. dungeon }
    local boss = ns.db.lastBoss and ns.db.lastBoss[dungeon]
    if boss then keys[#keys + 1] = "dend:" .. dungeon .. "|" .. boss end
    return filter(keys)
end

--- The chapter a quest belongs to, as the story-so-far panel beside the quest log shows it:
--- title, step, total, recapKey (the line the panel's Play recap plays; nil if this character may not hear it), chapterID.
--- Returns nil when the quest is not part of a chapter.
function api:ChapterOf(questID)
    local id = tonumber(questID)
    if not (id and ns.StoryLog and ns.char) then return nil end
    local arc, step = ns.StoryLog.ChapterOf(id)
    if not arc then return nil end
    local _, key = ns.StoryLog.StorySoFar(arc, step)
    return arc.title, step, #arc.quests, (key and allowed(key)) and key or nil, arc.id
end

-- Settings another addon may read and suggest. A suggestion never changes anything by itself: the player is asked
-- once, and the answer is remembered (asked again only if the addon later suggests something different).
local OPTIONS = {
    mapPins = L["Story chapters on the world map"],
    storyPanel = L["Story panel on the world map"],
    questMarkers = L["Quest givers on the map"],
    logStory = L["The story so far in the quest log"],
}

--- The current value of a setting another addon may ask about (see OPTIONS above), else nil.
function api:GetOption(key)
    if not OPTIONS[key] then return nil end
    return ns.settings[key] and true or false
end

local pending, early, started = {}, {}, false
local function askNext()
    local s = pending[1]
    if not s or (StaticPopup_Visible and StaticPopup_Visible("CHRONICLE_SUGGEST")) then return end
    StaticPopupDialogs.CHRONICLE_SUGGEST = StaticPopupDialogs.CHRONICLE_SUGGEST or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(_, data) ns.Options.Set(data.key, data.value) end,
        OnHide = function() table.remove(pending, 1); C_Timer.After(0.2, askNext) end,
    }
    local text = s.value and L["%s suggests turning on this Chronicle option:\n\n%s"]
        or L["%s suggests turning off this Chronicle option:\n\n%s"]
    StaticPopupDialogs.CHRONICLE_SUGGEST.text = text
    StaticPopup_Show("CHRONICLE_SUGGEST", s.from, OPTIONS[s.key], s)
end

--- Suggest a setting (see OPTIONS above). `from` is your addon's name, shown to the player. Returns true when the
--- player will be asked, false when the setting already has that value, was answered before, or is not one of OPTIONS.
function api:SuggestOption(key, value, from)
    if not OPTIONS[key] or type(from) ~= "string" then return false end
    value = value and true or false
    if not started then -- asked while addons are still loading: ask once the game has started
        early[#early + 1] = { key, value, from }
        return true
    end
    from = from:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 40)
    if api:GetOption(key) == value then return false end
    ns.db.suggested = ns.db.suggested or {}
    local seen = from .. "|" .. key
    if ns.db.suggested[seen] == value then return false end
    ns.db.suggested[seen] = value
    pending[#pending + 1] = { key = key, value = value, from = from }
    askNext()
    return true
end

table.insert(ns.onLogin, function()
    started = true
    for _, e in ipairs(early) do api:SuggestOption(e[1], e[2], e[3]) end
    early = {}
end)

-- callbacks: api:RegisterCallback("PLAYBACK_STARTED" or "PLAYBACK_STOPPED", function(event, key) end)
local callbacks = {}
function api:RegisterCallback(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

local function fire(event, key)
    for _, fn in ipairs(callbacks[event] or {}) do
        local ok, err = pcall(fn, event, key)
        if not ok and ns.settings.debug then ns.pr("debug: api callback error: " .. tostring(err)) end
    end
end

-- every change in what plays goes through Voice.UpdateQuestButton: turn it into started / stopped
local current
table.insert(ns.onLogin, function()
    hooksecurefunc(ns.Voice, "UpdateQuestButton", function()
        local now = ns.Voice.PlayingKey()
        if now == current then return end
        if current then fire("PLAYBACK_STOPPED", current) end
        current = now
        if now then fire("PLAYBACK_STARTED", now) end
    end)
end)

-- Chronicle / DialogueUI: when DialogueUI (by Peterodox) replaces the quest and gossip windows, its own speaker
-- button plays Chronicle's voices, through its public voiceover API (DialogueUIAPI.SetVOProvider). Chronicle still
-- starts the lines by itself as usual; the button replays them, and DialogueUI's own text-to-speech stays out of it.
local _, ns = ...
local L = ns.L

local KIND = { detail = "detail", progress = "progress", completion = "complete" }

-- DialogueUI's names for a page -> Chronicle's voice key (nil when there is no voice for it)
local function keyFor(interactionType, id, arg1, arg2)
    if ns.settings.journalOnly or not ns.settings.voice then return nil end
    if interactionType == "quest" then
        local kind = KIND[arg1 or ""]
        local key = kind and id and ns.Voice.QuestKey(id, kind)
        return key and ns.Voice.Get(key) and key or nil
    elseif interactionType == "gossip" and ns.settings.greetings then
        local npcID = tonumber(id)
        local key = npcID and type(arg2) == "string" and ns.Voice.GreetingKey(npcID, arg2)
        return key and ns.Voice.Get(key) and key or nil
    end
end

local provider = {
    name = "Chronicle",
    doesFileExist = function(...) return keyFor(...) ~= nil end,
    playFile = function(...)
        local key = keyFor(...)
        if not key then return end
        if ns.Voice.PlayingKey() == key or ns.Voice.Waiting(key) then return end -- Chronicle started it already
        -- someone else is talking (the narrator's recap, a greeting): wait in line instead of cutting them off
        if ns.Voice.IsPlaying() then ns.Voice.Enqueue(key) else ns.Voice.Play(key) end
    end,
    -- DialogueUI asks to stop on every page change (greeting -> hand-in -> next quest), which used to silence the
    -- hand-in line Chronicle had just started. A stop within half a second of a line starting is that page change and
    -- is ignored; later (its speaker button) it stops the quest giver's line only, never the narrator (thanks alche,
    -- disgruntledpandas). Closing the quest window is handled by Chronicle itself ("Stop when the window closes").
    stopPlaying = function()
        local k, t = ns.Voice.PlayingKey() or "", ns.Voice.PlayingFor()
        if not t or t < 0.5 then return end
        -- DialogueUI also calls this when its window closes ("TTS Auto Stop", on even with its own TTS off): that is
        -- Chronicle's own option ("Stop when the window closes"), not a stop for the speaker button
        local window = rawget(_G, "DUIQuestFrame")
        if window and not window:IsShown() and not ns.settings.stopOnClose then return end
        if k:match("^q%d") or k:match("^gos:") or k:match("^qg:") then ns.Voice.Skip() end
    end,
    isPlaying = function() return ns.Voice.IsPlaying() end,
    getAutoPlayDelay = function() return 0 end,
}

table.insert(ns.onLogin, function()
    -- DialogueUI takes one voice provider, the last addon to ask. With Chronicle's quest voices off (or Journal only)
    -- it leaves that place free, so another voice addon there (Spoken) keeps speaking (thanks AstroCat). Turning the
    -- voices on again takes effect after a /reload.
    if ns.settings.journalOnly or not ns.settings.voice then return end
    local api = rawget(_G, "DialogueUIAPI")
    if type(api) == "table" and type(api.SetVOProvider) == "function" then
        local ok = pcall(api.SetVOProvider, provider)
        if ns.settings.debug then ns.pr("debug: DialogueUI found, voice provider " .. (ok and "set" or "failed")) end
        -- its speaker button only shows with its own TTS option on: say so once (we don't change its settings)
        local db = rawget(_G, "DialogueUI_DB")
        if ok and type(db) == "table" and not db.TTSEnabled and not ns.db.dialogueUITip and not ns.settings.journalOnly then
            ns.db.dialogueUITip = true
            C_Timer.After(8, function()
                ns.pr(L["works with DialogueUI. Turn on its TTS option to get a speaker button that replays Chronicle's voices (they play by themselves either way)."])
            end)
        end
    end
end)

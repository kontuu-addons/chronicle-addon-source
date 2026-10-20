-- Chronicle / Options: the Options tab of the journal (also /lore options and a right-click on the minimap book). The
-- game's settings window (Esc > Options > AddOns > Chronicle) only has a button that opens it.
local _, ns = ...
local L = ns.L
local O = {}
ns.Options = O

-- the volume of the channel the voices play on (Dialog unless chosen otherwise)
local function volCvar() local _, ch = ns.Voice.Channel() return ch.vol end

-- Chronicle's own page inside the game's settings window (a canvas), with its own checkboxes and sliders. Nothing of
-- Chronicle's is registered with the game's settings system: the window saves those settings when it closes and runs
-- addon code while doing it, which taints the gamepad UI. With a controller every action bar update is then blocked
-- ("blocked action", the game hangs). Here the window has nothing of ours to save; each box saves itself when clicked.
local GREYED = { -- off while "Journal only" is on
    voice = true, recapAfterTurnIn = true, greetings = true, books = true, worldSpeech = true, ghostQuips = true,
    reactions = true, speaker = true, subtitles = true, bigSubtitles = true, skipHeard = true, stopOnClose = true,
    muteGameGreetings = true, ttsFallback = true, checkVoices = true, speakerPlayer = true, questEndsGreeting = true,
}
local ON_CHANGE = {
    minimap = function() ns.Minimap.Update() end,
    minimapFree = function() ns.Minimap.Update() end,
    mapPins = function() if ns.Map then ns.Map.Refresh() end end,
    storyPanel = function() if ns.Map then ns.Map.Refresh() end end,
    showLeft = function() if ns.Map then ns.Map.Refresh() end if ns.Journal then ns.Journal.Refresh() end end,
    hideUnfound = function() if ns.Map then ns.Map.Refresh() end if ns.Journal then ns.Journal.Refresh() end end,
    questMarkers = function() if ns.Map then ns.Map.Refresh() end end,
    muteGameGreetings = function() ns.ApplyGreetingMute() end,
    greetings = function() ns.ApplyGreetingMute() end,
    journalOnly = function() ns.SetJournalOnly(ns.settings.journalOnly) end,
}

-- Under each section's "More options" (folded until opened; the page remembers which are open): the settings most
-- players never need. Keys of checkboxes, or a slider's label.
local MORE = {
    bgVoices = true,
    questEndsGreeting = true, ["Greet me again after"] = true, mixedSure = true, ghostQuips = true, reactions = true,
    lockSpeaker = true, bigSubtitles = true, skipHeard = true, stopOnClose = true, muteGameGreetings = true,
    ttsFallback = true, speakerStays = true,
    chroniclePause = true, zoneRecap = true, logStory = true, tips = true, levelMilestones = true, flightStory = true,
    hideUnfound = true, showLeft = true, questTabs = true, newMarker = true,
    questHints = true, questMarkers = true, minimapFree = true,
    shareNudge = true,
}

local function build()
    local page = CreateFrame("Frame")
    page:Hide()
    -- the game's modern thin scrollbar where the client has it, the classic one otherwise
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, page, "ScrollFrameTemplate")
    if not (ok and scroll and scroll.ScrollBar) then
        if ok and scroll then scroll:Hide() end
        scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

    -- Every option is a row; a section and its rows are a group. layout() puts the groups in one column, or two
    -- when the page is wide (inside the journal), and runs again whenever the page changes size.
    local widgets, groups, cur = {}, {}, nil
    local moreLabel = {}
    for k in pairs(MORE) do moreLabel[L[k]] = true end
    local function newRow(h)
        local r = CreateFrame("Frame", nil, content)
        r:SetHeight(h)
        cur.rows[#cur.rows + 1] = r
        return r
    end
    local function tooltip(owner, title, text)
        owner:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- section headings on the game's ornate header bar (the character window's), plain text where it doesn't exist
    local bar = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-Character-Info-Title")
    local function section(title)
        cur = { rows = {}, title = title }
        groups[#groups + 1] = cur
        local r = newRow(bar and 42 or 30)
        if bar then
            local b = r:CreateTexture(nil, "BACKGROUND")
            b:SetAtlas("UI-Character-Info-Title"); b:SetSize(300, 40); b:SetPoint("LEFT", -6, 0)
            local t = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            t:SetPoint("CENTER", b, "CENTER", 0, 0); t:SetWidth(270); t:SetWordWrap(false)
            t:SetText(title)
        else
            local t = r:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            t:SetPoint("LEFT", 0, 0)
            t:SetText(title)
        end
    end
    -- a checkbox; get and set default to ns.settings[key]
    local function box(key, name, tip, get, set)
        local r = newRow(28)
        r.more = MORE[key]
        local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("LEFT", 10, 0)
        local label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0); label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT"); label:SetWordWrap(false)
        label:SetText(name)
        r.fit = function(w) cb:SetHitRectInsets(0, -(w - 40), 0, 0) end -- the whole row ticks the box
        tooltip(cb, name, tip)
        get = get or function() return ns.settings[key] and true or false end
        set = set or function(v) ns.settings[key] = v end
        cb:SetScript("OnClick", function(self)
            if SOUNDKIT then PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
            set(self:GetChecked() and true or false)
            if ON_CHANGE[key] then ON_CHANGE[key]() end
            O.Refresh()
        end)
        widgets[#widgets + 1] = function()
            cb:SetChecked(get())
            local on = not (GREYED[key] and ns.settings.journalOnly)
            cb:SetEnabled(on)
            local c = on and 1 or 0.5
            label:SetTextColor(c, c, c)
        end
    end
    -- a slider from lo to hi; fmt turns the value into its label, enabled() greys it out. The slider and its value
    -- line up on the right edge of the column.
    local function slider(name, tip, lo, hi, step, get, set, fmt, enabled)
        local r = newRow(32)
        r.more = moreLabel[name] -- (sliders get their label already translated)
        local label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", 14, 0)
        label:SetText(name)
        local s = CreateFrame("Slider", nil, r, "BackdropTemplate")
        s:SetOrientation("HORIZONTAL")
        s:SetSize(130, 17)
        s:SetPoint("RIGHT", r, "RIGHT", -70, 0)
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 } })
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        s:SetMinMaxValues(lo, hi)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
        local value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        value:SetPoint("LEFT", s, "RIGHT", 8, 0); value:SetWidth(62); value:SetJustifyH("LEFT")
        tooltip(s, name, tip)
        s:SetScript("OnValueChanged", function(_, v, userInput)
            value:SetText(fmt(v))
            if userInput then set(v) end
        end)
        widgets[#widgets + 1] = function()
            s:SetValue(get())
            value:SetText(fmt(get()))
            local on = enabled()
            s:SetEnabled(on)
            local c = on and 1 or 0.5
            label:SetTextColor(c, c, c)
            value:SetTextColor(c, c, c)
        end
    end
    local function voicesOn() return not ns.settings.journalOnly end
    -- a row with a button on the right (Test)
    local function action(name, label, tip, fn)
        local r = newRow(30)
        local caption = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        caption:SetPoint("LEFT", 14, 0); caption:SetText(name)
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(100, 22); b:SetPoint("RIGHT", r, "RIGHT", -70, 0); b:SetText(label)
        b:SetScript("OnClick", fn)
        tooltip(b, name, tip)
        widgets[#widgets + 1] = function()
            local on = voicesOn()
            b:SetEnabled(on)
            local c = on and 1 or 0.5
            caption:SetTextColor(c, c, c)
        end
    end

    section(L["General"])
    box("journalOnly", L["Journal only (no voices)"], L["Turns off every voice: quests, greetings, books, NPC speech, recaps and your character. The journal, chapter recaps as text and the map pins stay. You don't need the voice packs for this."])
    slider(L["Voice volume"], L["The game's volume for the sound channel Chronicle plays on (Dialog unless you choose another below)."], 0, 1, 0.05,
        function() return tonumber(GetCVar(volCvar())) or 1 end, function(v) SetCVar(volCvar(), v) end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, voicesOn)
    -- the channel: a button that steps through them (thanks AstroCat)
    do
        local r = newRow(30)
        local caption = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        caption:SetPoint("LEFT", 14, 0); caption:SetText(L["Sound channel"])
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(120, 22); b:SetPoint("RIGHT", r, "RIGHT", -70, 0)
        b:SetScript("OnClick", function()
            local chan, order = ns.Voice.Channel(), ns.Voice.CHANNEL_ORDER
            local i = 1
            for n, id in ipairs(order) do if id == chan then i = n end end
            if ns.Voice.ReleaseDuck then ns.Voice.ReleaseDuck(true) end -- the old channel's music level back first
            ns.settings.channel = order[i % #order + 1]
            O.Refresh()
        end)
        tooltip(b, L["Sound channel"], L["Which of the game's sound channels the voices play on, so you can set their level against the rest with the game's own sliders. Dialog is the usual one."])
        widgets[#widgets + 1] = function()
            local _, ch = ns.Voice.Channel()
            b:SetText(L[ch.name])
            local on = voicesOn()
            b:SetEnabled(on)
            local c = on and 1 or 0.5
            caption:SetTextColor(c, c, c)
        end
    end
    action(L["Test the voices"], L["Test"], L["Plays a short line from the narrator, so you can hear that the voices work and set the volume."],
        function() ns.Voice.Test() end)
    box("duck", L["Lower music while talking"], L["While Chronicle is talking, music and ambient sounds go down to a third, and come back up when it's done."],
        nil, function(v) ns.settings.duck = v; if not v and ns.Voice.ReleaseDuck then ns.Voice.ReleaseDuck(true) end end)
    box("bgVoices", L["Keep talking when alt-tabbed"], L["While Chronicle is talking, the game's Sound in Background is switched on, so the line goes on when you alt-tab, and switched back off when it's done. Other game sounds are heard in the background during that time too."],
        nil, function(v) ns.settings.bgVoices = v; if not v and ns.Voice.ReleaseBackground then ns.Voice.ReleaseBackground() end end)

    section(L["Voices"])
    box("voice", L["Voice quest givers"], L["NPCs speak their quest text when you open a quest."])
    box("recapAfterTurnIn", L["Narrator after turn-in"], L["After you hand in a quest, the narrator tells what it meant for the story."])
    box("greetings", L["Voice NPC greetings"], L["NPCs speak the text of their greeting window when you talk to them."])
    box("questEndsGreeting", L["A quest ends the greeting"], L["When you take a quest after listening to an NPC's welcome for a while, the welcome stops and the quest plays. A quest that opens right away (an auto-accept addon) still lets the greeting finish first. Untick to always let greetings finish."])
    slider(L["Greet me again after"], L["How long before an NPC's greeting plays again when you talk to them. 0 = every time."],
        0, 60, 5, function() return ns.settings.greetCooldown or ns.DEFAULTS.greetCooldown end,
        function(v) ns.settings.greetCooldown = v end,
        function(v) return v == 0 and L["every time"] or (math.floor(v) .. L[" min"]) end,
        function() return ns.settings.greetings and not ns.settings.journalOnly end)
    box("books", L["Read books and letters"], L["The narrator reads the page you open. Turning the page reads the next one."])
    box("worldSpeech", L["NPCs talking in the world"], L["Speech bubbles and yells, like guards, villains and mobs. Only when nothing else is talking, and not the same line twice within two minutes."])
    box("mixedSure", L["Quiet when unsure of man or woman"], L["Some enemies come as both men and women, like Defias and Twilight Thugs. When the addon can't see which one is talking (often in a fight), it picks a voice. Tick to stay quiet instead. Enemy nameplates help it see them."])
    box("ghostQuips", L["A word on the way back"], L["When you run back to your body as a ghost, the narrator now and then says a short line. At most once every 15 minutes."])
    box("reactions", L["My character reacts"], L["Now and then your own character says a short line after handing in a quest, in a voice for your race and gender."])

    section(L["While talking"])
    box("speaker", L["Show the speaker window"], L["The window with the speaker's portrait, subtitles and a stop button that pops up while someone talks. Turn off to only hear the voices. Drag the window to move it."])
    slider(L["Window background"], L["How dark the speaker window's background is: the box of the window, or the shade behind the cinematic subtitles. All the way left shows only the words."],
        0, 1, 0.05, function() return ns.settings.speakerBg or 1 end, function(v) ns.settings.speakerBg = v; if ns.TalkingHead then ns.TalkingHead.Restyle() end end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, function() return ns.settings.speaker and true or false end)
    box("speakerPlayer", L["Player controls"], L["A row at the foot of the speaker window with the time, back, stop, next and replay (in cinematic it shows while the mouse is over it). Untick for a plainer window with just play and replay next to the X."],
        nil, function(v) ns.settings.speakerPlayer = v; if ns.TalkingHead and ns.TalkingHead.Restyle then ns.TalkingHead.Restyle() end end)
    box("speakerStays", L["Keep the speaker window open"], L["After the last line the window stays until you close it, so you can play the line again, go back or mark it. Untick to close it when the voice ends."])
    box("lockSpeaker", L["Lock the speaker window"], L["The speaker window and the cinematic subtitles stay where they are and can't be moved by accident. Untick to drag them again."])
    -- the speaker window's look: the window with the portrait, or cinematic (thanks Alche and Hedge)
    do
        local r = newRow(30)
        local caption = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        caption:SetPoint("LEFT", 14, 0); caption:SetText(L["Speaker window style"])
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(120, 22); b:SetPoint("RIGHT", r, "RIGHT", -70, 0)
        b:SetScript("OnClick", function()
            ns.settings.speakerStyle = ns.settings.speakerStyle == "cinematic" and "window" or "cinematic"
            O.Refresh()
            if ns.Voice and ns.Voice.Test then ns.Voice.Test() end -- see it right away
        end)
        tooltip(b, L["Speaker window style"], L["Window: the speaker's portrait, name and subtitles in a box. Cinematic: no box, just the name and the subtitles in the middle of the screen, like a film. Drag it to move it; each style remembers its own place."])
        widgets[#widgets + 1] = function()
            b:SetText(ns.settings.speakerStyle == "cinematic" and L["Cinematic"] or L["Window"])
            local on = ns.settings.speaker and true or false
            b:SetEnabled(on)
            local c = on and 1 or 0.5
            caption:SetTextColor(c, c, c)
        end
    end
    box("subtitles", L["Subtitles"], L["Show the text of what is being said under the speaker's name."])
    box("bigSubtitles", L["Larger subtitles"], L["Bigger text for the subtitles, a little less of it at a time."])
    box("skipHeard", L["Don't repeat lines I've heard"], L["Lines this character has already heard are not played again automatically (like reopening an unfinished quest). The Listen buttons always replay."])
    box("stopOnClose", L["Stop when the window closes"], L["Off: the NPC finishes talking even if you (or an auto-accept addon) close the window."])
    box("muteGameGreetings", L["Mute the game's greetings"], L["Silences the game's short \"Greetings\" and \"Farewell\" voice clips so they don't talk over Chronicle's voices. Turn off to hear them again."])
    box("ttsFallback", L["Stand-in voice for new lines"], L["New quests and greetings nobody has recorded yet are read by the game's built-in text-to-speech (sounds robotic) until their proper voice is made."])

    section(L["Journal"])
    box("chroniclePause", L["Pause between chapters"], L["\"Tell my chronicle\" stops after each chapter, and its button turns into Continue. Handy when your story gets long."])
    slider(L["Journal size"], L["Makes the journal window bigger or smaller."], 0.8, 1.3, 0.05,
        function() return ns.settings.journalScale or 1 end, function(v) if ns.Journal.SetScale then ns.Journal.SetScale(v) end end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, function() return true end)
    box("zoneIntro", L["Welcome to new zones"], L["The first time you enter a zone, a short introduction to it. Click Listen to hear the narrator read it."])
    box("areaIntros", L["Tell me about new places"], L["The first time you walk into a named place inside a zone, like a village or a ruin, the narrator says a line or two about it. Only when nobody else is talking."])
    box("zoneRecap", L["\"Previously in...\" reminders"], L["After 30 minutes or more away, offers the narrator's recap of what you last did there."])
    box("logStory", L["The story so far in the quest log"], L["When you select a quest that belongs to a chapter, a small panel beside the quest log shows the chapter, your step and a recap of what happened last. Never anything you have not done yet."])
    box("tips", L["Tips in the journal"], L["A short tip about what Chronicle can do, under a chapter in the journal."])
    box("levelMilestones", L["Level milestones"], L["Every 10th level, a short word from the narrator and two or three zones where new stories open up for your level. Nothing plays unless you click Listen."])
    box("flightStory", L["The story on flights"], L["When you take a flight, a small note offers the story so far in the zone you're flying to, or its welcome if you haven't been there. Nothing plays unless you click Listen."])
    box("campfire", L["By the fire"], L["When you sit by a camp fire, a small window counts down the minute until the camp's benefits, offers a campfire tale about the zone while you wait, and then shows what the camp gave you."])
    box("hideUnfound", L["Hide what I haven't found"], L["No hints at all about what you haven't found yet: no chapters still to discover in the journal or on the map, no road ahead, and no empty places or totals in the Library. Everything you have been through stays."])
    box("showLeft", L["Show what's left"], L["Lists the quests still to do in each chapter by name, level and quest giver, and shows where the chapters you haven't found yet start, in the journal and on the map. No story is given away."])
    box("questTabs", L["Side tabs on the quest window"], L["Listen and Recap as tabs on the right side of the quest window, like the journal's, instead of buttons inside it. Handy when other addons put their own buttons there."],
        nil, function(v) ns.settings.questTabs = v; ns.Voice.UpdateQuestButton() end)
    box("newMarker", L["Mark new Forever quests"], L["Shows \"New in WoW: Forever\" on the quest window for quests that were not in original Classic, and whether they have a voice yet."])
    section(L["Map"])
    box("storyPanel", L["Story panel on the world map"], L["A small panel on a zone's map with its chapters and how far you are, with Play story. On the continent map, hover a zone to see how much of its story you've found."])
    box("mapPins", L["Story chapters on the world map"], L["A book at the quest giver of each chapter you have started. Click it to open the chapter."])
    box("questHints", L["Quest hints"], L["For playing with the map's quest objectives off: right-click a quest in the quest log or the tracker and choose Hint, or press Hint beside the story so far, and the map shows where that one quest's objectives are. Everything goes back as it was when you close the map."])
    box("questMarkers", L["Quest givers on the map"], L["Shows ! where a quest giver has quests for you right now (the game itself shows ? where to hand in). Turns itself off while Questie is running, which already shows these."])
    box("minimap", L["Minimap button"], L["Left-click opens the journal, right-click the options. Drag to move it around the minimap."])
    box("minimapFree", L["Detach the button from the minimap"], L["The book button can go anywhere on the screen, for example next to your action bars. Drag it where you want it."])

    section(L["Sharing"])
    box("partySync", L["Share recordings with my party"], L["When you group with other Chronicle players, the text of new quests, greetings, books and NPC speech that has no voice yet is swapped automatically, so it can be voiced in the next release. It includes your character's name (it appears in quest text). Never chat or mail."])
    box("checkVoices", L["Help check the voices"], L["Good and Bad buttons in the speaker window for the line that is playing. Bad asks what was wrong. Your Bad marks are sent in with /lore share, and /lore checks shows how many lines you have checked."])
    box("shareNudge", L["Remind me to share new quests"], L["After you hand in a quest, a small note offers to share the new Forever quests you found that have no voice yet. At most once a day, and only when a few have piled up."])

    -- low-key, under everything: where to find the community and how to support the project. The game can't open a
    -- browser, so a click shows the address ready to copy (Chronicle's own little box, not a game popup).
    local copy = CreateFrame("Frame", nil, page, "BackdropTemplate")
    copy:SetSize(300, 54); copy:SetFrameStrata("DIALOG"); copy:Hide()
    copy:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    copy:SetBackdropColor(0.06, 0.05, 0.04, 0.97); copy:SetBackdropBorderColor(0.85, 0.68, 0.35, 1)
    copy.hint = copy:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); copy.hint:SetPoint("TOP", 0, -7)
    copy.hint:SetText(L["Press Ctrl+C to copy, then paste it in your browser"])
    copy.edit = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
    copy.edit:SetSize(270, 20); copy.edit:SetPoint("BOTTOM", 0, 8); copy.edit:SetAutoFocus(false)
    copy.edit:SetScript("OnEscapePressed", function() copy:Hide() end)
    copy.edit:SetScript("OnEnterPressed", function() copy:Hide() end)
    copy.edit:SetScript("OnEditFocusLost", function() copy:Hide() end)
    copy.edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(copy.url); self:HighlightText() end end)
    local function showLink(anchor, url)
        copy.url = url
        copy:ClearAllPoints(); copy:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
        copy:Show()
        copy.edit:SetText(url); copy.edit:SetFocus(); copy.edit:HighlightText()
    end
    local footer = CreateFrame("Frame", nil, content)
    footer:SetHeight(20)
    local function link(label, url)
        local b = CreateFrame("Button", nil, footer)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); b.text:SetPoint("CENTER")
        b.text:SetText(label .. " |cffbbbbbb" .. url .. "|r")
        b:SetSize(b.text:GetStringWidth() + 8, 18)
        b:SetScript("OnClick", function(self) showLink(self, "https://" .. url) end)
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
        return b
    end
    link("Discord", "discord.gg/NKevry7mY"):SetPoint("RIGHT", footer, "CENTER", -12, 0)
    link("Ko-fi", "ko-fi.com/kontuu"):SetPoint("LEFT", footer, "CENTER", 12, 0)

    -- every option back to how it came, after a yes; the journal, what you've heard and where windows sit stay
    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetText(L["Reset to defaults"]); reset:SetSize(math.max(140, reset:GetFontString():GetStringWidth() + 24), 22)
    reset:SetPoint("TOP", footer, "BOTTOM", 0, -8)
    reset:SetScript("OnClick", function()
        StaticPopupDialogs.CHRONICLE_RESET = StaticPopupDialogs.CHRONICLE_RESET or {
            text = L["Put every Chronicle option back to its default? Your journal, the lines you've heard and where your windows sit are kept."],
            button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function() O.ResetDefaults() end,
        }
        StaticPopup_Show("CHRONICLE_RESET")
    end)

    -- "More options" at the foot of a section: a click folds the rest of its settings open or shut
    local relayout
    local function moreToggle(g)
        local b = CreateFrame("Button", nil, content)
        b:SetHeight(24)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        b.text:SetPoint("LEFT", 14, 0)
        b.update = function(open)
            b.text:SetText((open and "- " or "+ ") .. (open and L["Fewer options"] or L["More options"]))
        end
        b:SetScript("OnClick", function()
            ns.db.optionsMore = ns.db.optionsMore or {}
            ns.db.optionsMore[g.title] = not ns.db.optionsMore[g.title] or nil
            if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            if relayout then relayout() end
        end)
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
        return b
    end
    local lastW
    local function layout(w)
        lastW = w
        local cols = w >= 700 and 2 or 1
        local gap = 36
        local colW = (w - 24 - (cols - 1) * gap) / cols
        local h = {}
        for c = 1, cols do h[c] = 6 end
        for _, g in ipairs(groups) do
            local c = 1 -- the shortest column so far
            for k = 2, cols do if h[k] < h[c] then c = k end end
            local x = 12 + (c - 1) * (colW + gap)
            local main, extra = {}, {}
            for _, r in ipairs(g.rows) do table.insert(r.more and extra or main, r) end
            if #extra > 0 and not g.toggle then g.toggle = moreToggle(g) end
            local open = ns.db.optionsMore and ns.db.optionsMore[g.title]
            local order = {}
            for _, r in ipairs(main) do order[#order + 1] = r end
            if g.toggle then
                order[#order + 1] = g.toggle
                g.toggle.update(open)
                for _, r in ipairs(extra) do
                    r:SetShown(open and true or false)
                    if open then order[#order + 1] = r end
                end
            end
            for _, r in ipairs(order) do
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", content, "TOPLEFT", x, -h[c])
                r:SetWidth(colW)
                if r.fit then r.fit(colW) end
                h[c] = h[c] + r:GetHeight()
            end
            h[c] = h[c] + 12
        end
        local tallest = math.max(unpack(h))
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -tallest - 4)
        footer:SetWidth(w - 24)
        content:SetHeight(tallest + 72)
    end
    relayout = function() if lastW then layout(lastW) end end

    scroll:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        layout(w)
    end)
    layout(600)
    function O.Refresh()
        for _, refresh in ipairs(widgets) do refresh() end
    end
    page:SetScript("OnShow", O.Refresh) -- /lore commands may have changed something meanwhile

    O.page = page

    -- the game's settings window gets only a way to the journal's Options tab; a client without that tab shows the
    -- page here instead
    local stub = CreateFrame("Frame")
    stub:Hide()
    local title = stub:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText("Chronicle")
    local note = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10); note:SetText(L["Chronicle's options are in its journal."])
    local open = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    open:SetSize(200, 24); open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    open:SetText(L["Open Chronicle's options"]); ns.FitButton(open)
    open:SetScript("OnClick", function() O.Open() end)
    stub:SetScript("OnShow", function(self)
        if ns.Journal and ns.Journal.HasOptionsTab and ns.Journal.HasOptionsTab() then return end
        title:Hide(); note:Hide(); open:Hide()
        O.Embed(self)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(stub, "Chronicle")
    Settings.RegisterAddOnCategory(category)
    O.category = category
end

-- Options > Reset to defaults. Journal only stays as the edition or game language set it (Story Journal, non-English).
function O.ResetDefaults()
    local keepJournalOnly = ns.journalEdition or not ns.english
    for k, v in pairs(ns.DEFAULTS) do
        if not (k == "journalOnly" and keepJournalOnly) then ns.settings[k] = v end
    end
    ns.settings.channel, ns.settings.speakerStyle, ns.settings.questTabs = nil, nil, nil
    for _, fn in pairs(ON_CHANGE) do pcall(fn) end
    if ns.Voice.UpdateQuestButton then ns.Voice.UpdateQuestButton() end
    if ns.TalkingHead and ns.TalkingHead.Restyle then ns.TalkingHead.Restyle() end
    if O.Refresh then O.Refresh() end
    ns.pr(L["options are back to their defaults."])
end

-- Change a setting from code (the public API), with the same follow-up as clicking its box.
function O.Set(key, value)
    ns.settings[key] = value
    if ON_CHANGE[key] then ON_CHANGE[key]() end
    if O.page and O.page:IsVisible() and O.Refresh then O.Refresh() end
end

-- The page inside the journal (its Options tab), or inside the game's settings window on a client without that tab.
function O.Embed(host)
    if not O.page then return false end
    if O.page:GetParent() ~= host then O.home = O.page:GetParent() end
    O.page:SetParent(host)
    O.page:ClearAllPoints()
    O.page:SetAllPoints(host)
    O.page:Show()
    if O.Refresh then O.Refresh() end
    return true
end

function O.Unembed(host)
    if not (O.page and O.page:GetParent() == host) then return end
    O.page:Hide()
    -- no settings page to go back to (the options live in the journal): stay put, so the page keeps its size and
    -- needn't lay itself out again (a frame late) the next time it shows
    if not O.home then return end
    -- back where the settings window keeps it
    O.page:SetParent(O.home)
    O.page:ClearAllPoints()
    O.page:SetAllPoints(O.home)
end

-- The game won't open its settings window in combat: wait for the fight to end, then open it.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    O.OpenSettings()
end)

-- The game's settings window on Chronicle's page (the old way, for a journal without an Options tab).
function O.OpenSettings()
    if InCombatLockdown() then
        ns.pr(L["the options open when you leave combat."])
        afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if O.category then Settings.OpenToCategory(O.category:GetID())
    else ns.pr(L["the options panel is not available in this client. Use /lore voice, /lore stoponclose."]) end
    return true
end

-- The options: the journal on its Options tab (also in combat), else the game's settings window.
function O.Open()
    if ns.Journal and ns.Journal.ShowOptions and ns.Journal.ShowOptions() then
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        return true
    end
    return O.OpenSettings()
end

table.insert(ns.onLogin, function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local ok, err = pcall(build)
    if not ok then ns.pr(L["could not create the options panel: "] .. tostring(err)) end
end)

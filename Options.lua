-- Chronicle / Options: the Options tab of the journal (also /lore options and a right-click on the minimap book). The
-- game's settings window (Esc > Options > AddOns > Chronicle) only has a button that opens it.
-- A list of categories on the left with a search over all options, one page of options on the right, and a strip at the
-- foot that says what the option under the mouse does (and why it is greyed out, when it is).
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
    voice = true, recapAfterTurnIn = true, greetings = true, books = true, worldSpeech = true, tongues = true, ghostQuips = true,
    fishingLines = true, rareLines = true, reactions = true, speaker = true, subtitles = true, bigSubtitles = true, skipHeard = true, stopOnClose = true,
    muteGameGreetings = true, ttsFallback = true, checkVoices = true, speakerPlayer = true, questEndsGreeting = true,
    campfire = true,
    duck = true, bgVoices = true, mixedSure = true, areaIntros = true, chroniclePause = true,
}
local ON_CHANGE = {
    minimap = function() ns.Minimap.Update() end,
    minimapFree = function() ns.Minimap.Update() end,
    mapPins = function() if ns.Map then ns.Map.Refresh() end end,
    storyPanel = function() if ns.Map then ns.Map.Refresh() end end,
    showLeft = function() if ns.Map then ns.Map.Refresh() end if ns.Journal then ns.Journal.Refresh() end end,
    hideUnfound = function() if ns.Map then ns.Map.Refresh() end if ns.Journal then ns.Journal.Refresh() end end,
    questMarkers = function() if ns.Map then ns.Map.Refresh() end end,
    questHints = function() if ns.Hint then ns.Hint.Hook() end end, -- the quest log menu's Hint, only once it's on
    -- (nothing of ours is ever in the quest tracker: see Hint.lua)
    muteGameGreetings = function() ns.ApplyGreetingMute() end,
    greetings = function() ns.ApplyGreetingMute() end,
    journalOnly = function() ns.SetJournalOnly(ns.settings.journalOnly) end,
}

local ROW_H = 42
local COL = 220 -- the width of the column of controls
local COL_LABEL = -(COL + 24) -- where a name must end for it
local RAIL_W, EDGE = 178, 16 -- EDGE: the journal's border the rail stays clear of when it reaches into the margin
local GOLD = { 1, 0.82, 0 }
local function hasAtlas(a) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) end

-- the game's red button
local function button(parent, label, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(label)
    return b
end

local function build()
    -- the line under an option's name, by its setting (or the id given with the row); the whole description is the tooltip
    local SHORT = {
        journalOnly = L["No voices at all, just the journal."],
        volume = L["How loud the voices are."],
        channel = L["Which game sound channel the voices use."],
        test = L["Plays a short line from the narrator."],
        ttsFallback = L["Robot voice for lines without a recording."],
        duck = L["Music goes quiet while someone talks."],
        bgVoices = L["Voices keep going when you alt-tab."],
        voice = L["Quest givers speak their quest text."],
        recapAfterTurnIn = L["The narrator sums up after a hand-in."],
        skipHeard = L["Lines you've heard don't replay by themselves."],
        stopOnClose = L["The voice stops when the quest window closes."],
        greetings = L["NPCs speak their greeting."],
        questEndsGreeting = L["Taking a quest stops the greeting."],
        greetCooldown = L["How long before a greeting plays again."],
        muteGameGreetings = L["Mutes the game's own greeting clips."],
        books = L["The narrator reads books and letters."],
        worldSpeech = L["NPC speech bubbles and yells are spoken."],
        mixedSure = L["Stay quiet when man or woman is unclear."],
        reactions = L["Your character says a line after a hand-in."],
        zoneIntro = L["A short introduction to each new zone."],
        areaIntros = L["A line about each new named place."],
        zoneRecap = L["A recap when you come back to a zone."],
        dungeonStory = L["A dungeon's story, its bosses and its end."],
        flightStory = L["A story offer when you take a flight."],
        campfire = L["A campfire tale when you sit by a fire."],
        levelMilestones = L["A word from the narrator every 10th level."],
        ghostQuips = L["A word on the run back to your body."],
        fishingLines = L["A word now and then while you fish."],
        rareLines = L["A famous rare's story once you slay it."],
        bestiary = L["Locals tell of the creatures you slay."],
        tongues = L["Hear languages your character doesn't know."],
        speaker = L["The window that shows who is talking."],
        speakerStyle = L["A window with a portrait, or film subtitles."],
        subtitles = L["The words being said, under the name."],
        speakerBg = L["How dark the window's background is."],
        speakerPlayer = L["Back, stop, next and replay buttons."],
        speakerStays = L["The window stays open after the last line."],
        lockSpeaker = L["The window can't be dragged."],
        journalScale = L["Makes the journal window bigger or smaller."],
        chroniclePause = L["Tell my chronicle stops after each chapter."],
        tips = L["A short tip under each chapter."],
        hideUnfound = L["No hints about what you haven't found."],
        showLeft = L["Lists the quests still to do."],
        logStory = L["The story so far beside the quest log."],
        questTabs = L["Listen and Recap as tabs on the quest window."],
        newMarker = L["Marks quests that are new in WoW: Forever."],
        storyPanel = L["A story panel on the world map."],
        mapPins = L["A book at each chapter's quest giver."],
        questHints = L["Show where a quest's objectives are."],
        questMarkers = L["A ! at quest givers on the map."],
        minimap = L["The book button on the minimap."],
        minimapFree = L["Put the button anywhere on the screen."],
        partySync = L["Swap unvoiced recordings with your party."],
        shareNudge = L["Reminds you to share new quests."],
        checkVoices = L["Good and Bad buttons to check voices."],
    }

    local page = CreateFrame("Frame")
    page:Hide()

    -- ---------------------------------------------------------------- the frame: rail on the left, page on the right
    local rail = CreateFrame("Frame", nil, page)
    rail:SetPoint("TOPLEFT"); rail:SetPoint("BOTTOMLEFT"); rail:SetWidth(RAIL_W)
    local railLine = rail:CreateTexture(nil, "BORDER")
    railLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22); railLine:SetWidth(1)
    railLine:SetPoint("TOPRIGHT"); railLine:SetPoint("BOTTOMRIGHT")

    local main = CreateFrame("Frame", nil, page)
    main:SetPoint("TOPLEFT", rail, "TOPRIGHT", 16, 0); main:SetPoint("BOTTOMRIGHT")

    local header = CreateFrame("Frame", nil, main)
    header:SetHeight(58); header:SetPoint("TOPLEFT", 0, -4); header:SetPoint("TOPRIGHT", 0, -4)
    local title = header:CreateFontString(nil, "ARTWORK", _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 4, -2)
    local summary = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4); summary:SetTextColor(0.7, 0.7, 0.7)

    -- "changed from the default": what the gold strips on the rows and the dots on the categories mean
    local legend = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    legend:SetPoint("TOPRIGHT", -2, -8); legend:SetText(L["Changed from the default"]); legend:Hide()
    local legendMark = header:CreateTexture(nil, "ARTWORK")
    legendMark:SetColorTexture(0.85, 0.68, 0.35, 0.55); legendMark:SetSize(4, 4)
    legendMark:SetPoint("RIGHT", legend, "LEFT", -6, 0); legendMark:Hide()

    -- "Journal only is on": says why a page looks switched off, and the way back
    local banner = CreateFrame("Frame", nil, main)
    banner:SetPoint("TOPLEFT", header, "BOTTOMLEFT"); banner:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints(); bannerBg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)
    local bannerText = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bannerText:SetPoint("LEFT", 10, 0); bannerText:SetText(L["The voices are off while Journal only is on."])
    local bannerButton = button(banner, L["Turn voices on"], 120)
    bannerButton:SetPoint("RIGHT", -8, 0)
    bannerButton:SetScript("OnClick", function() O.Set("journalOnly", false) end)


    -- the game's modern thin scrollbar where the client has it, the classic one otherwise
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, main, "ScrollFrameTemplate")
    if not (ok and scroll and scroll.ScrollBar) then
        if ok and scroll then scroll:Hide() end
        scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -26, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(500, 10)
    scroll:SetScrollChild(content)

    -- ---------------------------------------------------------------- rows
    -- Every option is a row (label on the left, its control on the right), kept under the category it belongs to.
    -- with{} sets how the next row depends on others: after = indented, needs the option on; needs = needs it on;
    -- unless = off while that one is on; jo = off while Journal only is on.
    local cats, cur, pending = {}, nil, nil
    local labelOf = {}
    local function with(o) pending = o end
    local function color(fs, on) local c = on and 1 or 0.5; fs:SetTextColor(c, c, c) end
    local function hover(r, on)
        r.hl:SetShown(on)
        if on and r.more then
            GameTooltip:SetOwner(r, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetText(r.name, 1, 1, 1)
            GameTooltip:AddLine(r.tip, nil, nil, nil, true)
            GameTooltip:Show()
        elseif GameTooltip:IsOwned(r) then
            GameTooltip:Hide()
        end
    end
    local function hook(frame, r) -- a control inside the row: hovering it counts as hovering the row
        frame:HookScript("OnEnter", function() hover(r, true) end)
        frame:HookScript("OnLeave", function() hover(r, false) end)
    end
    -- the first sentence of a description: up to a full stop (or ! or ?) followed by a capital letter or a quote
    local function firstSentence(text)
        local i = 1
        while true do
            local a = text:find('[%.!%?]%s+[%u"%(]', i)
            if not a then return text end
            if a > 1 and text:sub(a - 1, a - 1):match("%S") then return text:sub(1, a) end
            i = a + 1
        end
    end
    local function newRow(h, key, name, tip)
        local r = CreateFrame("Frame", nil, content)
        r:SetHeight(ROW_H); r:EnableMouse(true)
        r.opt, pending = pending or {}, nil
        r.indent = r.opt.after and 22 or 0
        r.key, r.name, r.tip = key, name, tip
        r.search = (name .. " " .. tip):lower()
        local brief = SHORT[key or r.opt.setting or r.opt.id]
        local first = brief or firstSentence(tip)
        r.subText, r.more = first, brief ~= nil or first ~= tip or #first > 90 -- more than the line shows: the whole text in a tooltip
        r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false); r.label:SetText(name)
        r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false); r.sub:SetText(first)
        r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3); r.sub:SetPoint("TOPRIGHT", r.label, "BOTTOMRIGHT", 0, -3)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.9, 0.7, 0.09); r.hl:Hide()
        r.mark = r:CreateTexture(nil, "ARTWORK") -- shown by O.Refresh: this option is not at its default
        r.mark:SetColorTexture(0.85, 0.68, 0.35, 0.55); r.mark:SetSize(4, 4)
        r.mark:SetPoint("LEFT", 3, 0); r.mark:Hide()

        r:SetScript("OnEnter", function() hover(r, true) end)
        r:SetScript("OnLeave", function() hover(r, false) end)
        if key then labelOf[key] = name end
        r:Hide()
        cur.rows[#cur.rows + 1] = r
        return r
    end
    -- a heading on the game's ornate header bar (the character window's, as under the journal's zone headings);
    -- gold text with a line under it where the bar doesn't exist. Not a setting: the search skips it.
    local function heading(parent, text)
        local r = CreateFrame("Frame", nil, parent)
        r.isHead = true
        if hasAtlas("UI-Character-Info-Title") then
            r:SetHeight(46)
            local bar = r:CreateTexture(nil, "BACKGROUND")
            bar:SetAtlas("UI-Character-Info-Title"); bar:SetSize(300, 40); bar:SetPoint("LEFT", -6, -1)
            local t = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            t:SetPoint("CENTER", bar, "CENTER", 0, 0); t:SetWidth(270); t:SetWordWrap(false); t:SetText(text)
        else
            r:SetHeight(36)
            local t = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            t:SetPoint("BOTTOMLEFT", 6, 7); t:SetText(text)
            local line = r:CreateTexture(nil, "BORDER")
            line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3); line:SetHeight(1)
            line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
        end
        r:Hide()
        return r
    end
    local function category(name, summaryText, voices)
        cur = { name = name, lname = name:lower(), summary = summaryText, voices = voices, rows = {} }
        cur.resultHead = heading(content, name) -- the category's name above its hits in a search
        cats[#cats + 1] = cur
    end

    -- a checkbox; get and set default to ns.settings[key]. The whole row ticks it.
    local function box(key, name, tip, get, set)
        local r = newRow(30, key, name, tip)
        local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        cb:SetSize(26, 26); cb:SetPoint("LEFT", 10 + r.indent, 0)
        local label = r.label
        label:SetPoint("TOPLEFT", 40 + r.indent, -7); label:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -7)
        get = get or function() return ns.settings[key] and true or false end
        set = set or function(v) ns.settings[key] = v end
        cb:SetScript("OnClick", function(self)
            if SOUNDKIT then PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
            set(self:GetChecked() and true or false)
            if ON_CHANGE[key] then ON_CHANGE[key]() end
            O.Refresh()
        end)
        r:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" and cb:IsEnabled() then cb:Click() end end)
        hook(cb, r)
        r.refresh = function(on) cb:SetChecked(get()); cb:SetEnabled(on); color(label, on) end
    end
    -- a slider from lo to hi; fmt turns the value into its label, enabled() greys it out
    local function slider(name, tip, lo, hi, step, get, set, fmt, enabled)
        local r = newRow(34, nil, name, tip)
        r.enabled = enabled
        local value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", -12, 0); value:SetWidth(50); value:SetJustifyH("RIGHT")
        local okSlider, s = pcall(CreateFrame, "Slider", nil, r, "MinimalSliderTemplate")
        if not (okSlider and s) then
            s = CreateFrame("Slider", nil, r, "BackdropTemplate")
            s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
                edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 3, right = 3, top = 6, bottom = 6 } })
            s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        end
        s:SetOrientation("HORIZONTAL")
        s:SetSize(COL - 50 - 10, 19); s:SetPoint("RIGHT", value, "LEFT", -10, 0)
        s:SetMinMaxValues(lo, hi)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
        local label = r.label
        label:SetPoint("TOPLEFT", 40 + r.indent, -7); label:SetPoint("TOPRIGHT", r, "TOPRIGHT", COL_LABEL, -7)
        s:SetScript("OnValueChanged", function(_, v, userInput)
            value:SetText(fmt(v))
            if userInput then set(v) end
        end)
        hook(s, r)
        r.refresh = function(on)
            s:SetValue(get()); value:SetText(fmt(get()))
            s:SetEnabled(on); s:SetAlpha(on and 1 or 0.5); color(label, on); color(value, on)
        end
    end
    local function voicesOn() return not ns.settings.journalOnly end
    -- a row with a button on the right (Test)
    local function action(name, label, tip, fn)
        local r = newRow(34, nil, name, tip)
        r.enabled = voicesOn
        local caption = r.label
        caption:SetPoint("TOPLEFT", 40 + r.indent, -7); caption:SetPoint("TOPRIGHT", r, "TOPRIGHT", COL_LABEL, -7)
        local b = button(r, label, COL)
        b:SetPoint("RIGHT", -12, 0)
        b:SetScript("OnClick", fn)
        hook(b, r)
        r.refresh = function(on) b:SetEnabled(on); color(caption, on) end
    end
    -- a row with a dropdown on the right: items are { value, label }, get() the chosen value, set(value) to change it
    local function choice(key, name, tip, items, get, set, enabled)
        local r = newRow(34, key, name, tip)
        r.enabled = enabled
        local dd = CreateFrame("DropdownButton", nil, r, "WowStyle1DropdownTemplate")
        dd:SetWidth(COL); dd:SetPoint("RIGHT", -12, 0)
        dd:SetupMenu(function(_, root)
            for _, it in ipairs(items) do
                root:CreateRadio(it[2], function() return get() == it[1] end, function() set(it[1]); O.Refresh() end)
            end
        end)
        local label = r.label
        label:SetPoint("TOPLEFT", 40 + r.indent, -7); label:SetPoint("TOPRIGHT", r, "TOPRIGHT", COL_LABEL, -7)
        hook(dd, r) -- hooked, not set: the dropdown keeps its own hover look
        r.refresh = function(on)
            dd:GenerateMenu() -- shows the current choice, also after a change from elsewhere (/lore, Reset)
            dd:SetEnabled(on); color(label, on)
        end
    end

    -- ---------------------------------------------------------------- the options, by category
    category(L["Sound"], L["How the voices sound, and when the music steps back."], false)
    box("journalOnly", L["Journal only (no voices)"], L["Turns off every voice: quests, greetings, books, NPC speech, recaps and your character. The journal, chapter recaps as text and the map pins stay. You don't need the voice packs for this."])
    with({ jo = true, id = "volume" })
    slider(L["Voice volume"], L["The game's volume for the sound channel Chronicle plays on (Dialog unless you choose another below)."], 0, 1, 0.05,
        function() return tonumber(GetCVar(volCvar())) or 1 end, function(v) SetCVar(volCvar(), v) end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, voicesOn)
    -- the channel the voices play on (thanks AstroCat)
    do
        local channels = {}
        for _, id in ipairs(ns.Voice.CHANNEL_ORDER) do channels[#channels + 1] = { id, L[ns.Voice.CHANNELS[id].name] } end
        with({ jo = true, id = "channel", changed = function() return (ns.settings.channel or "Dialog") ~= "Dialog" end })
        choice(nil, L["Sound channel"], L["Which of the game's sound channels the voices play on, so you can set their level against the rest with the game's own sliders. Dialog is the usual one."],
            channels, function() return (ns.Voice.Channel()) end,
            function(id)
                if id == ns.Voice.Channel() then return end
                if ns.Voice.ReleaseDuck then ns.Voice.ReleaseDuck(true) end -- the old channel's music level back first
                ns.settings.channel = id
            end, voicesOn)
    end
    with({ id = "test" })
    action(L["Test the voices"], L["Test"], L["Plays a short line from the narrator, so you can hear that the voices work and set the volume."],
        function() ns.Voice.Test() end)
    box("ttsFallback", L["Stand-in voice for new lines"], L["New quests and greetings nobody has recorded yet are read by the game's built-in text-to-speech (sounds robotic) until their proper voice is made."])
    box("duck", L["Lower music while talking"], L["While Chronicle is talking, music and ambient sounds go down to a third, and come back up when it's done."],
        nil, function(v) ns.settings.duck = v; if not v and ns.Voice.ReleaseDuck then ns.Voice.ReleaseDuck(true) end end)
    box("bgVoices", L["Keep talking when alt-tabbed"], L["While Chronicle is talking, the game's Sound in Background is switched on, so the line goes on when you alt-tab, and switched back off when it's done. Other game sounds are heard in the background during that time too."],
        nil, function(v) ns.settings.bgVoices = v; if not v and ns.Voice.ReleaseBackground then ns.Voice.ReleaseBackground() end end)

    category(L["Voices"], L["Who speaks, and which lines play."], true)
    box("voice", L["Voice quest givers"], L["NPCs speak their quest text when you open a quest."])
    box("recapAfterTurnIn", L["Narrator after turn-in"], L["After you hand in a quest, the narrator tells what it meant for the story."])
    box("skipHeard", L["Don't repeat lines I've heard"], L["Lines this character has already heard are not played again automatically (like reopening an unfinished quest). The Listen buttons always replay."])
    box("stopOnClose", L["Stop when the window closes"], L["Off: the NPC finishes talking even if you (or an auto-accept addon) close the window."])
    box("greetings", L["Voice NPC greetings"], L["NPCs speak the text of their greeting window when you talk to them."])
    with({ after = "greetings" })
    box("questEndsGreeting", L["A quest ends the greeting"], L["When you take a quest after listening to an NPC's welcome for a while, the welcome stops and the quest plays. A quest that opens right away (an auto-accept addon) still lets the greeting finish first. Untick to always let greetings finish."])
    with({ after = "greetings", jo = true, setting = "greetCooldown" })
    slider(L["Greet me again after"], L["How long before an NPC's greeting plays again when you talk to them. 0 = every time."],
        0, 60, 5, function() return ns.settings.greetCooldown or ns.DEFAULTS.greetCooldown end,
        function(v) ns.settings.greetCooldown = v end,
        function(v) return v == 0 and L["every time"] or (math.floor(v) .. L[" min"]) end,
        function() return ns.settings.greetings and not ns.settings.journalOnly end)
    with({ after = "greetings" })
    box("muteGameGreetings", L["Mute the game's greetings"], L["Silences the game's short \"Greetings\" and \"Farewell\" voice clips so they don't talk over Chronicle's voices. Turn off to hear them again."])
    box("books", L["Read books and letters"], L["The narrator reads the page you open. Turning the page reads the next one."])
    box("worldSpeech", L["NPCs talking in the world"], L["Speech bubbles and yells, like guards, villains and mobs. Only when nothing else is talking, and not the same line twice within two minutes."])
    with({ after = "worldSpeech" })
    box("mixedSure", L["Quiet when unsure of man or woman"], L["Some enemies come as both men and women, like Defias and Twilight Thugs. When the addon can't see which one is talking (often in a fight), it picks a voice. Tick to stay quiet instead. Enemy nameplates help it see them."])
    box("tongues", L["Languages you don't know"], L["NPCs who speak a language your character doesn't know, like the Scarlet Crusade to the Horde or Blackrock orcs to the Alliance, stay silent. Tick to hear them say the scrambled words the game shows."])
    box("reactions", L["My character reacts"], L["Now and then your own character says a short line after handing in a quest, in a voice for your race and gender."])

    category(L["Narrator"], L["When the narrator speaks up on their own."], false)
    box("zoneIntro", L["Welcome to new zones"], L["The first time you enter a zone, a short introduction to it. Click Listen to hear the narrator read it."])
    box("areaIntros", L["Tell me about new places"], L["The first time you walk into a named place inside a zone, like a village or a ruin, the narrator says a line or two about it. Only when nobody else is talking."])
    box("zoneRecap", L["\"Previously in...\" reminders"], L["After 30 minutes or more away, offers the narrator's recap of what you last did there."])
    box("dungeonStory", L["Dungeon stories"], L["Walking into a dungeon or raid, a note offers its story. The first time you beat one of its bosses, the narrator tells who it was, and after the last one how the story ends. Nothing plays unless you click Listen."])
    box("flightStory", L["The story on flights"], L["When you take a flight, a small note offers the story so far in the zone you're flying to, or its welcome if you haven't been there. Nothing plays unless you click Listen."])
    box("campfire", L["By the fire"], L["Near a camp fire, a short note says when the zone has a tale you haven't heard. Sit down, and the narrator tells the next one."])
    box("levelMilestones", L["Level milestones"], L["Every 10th level, a short word from the narrator and two or three zones where new stories open up for your level. Nothing plays unless you click Listen."])
    box("ghostQuips", L["A word on the way back"], L["When you run back to your body as a ghost, the narrator now and then says a short line. At most once every 15 minutes."])
    box("fishingLines", L["A word while fishing"], L["When you cast your fishing line, the narrator now and then says a short line. At most once every 15 minutes."])
    box("rareLines", L["Famous rares"], L["The first time you slay a famous rare that has a real story, the narrator tells it once the fight is over."])
    box("bestiary", L["Bestiary"], L["The first time you slay one of a land's notable creatures (the Burning Blade, kobolds, scorpids...), someone who lives there tells what they know of them, and more as you slay more. A small note offers it once the fight is over. Nothing plays unless you click Listen."])

    category(L["Speaker window"], L["The window that shows who is talking."], true)
    box("speaker", L["Show the speaker window"], L["The window with the speaker's portrait, subtitles and a stop button that pops up while someone talks. Turn off to only hear the voices. Drag the window to move it."])
    with({ needs = "speaker", id = "speakerStyle", changed = function() return ns.settings.speakerStyle == "cinematic" end })
    choice(nil, L["Speaker window style"], L["Window: the speaker's portrait, name and subtitles in a box. Cinematic: no box, just the name and the subtitles in the middle of the screen, like a film. Drag it to move it; each style remembers its own place."],
        { { "window", L["Window"] }, { "cinematic", L["Cinematic"] } },
        function() return ns.settings.speakerStyle == "cinematic" and "cinematic" or "window" end,
        function(style)
            ns.settings.speakerStyle = style
            if ns.Voice and ns.Voice.Test then ns.Voice.Test() end -- see it right away
        end, function() return ns.settings.speaker and true or false end)
    with({ needs = "speaker", jo = true, id = "subtitles", changed = function() return not ns.settings.subtitles or (ns.settings.bigSubtitles and true or false) end })
    choice(nil, L["Subtitles"], L["The text of what is being said, under the speaker's name. Large: bigger text, a little less of it at a time."],
        { { "off", L["Off"] }, { "normal", L["Normal"] }, { "large", L["Large"] } },
        function() return not ns.settings.subtitles and "off" or ns.settings.bigSubtitles and "large" or "normal" end,
        function(v) ns.settings.subtitles = v ~= "off"; ns.settings.bigSubtitles = v == "large" end,
        function() return ns.settings.speaker and true or false end)
    with({ needs = "speaker", setting = "speakerBg" })
    slider(L["Window background"], L["How dark the speaker window's background is: the box of the window, or the shade behind the cinematic subtitles. All the way left shows only the words."],
        0, 1, 0.05, function() return ns.settings.speakerBg or 1 end, function(v) ns.settings.speakerBg = v; if ns.TalkingHead then ns.TalkingHead.Restyle() end end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, function() return ns.settings.speaker and true or false end)
    with({ needs = "speaker" })
    box("speakerPlayer", L["Player controls"], L["A row at the foot of the speaker window with the time, back, stop, next and replay (in cinematic it shows while the mouse is over it). Untick for a plainer window with just play and replay next to the X."],
        nil, function(v) ns.settings.speakerPlayer = v; if ns.TalkingHead and ns.TalkingHead.Restyle then ns.TalkingHead.Restyle() end end)
    with({ needs = "speaker" })
    box("speakerStays", L["Keep the speaker window open"], L["After the last line the window stays until you close it, so you can play the line again, go back or mark it. Untick to close it when the voice ends."])
    with({ needs = "speaker" })
    box("lockSpeaker", L["Lock the speaker window"], L["The speaker window and the cinematic subtitles stay where they are and can't be moved by accident. Untick to drag them again."])

    category(L["Journal & quests"], L["The journal, the quest log and the quest window."], false)
    with({ setting = "journalScale" })
    slider(L["Journal size"], L["Makes the journal window bigger or smaller."], 0.8, 1.3, 0.05,
        function() return ns.settings.journalScale or 1 end, function(v) if ns.Journal.SetScale then ns.Journal.SetScale(v) end end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end, function() return true end)
    box("chroniclePause", L["Pause between chapters"], L["\"Tell my chronicle\" stops after each chapter, and its button turns into Continue. Handy when your story gets long."])
    box("tips", L["Tips in the journal"], L["A short tip about what Chronicle can do, under a chapter in the journal."])
    box("hideUnfound", L["Hide what I haven't found"], L["No hints at all about what you haven't found yet: no chapters still to discover in the journal or on the map, no road ahead, and no empty places or totals in the Library. Everything you have been through stays."])
    with({ unless = "hideUnfound" })
    box("showLeft", L["Show what's left"], L["Lists the quests still to do in each chapter by name, level and quest giver, and shows where the chapters you haven't found yet start, in the journal and on the map. It also names the places and creatures you haven't found yet. No story is given away."])
    box("logStory", L["The story so far in the quest log"], L["When you select a quest that belongs to a chapter, a small panel beside the quest log shows the chapter, your step and a recap of what happened last. Never anything you have not done yet."])
    box("questTabs", L["Side tabs on the quest window"], L["Listen and Recap as tabs on the right side of the quest window, like the journal's, instead of buttons inside it. Handy when other addons put their own buttons there."],
        nil, function(v) ns.settings.questTabs = v; ns.Voice.UpdateQuestButton() end)
    box("newMarker", L["Mark new Forever quests"], L["Shows \"New in WoW: Forever\" on the quest window for quests that were not in original Classic, and whether they have a voice yet."])

    category(L["Map & minimap"], L["What Chronicle adds to the maps."], false)
    box("storyPanel", L["Story panel on the world map"], L["A small panel on a zone's map with its chapters and how far you are, with Play story. On the continent map, hover a zone to see how much of its story you've found."])
    box("mapPins", L["Story chapters on the world map"], L["A book at the quest giver of each chapter you have started. Click it to open the chapter."])
    box("questHints", L["Quest hints"], L["For playing with the map's quest objectives off: right-click a quest in the quest log and choose Hint, or press Hint beside the story so far, and the map shows where that one quest's objectives are. Everything goes back as it was when you close the map."])
    box("questMarkers", L["Quest givers on the map"], L["Shows ! where a quest giver has quests for you right now (the game itself shows ? where to hand in). Turns itself off while Questie is running, which already shows these."])
    box("minimap", L["Minimap button"], L["Left-click opens the journal, right-click the options. Drag to move it around the minimap."])
    with({ after = "minimap" })
    box("minimapFree", L["Detach the button from the minimap"], L["The book button can go anywhere on the screen, for example next to your action bars. Drag it where you want it."])

    category(L["Sharing"], L["Helping to bring voices to more quests."], false)
    box("partySync", L["Share recordings with my party"], L["When you group with other Chronicle players, the text of new quests, greetings, books and NPC speech that has no voice yet is swapped automatically, so it can be voiced in the next release. It includes your character's name (it appears in quest text). Never chat or mail."])
    box("shareNudge", L["Remind me to share new quests"], L["After you hand in a quest, a small note offers to share the new Forever quests you found that have no voice yet. At most once a day, and only when a few have piled up."])
    with({ needs = "speaker" })
    box("checkVoices", L["Help check the voices"], L["Good and Bad buttons in the speaker window for the line that is playing. Bad asks what was wrong. Your Bad marks are sent in with /lore share, and /lore checks shows how many lines you have checked."])

    -- ---------------------------------------------------------------- what a row may do, and the view
    local function gate(r)
        local o = r.opt
        if ((r.key and GREYED[r.key]) or o.jo) and ns.settings.journalOnly then return false, L["Turned off by Journal only."] end
        local need = o.after or o.needs
        if need and not ns.settings[need] then return false, (L["Needs \"%s\"."]):format(labelOf[need] or need) end
        if o.unless and ns.settings[o.unless] then return false, (L["Not while \"%s\" is on."]):format(labelOf[o.unless] or o.unless) end
        if r.enabled and not r.enabled() then return false end
        return true
    end

    -- not at its default: a checkbox by its default in ns.DEFAULTS, a slider by the setting named in with{ setting = },
    -- a dropdown by its own changed() in with{}. The volume and the buttons have no default of their own.
    local function changed(r)
        local o = r.opt
        if o.changed then return o.changed() end
        local k = r.key or o.setting
        if not k then return false end
        if k == "journalOnly" and (ns.journalEdition or not ns.english) then return false end -- set by the edition or the game language
        local def, cur = ns.DEFAULTS[k], ns.settings[k]
        if type(def) == "number" then return math.abs((tonumber(cur) or def) - def) > 0.001 end
        return (cur and true or false) ~= (def and true or false)
    end

    local sel = tonumber(ns.db and ns.db.optionsCat) or 1
    if not cats[sel] then sel = 1 end
    local railButtons = {}

    -- the rows of the open category, or the hits of a search, one under the other
    local function layout()
        local w = content:GetWidth()
        for _, c in ipairs(cats) do
            c.resultHead:Hide()
            for _, r in ipairs(c.rows) do r:Hide() end
        end
        local list, hits = {}, 0
        if O.query then
            for _, c in ipairs(cats) do
                local found = {}
                for _, r in ipairs(c.rows) do
                    if not r.isHead and (r.search:find(O.query, 1, true) or c.lname:find(O.query, 1, true)) then found[#found + 1] = r end
                end
                if #found > 0 then
                    list[#list + 1] = c.resultHead
                    for _, r in ipairs(found) do list[#list + 1] = r end
                    hits = hits + #found
                end
            end
        else
            for _, r in ipairs(cats[sel].rows) do list[#list + 1] = r end
        end
        local y = 4
        for _, r in ipairs(list) do
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); r:SetWidth(w)
            r:Show()

            y = y + r:GetHeight()
        end
        content:SetHeight(y + 8)
        return hits
    end
    local function updateLegend()
        local any = cats[sel].mod
        if O.query then
            any = false
            for _, c in ipairs(cats) do any = any or c.mod end
        end
        legend:SetShown(any and true or false); legendMark:SetShown(any and true or false)
    end
    local function updateBanner()
        local show = ns.settings and ns.settings.journalOnly and (O.query or cats[sel].voices)
        banner:SetHeight(show and 34 or 1); banner:SetShown(show and true or false)
    end
    local function refreshView()
        local hits = layout()
        if O.query then
            title:SetText(L["Search"])
            summary:SetText(hits > 0 and (L["%d options"]):format(hits) or (L["No option matches \"%s\"."]):format(O.query))
        else
            title:SetText(cats[sel].name); summary:SetText(cats[sel].summary)
        end
        for i, b in ipairs(railButtons) do
            local on = i == sel and not O.query
            b.bar:SetShown(on)
            if on then b.label:SetTextColor(1, 0.9, 0.5) else b.label:SetTextColor(0.85, 0.85, 0.85) end
        end
        updateBanner()
        updateLegend()
        scroll:SetVerticalScroll(0)
    end

    -- ---------------------------------------------------------------- the rail: search, categories, links, reset
    local okSearch, search = pcall(CreateFrame, "EditBox", nil, rail, "SearchBoxTemplate")
    if not (okSearch and search) then
        search = CreateFrame("EditBox", nil, rail, "InputBoxTemplate")
        search:SetAutoFocus(false)
    end
    search:SetSize(RAIL_W - 32, 22); search:SetPoint("TOPLEFT", 16, -14)
    if search.Instructions then search.Instructions:SetText(L["Search options"]) end
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local q = text ~= "" and text:lower() or nil
        if q ~= O.query then O.query = q; refreshView() end
    end)

    local function pick(i)
        sel = i
        if ns.db then ns.db.optionsCat = i end
        if (search:GetText() or "") ~= "" then search:SetText("") end
        O.query = nil
        refreshView()
        O.Refresh()
    end
    for i, c in ipairs(cats) do
        local b = CreateFrame("Button", nil, rail)
        b:SetHeight(34); b:SetPoint("TOPLEFT", 0, -48 - (i - 1) * 36); b:SetPoint("TOPRIGHT", -6, -48 - (i - 1) * 36)
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 0.9, 0.7, 0.08); b.hl:Hide()
        b.bar = b:CreateTexture(nil, "BACKGROUND", nil, 1) -- the open category sits on the ornate bar
        if hasAtlas("UI-Character-Info-Title") then b.bar:SetAtlas("UI-Character-Info-Title") else b.bar:SetColorTexture(1, 0.9, 0.7, 0.12) end
        b.bar:SetPoint("TOPLEFT", -6, 0); b.bar:SetPoint("BOTTOMRIGHT", 6, 0); b.bar:Hide()
        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetColorTexture(0.85, 0.68, 0.35, 0.6); b.dot:SetSize(4, 4); b.dot:SetPoint("RIGHT", -14, 0); b.dot:Hide()
        b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        b.label:SetPoint("LEFT", 22, 0); b.label:SetPoint("RIGHT", -10, 0); b.label:SetJustifyH("LEFT"); b.label:SetText(c.name)
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function()
            if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            pick(i)
        end)
        railButtons[i] = b
    end

    -- low-key, at the foot of the rail: where to find the community and how to support the project. The game can't
    -- open a browser, so a click shows the address ready to copy (Chronicle's own little box, not a game popup).
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
        copy:ClearAllPoints(); copy:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6)
        copy:Show()
        copy.edit:SetText(url); copy.edit:SetFocus(); copy.edit:HighlightText()
    end
    local links = {}
    local function link(label, url, y)
        local b = CreateFrame("Button", nil, rail)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); b.text:SetPoint("LEFT")
        b.text:SetText(label)
        b:SetSize(RAIL_W - 32, 16); b:SetPoint("BOTTOMLEFT", 16, y)
        links[#links + 1] = { b, y }
        b:SetScript("OnClick", function(self) showLink(self, "https://" .. url) end)
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    end
    link("Ko-fi", "ko-fi.com/kontuu", 50)
    link("Discord", "discord.gg/RPJFk8VAhn", 68)

    -- every option back to how it came, after a yes; the journal, what you've heard and where windows sit stay
    local reset = button(rail, L["Reset to defaults"], RAIL_W - 32)
    reset:SetPoint("BOTTOMLEFT", 16, 14)
    reset:SetScript("OnClick", function()
        StaticPopupDialogs.CHRONICLE_RESET = StaticPopupDialogs.CHRONICLE_RESET or {
            text = L["Put every Chronicle option back to its default? Your journal, the lines you've heard and where your windows sit are kept."],
            button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function() O.ResetDefaults() end,
        }
        StaticPopup_Show("CHRONICLE_RESET")
    end)

    -- the journal leaves a margin on the left for its portrait (top left); under the portrait the page uses it: the
    -- rail reaches out by n, the search box stays where it was. In the game's settings window n is 0.
    function O.setExtra(n)
        rail:ClearAllPoints()
        rail:SetPoint("TOPLEFT", -n, 0); rail:SetPoint("BOTTOMLEFT", -n, 0); rail:SetWidth(RAIL_W + n)
        search:ClearAllPoints(); search:SetPoint("TOPLEFT", n + 16, -14)
        reset:ClearAllPoints(); reset:SetPoint("BOTTOMLEFT", n + 16, 14)
        for _, l in ipairs(links) do l[1]:ClearAllPoints(); l[1]:SetPoint("BOTTOMLEFT", n + 16, l[2]) end
    end
    scroll:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        layout()
    end)
    function O.Refresh()
        for i, c in ipairs(cats) do
            c.mod = false
            for _, r in ipairs(c.rows) do
                if r.refresh then
                    local on, why = gate(r)
                    r.why = why
                    r.sub:SetText(why and ("|cffffa050" .. why .. "|r") or r.subText)
                    r.refresh(on)
                    local m = changed(r)
                    r.mark:SetShown(m and true or false)
                    if m then c.mod = true end
                end
            end
            railButtons[i].dot:SetShown(c.mod)
        end
        updateBanner()
        updateLegend()
    end
    page:SetScript("OnShow", O.Refresh) -- /lore commands may have changed something meanwhile
    refreshView()

    O.page = page

    -- the game's settings window gets only a way to the journal's Options tab; a client without that tab shows the
    -- page here instead
    local stub = CreateFrame("Frame")
    stub:Hide()
    local stubTitle = stub:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    stubTitle:SetPoint("TOPLEFT", 16, -16); stubTitle:SetText("Chronicle")
    local note = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", stubTitle, "BOTTOMLEFT", 0, -10); note:SetText(L["Chronicle's options are in its journal."])
    local open = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    open:SetSize(200, 24); open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    open:SetText(L["Open Chronicle's options"]); ns.FitButton(open)
    open:SetScript("OnClick", function() O.Open() end)
    stub:SetScript("OnShow", function(self)
        if ns.Journal and ns.Journal.HasOptionsTab and ns.Journal.HasOptionsTab() then return end
        stubTitle:Hide(); note:Hide(); open:Hide()
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


-- in the journal the page reaches into its left margin, under the portrait; in the game's settings window it doesn't
local embed = O.Embed
function O.Embed(host)
    local ok = embed(host)
    if ok and O.setExtra then
        -- as far as the journal's margin goes (the host's own left offset), keeping the window's edge free
        local _, _, _, x = host:GetPoint(1)
        local margin = host:GetParent() == _G.ChronicleJournalFrame and math.max(0, (x or 0) - EDGE) or 0
        O.setExtra(margin)
    end
    return ok
end

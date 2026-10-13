-- Chronicle: Story so far
-- Select a quest in the quest log that belongs to a chapter, and a small panel beside the log tells where you are in
-- that story: the chapter, your step, and the recap of the last step you finished (or the chapter's introduction).
-- Only what you have already done is shown, never what comes next.
local _, ns = ...
local L = ns.L

local panel, shownFor

local function selectedQuestID()
    local id = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    if (not id or id == 0) and GetQuestLogSelection and GetQuestLogTitle then
        local idx = GetQuestLogSelection()
        if idx and idx > 0 then id = select(8, GetQuestLogTitle(idx)) end
    end
    return (id and id > 0) and id or nil
end

-- the chapter a quest belongs to, for this character's faction
-- quest -> the chapters it is in (built once; the quest log asks four times a second while it is open)
local inArcs
local function chapterOf(id)
    if not inArcs then
        inArcs = {}
        for _, arc in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
            for i, qid in ipairs(arc.quests or {}) do
                local list = inArcs[qid] or {}
                list[#list + 1] = { arc, i }
                inArcs[qid] = list
            end
        end
    end
    local side = (UnitFactionGroup("player") or ""):sub(1, 1)
    for _, hit in ipairs(inArcs[id] or {}) do
        local arc = hit[1]
        if not (arc.side and side ~= "" and arc.side ~= side) then return arc, hit[2] end
    end
end

-- what to tell: the recap of the last finished step before this one, else the chapter's introduction
local function storySoFar(arc, step)
    local quests = (ns.Lore and ns.Lore.quests) or {}
    for i = step - 1, 1, -1 do
        local qid = arc.quests[i]
        if ns.char.done[qid] and quests[qid] and quests[qid].summary then
            return quests[qid].summary, "sum:" .. qid
        end
    end
    return arc.intro, "arc:" .. arc.id
end

ns.StoryLog = { ChapterOf = chapterOf, StorySoFar = storySoFar } -- the same answers for the public API

local function create(host)
    local p = CreateFrame("Frame", nil, ns.Overlay(host), "BackdropTemplate")
    p:SetWidth(260)
    -- docked to the quest log's right edge like an extra page of it; drag it elsewhere, right-click (or double-click)
    -- to dock it again
    -- the classic quest log has room at its right edge; the map's quest log ends at its scrollbar, so there the page
    -- docks outside the whole map window, level with the quest page
    local classic = host == QuestLogFrame
    local edge = classic and host or (WorldMapFrame or host)
    local function dock()
        local pos = ns.settings.storyLogPos3
        p:ClearAllPoints()
        if pos then
            p:SetPoint("TOPLEFT", edge, "TOPRIGHT", pos[1], pos[2])
        elseif classic then
            p:SetPoint("TOPLEFT", host, "TOPRIGHT", -33, -14)
        else
            p:SetPoint("LEFT", edge, "RIGHT", 2, 0)
            p:SetPoint("TOP", host, "TOP", 0, 0)
        end
    end
    dock()
    p:EnableMouse(true); p:SetMovable(true); p:SetClampedToScreen(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local dx, dy = self:GetLeft() - edge:GetRight(), self:GetTop() - edge:GetTop()
        -- dropped close to its place beside the window: it snaps back into the dock
        local x0, y0 = 2, (host:GetTop() or 0) - (edge:GetTop() or 0)
        if classic then x0, y0 = -33, -14 end
        if math.abs(dx - x0) < 25 and math.abs(dy - y0) < 25 then
            ns.settings.storyLogPos3 = nil
        else
            ns.settings.storyLogPos3 = { dx, dy }
        end
        dock()
    end)
    p:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" or (button == "LeftButton" and p.lastClick and GetTime() - p.lastClick < 0.35) then
            ns.settings.storyLogPos3 = nil; dock()
        end
        p.lastClick = GetTime()
    end)
    -- parchment, like the quest log's own page
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    p:SetBackdropColor(0.9, 0.84, 0.7, 1)
    p:SetBackdropBorderColor(0.36, 0.26, 0.12, 1)
    local paper = p:CreateTexture(nil, "BORDER")
    paper:SetPoint("TOPLEFT", 2, -2); paper:SetPoint("BOTTOMRIGHT", -2, 2)
    -- the very paper and frame of WoW: Forever's quest page beside it, where the client has them
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
    if hasAtlas and C_Texture.GetAtlasInfo("QuestDetailsBackgrounds") then
        paper:SetAtlas("QuestDetailsBackgrounds")
        paper:ClearAllPoints(); paper:SetPoint("TOPLEFT", 3, -3); paper:SetPoint("BOTTOMRIGHT", -3, 3)
        p:SetBackdropColor(0, 0, 0, 0); p:SetBackdropBorderColor(0, 0, 0, 0)
        if C_Texture.GetAtlasInfo("QuestLog-frame") then
            local rim = p:CreateTexture(nil, "ARTWORK")
            rim:SetAtlas("QuestLog-frame"); rim:SetAllPoints(p)
        end
    elseif paper:SetTexture("Interface\\QuestFrame\\QuestBG") then paper:SetTexCoord(0, 0.586, 0, 0.65) else paper:Hide() end
    local INK, SOFT, TITLE = { 0.18, 0.11, 0.04 }, { 0.27, 0.18, 0.07 }, { 0.08, 0.05, 0.02 }
    -- the quest page's own colours beside it: its body text and its near-black titles
    if GetMaterialTextColors then
        local ok, text, title = pcall(GetMaterialTextColors, "Parchment")
        if ok and type(text) == "table" and text[1] then INK = { text[1], text[2], text[3] } end
        if ok and type(title) == "table" and title[1] then TITLE = { title[1], title[2], title[3] } end
    end
    p.head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.head:SetPoint("TOPLEFT", 14, -12); p.head:SetPoint("RIGHT", -14, 0); p.head:SetJustifyH("LEFT")
    p.head:SetTextColor(SOFT[1], SOFT[2], SOFT[3]); p.head:SetShadowOffset(0, 0)
    p.head:SetText(L["The story so far"])
    p.title = p:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
    p.title:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -4); p.title:SetPoint("RIGHT", -14, 0); p.title:SetJustifyH("LEFT")
    p.title:SetTextColor(TITLE[1], TITLE[2], TITLE[3]); p.title:SetShadowColor(0, 0, 0, 0.35); p.title:SetShadowOffset(1, -1)
    p.step = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.step:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3); p.step:SetJustifyH("LEFT")
    p.step:SetTextColor(SOFT[1], SOFT[2], SOFT[3]); p.step:SetShadowOffset(0, 0)
    p.body = p:CreateFontString(nil, "OVERLAY", "QuestFont")
    p.body:SetPoint("TOPLEFT", p.step, "BOTTOMLEFT", 0, -8)
    p.body:SetJustifyH("LEFT"); p.body:SetSpacing(2)
    p.body:SetTextColor(INK[1], INK[2], INK[3]); p.body:SetShadowOffset(0, 0)
    p.body:SetWidth(232); p.body:SetWordWrap(true) -- the whole recap, not one line cut short
    if p.body.SetMaxLines then p.body:SetMaxLines(0) end
    p.play = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.play:SetSize(110, 20); ns.FitButton(p.play)
    p.play:SetPoint("TOPLEFT", p.body, "BOTTOMLEFT", 0, -8)
    p.play:SetScript("OnClick", function(b)
        if ns.Voice.Owner() == b then ns.Voice.Stop() elseif b.key then ns.Voice.Play(b.key, b) end
    end)
    p.journal = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.journal:SetSize(80, 20); ns.FitButton(p.journal)
    p.journal:SetPoint("LEFT", p.play, "RIGHT", 4, 0)
    p.journal:SetText(L["Journal"])
    p.journal:SetScript("OnClick", function(b) if b.chapter then ns.Journal.Open(b.chapter) end end)
    -- Quest hints (option): where this quest's objectives are, on the map
    p.hint = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.hint:SetSize(60, 20); ns.FitButton(p.hint)
    p.hint:SetPoint("LEFT", p.journal, "RIGHT", 4, 0)
    p.hint:SetText(L["Hint"])
    p.hint:SetScript("OnClick", function(b) if b.quest and ns.Hint then ns.Hint.Show(b.quest) end end)
    p:Hide()
    return p
end

local function update()
    if not panel then return end
    local id = ns.settings.logStory and ns.char and selectedQuestID()
    local arc, step = nil, nil
    if id then arc, step = chapterOf(id) end
    if not arc then panel:Hide(); shownFor = nil; return end
    local text, key = storySoFar(arc, step)
    if shownFor ~= id then
        shownFor = id
        panel.title:SetText(arc.title)
        panel.step:SetText((L["Step %d of %d"]):format(step, #arc.quests))
        panel.body:SetText(text or "")
        panel.play.key = key
        panel.journal.chapter = "arc:" .. arc.id
        local voiced = key and ns.Voice.Get(key) and not ns.settings.journalOnly
        panel.play:SetShown(voiced and true or false)
        panel.journal:ClearAllPoints()
        if voiced then panel.journal:SetPoint("LEFT", panel.play, "RIGHT", 4, 0)
        else panel.journal:SetPoint("TOPLEFT", panel.body, "BOTTOMLEFT", 0, -8) end
        local function fit()
            panel.body:SetHeight(panel.body:GetStringHeight())
            panel:SetHeight(panel.head:GetStringHeight() + panel.title:GetStringHeight() + panel.step:GetStringHeight()
                + panel.body:GetStringHeight() + 70)
        end
        fit()
        C_Timer.After(0, fit) -- the text's height is only known for sure once it has been laid out
    end
    panel.play:SetText(ns.Voice.Owner() == panel.play and L["Stop"] or L["Play recap"])
    panel.hint.quest = id
    panel.hint:SetShown(ns.Hint and ns.Hint.Available(id) or false)
    panel:Show()
end

table.insert(ns.onLogin, function()
    local host = QuestLogFrame or (QuestMapFrame and QuestMapFrame.DetailsFrame)
    if not host then return end
    panel = create(host)
    -- the log changes selection in many ways (clicks, keys, other addons): a light check while it is open
    local watcher = CreateFrame("Frame", nil, panel:GetParent())
    local wait = 0
    watcher:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.25
        update()
    end)
    panel:GetParent().onClose = function() shownFor = nil end -- the quest log closed (no hook on the game's window)
end)

-- Chronicle / TalkingHead: who is speaking. The NPC's 3D model (talking), name, title and what the line is about,
-- with progress and a stop button. The narrator gets a book. Drag to move; position is remembered.
local _, ns = ...
local L = ns.L
local T = {}
ns.TalkingHead = T

local TALK = 60 -- the "talk" emote animation
local f, current, startedAt, currentKey
local lingerToken = 0 -- a newer show or hide cancels a pending "hide after the line ended"
local pages, page -- subtitle pages of the current line: { text, at = share of the line where the page starts }

local PAGE_CHARS = 250 -- about six lines in the talking head

-- Whole sentences per page; a sentence longer than a page is split between words.
local function paginate(text)
    local pageChars = (ns.settings and ns.settings.bigSubtitles) and 170 or PAGE_CHARS -- bigger text, shorter pages
    local pieces = {}
    for s in text:gmatch("[^%.!%?]+[%.!%?]*[\"']?%s*") do
        if #s <= pageChars then
            pieces[#pieces + 1] = s
        else
            local cur = ""
            for w in s:gmatch("%S+%s*") do
                if #cur + #w > pageChars and cur ~= "" then pieces[#pieces + 1] = cur; cur = "" end
                cur = cur .. w
            end
            if cur ~= "" then pieces[#pieces + 1] = cur end
        end
    end
    if #pieces == 0 then pieces[1] = text end
    local out, cur, before = {}, "", 0
    local total = #text
    local function push()
        local t = cur:gsub("%s+$", "")
        if t ~= "" then out[#out + 1] = { text = t, at = before / total } end
        before = before + #cur
        cur = ""
    end
    for _, s in ipairs(pieces) do
        if #cur + #s > pageChars and cur ~= "" then push() end
        cur = cur .. s
    end
    push()
    return out
end

local function npcInfo(name)
    local npcs = ns.Lore and ns.Lore.npcs
    return npcs and npcs[name]
end

-- "Quest: Deaths in the Family", "Recap: ...", "Chapter: ..."
local function about(key)
    if not key then return "" end
    local kind, id = key:match("^(%a+):?(.*)$")
    local function questTitle(qid)
        qid = tonumber(qid)
        local q = qid and ns.db.quests[qid]
        if q and q.title then return q.title end
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
        return ok and t or nil
    end
    if kind == "gos" or kind == "qg" then
        return "Greeting"
    elseif kind == "bio" then
        return "Who's who"
    elseif kind == "book" or kind == "bookr" then
        return "Reading"
    elseif kind == "react" then
        return ""
    elseif key:match("^q%d+") then
        local t = questTitle(key:match("^q(%d+)"))
        return t and (L["Quest: %s"]):format(t) or ""
    elseif kind == "sum" then
        local t = questTitle(id)
        return t and (L["Recap: %s"]):format(t) or L["Recap"]
    elseif kind == "arc" then
        for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
            if a.id == id then return (L["Chapter: %s"]):format(a.title) end
        end
        return L["Chapter"]
    end
    return ""
end

local function create()
    f = CreateFrame("Frame", "ChronicleTalkingHead", UIParent, "BackdropTemplate") -- named so the game remembers where it was dragged
    f:SetSize(430, 104)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.07, 0.055, 0.04, 0.92)
    f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    -- held by its top right corner: the window grows downwards with long subtitles and narrows to the left when
    -- slim, so the X stays in one place (thanks timmeh)
    local function pin()
        local right, top = f:GetRight(), f:GetTop()
        if not (right and top) then return end
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * s, top * s)
        ns.settings.speakerPos = { "TOPRIGHT", "BOTTOMLEFT", right * s, top * s }
    end
    f:SetScript("OnDragStart", function(self) if not self.dockedTo then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not self.dockedTo then pin() end
    end)
    local pos = ns.settings.speakerPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and type(pos[3]) == "number" and type(pos[4]) == "number" then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 170) end
    pin() -- older saved places (and the default) were held by another corner

    -- portrait window: dark inset with a thin gold rim
    f.window = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.window:SetSize(90, 90)
    f.window:SetPoint("TOPLEFT", 7, -7)
    f.window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f.window:SetBackdropColor(0.02, 0.02, 0.03, 1)
    f.window:SetBackdropBorderColor(0.6, 0.48, 0.25, 0.8)

    f.model = CreateFrame("PlayerModel", nil, f.window)
    f.model:SetPoint("TOPLEFT", 1, -1); f.model:SetPoint("BOTTOMRIGHT", -1, 1)
    f.model:SetScript("OnAnimFinished", function(self)
        if current then pcall(self.SetAnimation, self, TALK) end -- keep talking until the line ends
    end)
    f.icon = f.window:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 8, -8); f.icon:SetPoint("BOTTOMRIGHT", -8, 8)

    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.window, "TOPRIGHT", 12, -6); f.name:SetPoint("RIGHT", -50, 0)
    f.name:SetJustifyH("LEFT"); f.name:SetWordWrap(false)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4); f.title:SetPoint("RIGHT", -12, 0)
    f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false); f.title:SetTextColor(0.8, 0.75, 0.65)
    f.about = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.about:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8); f.about:SetPoint("RIGHT", -12, 0)
    f.about:SetJustifyH("LEFT"); f.about:SetWordWrap(false)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.applySize = function()
        f.sub:SetFontObject((ns.settings and ns.settings.bigSubtitles) and GameFontHighlightLarge or GameFontHighlight)
    end
    f.sub:SetPoint("TOPLEFT", f.about, "BOTTOMLEFT", 0, -6); f.sub:SetPoint("RIGHT", -14, 0)
    f.sub:SetJustifyH("LEFT"); f.sub:SetJustifyV("TOP"); f.sub:SetSpacing(2)
    if f.sub.SetMaxLines then f.sub:SetMaxLines(6) end
    f.sub:SetTextColor(0.92, 0.88, 0.8)

    f.progress = CreateFrame("StatusBar", nil, f)
    f.progress:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 109, 10); f.progress:SetPoint("RIGHT", -14, 0)
    f.progress:SetHeight(5)
    f.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    f.progress:SetStatusBarColor(0.85, 0.68, 0.35)
    f.progress:SetMinMaxValues(0, 1)
    local bg = f.progress:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.08)

    -- "Help check the voices": Good / Bad for the line that is playing (Bad asks what was wrong)
    local function markButton(label, verdict, r, g, b)
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(44, 16)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("CENTER"); btn.text:SetText(label)
        btn.color = { r, g, b }
        btn.verdict = verdict
        btn:SetScript("OnClick", function()
            local key = currentKey
            if not key then return end
            if verdict == "bad" then
                StaticPopupDialogs.CHRONICLE_BADLINE = StaticPopupDialogs.CHRONICLE_BADLINE or {
                    text = L["What was wrong with this line? (optional)"],
                    button1 = L["Report"], button2 = CANCEL,
                    hasEditBox = true, maxLetters = 120, timeout = 0, whileDead = true, hideOnEscape = true,
                    OnAccept = function(self, k)
                        local box = self.editBox or self.EditBox
                        ns.MarkLine(k, "bad", box and box:GetText())
                        T.UpdateMarks()
                    end,
                    EditBoxOnEnterPressed = function(self)
                        local p = self:GetParent()
                        StaticPopupDialogs.CHRONICLE_BADLINE.OnAccept(p, p.data)
                        p:Hide()
                    end,
                }
                StaticPopup_Show("CHRONICLE_BADLINE", nil, nil, key)
            else
                ns.MarkLine(key, "good")
                T.UpdateMarks()
            end
        end)
        return btn
    end
    f.good = markButton(L["Good"], "good", 0.2, 0.55, 0.28)
    f.bad = markButton(L["Bad"], "bad", 0.7, 0.22, 0.18)
    f.bad:SetPoint("BOTTOMRIGHT", -12, 5)
    f.good:SetPoint("RIGHT", f.bad, "LEFT", -4, 0)

    local stop = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    stop:SetSize(26, 26); stop:SetPoint("TOPRIGHT", 1, 1)
    -- click: next line in the queue (the last one closes it); shift-click: stop everything
    local function skip()
        if not current then T.Hide(true) return end -- the line already ended (kept up for Good / Bad)
        if IsShiftKeyDown() then ns.Voice.Stop() else ns.Voice.Skip() end
    end
    stop:SetScript("OnClick", skip)
    -- replay: the last line again (also /lore replay)
    local replay = CreateFrame("Button", nil, f)
    replay:SetSize(16, 16); replay:SetPoint("RIGHT", stop, "LEFT", 0, 0)
    replay:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    replay:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    replay:SetScript("OnClick", function() ns.Voice.Replay() end)
    replay:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L["Replay"], 1, 1, 1); GameTooltip:Show()
    end)
    replay:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.replay = replay
    -- right-click anywhere on the window does the same, wherever the X ends up (thanks timmeh)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then skip() end end)

    f:SetScript("OnUpdate", function(self)
        if current and startedAt then
            local done = math.min(1, (GetTime() - startedAt) / math.max(current.d or 1, 0.1))
            self.progress:SetValue(done)
            if pages and pages[page + 1] and done >= pages[page + 1].at then
                page = page + 1
                self.sub:SetText(pages[page].text)
            end
        end
    end)
    f:Hide()
end

-- Without subtitles there is little to show: a slim window with only the name, who they are and what the line is
-- about, no portrait (thanks alche). With subtitles, the full window with the talking model.
local function layout(compact)
    if f.compact == compact then return end
    f.compact = compact
    f.window:SetShown(not compact)
    f.name:ClearAllPoints()
    if compact then
        f.name:SetPoint("TOPLEFT", 12, -8)
        f:SetWidth(320)
        f.progress:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    else
        f.name:SetPoint("TOPLEFT", f.window, "TOPRIGHT", 12, -6)
        f:SetWidth(430)
        f.progress:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 109, 10)
    end
    f.name:SetPoint("RIGHT", -50, 0)
end

-- The Good / Bad buttons: shown with the setting on; the one already chosen for this line is filled in.
function T.UpdateMarks()
    if not f then return end
    local on = ns.settings.checkVoices and currentKey ~= nil
    local mark = on and ns.db.checks and ns.db.checks[currentKey]
    for _, btn in ipairs({ f.good, f.bad }) do
        btn:SetShown(on)
        local c, chosen = btn.color, mark == btn.verdict
        btn:SetBackdropColor(c[1], c[2], c[3], chosen and 1 or 0.15)
        btn:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    f.progress:SetPoint("RIGHT", on and -112 or -14, 0)
end

local function showModel(who)
    local info = npcInfo(who)
    local m = f.model
    pcall(m.ClearModel, m)
    local ok = false
    local shown = UnitExists("npc") and UnitName("npc")
    if canaccessvalue and shown and not canaccessvalue(shown) then shown = nil end
    if shown and shown == who then
        ok = pcall(m.SetUnit, m, "npc")
    end
    if not ok and info and info.d then ok = pcall(m.SetDisplayInfo, m, info.d) end
    if not ok and info and info.id then ok = pcall(m.SetCreature, m, info.id) end
    if ok then
        pcall(m.SetPortraitZoom, m, 0.9)
        pcall(m.SetCamDistanceScale, m, 1)
        pcall(m.SetAnimation, m, TALK)
        m:Show(); f.icon:Hide()
    else
        m:Hide()
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); f.icon:Show()
    end
    return info
end

function T.Show(entry, key)
    if not f then create() end
    lingerToken = lingerToken + 1
    current, startedAt, currentKey = entry, GetTime(), key
    local subtitle = ns.settings.subtitles and ns.Voice.Subtitle(key) or nil
    if ns.Speech and ns.Speech.Bubbled(key) then subtitle = nil end -- the bubble over their head has the words
    local compact = not (subtitle and subtitle ~= "")
    layout(compact)
    local who = (entry.w and entry.w ~= "") and entry.w or "Narrator"  -- the voice data names these two in English
    f.name:SetText(who == "Narrator" and L["Narrator"] or who)
    if who == "You" then
        pcall(f.model.ClearModel, f.model)
        local ok = pcall(f.model.SetUnit, f.model, "player")
        if ok then
            pcall(f.model.SetPortraitZoom, f.model, 0.9)
            pcall(f.model.SetAnimation, f.model, TALK)
            f.model:Show(); f.icon:Hide()
        end
        f.name:SetText(ns.clean(UnitName("player")) or L["You"])
        f.title:SetText(L["Your character"])
    elseif who == "Narrator" then
        f.model:Hide()
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); f.icon:Show()
        -- recaps and chapters tell the story; quest text from a poster or an item, books and plaques are read out
        local k = key or ""
        local zone = k:match("^zone:(.+)") or k:match("^dng:(.+)") or k:match("^epi:([^|]+)") or k:match("^dend:([^:|]+)")
        local tale = k:match("^tale:(.+)")
        local attId, att = k:match("^att:(.+)"), nil
        local bioId = tonumber(k:match("^bio:(%d+)$") or "")
        for name, e in pairs(bioId and ns.Lore and ns.Lore.npcs or {}) do
            if e.id == bioId then att = name end -- the narrator on someone: their name as the title
        end
        for _, a in ipairs(attId and ns.Lore and ns.Lore.attunements or {}) do
            if a.id == attId then att = (L["The road to %s"]):format(a.title) end
        end
        f.title:SetText(att or tale and (L["By the fire: %s"]):format(ns.zoneLocal(tale)) or zone and ns.zoneLocal(zone)
            or (k:match("^sum:") or k:match("^arc:")) and L["The story so far"]
            or k:match("^ghost:") and L["On the way back"]
            or k:match("^lvl:(%d+)") and (L["Level %d"]):format(tonumber(k:match("^lvl:(%d+)")))
            or (k:match("^book") and L["Read aloud"]) or L["Read aloud from the page"])
    elseif compact then
        local info = npcInfo(who)
        local bits = {}
        if info and info.t then bits[#bits + 1] = "<" .. info.t .. ">" end
        if info and info.r then bits[#bits + 1] = info.r end
        f.title:SetText(table.concat(bits, "  "))
    else
        local info = showModel(who)
        local bits = {}
        if info and info.t then bits[#bits + 1] = "<" .. info.t .. ">" end
        if info and info.r then bits[#bits + 1] = info.r end
        f.title:SetText(table.concat(bits, "  "))
    end
    f.about:SetText(about(key))
    -- subtitles: long text is shown a page at a time, in step with the voice
    local text = subtitle
    if not compact then
        pages = paginate(text:gsub("[\r\n]+", " "))
        page = 1
        -- stage directions like <Kaltunk looks you over.> aren't spoken; show them grey
        for _, p in ipairs(pages) do p.text = p.text:gsub("<([^<>]+)>", "|cff9d9d9d<%1>|r") end
        -- size the frame once for the tallest page, so it doesn't jump while talking
        f.applySize()
        local tallest = 0
        for _, p in ipairs(pages) do
            f.sub:SetText(p.text)
            tallest = math.max(tallest, f.sub:GetStringHeight())
        end
        f.sub:SetText(pages[1].text)
        f.sub:Show()
        f:SetHeight(math.max(104, 74 + tallest + 22))
    else
        pages = nil
        f.sub:SetText("")
        f.sub:Hide()
        f:SetHeight(76)
    end
    f.progress:SetValue(0)
    T.UpdateMarks()
    f:Show()
end

-- Another addon's frame can hold the speaker window while it is open (the API's DockSpeaker): placed against that
-- frame, not draggable, and back where the player put it as soon as that frame closes or lets go. The player's
-- saved place is never touched.
local dockHooked = {}
local function backToSaved()
    local pos = ns.settings.speakerPos
    f:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and type(pos[3]) == "number" and type(pos[4]) == "number" then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 170) end
end

function T.Dock(target, point, relPoint, x, y)
    if type(target) ~= "table" or not target.GetObjectType then return false end
    if not f then create() end
    f.dockedTo = target
    f:ClearAllPoints()
    local ok = pcall(f.SetPoint, f, point or "TOPLEFT", target, relPoint or point or "TOPLEFT", x or 0, y or 0)
    if not ok then f.dockedTo = nil; backToSaved(); return false end
    if not dockHooked[target] and target.HookScript then
        dockHooked[target] = true
        target:HookScript("OnHide", function(self) if f.dockedTo == self then T.Undock() end end)
    end
    return true
end

function T.Undock()
    if not (f and f.dockedTo) then return end
    f.dockedTo = nil
    backToSaved()
end

function T.Hide(now)
    lingerToken = lingerToken + 1
    -- checking the voices: stay up a few seconds after the line ends, so a short line can still be marked
    if not now and f and f:IsShown() and currentKey and ns.settings.checkVoices then
        current, startedAt, pages = nil, nil, nil
        f.progress:SetValue(1)
        local token = lingerToken
        C_Timer.After(6, function()
            if token == lingerToken then T.Hide(true) end
        end)
        return
    end
    current, startedAt, pages, currentKey = nil, nil, nil, nil
    if f then f:Hide() end
end

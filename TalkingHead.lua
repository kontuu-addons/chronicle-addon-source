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

local SUB_LINES = 4 -- the words always have room for this many lines; longer text goes in pages of that size
local PAD = 10 -- the window's margin
local FOOT = 22 -- the height of the row at the foot

-- Whole sentences per page, as many as fit (fits(text) measures them in the window, so bigger text makes more
-- pages); a sentence longer than a page is split between words.
local function paginate(text, fits)
    local pieces = {}
    for s in text:gmatch("[^%.!%?]+[%.!%?]*[\"']?%s*") do
        if fits(s) then
            pieces[#pieces + 1] = s
        else
            local cur = ""
            for w in s:gmatch("%S+%s*") do
                if cur ~= "" and not fits(cur .. w) then pieces[#pieces + 1] = cur; cur = "" end
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
        if cur ~= "" and not fits(cur .. s) then push() end
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
    elseif kind == "area" then
        return id:match(":(.+)$") or ""
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
    ns.PadClose("ChronicleTalkingHead") -- with a controller, its back button (Escape) closes it; the voice goes on
    f:SetSize(430, 104)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.07, 0.055, 0.04, 0.92)
    f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    -- held by its top right corner: it changes size only between the full and the compact window, to the left and
    -- downwards, so the X stays in one place (thanks timmeh)
    local function pin()
        local right, top = f:GetRight(), f:GetTop()
        if not (right and top) then return end
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * s, top * s)
        ns.settings[f.cine and "speakerPosCine" or "speakerPos"] = { "TOPRIGHT", "BOTTOMLEFT", right * s, top * s }
    end
    -- locked (option) it stays put, so a stray drag can't move it (thanks Hedge)
    f:SetScript("OnDragStart", function(self)
        if not self.dockedTo and not ns.settings.lockSpeaker then self:StartMoving() end
    end)
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
    f.window:SetSize(84, 84)
    f.window:SetPoint("TOPLEFT", 10, -34) -- arrange() places it under the head
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
    f.sub:SetTextColor(0.92, 0.88, 0.8)

    -- the cinematic shade: dark in the middle, fading out to the sides and, in thin steps above and below the frame,
    -- to the top and bottom, so it reads as a soft band and not a box
    f.shade = {}
    -- one row of the band: its top at the frame's edge e1 (TOP or BOTTOM) + y1, its bottom at e2 + y2, darkness a
    local function shadeRow(e1, y1, e2, y2, a)
        local function strip(alpha)
            local t = f:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(0, 0, 0, alpha)
            t:Hide()
            f.shade[#f.shade + 1] = t
            return t
        end
        -- the sides fade out in thin strips (the game's gradient call drew nothing on some clients: a hard black box)
        local STEPS, W = 14, 10
        local left, right
        for k = 1, STEPS do
            local alpha = a * k / (STEPS + 1)
            local l, r = strip(alpha), strip(alpha)
            l:SetWidth(W); r:SetWidth(W)
            if left then
                l:SetPoint("TOPLEFT", left, "TOPRIGHT"); l:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
                r:SetPoint("TOPRIGHT", right, "TOPLEFT"); r:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
            else
                l:SetPoint("TOPLEFT", f, e1 .. "LEFT", 0, y1); l:SetPoint("BOTTOMLEFT", f, e2 .. "LEFT", 0, y2)
                r:SetPoint("TOPRIGHT", f, e1 .. "RIGHT", 0, y1); r:SetPoint("BOTTOMRIGHT", f, e2 .. "RIGHT", 0, y2)
            end
            left, right = l, r
        end
        local mid = strip(a)
        mid:SetPoint("TOPLEFT", left, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    end
    -- the frame itself, then six thin steps above and below it that get lighter
    shadeRow("TOP", 0, "BOTTOM", 0, 0.55)
    for i = 1, 6 do
        local a = 0.55 * (1 - i / 7)
        shadeRow("TOP", 3 * i, "TOP", 3 * (i - 1), a)
        shadeRow("BOTTOM", -3 * (i - 1), "BOTTOM", -3 * i, a)
    end

    f.progress = CreateFrame("StatusBar", nil, f)
    f.progress:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 109, 10); f.progress:SetPoint("RIGHT", -14, 0)
    f.progress:SetHeight(3)
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
        -- Bad: a few fixed reasons, one click each, and "Something else..." for a note of your own. Fixed reasons are
        -- quicker to give and show patterns, like a voice that is always too high (thanks BuzzTea)
        local REASONS = {
            { "voice", L["Wrong voice for this character"] },
            { "high", L["Voice too high"] },
            { "low", L["Voice too low"] },
            { "mood", L["Doesn't fit the moment"] },
            { "word", L["A word said wrong"] },
            { "text", L["Doesn't match the text"] },
        }
        local function askNote(key)
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
        end
        -- the reasons in a small list of our own: the game's context menu, opened from this window, crashed the client
        -- (an assertion in Blizzard_Menu's AcquireMenu)
        local list
        local function showReasons(owner, key)
            if not list then
                list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                list:SetFrameStrata("DIALOG")
                list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
                list:SetBackdropColor(0.07, 0.055, 0.04, 0.97); list:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
                list:EnableMouse(true)
                local title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                title:SetPoint("TOPLEFT", 10, -8); title:SetText(L["What was wrong?"])
                list.rows = {}
                local all = {}
                for _, reason in ipairs(REASONS) do all[#all + 1] = reason end
                all[#all + 1] = { "other", L["Something else..."] }
                local width = 120
                for i, choice in ipairs(all) do
                    local row = CreateFrame("Button", nil, list)
                    row:SetHeight(18)
                    row:SetPoint("TOPLEFT", 6, -8 - 14 - (i - 1) * 18); row:SetPoint("RIGHT", -6, 0)
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.text:SetPoint("LEFT", 4, 0); row.text:SetText(choice[2])
                    width = math.max(width, row.text:GetStringWidth() + 28)
                    local hl = row:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.5, 0.15)
                    row.reason = choice[1]
                    row:SetScript("OnClick", function(self)
                        list:Hide()
                        if self.reason == "other" then askNote(list.key) return end
                        ns.MarkLine(list.key, "bad", nil, self.reason)
                        T.UpdateMarks()
                    end)
                    list.rows[i] = row
                end
                list:SetSize(width, 8 + 14 + #all * 18 + 8)
                -- closes when the mouse has been away from it for a moment
                list:SetScript("OnUpdate", function(self, el)
                    self.away = self:IsMouseOver() and 0 or (self.away or 0) + el
                    if self.away > 1.5 then self:Hide() end
                end)
                list:SetScript("OnShow", function(self) self.away = 0 end)
            end
            list.key = key
            list:ClearAllPoints()
            list:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 4)
            list:Show()
        end
        btn:SetScript("OnClick", function(self)
            local key = currentKey
            if not key then return end
            if verdict == "bad" then
                showReasons(self, key)
            else
                ns.MarkLine(key, "good")
                T.UpdateMarks()
            end
        end)
        return btn
    end
    f.good = markButton(L["Good"], "good", 0.2, 0.55, 0.28)
    f.bad = markButton(L["Bad"], "bad", 0.7, 0.22, 0.18)
    -- the row at the foot, under the progress line (arrange() gives it its place): Good / Bad sit there
    f.player = CreateFrame("Frame", nil, f)
    f.player:SetHeight(22)
    f.bad:SetPoint("RIGHT", f.player, "RIGHT", 0, 0)
    f.good:SetPoint("RIGHT", f.bad, "LEFT", -4, 0)

    local stop = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    stop:SetSize(26, 26); stop:SetPoint("TOPRIGHT", 1, 1)
    f.stop = stop
    -- click: next line in the queue (the last one closes it); shift-click: stop everything
    local function skip()
        if ns.Voice.Paused() then ns.Voice.Stop(); T.Hide(true) return end
        if not current then T.Hide(true) return end -- the line already ended (kept up for Good / Bad)
        if IsShiftKeyDown() then ns.Voice.Stop() else ns.Voice.Skip() end
    end
    stop:SetScript("OnClick", skip)
    stop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Skip"], 1, 1, 1)
        GameTooltip:AddLine(L["Click: on to the next line, or close after the last one"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Shift-click: stop everything"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    stop:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    -- pause: two bars while someone is talking, a play arrow while paused; hidden when nothing is (thanks Rhiload)
    local pause = CreateFrame("Button", nil, f)
    pause:SetSize(16, 16); pause:SetPoint("RIGHT", replay, "LEFT", -2, 0)
    pause:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pause.bars = {}
    for i, x in ipairs({ -3, 3 }) do
        local bar = pause:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(1, 0.82, 0, 1); bar:SetSize(3, 10); bar:SetPoint("CENTER", x, 0)
        pause.bars[i] = bar
    end
    pause.play = pause:CreateTexture(nil, "ARTWORK")
    pause.play:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    pause.play:SetSize(14, 14); pause.play:SetPoint("CENTER", 1, 0)
    pause.update = function()
        local paused = ns.Voice.Paused()
        pause:SetShown(paused or current ~= nil)
        for _, bar in ipairs(pause.bars) do bar:SetShown(not paused) end
        pause.play:SetShown(paused)
    end
    pause:SetScript("OnClick", function()
        if ns.Voice.Paused() then ns.Voice.Resume() else ns.Voice.Pause() end
    end)
    pause:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if ns.Voice.Paused() then
            GameTooltip:SetText(L["Resume"], 1, 1, 1)
            GameTooltip:AddLine(L["Plays the line again from its start, then the rest"], 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText(L["Pause"], 1, 1, 1)
            GameTooltip:AddLine(L["Keeps this line and the ones waiting after it"], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    pause:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.pause = pause
    f.pausedText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.pausedText:SetPoint("RIGHT", pause, "LEFT", -4, 0)
    f.pausedText:SetText(L["Paused"])
    f.pausedText:Hide()
    -- right-click anywhere on the window does the same, wherever the X ends up (thanks timmeh)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then skip() end end)
    -- cinematic: the buttons stay faint until the mouse is over the band
    f.dimButtons = function()
        local a = (f.cine and not f:IsMouseOver()) and 0.3 or 1
        f.stop:SetAlpha(a); f.replay:SetAlpha(a); f.pause:SetAlpha(a)
    end
    f:SetScript("OnEnter", f.dimButtons)
    f:SetScript("OnLeave", f.dimButtons)

    -- a page of the words, and on the line of what it's about which page it is when there are several (2/3)
    f.showPage = function()
        f.sub:SetText(pages[page].text)
        f.about:SetText(f.aboutText .. (#pages > 1 and ("  |cff9d9d9d%d/%d|r"):format(page, #pages) or ""))
    end
    f:SetScript("OnUpdate", function(self)
        if current and startedAt then
            local done = math.min(1, (GetTime() - startedAt) / math.max(current.d or 1, 0.1))
            self.progress:SetValue(done)
            if pages and pages[page + 1] and done >= pages[page + 1].at then
                page = page + 1
                self.showPage()
            end
        end
    end)
    f:Hide()
end

-- Fixed bands, so nothing moves from one line to the next: the head (name and title, the X), the portrait and the
-- words (always room for SUB_LINES lines), the progress line and the row at the foot. Without subtitles there
-- is little to show: a slim window with only the head, what the line is about and the foot, no portrait (thanks
-- alche). Cinematic: the same bands centred on the soft band, without the box and the portrait.
local function arrange(compact)
    local cine = f.cine
    local shown = f.sub:GetText() -- the page on screen stays (an option changed while it talks)
    f.sub:SetText(("Ag\n"):rep(SUB_LINES - 1) .. "Ag")
    f.subHeight = f.sub:GetStringHeight()
    f.sub:SetText(shown or ""); f.sub:SetShown(not compact)
    f:SetWidth(cine and 640 or compact and 330 or 440)
    local inset = cine and 50 or PAD
    for _, r in ipairs({ f.name, f.about, f.sub, f.progress, f.player }) do r:ClearAllPoints() end
    f.window:SetShown(not (cine or compact))
    local just = cine and "CENTER" or "LEFT"
    f.name:SetJustifyH(just); f.about:SetJustifyH(just); f.sub:SetJustifyH(just)
    -- the head: the name (the title follows it on the same line, placed in T.Show); the X sits in the corner
    f.name:SetPoint("TOPLEFT", inset, -8); f.name:SetPoint("TOPRIGHT", cine and -inset or -60, -8)
    -- heights from the fonts, not the text: on the first line the name and the rest are still empty
    local function lineHeight(fs) local _, size = fs:GetFont() return (size or 12) + 2 end
    local top = 8 + lineHeight(f.name) + 8
    -- the words: right of the portrait, or the whole width
    local left = (cine or compact) and inset or PAD + 84 + 12
    f.window:ClearAllPoints(); f.window:SetPoint("TOPLEFT", PAD, -top)
    f.about:SetFontObject((compact and not cine) and GameFontNormal or GameFontNormalSmall)
    f.about:SetPoint("TOPLEFT", left, -top); f.about:SetPoint("TOPRIGHT", -inset, -top)
    local bottom = top + lineHeight(f.about)
    if not compact then
        -- under what it's about, both corners from it; cinematic a little wider: 36 from the edges
        local wider = cine and 14 or 0
        f.sub:SetPoint("TOPLEFT", f.about, "BOTTOMLEFT", -wider, -5)
        f.sub:SetPoint("TOPRIGHT", f.about, "BOTTOMRIGHT", wider, -5)
        bottom = bottom + 5 + f.subHeight
        if not cine then bottom = math.max(bottom, top + 84) end
    end
    -- the progress line over the whole width (a short one in the middle for cinematic), the row at the foot under it
    if cine then
        f.progress:SetPoint("TOP", 0, -(bottom + 8)); f.progress:SetSize(200, 2)
    else
        f.progress:SetPoint("TOPLEFT", inset, -(bottom + 8)); f.progress:SetPoint("TOPRIGHT", -inset, -(bottom + 8))
        f.progress:SetHeight(3)
    end
    f.player:SetPoint("TOPLEFT", inset, -(bottom + 16)); f.player:SetPoint("TOPRIGHT", -inset, -(bottom + 16))
    f:SetHeight(bottom + 16 + FOOT + 8)
end

-- Two looks (option "Speaker window"): the window with the portrait, or cinematic: no box or portrait, the name, what
-- it's about and the subtitles centred on a soft dark band, like a film's subtitles (thanks Alche and Hedge).
local function applyStyle(compact)
    local cine = ns.settings.speakerStyle == "cinematic"
    local changed = f.cine ~= cine
    f.cine, f.compact = cine, compact
    local bg = ns.settings.speakerBg or 1 -- the background's strength (option), 0 = only the words
    for _, t in ipairs(f.shade) do t:SetShown(cine and bg > 0); t:SetAlpha(bg) end
    if cine then
        f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0)
        f.title:Hide()
        f.sub:SetTextColor(1, 0.97, 0.9); f.sub:SetShadowOffset(1, -1); f.sub:SetShadowColor(0, 0, 0, 1)
    else
        f:SetBackdropColor(0.07, 0.055, 0.04, 0.92 * bg); f:SetBackdropBorderColor(0.6, 0.48, 0.25, bg)
        f.title:Show()
        f.sub:SetTextColor(0.92, 0.88, 0.8)
    end
    arrange(compact)
    if changed and not f.dockedTo then -- each look has its own place; cinematic starts low in the middle
        local pos = ns.settings[cine and "speakerPosCine" or "speakerPos"]
        f:ClearAllPoints()
        if type(pos) == "table" and type(pos[3]) == "number" then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        elseif cine then f:SetPoint("TOP", UIParent, "BOTTOM", 0, 300)
        else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 170) end
    end
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
    f.pausedText:Hide(); f.pause.update()
    local subtitle = ns.settings.subtitles and ns.Voice.Subtitle(key) or nil
    if ns.Speech and ns.Speech.Bubbled(key) then subtitle = nil end -- the bubble over their head has the words
    local compact = not (subtitle and subtitle ~= "")
    f.applySize() -- the subtitle size changes only here, with a new line: its pages are cut for it
    applyStyle(compact)
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
        local zone = k:match("^zone:(.+)") or k:match("^area:([^:]+):") or k:match("^dng:(.+)") or k:match("^epi:([^|]+)") or k:match("^dend:([^:|]+)")
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
    -- the title on the head line, right after the name
    if not f.cine then
        local width = math.min(f.name:GetStringWidth(), f:GetWidth() - 2 * PAD - 60 - 60)
        f.title:ClearAllPoints()
        f.title:SetPoint("BOTTOMLEFT", f.name, "BOTTOMLEFT", width + 8, 1); f.title:SetPoint("RIGHT", -60, 0)
    end
    f.aboutText = about(key)
    f.about:SetText(f.aboutText)
    -- subtitles: long text is shown a page at a time, in step with the voice
    local text = subtitle
    if not compact then
        -- pages of SUB_LINES lines, measured in the window itself (arrange() sized it for them)
        local function fits(s)
            f.sub:SetText((s:gsub("%s+$", "")))
            return f.sub:GetStringHeight() <= f.subHeight + 1
        end
        pages = paginate(text:gsub("[\r\n]+", " "), fits)
        page = 1
        -- stage directions like <Kaltunk looks you over.> aren't spoken; show them grey
        for _, p in ipairs(pages) do p.text = p.text:gsub("<([^<>]+)>", "|cff9d9d9d<%1>|r") end
        f.showPage()
        f.sub:Show()
    else
        pages = nil
        f.sub:SetText("")
        f.sub:Hide()
    end
    f.progress:SetValue(0)
    T.UpdateMarks()
    f.dimButtons()
    local fresh = not f:IsShown()
    f:Show()
    if f.cine and fresh and UIFrameFadeIn then UIFrameFadeIn(f, 0.25, 0, 1) -- cinematic: fades in, like a film's titles
    elseif not f.cine then f:SetAlpha(1) end
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

-- the speaker window, while it is up (the tour points at it)
function T.Frame() return f and f:IsShown() and f or nil end

-- an option changed (the background slider): the window on screen takes it at once, not at the next line
function T.Restyle() if f then applyStyle(f.compact) end end

-- Paused: the window stays up with the words where they were, and the pause button turns into resume
function T.ShowPaused()
    lingerToken = lingerToken + 1
    if not (f and f:IsShown()) then return end
    current, startedAt = nil, nil
    pcall(f.model.SetAnimation, f.model, 0)
    f.pausedText:Show(); f.pause.update()
end

function T.Hide(now)
    lingerToken = lingerToken + 1
    -- checking the voices: stay up a few seconds after the line ends, so a short line can still be marked
    if not now and f and f:IsShown() and currentKey and ns.settings.checkVoices then
        current, startedAt, pages = nil, nil, nil
        f.progress:SetValue(1)
        f.pause.update()
        local token = lingerToken
        C_Timer.After(6, function()
            if token == lingerToken then T.Hide(true) end
        end)
        return
    end
    current, startedAt, pages, currentKey = nil, nil, nil, nil
    if f then f:Hide() end
end

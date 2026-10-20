-- Chronicle / Tour: a short first-time tour, a bubble at a time beside the thing it explains: the minimap book, the
-- speaker window (with a test line, so it is there to point at), and a closing word on sharing. Once per account
-- for new players; /lore tour shows it again. The first quest window with a Listen button gets one tip of its own.
local _, ns = ...
local L = ns.L
local Tour = {}
ns.Tour = Tour

local bubble, steps, at

local function makeBubble()
    local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    b:SetFrameStrata("DIALOG")
    b:SetWidth(260)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0.07, 0.055, 0.04, 0.96); b:SetBackdropBorderColor(0.85, 0.68, 0.35, 1)
    b:SetClampedToScreen(true)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- fixed widths: the bubble's height is measured from the text right away, before anchors would give it a width
    b.title:SetPoint("TOPLEFT", 12, -10); b.title:SetWidth(236); b.title:SetJustifyH("LEFT")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -6); b.text:SetWidth(236)
    b.text:SetJustifyH("LEFT"); b.text:SetJustifyV("TOP"); b.text:SetWordWrap(true); b.text:SetSpacing(2)
    b.next = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    b.next:SetSize(80, 20); b.next:SetPoint("BOTTOMRIGHT", -10, 10)
    b.skip = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    b.skip:SetSize(80, 20); b.skip:SetPoint("RIGHT", b.next, "LEFT", -6, 0); b.skip:SetText(L["Skip tour"])
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.count:SetPoint("BOTTOMLEFT", 12, 15)
    b:Hide()
    return b
end

-- one bubble: beside a frame when there is one to point at, else in the middle of the screen
local function show(title, text, anchor, side)
    bubble = bubble or makeBubble()
    bubble.title:SetText(title)
    bubble.text:SetText(text)
    bubble:SetHeight(10 + bubble.title:GetStringHeight() + 6 + bubble.text:GetStringHeight() + 42)
    bubble:ClearAllPoints()
    if anchor and anchor:IsVisible() then
        -- no room where it should go (the anchor sits at the screen's edge): above falls back to the left, left to the
        -- right; a frame too wide for either keeps its side, and the clamp to the screen does the rest
        local k = anchor:GetEffectiveScale() / bubble:GetEffectiveScale()
        local w = bubble:GetWidth() + 12
        local roomLeft, roomRight = anchor:GetLeft() * k >= w, anchor:GetRight() * k + w <= UIParent:GetWidth()
        if side == "above" and anchor:GetTop() * k + bubble:GetHeight() + 12 > UIParent:GetHeight() then
            side = (roomLeft or not roomRight) and "left" or "right"
        elseif side == "left" and not roomLeft and roomRight then
            side = "right"
        end
        if side == "left" then bubble:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
        elseif side == "above" then bubble:SetPoint("BOTTOM", anchor, "TOP", 0, 12)
        else bubble:SetPoint("LEFT", anchor, "RIGHT", 12, 0) end
    else
        bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    bubble:Show()
end

local function leave() -- the step being left tidies up after itself (the options window it opened)
    local s = steps and at and steps[at]
    if s and s.leave then s.leave() end
end

local function finish()
    leave()
    if bubble then bubble:Hide() end
    steps, at = nil, nil
    ns.db.tourDone = true
end

local function step(n)
    leave()
    at = n
    local s = steps and steps[n]
    if not s then finish() return end
    local anchor = s.prepare and s.prepare()
    if s.prepare and not anchor and s.needed then return step(n + 1) end -- nothing to point at: on to the next
    show(s.title, s.text, anchor, s.side)
    bubble.count:SetText(("%d / %d"):format(n, #steps))
    bubble.next:SetText(n == #steps and L["Done"] or L["Next"])
    bubble.next:SetScript("OnClick", function() step(n + 1) end)
    bubble.skip:SetShown(n < #steps)
    bubble.skip:SetScript("OnClick", finish)
end

function Tour.Start()
    steps = {
        { title = L["Your journal"], side = "left",
          text = L["The book on the minimap opens your journal: each zone's story, your chapters with short recaps, and the Library of books you have read. Right-click it for the options. Also /lore."],
          prepare = function() return ns.Minimap and ns.Minimap.Button and ns.Minimap.Button() end },
        { title = L["Who is talking"], side = "above", needed = true,
          text = L["When someone speaks, this window shows who it is and the words. The row below has back, stop or play, next and replay; the X closes the window and stops everything. Drag it anywhere. For subtitles like a film, choose Cinematic under Options."],
          prepare = function()
              if not (ns.Voice and ns.Voice.Test and ns.Voice.Test()) then return nil end
              return ns.TalkingHead and ns.TalkingHead.Frame and ns.TalkingHead.Frame()
          end,
          leave = function() -- the test line needn't run on, and the window needn't linger for the voice check
              if ns.Voice and ns.Voice.Stop then ns.Voice.Stop() end
              if ns.TalkingHead and ns.TalkingHead.Hide then ns.TalkingHead.Hide(true) end
          end },
        { title = L["Make it yours"], side = "left", needed = true,
          text = L["A few things worth a look in the options:\n|cffffd100Speaker window style|r: a window with a portrait, or Cinematic subtitles.\n|cffffd100Sound channel|r: which volume slider the voices follow.\n|cffffd100What gets voiced|r: greetings, books, NPCs talking in the world, the narrator after a turn-in.\n|cffffd100Side tabs on the quest window|r: Listen and Recap as tabs.\n|cffffd100Journal only|r: the story without voices."],
          prepare = function()
              if not (ns.Options and ns.Options.Open and ns.Options.Open()) then return nil end
              -- the journal's Options tab, or the game's settings window on a client without it
              return SettingsPanel and SettingsPanel:IsShown() and SettingsPanel or ns.Options.page
          end,
          leave = function()
              if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
              if ChronicleJournalFrame and ChronicleJournalFrame:IsShown() then ChronicleJournalFrame:Hide() end
          end },
        { title = L["No voice yet?"],
          text = L["WoW: Forever keeps adding quests. When one has no voice, Chronicle keeps its text: type |cffffd100/lore share|r and send it in, and it gets a voice in the next update.\n\n|cffffd100/lore tour|r shows this tour again."] },
    }
    step(1)
end

-- the first quest window with a Listen button: one tip, once
local tipWatch = CreateFrame("Frame")
local tipWait = 0
tipWatch:SetScript("OnUpdate", function(self, dt)
    tipWait = tipWait - dt
    if tipWait > 0 then return end
    tipWait = 0.5
    if not ns.db then return end
    if ns.db.tourQuestTip then self:SetScript("OnUpdate", nil) return end
    if steps then return end -- not in the middle of the tour
    local b = ns.Voice and ns.Voice.ListenButton and ns.Voice.ListenButton()
    if not b then return end
    ns.db.tourQuestTip = true
    self:SetScript("OnUpdate", nil)
    show(L["Hear it again"], L["Listen plays the quest giver's words again. If it sits on another addon's button, hold Shift and drag it, or turn on side tabs on the quest window under Options."], b, "above")
    bubble.count:SetText("")
    bubble.next:SetText(L["Got it"])
    bubble.next:SetScript("OnClick", function() bubble:Hide() end)
    bubble.skip:Hide()
end)

-- new players: once, a little after logging in (runs before Core's welcome, so "welcomed" is still unset for them).
-- With the voice pack reminder up, it waits for the next login, when the packs are in.
table.insert(ns.onLogin, function()
    if not ns.db.welcomed then ns.db.tourPending = true end
    if ns.db.tourDone or not ns.db.tourPending then return end
    C_Timer.After(10, function()
        if StaticPopup_Visible and StaticPopup_Visible("CHRONICLE_PACKS") then return end
        ns.AfterCutscene(Tour.Start) -- a new character's intro plays first
    end)
end)

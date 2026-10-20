-- Chronicle / Share: exports recorded quest text that has no voiceover yet, so players can send it in
-- and the next release can voice it. /lore share
local _, ns = ...
local L = ns.L
local S = {}
ns.Share = S

local function ser(v, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = ("%q"):format(v)
    elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number") and type(x) ~= "function" then
                out[#out + 1] = "["; ser(k, out); out[#out + 1] = "]="; ser(x, out); out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    else out[#out + 1] = "nil" end
end

local FIELDS = { "title", "detail", "objectives", "progress", "complete", "giver", "ender", "zone", "subzone", "map", "by" }

local function size(v)
    local out = {}
    ser(v, out)
    return #table.concat(out)
end

-- Everything recorded that has no voice yet. opts.sync (party sync): only this player's own recordings, never
-- ones received from others, and at most opts.maxBytes of them. Returns the export text and how many records.
-- A small number for a quest page's text, the same as the builder's (lorekeeper.py text_check): letters only, without
-- the reader's name and any race or class word (the game fills those in for each reader). When it differs from the one
-- shipped for a voiced quest, Blizzard has rewritten the page since it was voiced, and the share sends the new text so
-- the voice can be fixed. This covers the original quests as well as the new ones.
local CHECK_SKIP = {}
for w in ("human orc dwarf night elf undead scourge tauren gnome troll warrior paladin hunter rogue priest shaman mage "
    .. "warlock druid"):gmatch("%a+") do CHECK_SKIP[w] = true end

local function textCheck(text, by)
    local name = by and type(by.name) == "string" and by.name:lower() or nil
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local words = {}
    for w in text:lower():gsub("'", ""):gmatch("%a+") do
        if w ~= name and not CHECK_SKIP[w] then words[#words + 1] = w end
    end
    local h = 5381
    local s = table.concat(words, " ")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end
S.TextCheck = textCheck

-- the voiced pages of a quest whose text the game now shows differently: { detail = true, ... } or nil
-- (pages saved by old versions don't say who read them, so the reader's name can't be told apart: skipped)
local function rewritten(id, q)
    local want = ns.TextCheck(id)
    if not want then return nil end
    local out
    for kind, short in pairs({ detail = "d", progress = "p", complete = "c" }) do
        local by = q.by and q.by[kind]
        local h = want[short] and by and type(q[kind]) == "string" and textCheck(q[kind], by)
        -- the voiced text, its female wording, or another version of the page voiced on its own
        local known = h and (h == want[short] or h == want[short .. "f"])
        for i = 2, 5 do known = known or (h and h == want[short .. i]) end
        if h and not known then
            out = out or {}
            out[kind] = true
        end
    end
    return out
end

function S.Build(opts)
    opts = opts or {}
    local n, budget = 0, opts.maxBytes or math.huge
    local function take(bucket, key, e)
        if opts.sync and e.fromParty then return end
        local b = size(e) + size(key) + 4 -- with the [key]= and , around it
        if b > budget then return end
        budget = budget - b
        bucket[key] = e
        n = n + 1
    end
    -- other client languages record text in that language, which the English voices can't use
    local quests, greetings, books, speech = {}, {}, {}, {}
    if ns.english then
        for id, q in pairs(ns.db.quests) do
            local missing = (q.detail and not ns.Voice.Get("q" .. id .. ":detail"))
                or (q.progress and not ns.Voice.Get("q" .. id .. ":progress"))
                or (q.complete and not ns.Voice.Get("q" .. id .. ":complete"))
            local changed = not opts.sync and not q.fromParty and rewritten(id, q)
            -- an original quest is voiced from the database: only sent when Blizzard has rewritten it
            if (missing and ns.IsNew(id)) or changed then
                local e = { fromParty = q.fromParty, changed = changed or nil }
                for _, k in ipairs(FIELDS) do e[k] = q[k] end
                take(quests, id, e)
            end
        end
        -- greetings recorded because no voiced line matched them
        for id, g in pairs(ns.db.greetings or {}) do
            if ns.GreetingPending(id, g) then take(greetings, id, g) end -- any page still without a voice
        end
        local lore = ns.Lore or {}
        for title, b in pairs(ns.db.books or {}) do
            if not (lore.books and lore.books[title]) then take(books, title, b) end -- voiced by a newer release
        end
        for name, r in pairs(ns.db.speech or {}) do take(speech, name, r) end
    elseif not opts.sync then
        -- another client language: the quest pages and greetings as this game shows them, for voices in that language.
        -- What went out once isn't sent again; a share too big for one go continues next time.
        ns.db.loc = ns.db.loc or {}
        local sent = ns.db.loc.sent or {}
        ns.db.loc.sent = sent
        for id, q in pairs(ns.db.quests) do
            if (q.detail or q.progress or q.complete) and not sent["q" .. id] and not q.fromParty then
                local e = {}
                for _, k in ipairs(FIELDS) do e[k] = q[k] end
                local before = n
                take(quests, id, e)
                if n > before then sent["q" .. id] = true end
            end
        end
        for id, g in pairs(ns.db.loc.greetings or {}) do
            local mark = "g" .. id .. ":" .. (#(g.more or {}))
            if not sent[mark] then
                local before = n
                take(greetings, id, g)
                if n > before then sent[mark] = true end
            end
        end
    end
    local version, build = GetBuildInfo()
    local data = { v = 1, loc = GetLocale(), client = version .. "." .. build,
                   quests = quests, greetings = greetings, books = books, speech = speech }
    if not opts.sync and ns.english and ns.db.offers and next(ns.db.offers) then
        data.offers = ns.db.offers -- where the givers of new quests stand (for the quest markers)
    end
    if not opts.sync and ns.english and ns.db.otherGivers and next(ns.db.otherGivers) then
        data.givers = ns.db.otherGivers -- quests another NPC also hands out, to voice in their voice too
        for _ in pairs(ns.db.otherGivers) do n = n + 1 end
    end
    if not opts.sync and ns.db.lastBoss and next(ns.db.lastBoss) then
        data.lastBoss = ns.db.lastBoss -- the last boss groups kill in each dungeon: when its ending plays
    end
    if not opts.sync and ns.english and ns.db.areas and next(ns.db.areas) then
        data.areas = ns.db.areas -- named places nobody has a line for yet: zone and name, to write and voice one
        for _, places in pairs(ns.db.areas) do for _ in pairs(places) do n = n + 1 end end
    end
    if not opts.sync and ns.db.reports and #ns.db.reports > 0 then
        data.reports = ns.db.reports -- /lore report notes: which line was wrong and why
        n = n + #ns.db.reports
    end
    local out = {}
    ser(data, out)
    return "CHRONICLE-SHARE-1\n" .. table.concat(out), n
end

-- the title, the how-to and the text box, in the standalone window or inside the journal's Share tab
local function fill(f, onEscape)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.help:SetPoint("TOPLEFT", 14, -36); f.help:SetPoint("RIGHT", -14, 0); f.help:SetJustifyH("LEFT")
    f.help:SetText(L["Press Ctrl+A then Ctrl+C to copy, and paste it in the |cffffd100share-recordings|r channel on the Chronicle Discord: |cffffd100discord.gg/NKevry7mY|r (long text turns into a file there, that's fine). The next release will voice it for everyone."])
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 14, -62); sf:SetPoint("BOTTOMRIGHT", -14, 14)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontSmall or ChatFontNormal)
    eb:SetWidth(590)
    eb:SetScript("OnEscapePressed", onEscape)
    sf:SetScrollChild(eb)
    sf:SetScript("OnSizeChanged", function(_, w) eb:SetWidth(w) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 60)))
    end)
    f.edit = eb
end

local function show(f, text, n)
    f.title:SetText(n == 1 and L["Share 1 recording and report"] or (L["Share %d recordings and reports"]):format(n))
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

local function collect()
    local text, n = S.Build()
    if n == 0 then
        ns.pr(ns.english and L["everything you have recorded already has voiceover. Nothing to share."]
            or L["nothing new to share since your last share. Play on and share again later."])
        return nil
    end
    return text, n
end

-- inside the journal (its Share tab): false when there is nothing to share
local embedded
function S.Embed(host)
    local text, n = collect()
    if not text then return false end
    if not embedded then
        embedded = CreateFrame("Frame", nil, host)
        embedded:SetAllPoints(host)
        fill(embedded, function(self) self:ClearFocus() end)
    end
    show(embedded, text, n)
    return true
end

local frame
local function getFrame()
    if frame then return frame end
    local f = CreateFrame("Frame", "ChronicleShareFrame", UIParent, "BackdropTemplate")
    f:SetSize(620, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.05, 0.04, 0.97)
    f:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ChronicleShareFrame")
    fill(f, function() f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    frame = f
    return f
end

function S.Open()
    -- /lore share and the share nudge: inside the journal when it's open in the new style, else its own window
    local text, n = collect()
    if not text then return end
    if ns.Journal.ShowShare and ns.Journal.ShowShare() then return end
    show(getFrame(), text, n)
end

-- ---------------------------------------------------------------- the nudge
-- After a turn-in: if you have recorded new Forever quests that have no voice yet, offer to share them. Only when
-- at least NUDGE_AT more have piled up since the last offer, and at most once a day.
local NUDGE_AT, NUDGE_EVERY = 3, 24 * 60 * 60

-- New Forever quests this player recorded that nobody has voiced yet (received from the party doesn't count)
function S.Unvoiced()
    if not ns.english then return 0 end
    local n = 0
    for id, q in pairs(ns.db.quests) do
        if not q.fromParty and ns.IsNew(id) and ((q.detail and not ns.Voice.Get("q" .. id .. ":detail"))
            or (q.complete and not ns.Voice.Get("q" .. id .. ":complete"))) then
            n = n + 1
        end
    end
    return n
end

local nudge
local function getNudge()
    if nudge then return nudge end
    local t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    t:SetSize(360, 78)
    t:SetPoint("TOP", UIParent, "TOP", 0, -140)
    t:SetFrameStrata("MEDIUM")
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    t:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    t:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    t:EnableMouse(true)
    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40); icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0); t.title:SetPoint("RIGHT", -28, 0); t.title:SetJustifyH("LEFT")
    t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3); t.sub:SetPoint("RIGHT", -12, 0); t.sub:SetJustifyH("LEFT")
    t.sub:SetText(L["Share them so everyone can hear them in the next update."])
    local share = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    share:SetSize(80, 20); ns.FitButton(share); share:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -4)
    share:SetText(L["Share"])
    share:SetScript("OnClick", function() t:Hide(); S.Open() end)
    local later = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    later:SetSize(80, 20); ns.FitButton(later); later:SetPoint("LEFT", share, "RIGHT", 6, 0)
    later:SetText(L["Not now"])
    later:SetScript("OnClick", function() t:Hide() end)
    local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 0, 0)
    t:SetScript("OnUpdate", function(self)
        if self:IsMouseOver() then self.hideAt = GetTime() + 5 end
        if GetTime() > (self.hideAt or 0) then self:Hide() end
    end)
    t:Hide()
    nudge = t
    return t
end

local function maybeNudge()
    if not ns.settings.shareNudge or InCombatLockdown() then return end
    local n = S.Unvoiced()
    local last = ns.db.shareNudge or { n = 0, at = 0 }
    if n < NUDGE_AT or n - (last.n or 0) < NUDGE_AT or time() - (last.at or 0) < NUDGE_EVERY then return end
    ns.db.shareNudge = { n = n, at = time() }
    local t = getNudge()
    t.title:SetText((L["You found %d quests without a voice yet"]):format(n))
    t.hideAt = GetTime() + 25
    t:Show()
end

-- what you just shared doesn't count toward the next offer
local open = S.Open
function S.Open()
    open()
    ns.db.shareNudge = { n = S.Unvoiced(), at = (ns.db.shareNudge or {}).at or 0 }
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:SetScript("OnEvent", function()
    C_Timer.After(4, maybeNudge) -- after the turn-in voices and the quest text are saved
end)

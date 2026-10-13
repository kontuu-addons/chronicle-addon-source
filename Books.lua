-- Chronicle / Books: the narrator reads letters, books and plaques. Each page ships a short phrase
-- (Data\Lore.lua "books") matched against the page on screen; pages nobody has voiced yet are recorded.
local _, ns = ...
local L = ns.L
local B = {}
ns.Books = B

local norm = function(s)
    return " " .. s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%a]+", " ") .. " "
end

function B.PageKey(title, text)
    local list = ns.Lore and ns.Lore.books and ns.Lore.books[title]
    if not (list and text) then return nil end
    local shown = norm(text)
    for _, item in ipairs(list) do
        if shown:find(" " .. item[2] .. " ", 1, true) then return item[1] end
    end
end

local current -- voice key of the page on screen
local btn

local function update()
    if not btn then return end
    local has = current and ns.Voice.Get(current)
    btn:SetShown(has and true or false)
    btn:SetText((ns.Voice.PlayingKey() == current and current) and L["Stop"] or L["Listen"])
end
B.Update = update

local function onPage()
    local title = ns.clean(ItemTextGetItem and ItemTextGetItem())
    local text = ns.clean(ItemTextGetText and ItemTextGetText())
    local page = ItemTextGetPage and ItemTextGetPage() or 1
    if not (title and text and text ~= "") then return end
    -- a letter written by a player (mail): private, never recorded, shared or read aloud
    local creator = ItemTextGetCreator and ns.clean(ItemTextGetCreator())
    if creator and creator ~= "" then
        current = nil
        update()
        return
    end
    current = B.PageKey(title, text)
    if ns.settings.debug then
        ns.pr(("debug: book %q page %d -> %s"):format(title, page, current and (ns.Voice.Get(current) and current or current .. " (not voiced yet)") or "no match"))
    end
    local known = ns.Lore and ns.Lore.books and ns.Lore.books[title]
    if known and ns.char then -- the journal's Library: the books, letters and plaques this character has read
        ns.char.library = ns.char.library or {}
        ns.char.library[title] = ns.char.library[title] or time()
    end
    local count = 0
    for _ in pairs(ns.db.books or {}) do count = count + 1 end
    if not current and not known and ns.english and ((ns.db.books or {})[title] or count < 100) then
        -- a book, letter or plaque nobody has voiced: keep it for /lore share and the next release
        ns.db.books = ns.db.books or {}
        local b = ns.db.books[title] or { pages = {} }
        b.pages[page] = text
        local _, class = UnitClass("player")
        b.by = { class = ns.clean(class), name = ns.clean(UnitName("player")) }
        ns.db.books[title] = b
        if ns.settings.books and ns.settings.ttsFallback then ns.Voice.Speak(text, false) end
    elseif current and ns.settings.books and ns.Voice.Get(current) then
        local heard = ns.char.heard
        if not (ns.settings.skipHeard and heard[current]) then
            heard[current] = true
            ns.Voice.SetText(current, text)
            ns.Voice.Play(current)
        end
    end
    update()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "ITEM_TEXT_READY" then
        onPage()
    elseif event == "ITEM_TEXT_CLOSED" then
        local k = ns.Voice.PlayingKey()
        if ns.settings.stopOnClose and k and k:sub(1, 4) == "book" then ns.Voice.Stop() end
        current = nil
    end
end)
for _, e in ipairs({ "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end

table.insert(ns.onLogin, function()
    if not ItemTextFrame then return end
    btn = CreateFrame("Button", nil, ns.Overlay(ItemTextFrame), "UIPanelButtonTemplate")
    btn:SetSize(70, 20); ns.FitButton(btn)
    btn:SetPoint("TOPRIGHT", ItemTextFrame, "TOPRIGHT", -30, -30)
    btn:SetScript("OnClick", function()
        if current and ns.Voice.PlayingKey() == current then ns.Voice.Stop()
        elseif current then ns.Voice.Play(current) end
        update()
    end)
    btn:Hide()
end)

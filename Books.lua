-- Chronicle / Books: the narrator reads letters, books and plaques. Each page ships a short phrase
-- (Data\Lore.lua "books") matched against the page on screen; pages nobody has voiced yet are recorded.
local _, ns = ...
local L = ns.L
local B = {}
ns.Books = B

local norm = function(s)
    -- a page written as HTML (the military ranks books): its words only, as the data's phrases are made
    if s:find("<[Hh][Tt][Mm][Ll]>") then s = s:gsub("<[^>]*>", " ") end
    return " " .. s:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%a]+", " ") .. " "
end

function B.PageKey(title, text)
    local list = ns.Lore and ns.Lore.books and ns.Lore.books[title]
    if not (list and text) then return nil end
    local shown = norm(text)
    for _, item in ipairs(list) do
        -- the opening, and how the page ends where the data has it (a letter's signature: the same letter for
        -- another race opens the same way)
        if shown:find(" " .. item[2] .. " ", 1, true) and not (item[3] and not shown:find(" " .. item[3] .. " ", 1, true)) then
            return item[1]
        end
    end
end

local current -- voice key of the page on screen
local btn
local makeButton -- below: the Listen button, made the first time a book opens

local function update()
    if not btn then return end
    local has = current and ns.Voice.Get(current)
    btn:SetShown(has and true or false)
    btn:SetText((ns.Voice.PlayingKey() == current and current) and L["Stop"] or L["Listen"])
end
B.Update = update

-- DialogueUI's own book window is on (it reads books instead of the game's window)
local function dialogueBooks()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI")) then return false end
    local db = _G.DialogueUI_DB -- its option "BookUIEnabled", on unless the player turned it off
    return not (type(db) == "table" and db.BookUIEnabled == false)
end
local wholeBook, bookTimer
-- which book each voiced page belongs to: a page turned in the book being read replaces it, another book waits its
-- turn (three plaques clicked one after another are all read)
local titleOf = {}
local function otherBookPlaying(title)
    local playing = ns.Voice.PlayingKey()
    return playing and playing:sub(1, 4) == "book" and titleOf[playing] ~= title
end

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
    makeButton()
    current = B.PageKey(title, text)
    if current then titleOf[current] = title end
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
    if not current and ns.english and ((ns.db.books or {})[title] or count < 100) then
        -- a book, letter or plaque nobody has voiced, or a page of a known one that reads differently (another
        -- race's letter under the same title, a page Blizzard rewrote): keep it for /lore share and the next release
        ns.db.books = ns.db.books or {}
        local b = ns.db.books[title] or { pages = {} }
        b.pages[page] = text
        local _, class = UnitClass("player")
        b.by = { class = ns.clean(class), name = ns.clean(UnitName("player")) }
        ns.db.books[title] = b
        if ns.settings.books and ns.settings.ttsFallback then ns.Voice.Speak(text, false) end
    elseif current and ns.settings.books and ns.Voice.Get(current) and dialogueBooks() then
        -- DialogueUI's book window turns through every page at once to keep the whole book: wait for that to settle,
        -- then read the book from its first page, in order (each page started on its own and only the last one was
        -- left; thanks Alche)
        wholeBook = title
        if not bookTimer then
            bookTimer = C_Timer.NewTimer(0.4, function()
                bookTimer = nil
                local keys = {}
                for _, item in ipairs(known or {}) do
                    if ns.Voice.Get(item[1]) and keys[#keys] ~= item[1] then keys[#keys + 1] = item[1] end
                end
                local heard = ns.char.heard
                if wholeBook ~= title or #keys == 0 or (ns.settings.skipHeard and heard[keys[1]]) then return end
                for _, k in ipairs(keys) do heard[k] = true end
                -- someone else talking (a quest giver, a recap) finishes first; the book follows
                local playing = ns.Voice.PlayingKey()
                for _, k in ipairs(keys) do titleOf[k] = title end
                if playing and (playing:sub(1, 4) ~= "book" or otherBookPlaying(title)) then
                    for _, k in ipairs(keys) do if not ns.Voice.Waiting(k) then ns.Voice.Enqueue(k) end end
                else
                    ns.Voice.PlayQueue(keys)
                end
            end)
        end
    elseif current and ns.settings.books and ns.Voice.Get(current) then
        local heard = ns.char.heard
        if not (ns.settings.skipHeard and heard[current]) then
            ns.Voice.SetText(current, text)
            -- turning the page replaces the page being read; anything else that is talking (a quest giver, a recap)
            -- is not cut off: the page waits its turn. It counts as heard once it starts (Voice.lua; thanks Pylo)
            local playing = ns.Voice.PlayingKey()
            if playing and playing ~= current and (playing:sub(1, 4) ~= "book" or otherBookPlaying(title)) then
                if not ns.Voice.Waiting(current) then ns.Voice.Enqueue(current) end
            else
                ns.Voice.Play(current)
            end
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

-- The Listen button on the book window. Made the first time a book opens: on newer clients the game only loads
-- that window then, so at login there was nothing to put it on (books played, but couldn't be played again).
function makeButton()
    if btn or not ItemTextFrame then return end
    btn = CreateFrame("Button", nil, ns.Overlay(ItemTextFrame), "UIPanelButtonTemplate")
    btn:SetSize(70, 20); ns.FitButton(btn)
    btn:SetPoint("TOPLEFT", ItemTextFrame, "TOPLEFT", 64, -30) -- left of the page number: the next-page arrow sits on the right
    btn:SetScript("OnClick", function()
        if current and ns.Voice.PlayingKey() == current then ns.Voice.Stop()
        elseif current then ns.Voice.Play(current) end
        update()
    end)
    btn:Hide()
end
table.insert(ns.onLogin, makeButton)

-- books read before the Library existed are only in "heard": put them on the shelf too (time unknown: 0, so they
-- sort after the ones read since; thanks Pylo)
table.insert(ns.onLogin, function()
    local heard, books = ns.char and ns.char.heard, ns.Lore and ns.Lore.books
    if not (heard and books) then return end
    ns.char.library = ns.char.library or {}
    -- a page shared by several titles (the same text on different objects) can't tell which one was read
    local titlesOf = {}
    for _, pages in pairs(books) do
        for _, page in ipairs(pages) do titlesOf[page[1]] = (titlesOf[page[1]] or 0) + 1 end
    end
    for title, pages in pairs(books) do
        if not ns.char.library[title] then
            for _, page in ipairs(pages) do
                if heard[page[1]] and titlesOf[page[1]] == 1 then ns.char.library[title] = 0; break end
            end
        end
    end
end)

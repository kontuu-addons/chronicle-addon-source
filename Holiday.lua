-- Chronicle / Holiday: which holiday is on today, from the game's own calendar. While one is on, its chapters show
-- in the journal like any other, and a note says it has begun (once a year per character).
local _, ns = ...
local L = ns.L
local H = {}
ns.Holiday = H

local on, loaded, day = {}, false, nil

local function readable(v) return v ~= nil and (not canaccessvalue or canaccessvalue(v)) end

-- the calendar's holidays today, matched to our holiday chapters by name ("Midsummer Fire Festival" -> Midsummer)
local function scan()
    if not (C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent and C_DateAndTime) then return end
    if CalendarFrame and CalendarFrame:IsShown() then return end -- don't move the month you are looking at
    local ok, now = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if not (ok and now) then return end
    local month, year, today = now.month, now.year, now.monthDay
    if canaccessvalue and not canaccessvalue(month) then return end
    if canaccessvalue and not canaccessvalue(year) then return end
    if canaccessvalue and not canaccessvalue(today) then return end
    local titles = {}
    local moved = false
    pcall(function()
        -- move the calendar only when it shows another month: moving it fires the calendar's update event again
        local shown = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
        local here = shown and readable(shown.month) and readable(shown.year) and shown.month == month and shown.year == year
        if not here and C_Calendar.SetAbsMonth then C_Calendar.SetAbsMonth(month, year); moved = true end
        for i = 1, C_Calendar.GetNumDayEvents(0, today) do
            local e = C_Calendar.GetDayEvent(0, today, i)
            local kind, title = e and e.calendarType, e and e.title
            if canaccessvalue and not canaccessvalue(kind) then kind = nil end
            if canaccessvalue and not canaccessvalue(title) then title = nil end
            if kind == "HOLIDAY" and type(title) == "string" then titles[#titles + 1] = title end
        end
    end)
    if moved then return nil end -- the new month's events are not loaded yet: read them when the game says so
    on = {}
    for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
        for _, t in ipairs(titles) do
            if a.event and string.find(t, a.event, 1, true) then on[a.event] = true end
        end
    end
    day = today
    return now
end

-- which holidays are on, as one string (the journal rebuilds its chapters when it changes)
function H.Signature()
    local t = {}
    for event in pairs(on) do t[#t + 1] = event end
    table.sort(t)
    return table.concat(t, ",")
end

function H.IsOn(event)
    if loaded and day then
        local ok, now = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and now and readable(now.monthDay) and now.monthDay ~= day then scan() end
    end
    return on[event] or false
end

-- a holiday that has begun: its first chapter for this character, in a note (Listen: the chapter's introduction)
local function announce(now)
    if not (ns.char and ns.Reminder and ns.Journal) then return end
    ns.char.holidays = ns.char.holidays or {}
    -- once: holidays announced with the other faction's chapter (before the faction check) get their own
    if not ns.char.holidaysSide then ns.char.holidays, ns.char.holidaysSide = {}, true end
    for event in pairs(on) do
        local seen = ns.char.holidays[event]
        if seen ~= now.year then
            for _, a in ipairs((ns.Lore and ns.Lore.arcs) or {}) do
                if a.event == event and ns.Journal.ArcForMe(a) then
                    ns.char.holidays[event] = now.year
                    ns.Reminder.ShowStory((L["%s has begun"]):format(L[event]), a.intro or "", { "arc:" .. a.id },
                        function() ns.Journal.Open("arc:" .. a.id) end)
                    return -- one note at a time
                end
            end
        end
    end
end

local ev = CreateFrame("Frame")
local busy -- reading the calendar fires its update event at once; another addon moving the month does too
ev:SetScript("OnEvent", function(self)
    if busy then return end
    busy = true
    local ok, now = pcall(scan)
    busy = false
    if not ok then return end
    if not now then
        -- the calendar is open on another month, or not ready: the move to this month fires the event again, and if
        -- that was swallowed above (busy), look once more a little later
        self.tries = (self.tries or 0) + 1
        if self.tries <= 5 then C_Timer.After(2, function() self:GetScript("OnEvent")(self) end) end
        return
    end
    self:UnregisterAllEvents() -- once: reading the month fires this event again
    local first = not loaded
    loaded = true
    if first and now then C_Timer.After(20, function() pcall(announce, now) end) end
end)

table.insert(ns.onLogin, function()
    if not (C_Calendar and C_Calendar.OpenCalendar) then return end
    pcall(ev.RegisterEvent, ev, "CALENDAR_UPDATE_EVENT_LIST")
    pcall(C_Calendar.OpenCalendar)
end)

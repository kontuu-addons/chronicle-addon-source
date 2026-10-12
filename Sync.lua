-- Chronicle / Sync: share recordings with your party automatically.
-- When you join or change a party, each Chronicle sends the recordings it has that have no voice yet (new quests,
-- greetings, books, NPC speech) as addon messages. The receiver keeps anything it does not have yet, so the
-- developer's next voice build picks it up. Incoming data is parsed by a strict reader for plain values only:
-- nothing received is ever run as code, and every record is rebuilt field by field from an allow-list.
local _, ns = ...
local L = ns.L
local Y = {}
ns.Sync = Y

local PREFIX = "CHRONICLE"
local CHUNK = 230         -- bytes of payload per message (addon messages are limited to 255)
local SEND_EVERY = 1.1    -- seconds between messages: stays under the server's addon message throttle
local MAX_CHUNKS = 60     -- one transfer is at most ~14 KB; the rest goes with the next party
-- the records' budget leaves room for the table around them (version, client, the four lists), or the transfer comes
-- to more than MAX_CHUNKS pieces and every receiver drops it
local BUDGET = CHUNK * MAX_CHUNKS - 256
local RESEND_AFTER = 600  -- seconds before the same party gets our recordings again
local STALE = 120         -- seconds before a half-received transfer is dropped
local LIMIT = { quests = 1000, greetings = 400, books = 100, speech = 200 }

-- ---------------------------------------------------------------- safe reader for Share.lua's format
-- Accepts only: "strings" (%q style), numbers, true/false/nil, and { [key]=value, ... } tables.
---@param s string
local function parse(s)
    local i, n = 1, #s
    local depth = 0
    local value
    local function ws() while i <= n and s:sub(i, i):match("%s") do i = i + 1 end end
    local function str()
        i = i + 1
        local out = {}
        while i <= n do
            local c = s:sub(i, i)
            if c == "\\" then
                local nx = s:sub(i + 1, i + 1)
                if nx:match("%d") then
                    local d = s:match("^%d%d?%d?", i + 1)
                    out[#out + 1] = string.char(tonumber(d) % 256)
                    i = i + 1 + #d
                else
                    out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", ["\n"] = "\n" })[nx] or nx
                    i = i + 2
                end
            elseif c == '"' then
                i = i + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        error("unterminated string")
    end
    local function tbl()
        i = i + 1
        depth = depth + 1
        if depth > 8 then error("too deep") end
        local t = {}
        while true do
            ws()
            local c = s:sub(i, i)
            if c == "}" then i = i + 1; depth = depth - 1; return t end
            if c ~= "[" then error("expected [") end
            i = i + 1
            local k = value()
            ws(); if s:sub(i, i) ~= "]" then error("expected ]") end; i = i + 1
            ws(); if s:sub(i, i) ~= "=" then error("expected =") end; i = i + 1
            local v = value()
            if type(k) == "string" or type(k) == "number" then t[k] = v end
            ws(); if s:sub(i, i) == "," then i = i + 1 end
        end
    end
    value = function()
        ws()
        local c = s:sub(i, i)
        if c == '"' then return str() end
        if c == "{" then return tbl() end
        if s:sub(i, i + 3) == "true" then i = i + 4; return true end
        if s:sub(i, i + 4) == "false" then i = i + 5; return false end
        if s:sub(i, i + 2) == "nil" then i = i + 3; return nil end
        local num = s:match("^%-?[%d%.]+[eE]?[%-+]?%d*", i)
        if num and tonumber(num) then i = i + #num; return tonumber(num) end
        error("unexpected " .. c)
    end
    local ok, result = pcall(value)
    return ok and type(result) == "table" and result or nil
end
Y.Parse = parse

-- ---------------------------------------------------------------- cleaning what arrives
-- Only known fields of the right type and size survive; "|" is escaped so no texture or link codes get through.
local function str(v, max)
    if type(v) ~= "string" or v == "" or #v > (max or 4000) then return nil end
    return (v:gsub("|", "||"))
end
local function num(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 and v or nil end
local function unit(t)
    if type(t) ~= "table" then return nil end
    return { name = str(t.name, 64), npcID = num(t.npcID), kind = str(t.kind, 32), sex = num(t.sex), creature = str(t.creature, 64),
             model = num(t.model) }
end
local function reader(t)
    if type(t) ~= "table" then return nil end
    return { class = str(t.class, 32), race = str(t.race, 32), sex = num(t.sex), name = str(t.name, 64) }
end
local function list(t, max, len)
    if type(t) ~= "table" then return nil end
    local out = {}
    for i = 1, max do out[i] = str(t[i], len) end
    return next(out) and out or nil
end

local CLEAN = {
    quests = function(q)
        local by
        if type(q.by) == "table" then
            by = {}
            for _, k in ipairs({ "detail", "objectives", "progress", "complete" }) do by[k] = reader(q.by[k]) end
        end
        local e = { title = str(q.title, 200), detail = str(q.detail), objectives = str(q.objectives),
                    progress = str(q.progress), complete = str(q.complete), zone = str(q.zone, 100),
                    subzone = str(q.subzone, 100), map = num(q.map), giver = unit(q.giver), ender = unit(q.ender), by = by }
        return (e.detail or e.progress or e.complete) and e or nil
    end,
    greetings = function(g)
        local text = str(g.text)
        return text and { text = text, name = str(g.name, 64), sex = num(g.sex), creature = str(g.creature, 64),
                          model = num(g.model), kind = str(g.kind, 32), zone = str(g.zone, 100), by = reader(g.by) } or nil
    end,
    books = function(b)
        local pages = list(b.pages, 20)
        return pages and { pages = pages, by = reader(b.by) } or nil
    end,
    speech = function(r)
        local texts = list(r.texts, 12, 500)
        local npc = type(r.npc) == "table" and { sex = num(r.npc.sex), creature = str(r.npc.creature, 64) } or nil
        return texts and { texts = texts, npc = npc, by = reader(r.by) } or nil
    end,
}

local function validKey(part, id)
    if part == "quests" or part == "greetings" then return type(id) == "number" and id > 0 and id < 1e7 end
    return type(id) == "string" and #id > 0 and #id <= 100
end

local function merge(data, sender)
    local added = 0
    for part, clean in pairs(CLEAN) do
        if type(data[part]) == "table" then
            local store = ns.db[part] or {}
            ns.db[part] = store
            local count = 0
            -- only what came from the party counts against the limit: a long-time player's own quests (all of
            -- db.quests) would otherwise fill it and nothing from the party would be kept any more
            for _, e in pairs(store) do
                if type(e) == "table" and e.fromParty then count = count + 1 end
            end
            for id, item in pairs(data[part]) do
                if count >= LIMIT[part] then break end
                -- only things we have nothing of: our own recordings are never overwritten or mixed with others
                if store[id] == nil and type(item) == "table" and validKey(part, id) then
                    local e = clean(item)
                    if e then
                        e.fromParty = str(sender, 64)
                        store[id] = e
                        count = count + 1
                        added = added + 1
                    end
                end
            end
        end
    end
    return added
end
Y.Merge = merge

-- ---------------------------------------------------------------- sending
local sending = false

local function sendResult(ok)
    -- older clients return a boolean, newer ones a result code (0 = success)
    return ok == nil or ok == true or ok == 0 or (Enum and Enum.SendAddonMessageResult and ok == Enum.SendAddonMessageResult.Success)
end

local function partyKey()
    local roster = {}
    for i = 1, GetNumSubgroupMembers() do roster[#roster + 1] = ns.clean(UnitName("party" .. i)) or "" end
    table.sort(roster)
    return table.concat(roster, ",")
end

local function homeParty()
    if IsInRaid() then return false end
    if LE_PARTY_CATEGORY_HOME then return IsInGroup(LE_PARTY_CATEGORY_HOME) end
    return IsInGroup()
end

local function send()
    if sending or not homeParty() or not ns.english then return end
    if not (ns.settings.partySync and ns.Share) then return end
    local who = partyKey()
    -- kept in the saved data: a /reload or a new login must not send the same recordings to the same party again
    local sent = ns.db.syncSent or {}
    ns.db.syncSent = sent
    for k, t in pairs(sent) do if time() - t >= RESEND_AFTER then sent[k] = nil end end
    if sent[who] then return end
    local text, n = ns.Share.Build({ sync = true, maxBytes = BUDGET })
    if n == 0 then return end
    sent[who] = time()

    local body = text:gsub("^CHRONICLE%-SHARE%-1\n", "")
    local id = tostring(math.random(100000, 999999))
    local total = math.ceil(#body / CHUNK)
    local seq, retries = 1, 0
    sending = true
    local function nextChunk()
        if seq > total or not homeParty() then sending = false; return end
        local piece = body:sub((seq - 1) * CHUNK + 1, seq * CHUNK)
        if sendResult(C_ChatInfo.SendAddonMessage(PREFIX, id .. ":" .. seq .. ":" .. total .. ":" .. piece, "PARTY")) then
            seq, retries = seq + 1, 0
            C_Timer.After(SEND_EVERY, nextChunk)
        elseif retries < 5 then
            retries = retries + 1                       -- throttled: wait and send the same piece again
            C_Timer.After(3, nextChunk)
        else
            sending = false
        end
    end
    nextChunk()
    if ns.settings.debug then ns.pr(("debug: sharing %d recordings with the party (%d messages)"):format(n, total)) end
end
Y.Send = send

-- ---------------------------------------------------------------- receiving
local incoming = {}   -- [sender] = { id, parts, got, total, last }
local announced = {}  -- [sender] = time of the last chat line about them
local pending = false

local function fromPartyMember(sender)
    local short = Ambiguate and Ambiguate(sender, "none") or sender:match("^([^%-]+)")
    if not (short and UnitInParty(short)) then return false end
    local me = UnitIsUnit(short, "player")
    if canaccessvalue and not canaccessvalue(me) then return false end -- secret in restricted contexts: skip
    return not me
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- roster events come in bursts: one look a few seconds after the last of them
        if not pending then
            pending = true
            C_Timer.After(5, function() pending = false; send() end)
        end
        return
    end
    if canaccessvalue and not canaccessvalue(prefix) then return end
    if canaccessvalue and not canaccessvalue(message) then return end
    if canaccessvalue and not canaccessvalue(sender) then return end
    if prefix ~= PREFIX or channel ~= "PARTY" or not ns.db or not ns.settings.partySync or not ns.english then return end
    if type(sender) ~= "string" or type(message) ~= "string" or not fromPartyMember(sender) then return end
    local id, seq, total, piece = message:match("^(%d+):(%d+):(%d+):(.*)$")
    seq, total = tonumber(seq), tonumber(total)
    if not (id and seq and total) or total > MAX_CHUNKS or seq < 1 or seq > total or #piece > 255 then return end

    local now = GetTime()
    for who, t in pairs(incoming) do if now - t.last > STALE then incoming[who] = nil end end
    local t = incoming[sender]
    if not t or t.id ~= id then
        t = { id = id, parts = {}, got = 0, total = total }  -- one open transfer per sender
        incoming[sender] = t
    end
    if t.total ~= total then return end
    t.last = now
    if not t.parts[seq] then t.parts[seq] = piece; t.got = t.got + 1 end
    if t.got < t.total then return end
    incoming[sender] = nil

    local data = parse(table.concat(t.parts))
    if not data or (data.loc and data.loc ~= "enUS" and data.loc ~= "enGB") then return end
    local added = merge(data, sender)
    if added > 0 and (not announced[sender] or now - announced[sender] > 600) then
        announced[sender] = now
        ns.pr((L["got %d new recordings from %s. They get voiced in the next build."]):format(added, Ambiguate and Ambiguate(sender, "short") or sender))
    end
end)

table.insert(ns.onLogin, function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
end)

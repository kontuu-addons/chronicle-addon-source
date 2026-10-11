-- Chronicle / Immersion: when Immersion (by MunkDev) shows quests and gossip in its own talk box, Chronicle's voices
-- still start by themselves (they follow the game's quest events). Here: a small speaker button in Immersion's talk
-- box to replay or stop the line, Chronicle's own speaker window stays hidden while Immersion shows the NPC and the
-- text, and a one-time tip if Immersion's own text-to-speech would talk over the voices.
local _, ns = ...
local L = ns.L

local function frame() return rawget(_G, "ImmersionFrame") end

-- true while Immersion's talk box is on screen (Voice.lua then skips Chronicle's speaker window)
function ns.ExternalDialogShown()
    local f = frame()
    return f and f:IsShown() or false
end

local button

local function update()
    if not button then return end
    local key = ns.lastKey
    -- only the quest that's open now (gossip pages, or a quest from before, get no button)
    local open = GetQuestID and GetQuestID()
    if not open or open == 0 or open ~= ns.lastQuestID then key = nil end
    local has = key and ns.Voice.Get(key)
    button:SetShown(has and not ns.settings.journalOnly and true or false)
    button.icon:SetDesaturated(not ns.Voice.IsPlaying())
end

local function create(f)
    local box = f.TalkBox or f
    button = CreateFrame("Button", nil, box)
    button:SetSize(24, 24)
    button:SetPoint("TOPRIGHT", box, "TOPRIGHT", -14, -14)
    button:SetFrameLevel(box:GetFrameLevel() + 10)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function()
        if ns.Voice.IsPlaying() then ns.Voice.Stop() elseif ns.lastKey then ns.Voice.Play(ns.lastKey) end
        update()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Chronicle")
        GameTooltip:AddLine(L["Play or stop the voice for this quest."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:HookScript("OnShow", function()
        C_Timer.After(0.3, update)
        if ns.TalkingHead then ns.TalkingHead.Hide(true) end -- Immersion shows the NPC and the text
    end)
end

table.insert(ns.onLogin, function()
    local f = frame()
    if not f then return end
    create(f)
    hooksecurefunc(ns.Voice, "UpdateQuestButton", update)
    -- Immersion can read the text with the game's robot voice: say once that it would talk over Chronicle
    local cfg = rawget(_G, "ImmersionSetup")
    if type(cfg) == "table" and cfg.ttsenabled and not ns.db.immersionTip and not ns.settings.journalOnly then
        ns.db.immersionTip = true
        C_Timer.After(8, function()
            ns.pr(L["works with Immersion. Its own text-to-speech is on and will talk over Chronicle's voices: you can turn it off in Immersion's options."])
        end)
    end
end)

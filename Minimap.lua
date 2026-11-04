-- Chronicle / Minimap: a book on the minimap edge. Left-click: journal. Right-click: options. Drag: move.
-- Detached (option): the same book anywhere on the screen, dragged freely, for players who keep it by their action bars.
local _, ns = ...
local L = ns.L
local M = {}
ns.Minimap = M

local btn

local function place()
    btn:ClearAllPoints()
    if ns.settings.minimapFree then
        btn:SetParent(UIParent)
        btn:SetFrameStrata("MEDIUM")
        local pos = ns.settings.minimapFreePos
        if pos then
            btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
        else -- just detached: start where it sat on the minimap, then the player drags it away
            local a = math.rad(ns.settings.minimapAngle or 210)
            local r = (Minimap:GetWidth() / 2) + 5
            btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
        end
        return
    end
    btn:SetParent(Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    local a = math.rad(ns.settings.minimapAngle or 210)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function create()
    btn = CreateFrame("Button", nil, Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.Options.Open() else ns.Journal.Toggle() end
    end)
    btn:SetMovable(true); btn:SetClampedToScreen(true)
    btn:SetScript("OnDragStart", function(self)
        if ns.settings.minimapFree then self:StartMoving(); return end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.settings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            place()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if ns.settings.minimapFree then
            self:StopMovingOrSizing()
            local x, y = self:GetCenter() -- parented to UIParent: already in its coordinates
            ns.settings.minimapFreePos = { x, y }
            place()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Chronicle")
        GameTooltip:AddLine(L["Left-click: the story so far"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
end

-- With LibDataBroker and LibDBIcon loaded by another addon (most minimap button bags, Leatrix Plus and many others
-- bring them), Chronicle's icon is registered there, so those bags can collect it. Otherwise our own button.
local brokered = false

local function broker()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub("LibDBIcon-1.0", true)
    if not (LDB and DBI) then return nil end
    ns.settings.minimapIcon = ns.settings.minimapIcon or { minimapPos = ns.settings.minimapAngle or 210 }
    local obj = LDB:NewDataObject("Chronicle", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        OnClick = function(_, mouse)
            if mouse == "RightButton" then ns.Options.Open() else ns.Journal.Toggle() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Chronicle")
            tt:AddLine(L["Left-click: the story so far"], 1, 1, 1)
            tt:AddLine(L["Right-click: options"], 1, 1, 1)
        end,
    })
    if not obj then return nil end
    DBI:Register("Chronicle", obj, ns.settings.minimapIcon)
    return DBI
end

-- the book itself, when it is on screen (the tour points at it)
function M.Button() return btn and btn:IsVisible() and btn or nil end

-- Near a camp fire with a tale still to hear (Campfire.lua): a pulsing golden ring, and the book fades into a camp
-- fire and straight back, the book staying three seconds. On our own button or on the one LibDBIcon made for us.
local campOn, lit

local function decorate(b, icon)
    local glow = CreateFrame("Frame", nil, b)
    glow:SetAllPoints(b); glow:SetFrameLevel(b:GetFrameLevel() + 1)
    local ring = glow:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53); ring:SetPoint("TOPLEFT", b)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetBlendMode("ADD"); ring:SetVertexColor(1, 0.82, 0)
    glow.anim = ring:CreateAnimationGroup()
    glow.anim:SetLooping("BOUNCE")
    local pulse = glow.anim:CreateAnimation("Alpha")
    pulse:SetFromAlpha(0.6); pulse:SetToAlpha(1); pulse:SetDuration(0.9)
    local layer, sub = icon:GetDrawLayer()
    local fire = b:CreateTexture(nil, layer, nil, math.min((sub or 0) + 1, 7))
    fire:SetAllPoints(icon); fire:SetTexture("Interface\\Icons\\Spell_Fire_Fire"); fire:SetTexCoord(icon:GetTexCoord())
    fire:SetAlpha(0)
    glow.swap = fire:CreateAnimationGroup()
    glow.swap:SetLooping("REPEAT")
    local fadeIn = glow.swap:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(0.7); fadeIn:SetStartDelay(3); fadeIn:SetDuration(1); fadeIn:SetOrder(1)
    local fadeOut = glow.swap:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.7); fadeOut:SetToAlpha(0); fadeOut:SetDuration(1); fadeOut:SetOrder(2)
    glow.fire = fire
    b.campGlow = glow
end

function M.SetCampfire(on)
    on = on and true or false
    if on == campOn then return end
    campOn = on
    if lit then
        lit.campGlow.anim:Stop(); lit.campGlow.swap:Stop(); lit.campGlow:Hide(); lit.campGlow.fire:Hide()
        lit = nil
    end
    if not on then return end
    local b = btn and btn:IsShown() and btn
        or brokered and brokered.GetMinimapButton and brokered:GetMinimapButton("Chronicle")
    local icon = b and b.icon
    if not icon then return end -- shortcut: a button that appears while near a fire stays plain until the next fire
    if not b.campGlow then decorate(b, icon) end
    b.campGlow:Show(); b.campGlow.fire:Show(); b.campGlow.anim:Play(); b.campGlow.swap:Play()
    lit = b
end

function M.Update()
    if brokered == false then
        local ok, dbi = pcall(broker)
        brokered = ok and dbi or nil
    end
    local free = ns.settings.minimapFree
    -- the minimap bags only hold buttons on the minimap: a detached book is always our own button
    if brokered then
        local onMap = ns.settings.minimap and not free
        ns.settings.minimapIcon.hide = not onMap
        if onMap then brokered:Show("Chronicle") else brokered:Hide("Chronicle") end
    end
    if ns.settings.minimap and (free or not brokered) then
        if not btn then create() end
        place()
        btn:Show()
    elseif btn then
        btn:Hide()
    end
end

table.insert(ns.onLogin, function()
    if Minimap then M.Update() end
end)

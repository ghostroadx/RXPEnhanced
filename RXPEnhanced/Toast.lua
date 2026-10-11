-- RXP Enhanced: a toast when you reach a waypoint or RestedXP moves to the next step. A small card
-- in the cards' look rises into place as it fades in, stays for three seconds, then fades away
-- drifting up a little. It never takes the mouse, so it can't get in the way; "Move toast" in the
-- settings shows a sample you can drag into place.
--
-- When it shows:
--  - RestedXP moves to another step (not while a guide is loading and RestedXP jumps to your
--    saved step): the step you're on now.
--  - You reach a waypoint: RestedXP marks the spot reached (its arrow then moves on), or the
--    waypoint marker sees you within its arrive distance.
-- Things that happen together (you arrive, the step completes, RestedXP moves on) make one toast:
-- whatever comes within a moment is gathered, and a new step beats an arrival.

local ADDON_NAME = ...
local NS = _G.RXPEnhanced
if not (NS and NS.private and NS.Card and NS.Card.UI) then return end
local P, Card, UI = NS.private, NS.Card, NS.Card.UI
local Toast = {}
NS.Toast = Toast

local floor, max, min = math.floor, math.max, math.min
local IN_TIME, HOLD_TIME, OUT_TIME = 0.32, 3.0, 0.5
local RISE, DRIFT = 16, 6 -- px: rises this far into place; drifts up this far as it fades
local GATHER = 0.3 -- seconds: notices this close together make one toast
local SETTLE = 5 -- seconds after a guide loads with no step toasts (RestedXP jumps to your saved step)
local REPEAT = 15 -- seconds: the same spot doesn't toast twice
local WIDTH = 320
local DEFAULT_POINT = { "TOP", "TOP", 0, -170 }
-- The soft shadow (Media\toastshadow, made by tools/make_ui_assets.py): a 128 px nine-slice
-- with the card's edge 20 px in from each side, so with 24-unit corners it reaches 15 out.
local SHADOW_FILE = "Interface\\AddOns\\" .. (ADDON_NAME or "RXPEnhanced") .. "\\Media\\toastshadow"
local SHADOW_CORNER, SHADOW_OUT, SHADOW_DROP, SHADOW_ALPHA = 24, 15, 3, 0.6
Toast.TIMES = { inTime = IN_TIME, hold = HOLD_TIME, outTime = OUT_TIME, gather = GATHER, settle = SETTLE }

local db, rxp
local function ready()
    db = P.db()
    rxp = P.getRXP()
    return db ~= nil and rxp ~= nil
end

local f -- the toast
local anim = { phase = "hidden", t = 0 } -- phase: hidden, in, hold, out, moving
local pending -- { kind, build = function() return payload end, rank, at }
local watch = { guide = nil, index = nil, since = 0, element = nil, arrived = {} }

local function easeOutCubic(x) return 1 - (1 - x) ^ 3 end
local function easeInQuad(x) return x * x end

-- ---------------------------------------------------------------- drawing

local function build()
    f = UI.newPanel("RXPEnhancedToast")
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:EnableMouse(false)
    f:SetClampedToScreen(true)
    -- A soft drop shadow, a little below. Its textures belong to the toast, so they draw under
    -- its panel; an empty frame just sizes them.
    local box = CreateFrame("Frame", nil, f)
    box:EnableMouse(false)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", -SHADOW_OUT, SHADOW_OUT - SHADOW_DROP)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", SHADOW_OUT, -SHADOW_OUT - SHADOW_DROP)
    f.shadow = UI.nineSlice(f, SHADOW_FILE, "BACKGROUND", SHADOW_CORNER, -8, box)
    f.shadow:SetColor(0, 0, 0, SHADOW_ALPHA)
    f.header = f:CreateFontString(nil, "ARTWORK")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.title = f:CreateFontString(nil, "ARTWORK")
    f.sub = f:CreateFontString(nil, "ARTWORK")
    f.bar = f:CreateTexture(nil, "ARTWORK") -- a thin accent line down the left edge
    -- Move mode: drag it, and a hint under it.
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if anim.phase == "moving" then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point and db then db.toastPoint = { point, relPoint, x, y } end
    end)
    f:SetScript("OnUpdate", function(_, elapsed) Toast.Animate(elapsed) end)
    f:Hide()
    Toast.frame = f
end

local function place(offsetY)
    local p = (db and db.toastPoint) or DEFAULT_POINT
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4] + (offsetY or 0))
end

-- payload: { kind, header, title, sub, icon, tint }
local function layout(payload)
    local T = UI.SetTheme(db.cardTheme)
    local base = db.cardTextSize or 13
    local pad = 14
    local accent = payload.kind == "arrived" and UI.C.success or db.color
    UI.paintPanel(f)
    f:SetWidth(WIDTH)
    local inner = WIDTH - pad * 2
    UI.setText(f.header, "medium", base - 3, T.text3, inner, payload.header or "", 1)
    f.header:ClearAllPoints()
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -12)
    local y = -30
    local titleSize = base + 1
    UI.setIcon(f.icon, payload.icon or "navigation")
    UI.tint(f.icon, payload.kind == "arrived" and UI.C.success or (UI.TINT[payload.tint] or T.text2))
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y - floor((UI.lineHeight(titleSize) - 18) / 2))
    local h = UI.setText(f.title, "semibold", titleSize, T.text1, inner - 26, payload.title or "", 2)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 26, y)
    y = y - h
    if payload.sub and payload.sub ~= "" then
        y = y - 3
        local hs = UI.setText(f.sub, "regular", base - 1, T.text2, inner - 26, payload.sub, 2)
        f.sub:ClearAllPoints()
        f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 26, y)
        y = y - hs
    else
        f.sub:Hide()
    end
    local height = -y + 12
    f:SetHeight(height)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -12)
    f.bar:SetSize(2, max(10, height - 24))
    f.bar:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    Toast.shown = payload
end

-- ---------------------------------------------------------------- animation

function Toast.Animate(elapsed)
    if not f then return end
    local phase = anim.phase
    if phase == "hidden" then
        if f:IsShown() then f:Hide() end
        return
    elseif phase == "moving" then
        f:SetAlpha(1)
        return
    end
    -- The first frame after Show draws the starting pose; a long frame (a loading hitch)
    -- never skips the animation.
    if anim.fresh then anim.fresh = false; elapsed = 0 end
    anim.t = anim.t + min(elapsed or 0, 0.1)
    if phase == "in" then
        local p = min(1, anim.t / IN_TIME)
        local e = easeOutCubic(p)
        f:SetAlpha(e)
        place(-RISE * (1 - e)) -- rises into place
        if p >= 1 then anim.phase, anim.t = "hold", 0 end
    elseif phase == "hold" then
        f:SetAlpha(1)
        place(0)
        if anim.t >= HOLD_TIME - 1e-6 then anim.phase, anim.t = "out", 0 end
    elseif phase == "out" then
        local p = min(1, anim.t / OUT_TIME)
        f:SetAlpha(1 - easeInQuad(p))
        place(DRIFT * p) -- drifts up as it fades
        if p >= 1 then
            anim.phase, anim.t = "hidden", 0
            f:Hide()
        end
    end
end

-- Shows a toast now. A toast already up takes the new text and starts again from where it is.
function Toast.Show(payload)
    if not (payload and ready()) then return end
    if not f then build() end
    if anim.phase == "moving" then return end
    layout(payload)
    local alpha = (anim.phase == "hidden") and 0 or f:GetAlpha()
    anim.phase = "in"
    anim.t = IN_TIME * min(1, alpha) * 0.6 -- already showing: a short rise, not the whole way
    if anim.t == 0 then f:SetAlpha(0) end
    place(-RISE)
    f:Show()
    Toast.Animate(0)
    anim.fresh = true -- the next frame's time doesn't count: it draws the start
end

-- ---------------------------------------------------------------- what a toast says

local KIND_LABEL = { next = "NEXT STEP", back = "BACK TO", arrived = "ARRIVED" }

-- The toast for a step: the card's own words for the step you're on, else the step's label.
function Toast.PayloadFor(kind, step)
    if not (ready() and type(step) == "table") then return nil end
    local guide = rxp.currentGuide
    local total = type(guide) == "table" and type(guide.steps) == "table" and #guide.steps or nil
    local cur = P.call(rxp.GetGuideProgress)
    local index = step.index or cur
    local title, sub, icon, tint
    if index == cur and Card.BuildModel then
        local ok, m = pcall(Card.BuildModel)
        if ok and type(m) == "table" then
            title, icon, tint = m.headline, m.icon, m.tint
            sub = m.context or (m.rows and m.rows[1] and m.rows[1].text) or nil
        end
    end
    if not title then
        title = P.labelOf(step, 120)
        if Card.StepIcon then icon, tint = Card.StepIcon(step) end
    end
    local header = ("%s  ·  STEP %s%s"):format(KIND_LABEL[kind] or "STEP", tostring(index or "?"),
        total and (" OF " .. total) or "")
    return { kind = kind, header = header, title = title, sub = sub, icon = icon, tint = tint, index = index }
end

-- Something happened: gather it with anything else that comes within a moment.
local RANK = { arrived = 1, back = 2, next = 2 }
function Toast.Notify(kind, step)
    if not (ready() and db.toast) or anim.phase == "moving" then return end
    local rank = RANK[kind] or 1
    if pending and pending.rank > rank and GetTime() - pending.at < GATHER then return end
    pending = { kind = kind, step = step, rank = rank, at = GetTime() }
end

-- The waypoint marker saw you arrive (Waypoint.lua).
function Toast.Arrived(el)
    if type(el) ~= "table" or el.hidePin or type(el.step) ~= "table" then return end
    local last = watch.arrived[el]
    if last and GetTime() - last < REPEAT then return end
    watch.arrived[el] = GetTime()
    Toast.Notify("arrived", el.step)
end

-- ---------------------------------------------------------------- watching RestedXP

function Toast.Watch()
    if not ready() then return end
    local profile = rxp.settings and rxp.settings.profile
    if profile and profile.showEnabled == false then return end
    local now = GetTime()
    -- Step changes.
    local guide = rxp.currentGuide
    local cur = P.call(rxp.GetGuideProgress)
    if type(guide) == "table" and type(guide.steps) == "table" and type(cur) == "number" then
        local key = guide.key or guide.name
        if watch.guide ~= key then
            watch.guide, watch.index, watch.since = key, cur, now
        elseif cur ~= watch.index then
            local last = watch.index
            watch.index = cur
            if now - watch.since >= SETTLE and type(guide.steps[cur]) == "table" then
                Toast.Notify(cur < last and "back" or "next", guide.steps[cur])
            end
        end
    end
    -- A spot RestedXP marked reached: its arrow moves on and the old spot is flagged done.
    local af = _G.RXPG_ARROW
    local el = af and af.element
    if el ~= watch.element then
        local old = watch.element
        watch.element = el
        if type(old) == "table" and old.skip and not old.hidePin then Toast.Arrived(old) end
    end
end

local sinceWatch = 0
local function tick(elapsed)
    sinceWatch = sinceWatch + (elapsed or 0)
    if sinceWatch >= 0.1 - 1e-6 then
        sinceWatch = 0
        Toast.Watch()
    end
    if pending and GetTime() - pending.at >= GATHER - 1e-6 then
        local p = pending
        pending = nil
        if db and db.toast and anim.phase ~= "moving" then Toast.Show(Toast.PayloadFor(p.kind, p.step)) end
    end
end
Toast.Tick = tick

-- ---------------------------------------------------------------- settings

local SAMPLE = {
    kind = "next", header = "NEXT STEP  ·  STEP 61 OF 209", icon = "talk", tint = "talk",
    title = "Talk to |cff6fd08cBareth Dawnstone|r at the tower",
    sub = "Accept Escorting Erland",
}

-- Move mode: a sample toast that stays up and can be dragged. Call again to finish.
function Toast.SetMoving(on)
    if not ready() then return end
    if not f then build() end
    if on then
        layout({ kind = "next", header = "TOAST POSITION", icon = "hand", tint = "travel",
            title = "Drag this where you want toasts", sub = "Then click Done moving in the settings." })
        anim.phase = "moving"
        f:EnableMouse(true)
        place(0)
        f:SetAlpha(1)
        f:Show()
    else
        f:EnableMouse(false)
        anim.phase, anim.t = "hidden", 0
        f:Hide()
    end
    Toast.moving = on and true or false
end

function Toast.IsMoving() return anim.phase == "moving" end

function Toast.Preview()
    if Toast.IsMoving() then Toast.SetMoving(false) end
    Toast.Show(SAMPLE)
end

function Toast.ResetPosition()
    if not ready() then return end
    db.toastPoint = nil
    if f and f:IsShown() then place(0) end
end

-- Settings changed: a toast on screen takes the new look; turned off, it goes.
function Toast.Apply()
    if not (f and ready()) then return end
    if not db.toast and anim.phase ~= "moving" then
        anim.phase = "hidden"
        f:Hide()
    elseif Toast.shown and f:IsShown() then
        layout(Toast.shown)
    end
end

function Toast.Init()
    if Toast.driver or not ready() then return end
    local d = CreateFrame("Frame")
    d:SetScript("OnUpdate", function(_, elapsed) tick(elapsed) end)
    Toast.driver = d
end

Toast.anim = anim -- for the tests

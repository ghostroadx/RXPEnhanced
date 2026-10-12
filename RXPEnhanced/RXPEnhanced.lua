-- RXP Enhanced: a second RestedXP arrow, plus a world map and minimap pin, for the step
-- after the one RestedXP is on, so you can be thinking one step ahead.
--
-- It reads RestedXP's own guide data (its private AceAddon table) and never changes it. The next
-- step is the first later step that RestedXP won't skip: steps whose quest checks fail
-- (isOnQuest, isQuestTurnedIn, ...) or whose quest objectives are all done already are passed
-- over, as are #completewith steps. Of those, it points at the first one with a place to go.
--
-- Settings: /rxpe opens a small settings window; the same controls are under
-- Options > AddOns > RXP Enhanced.

local ADDON_NAME = ...
local NS = {}
_G.RXPEnhanced = NS

local function hexToRGB(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

local function rgbToHex(c)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

-- The colour choices in the settings window.
local PRESETS = {
    { name = "Muted red", hex = "d1706b" },
    { name = "Light blue", hex = "6ec6ff" },
    { name = "Gold", hex = "f2c75c" },
    { name = "Green", hex = "7fd67a" },
    { name = "Violet", hex = "b58cff" },
    { name = "White", hex = "e8e8e8" },
}
local DEFAULT_COLOR_INDEX = 6 -- white: the second arrow, the pins and the marked step
local DEFAULT_WP_COLOR_INDEX = 5 -- violet: the waypoint's pin and beacon

local DEFAULTS = {
    enabled = true,
    arrow = true,
    label = true, -- the step name and distance under the arrow
    mapPin = true,
    minimapPin = true,
    locked = false,
    scale = 1,
    alpha = 0.9,
    color = hexToRGB(PRESETS[DEFAULT_COLOR_INDEX].hex),
    point = nil,
    -- The guide card (Card.lua).
    card = true, -- the enhanced UI: the cards, the settings in their look, RestedXP's windows restyled
    cardHidesRXP = true, -- RestedXP's own window is shrunk away while the card is up
    cardLocked = false,
    cardCollapsed = false,
    cardTextSize = 11,
    cardWidth = 280,
    cardPalette = "card", -- "card", "safe" (colour-blind safe) or "rxp" (RestedXP's colours)
    cardTheme = "glass", -- "dark" or "glass"; the settings window takes it too
    nextCount = 3, -- rows in the step list (the mouse wheel scrolls ahead, or back to earlier steps)
    cardPoint = nil,
    skinRXP = true, -- RestedXP's active items, active targets and level splits get the cards' look
    targetGlow = true, -- a ring on Active targets buttons whose NPC is near you
    along = true, -- the along-the-way card
    alongCollapsed = false,
    alongDock = "right", -- where it sits against the main card: "bottom", "top", "left", "right" or "free"
    alongPoint = nil, -- its own spot, when "free"
    -- The in-world waypoint marker (Waypoint.lua).
    wpEnabled = true,
    wpStyle = "pin", -- "pin", "ring" or "beacon"
    wpScale = 2,
    wpColor = hexToRGB(PRESETS[DEFAULT_WP_COLOR_INDEX].hex), -- for the beacon and the pin
    wpLabel = true,
    wpQuest = false, -- quest steps: the game's quest navigation instead of RestedXP's coordinates
    wpOnNpc = true, -- stand on the step's NPC when its nameplate is on screen
    wpArrive = 10, -- yards
    wpSounds = true,
    wpSound = "chime",
    wpNewSound = true,
    -- The toast (Toast.lua).
    toast = true, -- a toast when you reach a waypoint or move to the next step
    toastPoint = nil, -- where it shows, once moved
    skipIntro = true, -- skip the opening cinematic on a new character's first login
    -- The timing log for the route engine (Log.lua).
    logTimes = false, -- off unless you turn it on
}
local OLD_DEFAULT_COLOR = { 0.43, 0.78, 1.0 } -- 1.0.0's light blue
local LOOKAHEAD = 60 -- steps to look through for the next one
local RETARGET = 0.5 -- seconds between looks
local PIN_TEXTURE = "Interface\\AddOns\\" .. (ADDON_NAME or "RXPEnhanced") .. "\\Media\\pin"
local ARROW_FALLBACK = "Interface\\AddOns\\RXPGuides\\Textures\\rxp_navigation_arrow-1"

local db
local rxp, HBD, HBDPins

local function msg(text)
    print("|cffd1706bRXP Enhanced:|r " .. text)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function getRXP()
    if rxp then return rxp end
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    rxp = AceAddon and AceAddon:GetAddon("RXPGuides", true) or nil
    return rxp
end

-- ---------------------------------------------------------------- which step is next

local function onQuest(id) return id and call(rxp.IsOnQuest, id) or false end
local function turnedIn(id, account) return id and call(rxp.IsQuestTurnedIn, id, account) or false end
local function questComplete(id) return id and call(rxp.IsQuestComplete, id) or false end

local function objectiveDone(id, obj)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return false end
    local objectives = call(C_QuestLog.GetQuestObjectives, id)
    local o = type(objectives) == "table" and objectives[tonumber(obj)]
    return o and o.finished and true or false
end

-- RestedXP's quest checks, evaluated the way its own functions do (functions.lua): true when the
-- check would skip the step.
local function guardSkips(el)
    local tag = el.tag
    if tag == "isOnQuest" or tag == "isNotOnQuest" then
        local on = false
        for _, id in pairs(el.questIds or {}) do
            if onQuest(id) then on = true end
        end
        if el.reverse or tag == "isNotOnQuest" then return on end
        return not on
    elseif tag == "isQuestTurnedIn" or tag == "isQuestAvailable" then
        local reverse = el.reverse or tag == "isQuestAvailable"
        local pass = false
        for _, id in pairs(el.questIds or {}) do
            local t = turnedIn(id, el.account)
            if reverse then t = not t end
            pass = pass or t
        end
        return not pass
    elseif tag == "isQuestComplete" or tag == "isQuestNotComplete" then
        local done = onQuest(el.questId) and questComplete(el.questId)
        return (not done) == (not el.reverse)
    end
    return false
end

-- Whether an objective is already done; nil for objectives this can't judge (a checkbox, a kill
-- count, getting somewhere), which count as still to do.
local function elementDone(el)
    local tag, q = el.tag, el.questId
    if tag == "accept" then
        return onQuest(q) or turnedIn(q)
    elseif tag == "turnin" then
        return turnedIn(q) or (el.skipIfMissing and not onQuest(q)) or false
    elseif tag == "complete" then
        if turnedIn(q) then return true end
        if not onQuest(q) then return el.skipIfMissing and true or false end
        if questComplete(q) then return true end
        if el.obj then return objectiveDone(q, el.obj) end
        return false
    elseif tag == "xp" and tonumber(el.level) and not el.reverseLogic then
        return (UnitLevel("player") or 0) >= tonumber(el.level)
    end
    return nil
end

local function objectivesDone(step)
    local judged = 0
    for _, el in ipairs(step.elements or {}) do
        if not el.textOnly then
            if not elementDone(el) then return false end
            judged = judged + 1
        end
    end
    return judged > 0
end

local function willSkip(step)
    if step.sticky or step.tip then return true end
    local profile = rxp.settings and rxp.settings.profile
    if not (profile and profile.disableAutoSkip) then
        for _, el in ipairs(step.elements or {}) do
            if guardSkips(el) then return true end
        end
    end
    return objectivesDone(step)
end

-- Where a step goes: its first Go to with a pin (the hidden waypoints of a path lead there), else
-- its first point of any kind.
local function placeOf(step)
    local first
    for _, el in ipairs(step.elements or {}) do
        if el.wx and el.wy and el.instance then
            if not el.hidePin then return el end
            first = first or el
        end
    end
    return first
end

-- Where step i of a guide happens. RestedXP's Speedrun guides often put the coordinates on a travel
-- step marked "#completewith next" ("Travel to Bael Modan") and leave the step it leads to ("Talk to
-- Feegly") without a Go to of its own. A step with no place takes the place of the travel step right
-- before it, or of a #completewith step in the same run that names its label. from: the first step
-- index to look back to (#completewith steps before it are already active, and lead elsewhere).
local function placeIn(guide, i, from)
    local step = guide and guide.steps and guide.steps[i]
    if type(step) ~= "table" then return nil end
    local place = placeOf(step)
    if place then return place end
    for j = i - 1, math.max(from or 1, 1), -1 do
        local s = guide.steps[j]
        if type(s) ~= "table" or not s.sticky then break end
        local leads = (s.completewith == "next" and j == i - 1) or (step.label ~= nil and s.completewith == step.label)
        if leads then
            local p = placeOf(s)
            if p then return p, s end
        end
    end
end

local function plain(s)
    s = s:gsub("|cRXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("^%s*>>%s*", ""):gsub("%s+", " ")
    return s
end

local function labelOf(step, limit)
    limit = limit or 64
    local t = step.arrowtext or step.title
    if not t then
        -- The step's first line of text (">>Talk to ..."), else the text on one of its Go tos.
        local fallback
        for _, el in ipairs(step.elements or {}) do
            local s = el.text
            if type(s) == "string" and s ~= "" then
                if s:find("%*quest%*") and el.questId then
                    local name = call(rxp.GetQuestName, el.questId)
                        or (C_QuestLog and call(C_QuestLog.GetTitleForQuestID, el.questId))
                    s = s:gsub("%*quest%*", name or ("quest " .. el.questId))
                end
                if el.tag ~= "goto" then
                    t = s
                    break
                end
                fallback = fallback or s
            end
        end
        t = t or fallback
    end
    t = plain(t or "")
    if t == "" then t = "Step " .. tostring(step.index or "?") end
    if #t > limit then t = t:sub(1, limit - 3) .. "..." end
    return t
end

-- The step after RestedXP's current one that will actually come up, and where it goes.
function NS.FindNext()
    if not getRXP() then return end
    local guide = rxp.currentGuide
    if type(guide) ~= "table" or guide.empty or type(guide.steps) ~= "table" then return end
    local current = call(rxp.GetGuideProgress)
    if type(current) ~= "number" then return end
    for i = current + 1, math.min(#guide.steps, current + LOOKAHEAD) do
        local step = guide.steps[i]
        if type(step) == "table" and not willSkip(step) then
            -- A step with no place of its own and no travel step leading to it happens where you
            -- already are (an item to equip, a second NPC beside the first): look past it.
            local place = placeIn(guide, i, current + 1)
            if place then
                return { step = step, index = step.index or i, place = place, label = labelOf(step), current = current }
            end
        end
    end
end

-- For Card.lua: the guide card reads RestedXP the same way.
NS.private = {
    call = call, getRXP = getRXP, onQuest = onQuest, turnedIn = turnedIn, questComplete = questComplete,
    guardSkips = guardSkips, elementDone = elementDone, objectivesDone = objectivesDone, willSkip = willSkip,
    placeOf = placeOf, placeIn = placeIn, plain = plain, labelOf = labelOf, hexToRGB = hexToRGB, rgbToHex = rgbToHex,
    db = function() return db end,
    hbd = function() return HBD end,
}

-- ---------------------------------------------------------------- the arrow

local arrow = CreateFrame("Frame", "RXPEnhancedArrow", UIParent)
arrow:SetSize(32, 32)
arrow:SetFrameStrata("MEDIUM")
arrow:SetClampedToScreen(true)
arrow:SetMovable(true)
arrow:EnableMouse(true)
arrow:Hide()
arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
arrow.tex:SetAllPoints()
arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
arrow.text:SetPoint("TOP", arrow, "BOTTOM", 0, -3)
arrow.text:SetJustifyH("CENTER")
arrow.distance = -1
arrow.orientation = 0

local function arrowTexture()
    local tex = _G.RXPG_ARROW and _G.RXPG_ARROW.texture and _G.RXPG_ARROW.texture:GetTexture()
    return tex or ARROW_FALLBACK
end

local function applyLook()
    arrow.tex:SetTexture(arrowTexture())
    arrow.tex:SetDesaturated(true)
    local c = db.color
    arrow.tex:SetVertexColor(c[1], c[2], c[3], 1)
    arrow.text:SetTextColor(c[1], c[2], c[3], 1)
    if rxp and rxp.font then pcall(arrow.text.SetFont, arrow.text, rxp.font, 9, "OUTLINE") end
    if db.label then arrow.text:Show() else arrow.text:Hide() end
    arrow:SetScale(db.scale)
    arrow:SetAlpha(db.alpha)
end

local function placeArrow()
    arrow:ClearAllPoints()
    local p = db.point
    if p then
        arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif _G.RXPG_ARROW then
        -- Under RestedXP's arrow and its two lines of text.
        arrow:SetPoint("TOP", _G.RXPG_ARROW, "BOTTOM", 0, -40)
    else
        arrow:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

arrow:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not db.locked then self:StartMoving() end
end)
arrow:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if point then db.point = { point, relPoint, x, y } end
end)

local function drawArrow(self)
    local ahead = NS.ahead
    if not ahead then return end
    local place = ahead.place
    local dist
    -- Wrapped: the position calls can fail in places the game hides it (and on secret values).
    local turned = pcall(function()
        local x, y, instance = HBD:GetPlayerWorldPosition()
        if not (x and y and instance == place.instance) then error("elsewhere") end
        local angle, d = HBD:GetWorldVector(instance, x, y, place.wx, place.wy)
        local facing = GetPlayerFacing()
        if not (angle and d and facing) then error("no direction") end
        self.tex:SetRotation(angle - facing)
        dist = math.floor(d)
    end)
    if not turned then
        -- On another continent (or the position isn't available): no direction to give.
        self.tex:SetRotation(0)
        self.tex:SetAlpha(0.25)
        if self.distance ~= -2 then
            self.distance = -2
            self.text:SetText(("Next: %s\n(elsewhere)"):format(ahead.label))
        end
        return
    end
    self.tex:SetAlpha(1)
    if dist ~= self.distance then
        self.distance = dist
        self.text:SetText(("Next: %s\n(%dyd)"):format(ahead.label, dist))
    end
end

-- ---------------------------------------------------------------- the map pins

local function makePin(size)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f.tex:SetTexture(PIN_TEXTURE)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local ahead = NS.ahead
        if not ahead then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local c = db.color
        GameTooltip:SetText(("Next: step %d"):format(ahead.index), c[1], c[2], c[3])
        GameTooltip:AddLine(ahead.label, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

local worldPin = makePin(16)
local miniPin = makePin(12)

local function clearPins()
    if not HBDPins then return end
    HBDPins:RemoveAllWorldMapIcons(NS)
    HBDPins:RemoveAllMinimapIcons(NS)
end

local function showPins()
    clearPins()
    local ahead = NS.ahead
    if not (HBDPins and ahead and db.enabled) then return end
    local c = db.color
    worldPin.tex:SetVertexColor(c[1], c[2], c[3], 1)
    miniPin.tex:SetVertexColor(c[1], c[2], c[3], 1)
    local p = ahead.place
    if db.mapPin then
        HBDPins:AddWorldMapIconWorld(NS, worldPin, p.instance, p.wx, p.wy, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
    end
    if db.minimapPin then
        -- On the minimap it rides the rim when it's out of range, so it shows the way there too.
        HBDPins:AddMinimapIconWorld(NS, miniPin, p.instance, p.wx, p.wy, true)
    end
end

-- ---------------------------------------------------------------- keeping up with RestedXP

local function rxpShowing()
    local profile = rxp and rxp.settings and rxp.settings.profile
    if profile and profile.showEnabled == false then return false end
    local inInstance = IsInInstance and IsInInstance()
    return not inInstance
end

local function sameTarget(a, b)
    if not a or not b then return a == b end
    return a.place == b.place and a.index == b.index and a.label == b.label
end

function NS.Refresh()
    if not (db and HBD) then return end
    local ahead = db.enabled and getRXP() and rxpShowing() and NS.FindNext() or nil
    local changed = NS.dirty or not sameTarget(ahead, NS.ahead)
    NS.dirty = false
    NS.ahead = ahead
    if changed then
        arrow.distance = -1
        showPins()
    end
    if ahead and db.arrow then
        if not arrow:IsShown() then arrow:Show() end
    elseif arrow:IsShown() then
        arrow:Hide()
    end
end

local driver = CreateFrame("Frame")
local elapsed = RETARGET
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= RETARGET then
        elapsed = 0
        NS.Refresh()
    end
    if arrow:IsShown() then drawArrow(arrow) end
end)
driver:Hide()

-- ---------------------------------------------------------------- the new-character intro
-- A new character's first login plays an opening cinematic (Escape, then Yes, skips it). With
-- skipIntro on it's skipped by itself, but only on a level 1 character with no XP yet, in its
-- first two minutes in the world, so cinematics later on still play.
local INTRO_WINDOW = 120 -- seconds after the first login's loading screen
local enteredAt -- when this session entered the world (-huge after a /reload)

local function introSkipWanted()
    local saved = db or RXPEnhancedDB -- a cinematic can start before PLAYER_LOGIN has run
    if type(saved) == "table" and saved.skipIntro == false then return false end
    if call(UnitLevel, "player") ~= 1 then return false end
    local xp = call(UnitXP, "player")
    if type(xp) == "number" and xp > 0 then return false end
    return enteredAt == nil or GetTime() - enteredAt <= INTRO_WINDOW
end
NS.IntroSkipWanted = introSkipWanted

local function introSkipped()
    NS.introSkipped = true
    msg("skipped the new-character intro (/rxpe intro to keep it next time).")
end

local intro = CreateFrame("Frame")
intro:RegisterEvent("PLAYER_ENTERING_WORLD")
intro:RegisterEvent("CINEMATIC_START")
intro:SetScript("OnEvent", function(_, event, a)
    if event == "PLAYER_ENTERING_WORLD" then
        if enteredAt == nil then enteredAt = a and GetTime() or -math.huge end -- a: the first login
    elseif event == "CINEMATIC_START" and a ~= false and introSkipWanted() then -- a: can be cancelled
        -- A moment later, once Blizzard's own handler has set the cinematic up.
        local function stop()
            if InCinematic and call(InCinematic) == false then return end
            if StopCinematic and pcall(StopCinematic) then introSkipped() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, stop) else stop() end
    end
end)
-- The same for a pre-rendered intro movie.
if MovieFrame and type(MovieFrame.PlayMovie) == "function" and hooksecurefunc then
    hooksecurefunc(MovieFrame, "PlayMovie", function(self)
        if not introSkipWanted() then return end
        local function stop()
            if self:IsShown() and self.FinishMovie and pcall(self.FinishMovie, self) then introSkipped() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, stop) else stop() end
    end)
end

local function init()
    RXPEnhancedDB = type(RXPEnhancedDB) == "table" and RXPEnhancedDB or {}
    db = RXPEnhancedDB
    -- 1.0.0 had one switch for both pins.
    if db.pins ~= nil then
        if db.mapPin == nil then db.mapPin = db.pins end
        if db.minimapPin == nil then db.minimapPin = db.pins end
        db.pins = nil
    end
    -- 1.0.0's light blue default becomes the new default colour.
    if type(db.color) == "table" and rgbToHex(db.color) == rgbToHex(OLD_DEFAULT_COLOR) then
        db.color = nil
    end
    if db.alongDock == nil and db.alongPoint then db.alongDock = "free" end -- 1.3 kept a dragged card in place
    -- 1.5 changed two defaults: the Pin marker, and the along-the-way card on the right. Settings
    -- still on the old defaults move to the new ones once.
    if not db.defaults15 then
        db.defaults15 = true
        if db.wpStyle == "ring" then db.wpStyle = "pin" end
        if db.alongDock == "bottom" then db.alongDock = "right" end
    end
    if db.wpStyle == "blizzard" then db.wpStyle = "pin" end -- that choice is gone
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and { unpack(v) } or v end
    end
    if NS.SetupSettings then NS.SetupSettings() end
    HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not (getRXP() and HBD and HBDPins) then
        msg("RestedXP isn't loaded, so there's nothing to follow.")
        return
    end
    applyLook()
    placeArrow()
    driver:Show()
    if NS.Card and NS.Card.Init then NS.Card.Init() end
    if NS.Waypoint and NS.Waypoint.Init then NS.Waypoint.Init() end
    if NS.Toast and NS.Toast.Init then NS.Toast.Init() end
    if NS.Log and NS.Log.Init then NS.Log.Init() end
    -- The game only picks up an addon's new files when it starts, not on /reload.
    if not (NS.Card and NS.Waypoint and NS.Toast and NS.Log) then
        msg("quit and restart WoW (not just /reload) to finish updating: some of its files aren't loaded yet.")
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:RegisterEvent("QUEST_TURNED_IN")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        init()
    else
        elapsed = RETARGET -- look again on the next frame
    end
end)


-- ---------------------------------------------------------------- settings window
-- The same controls appear twice: in a small movable window (/rxpe) and under
-- Options > AddOns > RXP Enhanced. Every change goes through settingsChanged, which redraws the
-- arrow and pins and brings both sets of controls up to date.

local WINDOW_WIDTH = 360
local panels = {}
local syncing = false

local function syncPanels()
    syncing = true
    for _, p in ipairs(panels) do p:Sync() end
    syncing = false
end

local function settingsChanged()
    if not db then return end
    applyLook()
    NS.dirty = true -- redraw the arrow and pins with the new settings
    NS.Refresh()
    if NS.Card and NS.Card.Apply then NS.Card.Apply() end
    if NS.Waypoint and NS.Waypoint.Apply then NS.Waypoint.Apply() end
    if NS.Toast and NS.Toast.Apply then NS.Toast.Apply() end
    if NS.Log and NS.Log.Apply then NS.Log.Apply() end
    if NS.SettingsLookChanged then NS.SettingsLookChanged() end
    syncPanels()
end
NS.SettingsChanged = settingsChanged

local function resetPosition()
    db.point = nil
    placeArrow()
end

local function resetAll()
    for k, v in pairs(DEFAULTS) do
        db[k] = type(v) == "table" and { unpack(v) } or v
    end
    db.cardPoint, db.alongPoint, db.toastPoint = nil, nil, nil
    if NS.Toast and NS.Toast.IsMoving and NS.Toast.IsMoving() then NS.Toast.SetMoving(false) end
    resetPosition()
    settingsChanged()
end

local function clickSound(on)
    if PlaySound and SOUNDKIT then
        pcall(PlaySound, on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function statusText()
    if not getRXP() then return "RestedXP isn't loaded, so there's nothing to follow." end
    if not db.enabled then return "Turned off." end
    local ahead = NS.ahead
    if ahead then return ("Next: step %d · %s"):format(ahead.index, ahead.label) end
    if not rxpShowing() then return "Hidden while RestedXP's guide is hidden or you're in an instance." end
    return "Nothing coming up in this guide has a place to go."
end

local function addTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function openColorPicker(key)
    key = type(key) == "string" and key or "color"
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        msg("the colour picker isn't available; use /rxpe color <hex> instead.")
        return
    end
    local c = db[key]
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3],
        hasOpacity = false,
        -- Called as the colour is dragged, so the change shows live.
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            db[key] = { r, g, b }
            settingsChanged()
        end,
        cancelFunc = function(previous)
            if previous then db[key] = { previous.r, previous.g, previous.b } end
            settingsChanged()
        end,
    })
end

-- ---------------------------------------------------------------- the cards' look
-- With Card.lua loaded, the settings are drawn like the guide cards, in the look picked for them
-- (Dark or Glass), and change with it: Inter text and rounded controls. Without it (an update
-- that isn't fully loaded yet), Blizzard's own controls.
local TEXT_STYLES = {
    heading = { "medium", 10, "text3", upper = true }, -- like the cards' "UP NEXT"
    title = { "semibold", 15, "text1" },
    label = { "regular", 12, "text1" },
    small = { "regular", 11, "text2" },
    note = { "regular", 11, "text3" },
    warn = { "regular", 11, "warn" },
    tab = { "medium", 12, "text3" },
    button = { "medium", 12, "text1" },
}
local BLIZZARD_FONTS = {
    heading = "GameFontNormal", title = "GameFontNormalLarge", label = "GameFontHighlight",
    small = "GameFontHighlightSmall", note = "GameFontDisableSmall", warn = "GameFontNormalSmall",
    tab = "GameFontNormal", button = "GameFontNormal",
}
local INK = { 0.067, 0.075, 0.090 } -- the tick on a ticked box: the dark card's colour
local ENHANCED_TIP = "The guide cards, this window in the cards' look, and RestedXP's other windows restyled. Off, RestedXP's own window comes back and everything is in RestedXP's and Blizzard's own look. The second arrow, the map pins, the waypoint marker and the toast have their own switches."
local LOG_TIP = "Off unless you turn it on. While it's on, it records how long each guide step takes you, and each kill: from engaging the mob to its death, the walk to it, and the loot and rest after. Also level-ups, deaths and time at NPCs. It's kept with these settings in WTF\\Account\\<account>\\SavedVariables\\RXPEnhanced.lua, written when you log out or reload; tools/timing_log.py turns it into the route engine's numbers."
local LOG_CLEAR_WINDOW = 4 -- seconds the Clear log button waits for its second click
local logClearArmed -- when Clear log was clicked once

local function cardUI() return NS.Card and NS.Card.UI end

-- Colours for the controls in a look.
local function controlColors(T)
    local glass = T.shadow and true or false
    return {
        fill = { 1, 1, 1, glass and 0.10 or 0.05 },
        ring = { T.text3[1], T.text3[2], T.text3[3], glass and 0.9 or 0.75 },
        track = { 1, 1, 1, glass and 0.22 or 0.12 },
        button = { 1, 1, 1, glass and 0.14 or 0.07 },
        hover = { 1, 1, 1, glass and 0.10 or 0.06 },
    }
end

-- Media\controls (tools/make_ui_assets.py), 32 px cells: 1 box, 2 box ring, 3 dot, 4 dot ring.
local function controlTexture(UI, tex, cell)
    tex:SetTexture(UI.CONTROLS_FILE)
    tex:SetTexCoord((cell - 1) / 4, cell / 4, 0, 1)
end

local function paint(tex, c, a) tex:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
local function solid(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end -- lines and tracks

local function setTextLook(fs, style, T)
    local UI = cardUI()
    UI.setFont(fs, style[1], style[2])
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, T.shadow and 0.7 or 0) -- a clear shadow for the dark look
end

-- Builds one set of controls inside parent. Returns the set and the height it used.
local function buildPanel(parent, opts)
    local p = { checks = {}, extraChecks = {}, sliders = {}, swatches = {}, radios = {}, tabs = {}, sections = {},
        texts = {}, paints = {} }
    local UI = opts.styled and cardUI() or nil
    local styled = UI ~= nil
    p.styled = styled
    local left, width = opts.inset, opts.width
    local y = -opts.inset
    local target = parent -- the frame the helpers below build into

    -- A text in one of TEXT_STYLES. own: its colour is set elsewhere (labels that grey out, tabs).
    local function text(frame, kind, value, own)
        local fs
        if styled then
            fs = frame:CreateFontString(nil, "ARTWORK")
            local style = TEXT_STYLES[kind]
            UI.setFont(fs, style[1], style[2]) -- now, so widths can be measured while building
            p.texts[#p.texts + 1] = { fs = fs, style = style, own = own }
            if value and style.upper then value = value:upper() end
        else
            fs = frame:CreateFontString(nil, "ARTWORK", BLIZZARD_FONTS[kind])
        end
        if value then fs:SetText(value) end
        return fs
    end

    local function divider(frame)
        local d = frame:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1)
        d:SetWidth(width)
        d:SetColorTexture(1, 1, 1, styled and 1 or 0.12)
        if styled then p.paints[#p.paints + 1] = function(T) solid(d, T.divider) end end
        return d
    end

    if opts.title then
        local title = text(parent, "title", "RXP Enhanced")
        title:SetPoint("TOPLEFT", left, y)
        y = y - 28
    end

    -- The arrow as it will look, turning slowly, and what it's pointing at right now.
    local preview = parent:CreateTexture(nil, "ARTWORK")
    preview:SetSize(40, 40)
    preview:SetPoint("TOPLEFT", left + width - 44, y + 2)
    local status = text(parent, "small")
    status:SetPoint("TOPLEFT", left, y)
    status:SetWidth(width - 56)
    status:SetHeight(36)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    y = y - 44

    local function header(value)
        local h = text(target, "heading", value)
        h:SetPoint("TOPLEFT", left, styled and y - 4 or y)
        y = y - 18
    end

    -- A checkbox (radio: a round one) in the cards' look. Its label is part of the button.
    local function cardToggle(radio)
        local cb = CreateFrame("CheckButton", nil, target)
        cb:SetSize(16, 16)
        cb.box = cb:CreateTexture(nil, "BACKGROUND")
        cb.box:SetAllPoints()
        controlTexture(UI, cb.box, radio and 3 or 1)
        cb.ring = cb:CreateTexture(nil, "BORDER")
        cb.ring:SetAllPoints()
        controlTexture(UI, cb.ring, radio and 4 or 2)
        cb.mark = cb:CreateTexture(nil, "ARTWORK")
        cb.mark:SetPoint("CENTER", cb, "CENTER", 0, 0)
        if radio then
            cb.mark:SetSize(6, 6)
            controlTexture(UI, cb.mark, 3)
        else
            cb.mark:SetSize(12, 12)
            UI.setIcon(cb.mark, "check")
        end
        cb.glow = cb:CreateTexture(nil, "HIGHLIGHT")
        cb.glow:SetAllPoints()
        controlTexture(UI, cb.glow, radio and 4 or 2)
        cb.Text = text(cb, "label", nil, true)
        cb.Text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        function cb:Paint(on)
            local T, K = p.T, p.K
            local checked = self:GetChecked() and true or false
            local a = on and 1 or 0.4
            if radio then
                paint(self.box, K.fill, K.fill[4] * a)
                paint(self.ring, checked and T.text1 or K.ring, (checked and 1 or K.ring[4]) * a)
                paint(self.mark, T.text1, a)
            else
                paint(self.box, checked and T.text1 or K.fill, (checked and 1 or K.fill[4]) * a)
                paint(self.ring, K.ring, checked and 0 or K.ring[4] * a)
                paint(self.mark, INK, a)
            end
            if checked then self.mark:Show() else self.mark:Hide() end
            paint(self.glow, T.text1, 0.5)
            local c = on and T.text1 or T.text3
            self.Text:SetTextColor(c[1], c[2], c[3], on and 1 or 0.6)
            self:SetHitRectInsets(0, -math.floor((self.Text:GetStringWidth() or 0) + 10), -4, -4)
        end
        return cb
    end

    -- needs: the settings that must be on for this one to matter (it's greyed out otherwise).
    local function check(key, label, tip, indent, needs)
        local cb
        if styled then
            cb = cardToggle(false)
            cb:SetPoint("TOPLEFT", left + (indent or 0), y - 4)
        else
            cb = CreateFrame("CheckButton", nil, target, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", left - 4 + (indent or 0), y)
            cb.Text:SetFontObject("GameFontHighlight")
        end
        cb.Text:SetText(label)
        cb:SetScript("OnClick", function(self)
            db[key] = self:GetChecked() and true or false
            clickSound(db[key])
            settingsChanged()
        end)
        if tip then addTooltip(cb, label, tip) end
        cb.needs, cb.key = needs, key
        -- The same setting can appear on two tabs; both stay in step.
        if p.checks[key] then table.insert(p.extraChecks, cb) else p.checks[key] = cb end
        y = y - 24
    end

    -- One of a set: ticks when db[key] == value.
    local function radio(key, value, label, tip, needs, x)
        local cb
        if styled then
            cb = cardToggle(true)
            cb:SetPoint("TOPLEFT", left + (x or 12) + 4, y - 4)
        else
            cb = CreateFrame("CheckButton", nil, target, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", left + (x or 12), y)
            cb.Text:SetFontObject("GameFontHighlight")
        end
        cb.Text:SetText(label)
        cb:SetScript("OnClick", function()
            db[key] = value
            if key == "wpSound" and NS.Waypoint then NS.Waypoint.PlaySound(value) else clickSound(true) end
            if key == "alongDock" and value == "free" and NS.Card and NS.Card.FreeAlong then NS.Card.FreeAlong() end
            settingsChanged()
        end)
        if tip then addTooltip(cb, label, tip) end
        cb.key, cb.value, cb.needs = key, value, needs
        p.radios[#p.radios + 1] = cb
        y = y - 24
    end

    local function slider(key, label, minValue, maxValue, step, format)
        local t = text(target, "label", label)
        t:SetPoint("TOPLEFT", left, y - 6)
        local function settle(value)
            local rounded = tonumber(("%.2f"):format(math.floor(value / step + 0.5) * step))
            if rounded == db[key] then return end
            db[key] = rounded
            settingsChanged()
        end
        local s
        if styled then
            -- A thin track, filled up to a round thumb; the mouse wheel steps it.
            s = CreateFrame("Slider", nil, target)
            s:SetOrientation("HORIZONTAL")
            s:SetSize(width - 72 - 52, 16)
            s:SetPoint("TOPLEFT", left + 72, y - 4)
            s:SetMinMaxValues(minValue, maxValue)
            s:SetValueStep(step)
            s:SetObeyStepOnDrag(true)
            s:EnableMouseWheel(true)
            s.track = s:CreateTexture(nil, "BACKGROUND")
            s.track:SetHeight(2)
            s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
            s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
            s.track:SetColorTexture(1, 1, 1, 1)
            s.thumb = s:CreateTexture(nil, "OVERLAY")
            s.thumb:SetSize(12, 12)
            controlTexture(UI, s.thumb, 3)
            s:SetThumbTexture(s.thumb)
            s.fill = s:CreateTexture(nil, "ARTWORK")
            s.fill:SetHeight(2)
            s.fill:SetPoint("LEFT", s.track, "LEFT", 0, 0)
            s.fill:SetPoint("RIGHT", s.thumb, "CENTER", 0, 0)
            s.fill:SetColorTexture(1, 1, 1, 1)
            s.label = text(target, "small")
            s.label:SetPoint("LEFT", s, "RIGHT", 10, 0)
            s.format = format
            function s:ShowValue(value)
                self.label:SetText(format(value))
                self.valueText = self.label:GetText()
            end
            s:SetScript("OnValueChanged", function(self, value)
                self:ShowValue(value)
                if not syncing then settle(value) end
            end)
            s:SetScript("OnMouseWheel", function(self, delta)
                local lo, hi = self:GetMinMaxValues()
                self:SetValue(math.max(lo, math.min(hi, (self:GetValue() or lo) + delta * step)))
            end)
            s:SetValue(db[key])
            s:ShowValue(db[key])
            p.paints[#p.paints + 1] = function(T, K)
                solid(s.track, K.track)
                solid(s.fill, T.text2)
                paint(s.thumb, T.text1)
            end
        else
            s = CreateFrame("Frame", nil, target, "MinimalSliderWithSteppersTemplate")
            s:SetSize(width - 76 - 40, 24)
            s:SetPoint("TOPLEFT", left + 72, y - 2)
            s:Init(db[key], minValue, maxValue, math.floor((maxValue - minValue) / step + 0.5),
                { [MinimalSliderWithSteppersMixin.Label.Right] = format })
            s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
                if syncing then return end
                settle(value)
            end, p)
        end
        p.sliders[key] = s
        y = y - 30
    end

    local function button(label, w, x, tipTitle, tipText, onClick)
        local b
        if styled then
            b = CreateFrame("Button", nil, target)
            b.bg = UI.nineSlice(b, UI.PANEL_FILE, "BACKGROUND", 6, 0)
            b.edge = UI.nineSlice(b, UI.BORDER_FILE, "BORDER", 6, 0)
            b.glow = UI.nineSlice(b, UI.PANEL_FILE, "HIGHLIGHT", 6, 0)
            local fs = text(b, "button")
            fs:SetPoint("CENTER", b, "CENTER", 0, 0)
            b:SetFontString(fs)
            p.paints[#p.paints + 1] = function(T, K)
                b.bg:SetColor(unpack(K.button))
                b.edge:SetColor(unpack(T.border))
                b.glow:SetColor(unpack(K.hover))
            end
        else
            b = CreateFrame("Button", nil, target, "UIPanelButtonTemplate")
        end
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", left + (x or 0), y)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        if tipTitle then addTooltip(b, tipTitle, tipText) end
        return b
    end

    -- A row of colour swatches plus Custom... for a colour setting. Returns the Custom button.
    local function swatchRow(key, label, defaultIndex, tip)
        local t = text(target, "label", label)
        t:SetPoint("TOPLEFT", left, y - 4)
        for i, preset in ipairs(PRESETS) do
            local b = CreateFrame("Button", nil, target)
            b:SetSize(20, 20)
            b:SetPoint("TOPLEFT", left + 72 + (i - 1) * 26, y)
            local c = hexToRGB(preset.hex)
            if styled then
                b.ring = b:CreateTexture(nil, "BACKGROUND") -- shows which colour is picked
                b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
                b.ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
                controlTexture(UI, b.ring, 2)
                local fill = b:CreateTexture(nil, "ARTWORK")
                fill:SetAllPoints()
                controlTexture(UI, fill, 1)
                fill:SetVertexColor(c[1], c[2], c[3], 1)
                local glow = b:CreateTexture(nil, "HIGHLIGHT")
                glow:SetAllPoints()
                controlTexture(UI, glow, 1)
                glow:SetVertexColor(1, 1, 1, 0.25)
                p.paints[#p.paints + 1] = function(T) paint(b.ring, T.text1) end
            else
                b.ring = b:CreateTexture(nil, "BACKGROUND") -- shows which colour is picked
                b.ring:SetPoint("TOPLEFT", -2, 2)
                b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
                b.ring:SetColorTexture(1, 1, 1, 1)
                local edge = b:CreateTexture(nil, "BORDER")
                edge:SetAllPoints()
                edge:SetColorTexture(0, 0, 0, 1)
                local fill = b:CreateTexture(nil, "ARTWORK")
                fill:SetPoint("TOPLEFT", 1, -1)
                fill:SetPoint("BOTTOMRIGHT", -1, 1)
                fill:SetColorTexture(c[1], c[2], c[3], 1)
                local glow = b:CreateTexture(nil, "HIGHLIGHT")
                glow:SetAllPoints(fill)
                glow:SetColorTexture(1, 1, 1, 0.25)
            end
            b:SetScript("OnClick", function()
                db[key] = hexToRGB(preset.hex)
                clickSound(true)
                settingsChanged()
            end)
            addTooltip(b, preset.name .. (i == defaultIndex and " (default)" or ""), tip)
            b.hex, b.key = preset.hex, key
            p.swatches[#p.swatches + 1] = b
        end
        local rowY = y
        y = y + 1
        local custom = button("Custom...", 72, 72 + #PRESETS * 26 + 4, "Custom colour", "Pick any colour. It changes as you drag.",
            function() openColorPicker(key) end)
        y = rowY
        return custom
    end

    -- Four tabs: the arrow and pins, the waypoint marker, the guide cards, and the rest.
    local tabLine = divider(parent)
    tabLine:SetPoint("TOPLEFT", left, y - 22)
    local tabX = 0
    local function tab(id, label)
        local b = CreateFrame("Button", nil, parent)
        b:SetPoint("TOPLEFT", left + tabX, y)
        b.text = text(b, "tab", label, true)
        b.text:SetPoint("TOPLEFT", 0, -4)
        local w = math.floor((b.text:GetStringWidth() or 80) + 0.5)
        b:SetSize(w + 4, 22)
        b.line = b:CreateTexture(nil, "OVERLAY")
        if styled then b.line:SetColorTexture(1, 1, 1, 1) else b.line:SetColorTexture(1, 0.82, 0, 1) end
        b.line:SetHeight(2)
        b.line:SetPoint("TOPLEFT", 0, -21)
        b.line:SetWidth(w)
        b:SetScript("OnClick", function()
            p.tab = id
            clickSound(true)
            p:Sync()
        end)
        b.id = id
        p.tabs[#p.tabs + 1] = b
        tabX = tabX + w + 16
    end
    tab("arrow", "Arrow & pins")
    tab("waypoint", "Waypoint")
    tab("card", "Guide cards")
    tab("general", "General")
    y = y - 34
    local sectionTop = y
    p.tab = opts.tab or "arrow"

    local function section(id)
        local f = CreateFrame("Frame", nil, parent)
        f:SetPoint("TOPLEFT", 0, sectionTop)
        f:SetSize(left * 2 + width, 10)
        p.sections[id] = f
        target, y = f, 0
        return f
    end

    -- The second arrow and the map pins.
    section("arrow")
    header("Show")
    check("enabled", "Show the next step", "Everything below: the second arrow and the map pins.")
    check("arrow", "Second arrow", "A second arrow under RestedXP's, pointing at the step after yours.", 16, { "enabled" })
    check("label", "Step name and distance under it", nil, 32, { "enabled", "arrow" })
    check("mapPin", "World map pin", "A pin on the world map at the next step.", 16, { "enabled" })
    check("minimapPin", "Minimap pin", "A pin on the minimap. When the next step is out of range it sits on the minimap's edge, pointing the way.", 16, { "enabled" })

    y = y - 8
    header("Arrow")
    check("locked", "Lock in place", "Unlocked, you can drag the arrow anywhere on screen.")
    slider("scale", "Size", 0.4, 2.5, 0.05, function(v) return ("%.2f"):format(v) end)
    slider("alpha", "Opacity", 0.2, 1, 0.05, function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)

    p.custom = swatchRow("color", "Colour", DEFAULT_COLOR_INDEX, "Used for the second arrow, the pins, and the marked step in the guide card's Up next list.")
    y = y - 32
    p.resetPosition = button("Reset position", 130, 0, "Reset position", "Put the arrow back under RestedXP's arrow.", function()
        resetPosition()
        settingsChanged()
    end)
    y = y - 26
    local arrowHeight = -y

    -- The in-world waypoint marker.
    section("waypoint")
    header("Waypoint")
    check("wpEnabled", "Waypoint marker in the world", "Marks the spot RestedXP's arrow points at, in the game world, using the game's own waypoint. Off screen, an arrow at the edge points the way. While it's on, the game's In-Game Navigation option is on too (it has to be for the game to place waypoints on screen); it goes back to how it was when you log out.")
    check("wpLabel", "Step name and distance under it", nil, 16, { "wpEnabled" })
    check("wpQuest", "On quest steps, use the game's quest navigation", "Instead of RestedXP's coordinates: for a turn-in that's ready it points at the turn-in NPC, for objectives at their area. Off (the default), it always uses RestedXP's coordinates.", 16, { "wpEnabled" })
    check("wpOnNpc", "Stand on the step's NPC when you can see it", "When the NPC the step leads to has its nameplate on screen, the marker stands right on that NPC. Turn on friendly nameplates for this to see quest NPCs.", 16, { "wpEnabled" })
    check("arrow", "Second arrow", "The second, coloured arrow under RestedXP's that points at the step after yours. The same switch as on the Arrow & pins tab.")
    y = y - 4
    local styleText = text(target, "label", "Marker")
    styleText:SetPoint("TOPLEFT", left, y - 4)
    y = y - 22
    local styles = NS.Waypoint and NS.Waypoint.STYLES or {}
    for i, st in ipairs(styles) do
        local rowY = y
        radio("wpStyle", st.key, st.name, st.tip, { "wpEnabled" }, (i % 2 == 1) and 12 or 170)
        if i % 2 == 1 and i < #styles then y = rowY end
    end
    slider("wpScale", "Size", 0.5, 2, 0.05, function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
    p.wpCustom = swatchRow("wpColor", "Colour", DEFAULT_WP_COLOR_INDEX, "Used for the beacon and the pin.")
    y = y - 32
    slider("wpArrive", "Arrive at", 5, 30, 1, function(v) return ("%d yd"):format(math.floor(v + 0.5)) end)
    y = y - 4
    header("Sounds")
    check("wpSounds", "Waypoint sounds", "A sound when you reach a waypoint.")
    local sounds = NS.Waypoint and NS.Waypoint.SOUNDS or {}
    for i, snd in ipairs(sounds) do
        local rowY = y
        radio("wpSound", snd.key, snd.name, "Click to hear it.", { "wpSounds" }, (i % 2 == 1) and 12 or 170)
        if i % 2 == 1 and i < #sounds then y = rowY end
    end
    check("wpNewSound", "A soft tick for each new waypoint", nil, 0, { "wpSounds" })
    y = y - 4
    header("Toast")
    check("toast", "Toast when you arrive or move to the next step", "A small card with the step, in the cards' look. It rises in, stays three seconds, then fades. It never takes the mouse.")
    local function toastCall(name, ...)
        if NS.Toast and NS.Toast[name] then return NS.Toast[name](...) end
    end
    p.toastMove = button("Move toast", 110, 0, "Move toast", "Shows a sample toast you can drag where you want it. Click Done moving when it's placed.", function()
        toastCall("SetMoving", not toastCall("IsMoving"))
        clickSound(true)
        syncPanels()
    end)
    p.toastPreview = button("Preview", 90, 116, "Preview", "Shows a sample toast, the way it appears and fades.", function()
        toastCall("Preview")
        syncPanels()
    end)
    p.toastReset = button("Reset position", 120, 212, "Reset position", "Puts the toast back at the top of the screen.", function()
        toastCall("ResetPosition")
        clickSound(true)
    end)
    y = y - 26
    -- Another waypoint addon draws its own marker; offer to turn it off.
    p.otherText = text(target, "warn")
    p.otherText:SetPoint("TOPLEFT", left, y - 6)
    p.otherText:SetWidth(width - 150)
    p.otherText:SetJustifyH("LEFT")
    p.otherButton = button("Turn it off", 140, width - 140, "Turn it off",
        "It draws its own marker, so with both on you'd see two. This turns it off for your next reload; turn it back on any time in the AddOns list.",
        function()
            if NS.Waypoint and NS.Waypoint.otherDisabled then
                ReloadUI()
            elseif NS.Waypoint then
                NS.Waypoint.DisableOther()
                syncPanels()
            end
        end)
    y = y - 30
    local waypointHeight = -y

    -- The guide cards.
    section("card")
    header("Guide cards")
    check("card", "Use enhanced UI", ENHANCED_TIP)
    check("cardHidesRXP", "Hide RestedXP's window while the card is up", "RestedXP keeps working in the background. The eye button on the card brings its window back.", 16, { "card" })
    check("along", "Along-the-way card", "A second card with every open #completewith step and all its lines: things to kill, loot or watch for while you go.", 16, { "card" })
    local docks = {
        { "bottom", "Below", "Under the main card, moving with it." },
        { "top", "Above", "Over the main card, moving with it." },
        { "left", "Left", "To the left of the main card, moving with it." },
        { "right", "Right", "To the right of the main card, moving with it." },
        { "free", "Free", "Wherever you drag it. Dragging it also picks this." },
    }
    for i, d in ipairs(docks) do
        local rowY = y
        local col = (i - 1) % 3
        radio("alongDock", d[1], d[2], d[3], { "card", "along" }, 36 + col * 96)
        if col < 2 and i < #docks then y = rowY end
    end
    check("cardLocked", "Lock the cards in place", "Unlocked, you can drag each card by its top row.", 16, { "card" })
    y = y - 8
    header("Layout")
    slider("nextCount", "Up next", 1, 10, 1, function(v) local n = math.floor(v + 0.5) return n == 1 and "1 step" or (n .. " steps") end)
    slider("cardTextSize", "Text size", 11, 16, 1, function(v) return ("%d px"):format(math.floor(v + 0.5)) end)
    slider("cardWidth", "Width", 240, 420, 10, function(v) return tostring(math.floor(v + 0.5)) end)
    local lookText = text(target, "label", "Look")
    lookText:SetPoint("TOPLEFT", left, y - 5)
    local lookY = y
    radio("cardTheme", "dark", "Dark", "A dark, solid card. Easiest to read anywhere. These settings take the same look.", { "card" }, 60)
    y = lookY
    radio("cardTheme", "glass", "Glass", "Frosted white glass: the world shows through, softened. These settings take the same look.", { "card" }, 150)
    y = y - 4
    local paletteText = text(target, "label", "Colours for names and items")
    paletteText:SetPoint("TOPLEFT", left, y - 4)
    y = y - 22
    -- One row: Soft, Colour-blind safe, RestedXP's.
    local paletteY = y
    radio("cardPalette", "card", "Soft", "Calm versions of RestedXP's colours, made for the cards: green for friendly, coral for enemies, cyan for loot.", { "card" }, 12)
    y = paletteY
    radio("cardPalette", "safe", "Colour-blind safe", "Blue for friendly, orange for enemies, so they stay apart with any kind of colour blindness.", { "card" }, 92)
    y = paletteY
    radio("cardPalette", "rxp", "RestedXP's", "RestedXP's own colours, whatever its settings use.", { "card" }, 232)
    y = y - 8
    p.resetCard = button("Reset card positions", 160, 0, "Reset card positions", "Put both cards back where they started.", function()
        db.cardPoint, db.alongPoint, db.alongDock = nil, nil, DEFAULTS.alongDock
        settingsChanged()
    end)
    y = y - 26
    local cardHeight = -y

    -- Everything else.
    section("general")
    header("Look")
    check("card", "Use enhanced UI", ENHANCED_TIP)
    check("skinRXP", "Restyle RestedXP's other windows", "Active items, active targets and level splits get the cards' look. Only the look changes: RestedXP's buttons work just as before, and its own \"hide background\" settings still apply.", 16, { "card" })
    y = y - 8
    header("New characters")
    check("skipIntro", "Skip the intro when a new character first logs in", "The opening cinematic plays on a new character's first login; this skips it for you, as if you'd pressed Escape and Yes. Only on a level 1 character's first minutes in the world: cinematics later on still play.")
    y = y - 8
    header("RestedXP's windows")
    check("targetGlow", "Highlight active targets near you", "A green ring on each Active targets button whose NPC is near you, before you target or mouse over it. It sees NPCs whose nameplates are showing (turn on friendly nameplates to catch quest NPCs, and enemy ones for mobs), plus whatever RestedXP's own proximity scan finds when that's on in RestedXP.")
    y = y - 8
    header("Timing log")
    check("logTimes", "Log step and kill times for the route engine", LOG_TIP)
    p.logStatus = text(target, "small")
    p.logStatus:SetPoint("TOPLEFT", left, y - 4)
    p.logStatus:SetWidth(width)
    p.logStatus:SetJustifyH("LEFT")
    y = y - 42
    p.logNew = button("New session", 110, 0, "New session", "Starts a new session in the log, kept apart from what came before: a fresh character, or a run you want timed on its own. Sessions also start by themselves when you log in after more than 15 minutes away.", function()
        if not NS.Log then return end
        NS.Log.NewSession()
        clickSound(true)
        syncPanels()
    end)
    p.logClear = button("Clear log", 120, 116, "Clear log", "Deletes everything logged so far. Click twice: the second click deletes it.", function()
        if not NS.Log then return end
        if logClearArmed and GetTime() - logClearArmed <= LOG_CLEAR_WINDOW then
            logClearArmed = nil
            NS.Log.Clear()
            msg("timing log cleared.")
        else
            logClearArmed = GetTime()
        end
        clickSound(true)
        syncPanels()
    end)
    y = y - 26
    local generalHeight = -y

    local tallest = math.max(arrowHeight, waypointHeight, cardHeight, generalHeight)
    for _, f in pairs(p.sections) do f:SetHeight(tallest) end
    target = parent
    y = sectionTop - tallest - 4
    local bottomLine = divider(parent)
    bottomLine:SetPoint("TOPLEFT", left, y)
    y = y - 10

    p.resetAll = button("Reset all", 110, 0, "Reset all", "Every setting back to how it started, and the arrow, cards and toast back in place.", resetAll)
    p.saveReload = button("Save and reload", 130, 116, "Save and reload", "Saves your settings and reloads the interface. WoW writes addon settings to disk when it reloads or you log out.", function()
        if ReloadUI then ReloadUI() end
    end)
    y = y - 26

    if opts.tip then
        y = y - 10
        local tip = text(parent, "note", "Type /rxpe to open these settings in a small window you can keep beside the arrow.")
        tip:SetPoint("TOPLEFT", left, y)
        tip:SetWidth(width)
        tip:SetJustifyH("LEFT")
        y = y - 14
    end

    -- Keeps the preview turning and the status line current while the controls are on screen.
    local ticker = CreateFrame("Frame", nil, parent)
    local turn, since = 0, 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        turn = (turn + elapsed * 0.8) % (2 * math.pi)
        preview:SetRotation(turn)
        since = since + elapsed
        if since >= 0.5 then
            since = 0
            status:SetText(statusText())
            if p.logStatus and p.logStatus:IsVisible() then p:SyncLog() end
        end
    end)

    local function usable(needs)
        for _, need in ipairs(needs or {}) do
            if not db[need] then return false end
        end
        return true
    end

    local function syncToggle(cb, checked)
        cb:SetChecked(checked)
        local on = usable(cb.needs)
        cb:SetEnabled(on)
        if cb.Paint then
            cb:Paint(on)
        elseif on then
            cb.Text:SetTextColor(1, 1, 1)
        else
            cb.Text:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- The timing log's line and buttons.
    function p:SyncLog()
        local L = NS.Log
        self.logStatus:SetText(L and L.StatusText() or "Needs a full restart of WoW (not just /reload) to load.")
        if logClearArmed and GetTime() - logClearArmed > LOG_CLEAR_WINDOW then logClearArmed = nil end
        self.logClear:SetText(logClearArmed and "Click to confirm" or "Clear log")
        self.logNew:SetEnabled(L ~= nil)
        self.logClear:SetEnabled(L ~= nil)
    end

    function p:Sync()
        if styled then
            -- The look picked for the cards. Fonts are set again each time, which also mends
            -- any text that came out blank the first time.
            local T = UI.THEMES[db.cardTheme] or UI.THEMES.dark
            self.T, self.K = T, controlColors(T)
            for _, e in ipairs(self.texts) do
                setTextLook(e.fs, e.style, T)
                if not e.own then
                    local c = e.style[3] == "warn" and UI.C.warn or T[e.style[3]]
                    e.fs:SetTextColor(c[1], c[2], c[3], 1)
                end
            end
            for _, fn in ipairs(self.paints) do fn(T, self.K) end
            if self.chrome then self.chrome(T) end
        end
        for _, cb in pairs(self.checks) do syncToggle(cb, db[cb.key] and true or false) end
        for _, cb in ipairs(self.extraChecks) do syncToggle(cb, db[cb.key] and true or false) end
        for _, cb in ipairs(self.radios) do syncToggle(cb, db[cb.key] == cb.value) end
        for key, s in pairs(self.sliders) do
            s:SetValue(db[key])
            if s.ShowValue then s:ShowValue(db[key]) end
        end
        for _, b in ipairs(self.swatches) do
            if b.hex == rgbToHex(db[b.key]) then b.ring:Show() else b.ring:Hide() end
        end
        local W = NS.Waypoint
        local other
        if W and W.OtherWaypointAddon then other = select(2, W.OtherWaypointAddon()) end
        if other and db.wpEnabled then
            self.otherText:SetText(W.otherDisabled and ("%s turns off when you reload."):format(other)
                or ("%s is also running: you'll see two markers."):format(other))
            self.otherButton:SetText(W.otherDisabled and "Reload now" or ("Turn off %s"):format(other))
            self.otherText:Show()
            self.otherButton:Show()
        else
            self.otherText:Hide()
            self.otherButton:Hide()
        end
        if self.toastMove then
            local moving = NS.Toast and NS.Toast.IsMoving and NS.Toast.IsMoving()
            self.toastMove:SetText(moving and "Done moving" or "Move toast")
        end
        if self.logStatus then self:SyncLog() end
        for _, b in ipairs(self.tabs) do
            local selected = b.id == self.tab
            if styled then
                local c = selected and self.T.text1 or self.T.text3
                b.text:SetTextColor(c[1], c[2], c[3], 1)
                solid(b.line, self.T.text1)
            elseif selected then
                b.text:SetTextColor(1, 0.82, 0)
            else
                b.text:SetTextColor(0.6, 0.6, 0.6)
            end
            if selected then b.line:Show() else b.line:Hide() end
        end
        for id, f in pairs(self.sections) do
            if id == self.tab then f:Show() else f:Hide() end
        end
        local c = db.color
        preview:SetTexture(arrowTexture())
        preview:SetDesaturated(true)
        preview:SetVertexColor(c[1], c[2], c[3], 1)
        preview:SetAlpha(db.alpha)
        status:SetText(statusText())
        self.statusText = status -- for the tests
        self.preview = preview
    end

    panels[#panels + 1] = p
    p:Sync()
    return p, -y + opts.inset
end

local window
local function windowClosed()
    if NS.Toast and NS.Toast.IsMoving and NS.Toast.IsMoving() then NS.Toast.SetMoving(false) end
end

-- Which look the window takes: the cards' with the enhanced UI on, Blizzard's with it off (or
-- when Card.lua isn't loaded).
local function windowLook() return (db.card and cardUI()) and "card" or "blizzard" end

-- One window, two looks: each look is a frame filling the window, with its own set of controls,
-- built the first time it's needed.
local function buildLook(f, look)
    local UI = cardUI()
    local c, p, height
    if look == "card" then
        -- A card of its own, with the cards' small header.
        c = CreateFrame("Frame", nil, f)
        c:SetAllPoints(f)
        c.layers = { UI.nineSlice(c, UI.PANEL_FILE, "BACKGROUND", 8, -7), UI.nineSlice(c, UI.PANEL_FILE, "BACKGROUND", 8, -6) }
        c.edge = UI.nineSlice(c, UI.BORDER_FILE, "BORDER", 8)
        c.titleText = c:CreateFontString(nil, "ARTWORK")
        c.titleText:SetPoint("TOPLEFT", 16, -16)
        UI.setFont(c.titleText, "medium", 10) -- a font before any text
        c.titleText:SetText("RXP ENHANCED  ·  SETTINGS")
        c.close = CreateFrame("Button", nil, c)
        c.close:SetSize(20, 20)
        c.close:SetPoint("TOPRIGHT", -10, -11)
        c.close.icon = c.close:CreateTexture(nil, "ARTWORK")
        c.close.icon:SetSize(14, 14)
        c.close.icon:SetPoint("CENTER", c.close, "CENTER", 0, 0)
        UI.setIcon(c.close.icon, "close")
        c.close:SetScript("OnClick", function() f:Hide() end)
        local content = CreateFrame("Frame", nil, c)
        content:SetPoint("TOPLEFT", 0, -30)
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        p, height = buildPanel(content, { inset = 16, width = WINDOW_WIDTH - 32, styled = true })
        p.chrome = function(T)
            UI.SetTheme(db.cardTheme)
            UI.paintPanel(c)
            setTextLook(c.titleText, TEXT_STYLES.heading, T)
            c.titleText:SetTextColor(T.text3[1], T.text3[2], T.text3[3], 1)
            paint(c.close.icon, T.text3)
        end
        c.close:SetScript("OnEnter", function() if p.T then paint(c.close.icon, p.T.text1) end end)
        c.close:SetScript("OnLeave", function() if p.T then paint(c.close.icon, p.T.text3) end end)
        height = height + 30
    else
        c = CreateFrame("Frame", nil, f, "DefaultPanelTemplate")
        c:SetAllPoints(f)
        c:SetTitle("RXP Enhanced")
        c.CloseButton = CreateFrame("Button", nil, c, "UIPanelCloseButtonDefaultAnchors")
        c.CloseButton:SetScript("OnClick", function() f:Hide() end)
        local content = CreateFrame("Frame", nil, c)
        content:SetPoint("TOPLEFT", 4, -22)
        content:SetPoint("BOTTOMRIGHT", -4, 4)
        p, height = buildPanel(content, { inset = 12, width = WINDOW_WIDTH - 8 - 24, styled = false })
        height = height + 26
    end
    -- Either look drags the window.
    c:EnableMouse(true)
    c:RegisterForDrag("LeftButton")
    c:SetScript("OnDragStart", function() f:StartMoving() end)
    c:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    c:Hide()
    return { chrome = c, panel = p, height = height }
end

local function buildWindow()
    local f = CreateFrame("Frame", "RXPEnhancedSettings", UIParent)
    f:SetSize(WINDOW_WIDTH, 100)
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.looks = {}
    -- Shows the window in a look, on the tab it was on.
    function f:UseLook(look)
        local old = self.looks[self.look]
        local set = self.looks[look]
        if not set then
            set = buildLook(self, look)
            self.looks[look] = set
        end
        if old and old ~= set then
            set.panel.tab = old.panel.tab
            old.chrome:Hide()
        end
        if self.tab then set.panel.tab, self.tab = self.tab, nil end
        self.look, self.panel, self.chrome = look, set.panel, set.chrome
        self:SetHeight(set.height)
        set.chrome:Show()
        set.panel:Sync()
    end
    f:SetScript("OnShow", function(self) self:UseLook(windowLook()) end)
    f:SetScript("OnHide", windowClosed)
    if UISpecialFrames then table.insert(UISpecialFrames, "RXPEnhancedSettings") end -- Escape closes it
    f:UseLook(windowLook())
    f:Hide()
    return f
end

-- The enhanced UI was turned on or off: an open window changes look.
function NS.SettingsLookChanged()
    if window and window:IsShown() and window.look ~= windowLook() then window:UseLook(windowLook()) end
end

-- tab: open on that tab ("arrow", "waypoint", "card" or "general"), and keep it open.
function NS.OpenSettings(tab)
    if not db then return end
    window = window or buildWindow()
    if tab then
        window.tab = tab
        if window:IsShown() then window:UseLook(windowLook()) else window:Show() end
    elseif window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

-- Options > AddOns > RXP Enhanced.
function NS.SetupSettings()
    if NS.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local frame = CreateFrame("Frame")
    local p = buildPanel(frame, { inset = 16, width = WINDOW_WIDTH - 24, title = true, tip = true, styled = false })
    frame.panel = p
    frame.OnRefresh = function() p:Sync() end
    frame.OnDefault = function() resetAll() end
    frame:SetScript("OnShow", function() p:Sync() end)
    frame:SetScript("OnHide", function()
        if NS.Toast and NS.Toast.IsMoving and NS.Toast.IsMoving() then NS.Toast.SetMoving(false) end
    end)
    frame:Hide() -- the Options window shows it when its entry is picked
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, frame, "RXP Enhanced")
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
        NS.category = category
        NS.optionsFrame = frame
    end
end

-- ---------------------------------------------------------------- /rxpe

local function onOff(v) return v and "|cff00ff00on|r" or "|cffff5555off|r" end

local OPEN_WORDS = { [""] = true, config = true, options = true, settings = true, gui = true }

SLASH_RXPENHANCED1 = "/rxpe"
SlashCmdList.RXPENHANCED = function(input)
    if not db then return end
    local cmd, rest = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if OPEN_WORDS[cmd] then
        NS.OpenSettings()
        return
    elseif cmd == "debug" then
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and call(C_AddOns.GetAddOnMetadata, ADDON_NAME or "RXPEnhanced", "Version")
        msg(("version %s · files loaded: card %s, waypoint %s, toast %s, log %s"):format(tostring(version or "?"), onOff(NS.Card ~= nil),
            onOff(NS.Waypoint ~= nil), onOff(NS.Toast ~= nil), onOff(NS.Log ~= nil)))
        if NS.Card and NS.Card.Debug then NS.Card.Debug() end
        if NS.Waypoint and NS.Waypoint.Debug then NS.Waypoint.Debug() end
        if NS.Log and NS.Log.Debug then NS.Log.Debug() end
        return
    elseif cmd == "log" then
        local L = NS.Log
        if not L then
            msg("the timing log loads after a full restart of WoW (not just /reload).")
            return
        end
        if rest == "" or rest == "toggle" then
            db.logTimes = not db.logTimes
        elseif rest == "on" or rest == "off" then
            db.logTimes = rest == "on"
        elseif rest == "status" then
            msg(L.StatusText())
            return
        elseif rest == "new" then
            L.NewSession()
            msg(db.logTimes and "started a new log session." or "the log starts a new session when you turn it on.")
            return
        elseif rest == "clear" then
            local st = L.Stats()
            msg(("this deletes %d steps and %d kills in %d sessions. Type /rxpe log clear yes to go ahead."):format(st.steps, st.kills, st.sessions))
            return
        elseif rest == "clear yes" then
            L.Clear()
            msg("timing log cleared.")
            return
        else
            msg("log takes on, off, status, new or clear, e.g. /rxpe log on")
            return
        end
        msg("step and kill timing log " .. onOff(db.logTimes) .. (db.logTimes and ": saved when you log out or reload." or "."))
    elseif cmd == "toast" then
        local T = NS.Toast
        if rest == "move" and T then
            T.SetMoving(not T.IsMoving())
            msg(T.IsMoving() and "drag the sample toast where you want it, then type /rxpe toast move again." or "toast position saved.")
            return
        elseif (rest == "test" or rest == "preview") and T then
            T.Preview()
            return
        elseif rest == "reset" and T then
            T.ResetPosition()
            msg("toast back at the top of the screen.")
            return
        end
        db.toast = not db.toast
        msg("toasts " .. onOff(db.toast) .. ".")
    elseif cmd == "intro" then
        db.skipIntro = not db.skipIntro
        msg("skip the new-character intro " .. onOff(db.skipIntro) .. ".")
    elseif cmd == "skin" then
        db.skinRXP = not db.skinRXP
        msg("RestedXP's other windows in the cards' look " .. onOff(db.skinRXP) .. ".")
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
        msg("next-step arrow and pins " .. onOff(db.enabled) .. ".")
    elseif cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        msg("next-step arrow and pins " .. onOff(db.enabled) .. ".")
    elseif cmd == "arrow" then
        db.arrow = not db.arrow
        msg("arrow " .. onOff(db.arrow) .. ".")
    elseif cmd == "label" or cmd == "text" then
        db.label = not db.label
        msg("step name under the arrow " .. onOff(db.label) .. ".")
    elseif cmd == "pins" or cmd == "pin" then
        local on = not (db.mapPin or db.minimapPin)
        db.mapPin, db.minimapPin = on, on
        msg("map and minimap pins " .. onOff(on) .. ".")
    elseif cmd == "waypoint" or cmd == "wp" then
        db.wpEnabled = not db.wpEnabled
        msg("waypoint marker " .. onOff(db.wpEnabled) .. ".")
    elseif cmd == "marker" then
        local ok
        for _, st in ipairs(NS.Waypoint and NS.Waypoint.STYLES or {}) do
            if rest == st.key then ok = true end
        end
        if not ok then
            msg("marker takes pin, ring or beacon, e.g. /rxpe marker beacon")
            return
        end
        db.wpStyle = rest
        msg("waypoint marker: " .. rest .. ".")
    elseif cmd == "sound" or cmd == "sounds" then
        if rest == "on" or rest == "off" then
            db.wpSounds = rest == "on"
            msg("waypoint sounds " .. onOff(db.wpSounds) .. ".")
        else
            local ok
            for _, snd in ipairs(NS.Waypoint and NS.Waypoint.SOUNDS or {}) do
                if rest == snd.key then ok = true end
            end
            if not ok then
                msg("sound takes on, off, glass, azerite, crystal, chime or ping")
                return
            end
            db.wpSound = rest
            NS.Waypoint.PlaySound(rest)
            msg("waypoint sound: " .. rest .. ".")
        end
    elseif cmd == "card" or cmd == "ui" then
        db.card = not db.card
        msg("enhanced UI " .. onOff(db.card) .. ".")
    elseif cmd == "rxp" then
        db.cardHidesRXP = not db.cardHidesRXP
        msg(db.cardHidesRXP and "RestedXP's window hidden while the card is up." or "RestedXP's window shown.")
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = cmd == "lock"
        msg(db.locked and "arrow locked." or "arrow unlocked: drag it where you want it.")
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and s >= 0.4 and s <= 2.5 then
            db.scale = s
            msg(("arrow scale %.2f."):format(s))
        else
            msg("scale takes a number from 0.4 to 2.5, e.g. /rxpe scale 1")
            return
        end
    elseif cmd == "opacity" or cmd == "alpha" then
        local a = tonumber((rest:gsub("%%$", "")))
        if a and a > 1 then a = a / 100 end
        if a and a >= 0.2 and a <= 1 then
            db.alpha = a
            msg(("arrow opacity %d%%."):format(math.floor(a * 100 + 0.5)))
        else
            msg("opacity takes 20 to 100 (percent), e.g. /rxpe opacity 80")
            return
        end
    elseif cmd == "color" or cmd == "colour" then
        local hex = rest:match("^#?(%x%x%x%x%x%x)$")
        if hex then
            db.color = hexToRGB(hex)
            msg("colour set.")
        else
            msg("colour takes a hex code, e.g. /rxpe color " .. PRESETS[1].hex)
            return
        end
    elseif cmd == "reset" then
        resetAll()
        msg("all settings reset, and the arrow is back under RestedXP's.")
        return
    elseif cmd == "status" then
        local current = getRXP() and call(rxp.GetGuideProgress)
        local ahead = NS.FindNext()
        msg(("on %s · arrow %s · map pin %s · minimap pin %s · %s"):format(onOff(db.enabled), onOff(db.arrow),
            onOff(db.mapPin), onOff(db.minimapPin), db.locked and "locked" or "unlocked"))
        msg(("RestedXP step: %s · next: %s"):format(tostring(current or "none"),
            ahead and ("step " .. ahead.index .. " — " .. ahead.label) or "nothing ahead with a place to go"))
        return
    else
        msg("/rxpe opens the settings · on|off|toggle · arrow · label · pins · waypoint · marker <style> · sound <on|off|name> · ui (enhanced UI) · rxp · skin · toast [move|test|reset] · intro · log [on|off|status|new|clear] · lock · unlock · scale <n> · opacity <n> · color <hex> · reset · status · debug")
        return
    end
    settingsChanged()
end

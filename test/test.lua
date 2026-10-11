-- Offline checks for RXP Enhanced: a mock WoW client and a mock RestedXP, then scenarios.
-- lua5.1 test.lua
local ADDON_FILE = "../RXPEnhanced/RXPEnhanced.lua"

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL: " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "") .. "\n") end
end

-- ---------------------------------------------------------------- mock client
local printed = {}
local realPrint = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
unpack = unpack or table.unpack

local now = 0
function GetTime() return now end
local facing = 0
function GetPlayerFacing() return facing end
local level = 5
function UnitLevel() return level end
local inInstance = false
function IsInInstance() return inInstance end

local frames = {}
local function newObject(kind, name)
    local o = { kind = kind, name = name, shown = (kind ~= "Frame"), scripts = {}, points = {}, events = {}, alpha = 1, scale = 1 }
    function o:SetSize(w, h) self.w, self.h = w, h end
    function o:SetFrameStrata(s) self.strata = s end
    function o:SetClampedToScreen() end
    function o:SetMovable() end
    function o:EnableMouse() end
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsShown() return self.shown end
    function o:SetScript(k, f) self.scripts[k] = f end
    function o:RegisterEvent(e) self.events[e] = true end
    function o:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function o:ClearAllPoints() self.points = {} end
    function o:GetPoint() local p = self.points[1] if not p then return end if type(p[2]) == "table" then return p[1], p[2], p[3], p[4], p[5] end return p[1], nil, p[2], p[3], p[4] end
    function o:SetAlpha(a) self.alpha = a end
    function o:SetScale(s) self.scale = s end
    function o:StartMoving() self.moving = true end
    function o:StopMovingOrSizing() self.moving = false; self.points = { { "CENTER", UIParent, "BOTTOMLEFT", 400, 300 } } end
    function o:CreateTexture() local t = newObject("Texture") t.rotation = 0 return t end
    function o:CreateFontString() local t = newObject("FontString") return t end
    function o:SetAllPoints() end
    function o:SetTexture(t) self.texture = t end
    function o:GetTexture() return self.texture end
    function o:SetDesaturated(d) self.desaturated = d end
    function o:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function o:SetRotation(r) self.rotation = r end
    function o:SetText(t) self.text = t end
    function o:GetText() return self.text end
    function o:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function o:SetJustifyH() end
    function o:SetFont(f, s, flags) self.font = f; self.fontSize = s end
    function o:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function o:SetJustifyV() end
    function o:SetWidth(w) self.w = w end
    function o:SetHeight(h) self.h = h end
    function o:SetFontObject(f) self.fontObject = f end
    function o:SetToplevel() end
    function o:RegisterForDrag() end
    function o:SetEnabled(e) self.enabled = e end
    function o:SetChecked(c) self.checked = c end
    function o:GetChecked() return self.checked end
    function o:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function o:Click() self.scripts.OnClick(self, "LeftButton") end
    function o:SetShown(s) if s then self:Show() else self:Hide() end end
    -- Anything else (edit boxes, scroll frames, measuring) does nothing here.
    return setmetatable(o, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
local templates = {}
function templates.UICheckButtonTemplate(f) f.Text = newObject("FontString"); f.checked = false; f.enabled = true end
function templates.MinimalSliderWithSteppersTemplate(f)
    f.callbacks = {}
    function f:Init(value, minValue, maxValue, steps, formatters) self.value = value; self.min = minValue; self.max = maxValue; self.steps = steps; self.formatters = formatters; self:Format() end
    function f:Format() for _, fmt in pairs(self.formatters or {}) do self.valueText = fmt(self.value) end end
    function f:RegisterCallback(event, fn, owner) self.callbacks[#self.callbacks + 1] = { event = event, fn = fn, owner = owner } end
    function f:SetValue(v)
        v = math.max(self.min, math.min(self.max, v))
        if v == self.value then return end
        self.value = v
        self:Format()
        for _, c in ipairs(self.callbacks) do if c.event == "OnValueChanged" then c.fn(c.owner, v) end end
    end
end
function templates.UIPanelButtonTemplate(f) end
function templates.UIPanelCloseButtonDefaultAnchors(f) end
function templates.DefaultPanelTemplate(f) function f:SetTitle(t) self.title = t end end
function CreateFrame(kind, name, parent, template)
    local f = newObject(kind or "Frame", name)
    f.parent = parent
    if template then
        assert(templates[template], "unknown template " .. tostring(template))
        templates[template](f)
        f.template = template
    end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 }, Event = { OnValueChanged = "OnValueChanged" } }
UISpecialFrames = {}
local sounds = {}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound(id) sounds[#sounds + 1] = id end
local categories = {}
Settings = {}
function Settings.RegisterCanvasLayoutCategory(frame, name) local c = { frame = frame, name = name } return c, {} end
function Settings.RegisterAddOnCategory(c) categories[#categories + 1] = c end
ColorPickerFrame = { rgb = { 0, 0, 0 } }
function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info end
function ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end
UIParent = newObject("Frame", "UIParent")
GameTooltip = newObject("Frame", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
local origSetText = GameTooltip.SetText
function GameTooltip:SetText(t) self.title = t end
SlashCmdList = {}
C_QuestLog = {}
local objectives = {}
function C_QuestLog.GetQuestObjectives(id) return objectives[id] end
function C_QuestLog.GetTitleForQuestID(id) return "Quest #" .. id end
HBD_PINS_WORLDMAP_SHOW_CONTINENT = 2

-- HereBeDragons: world vector with angle measured like the game's facing (0 = north, counter-clockwise).
local player = { x = 0, y = 0, instance = 0 }
local HBD = {}
function HBD:GetPlayerWorldPosition() return player.x, player.y, player.instance end
function HBD:GetWorldVector(instance, ox, oy, dx, dy)
    local vx, vy = dx - ox, dy - oy -- x north, y west
    return math.atan2(vy, vx) % (2 * math.pi), math.sqrt(vx * vx + vy * vy)
end
local pins = { world = {}, mini = {} }
local HBDPins = {}
function HBDPins:AddWorldMapIconWorld(ref, icon, inst, x, y, flag) pins.world[#pins.world + 1] = { ref = ref, icon = icon, inst = inst, x = x, y = y, flag = flag } end
function HBDPins:AddMinimapIconWorld(ref, icon, inst, x, y, edge) pins.mini[#pins.mini + 1] = { ref = ref, icon = icon, inst = inst, x = x, y = y, edge = edge } end
function HBDPins:RemoveAllWorldMapIcons() pins.world = {} end
function HBDPins:RemoveAllMinimapIcons() pins.mini = {} end

-- ---------------------------------------------------------------- mock RestedXP
local quests = { on = {}, done = {}, complete = {} }
local RXP = {
    settings = { profile = { showEnabled = true } },
    font = "Fonts\\FRIZQT__.TTF",
    currentGuide = nil,
    progress = 1,
}
function RXP.GetGuideProgress() return RXP.progress end
function RXP.IsOnQuest(id) return quests.on[id] or false end
function RXP.IsQuestTurnedIn(id) return quests.done[id] or false end
function RXP.IsQuestComplete(id) return quests.complete[id] or false end
function RXP.GetQuestName(id) return "Quest Name " .. id end

local rxpLoaded = true
local libs = {
    ["AceAddon-3.0"] = { GetAddon = function(_, name) return rxpLoaded and name == "RXPGuides" and RXP or nil end },
    ["HereBeDragons-2.0"] = HBD,
    ["HereBeDragons-Pins-2.0"] = HBDPins,
}
function LibStub(name) return libs[name] end

RXPG_ARROW = newObject("Frame", "RXPG_ARROW")
RXPG_ARROW.texture = newObject("Texture")
RXPG_ARROW.texture.texture = "Interface/AddOns/RXPGuides/Textures/v2/rxp_navigation_arrow-1"

-- Elements the way RestedXP's parser builds them.
local function goto(wx, wy, opts)
    local e = { tag = "goto", wx = wx, wy = wy, instance = 0, textOnly = true, arrow = true }
    for k, v in pairs(opts or {}) do e[k] = v end
    return e
end
local function text(t) return { text = t, textOnly = true } end
local function accept(id, t) return { tag = "accept", questId = id, text = t or "Accept *quest*" } end
local function turnin(id, t) return { tag = "turnin", questId = id, text = t or "Turn in *quest*" } end
local function complete(id, obj) return { tag = "complete", questId = id, obj = obj } end
local function guard(tag, ids, extra) local e = { tag = tag, questIds = ids, textOnly = true } for k, v in pairs(extra or {}) do e[k] = v end return e end
local function step(elements, extra) local s = { elements = elements } for k, v in pairs(extra or {}) do s[k] = v end return s end

local function setGuide(steps)
    for i, s in ipairs(steps) do s.index = i end
    RXP.currentGuide = { name = "Test", group = "G", key = "G|Test", steps = steps }
end

-- ---------------------------------------------------------------- load the addon
local chunk = assert(loadfile(ADDON_FILE))
chunk("RXPEnhanced")
local NS = RXPEnhanced
local arrow = RXPEnhancedArrow
local driver
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then driver = f end end
assert(driver, "driver frame")

local function tick(dt) now = now + (dt or 0.6); driver.scripts.OnUpdate(driver, dt or 0.6) end
local function event(e, ...) driver.scripts.OnEvent(driver, e, ...) end
local function slash(s) SlashCmdList.RXPENHANCED(s) end

-- ---------------------------------------------------------------- scenarios
setGuide({
    step({ goto(100, 0), text("Talk to |cRXP_FRIENDLY_Undertaker Mordo|r"), accept(363, "Accept Rude Awakening") }),       -- 1 current
    step({ text("Not Well Fed? Eat"), { tag = "aura", textOnly = true } }, { sticky = true }),                                -- 2 #completewith
    step({ goto(0, 200), text(">>Talk to |cRXP_FRIENDLY_Shadow Priest Sarvis|r"), turnin(363), accept(364) }),            -- 3
})
event("PLAYER_LOGIN")
check("init: driver running", driver.shown)
check("init: arrow texture is RestedXP's", arrow.tex.texture == RXPG_ARROW.texture.texture)
check("init: arrow desaturated and tinted white (the default)", arrow.tex.desaturated and arrow.tex.color and math.abs(arrow.tex.color[1] - 0xe8 / 255) < 1e-6 and math.abs(arrow.tex.color[2] - 0xe8 / 255) < 1e-6)
check("defaults: the 1.7 defaults", RXPEnhancedDB.scale == 1 and RXPEnhancedDB.cardTextSize == 11 and RXPEnhancedDB.cardWidth == 280
    and RXPEnhancedDB.cardTheme == "glass" and RXPEnhancedDB.nextCount == 3 and RXPEnhancedDB.wpScale == 2 and RXPEnhancedDB.wpSound == "chime"
    and RXPEnhancedDB.wpNewSound == true and RXPEnhancedDB.wpStyle == "pin" and RXPEnhancedDB.skipIntro == true
    and math.abs(RXPEnhancedDB.wpColor[1] - 0xb5 / 255) < 1e-6 and math.abs(RXPEnhancedDB.wpColor[2] - 0x8c / 255) < 1e-6)
check("init: default spot under RestedXP's arrow", arrow.points[1] and arrow.points[1][2] == RXPG_ARROW and arrow.points[1][3] == "BOTTOM")
check("init: font is RestedXP's", arrow.text.font == RXP.font)

tick()
check("next: skips the #completewith step, picks step 3", NS.ahead and NS.ahead.index == 3, NS.ahead and NS.ahead.index)
check("next: label from the >> line, codes stripped", NS.ahead and NS.ahead.label == "Talk to Shadow Priest Sarvis", NS.ahead and NS.ahead.label)
check("arrow shown", arrow.shown)
check("pins: world and minimap pin at step 3", #pins.world == 1 and #pins.mini == 1 and pins.world[1].x == 0 and pins.world[1].y == 200 and pins.mini[1].edge == true)
check("pins: world pin shows on the continent map", pins.world[1].flag == 2)
-- Player at origin facing north (0): target is due west (+y) = 90° counter-clockwise.
check("arrow points west", math.abs(arrow.tex.rotation - math.pi / 2) < 1e-6, arrow.tex.rotation)
check("arrow text has distance", arrow.text.text == "Next: Talk to Shadow Priest Sarvis\n(200yd)", arrow.text.text)
facing = math.pi / 2
tick(0.016)
check("arrow turns with the player", math.abs(arrow.tex.rotation) < 1e-6, arrow.tex.rotation)
facing = 0

-- Guards: a quest check that fails skips the step.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ guard("isOnQuest", { 999 }), goto(10, 10), text("Only if on 999") }),
    step({ guard("isQuestTurnedIn", { 50 }), goto(20, 20), text("Only after 50") }),
    step({ guard("isQuestAvailable", { 60 }), goto(30, 30), text("Only if 60 not done") }),
    step({ guard("isQuestComplete", { }, { questIds = nil, questId = 70 }), goto(40, 40), text("Only if 70 complete") }),
    step({ guard("isNotOnQuest", { 80 }, { reverse = true }), goto(50, 50), text("Only if not on 80") }),
})
quests.done[60] = true
quests.on[80] = true
tick()
check("guards: all five fail, nothing ahead", NS.ahead == nil, NS.ahead and NS.ahead.index)
check("guards: arrow hidden with nothing ahead", not arrow.shown)
check("guards: pins cleared", #pins.world == 0 and #pins.mini == 0)
quests.on[999] = true
event("QUEST_LOG_UPDATE")
tick(0.016)
check("guards: on 999 now, step 2 is next (re-checked on the quest event)", NS.ahead and NS.ahead.index == 2, NS.ahead and NS.ahead.index)
quests.on[999] = nil
quests.done[50] = true
tick()
check("guards: isQuestTurnedIn passes once 50 is done", NS.ahead and NS.ahead.index == 3)
quests.done[50] = nil
quests.done[60] = nil
tick()
check("guards: isQuestAvailable passes while 60 isn't done", NS.ahead and NS.ahead.index == 4)
quests.done[60] = true
quests.on[70] = true; quests.complete[70] = true
tick()
check("guards: isQuestComplete passes when 70 is complete", NS.ahead and NS.ahead.index == 5)
quests.on[70] = nil; quests.complete[70] = nil
quests.on[80] = nil
tick()
check("guards: isNotOnQuest passes when not on 80", NS.ahead and NS.ahead.index == 6)
RXP.settings.profile.disableAutoSkip = true
quests.on[80] = true
tick()
check("guards: with RestedXP's auto-skip off, guarded steps still come up", NS.ahead and NS.ahead.index == 2)
RXP.settings.profile.disableAutoSkip = nil

-- Objectives already done skip the step; unknown objectives don't.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(1, 1), accept(500) }),                         -- already on 500
    step({ goto(2, 2), turnin(501) }),                         -- 501 already turned in
    step({ goto(3, 3), complete(502, 1) }),                    -- objective 1 of 502 finished
    step({ goto(4, 4), { tag = "xp", level = 5 } }),            -- already level 5
    step({ text("+Tick this when you've eaten"), { text = "Tick", tag = nil } }), -- checkbox, no place
    step({ goto(7, 7, { hidePin = true, radius = 20 }), goto(8, 8, { hidePin = true, radius = 20 }), goto(9, 9), text("Run to the farm") }),
})
quests.on[500] = true
quests.done[501] = true
quests.on[502] = true
objectives[502] = { { finished = true }, { finished = false } }
tick()
check("done: accepted, turned-in, finished-objective and level steps are passed over", NS.ahead and NS.ahead.index == 7, NS.ahead and NS.ahead.index)
check("done: a path step points at its main Go to, not the hidden waypoints", NS.ahead and NS.ahead.place.wx == 9 and NS.ahead.place.wy == 9)
check("done: label", NS.ahead and NS.ahead.label == "Run to the farm", NS.ahead and NS.ahead.label)
objectives[502] = { { finished = false } }
tick()
check("done: an unfinished objective keeps its step", NS.ahead and NS.ahead.index == 4)
level = 4
objectives[502] = { { finished = true } }
tick()
check("done: under the level, the xp step stays", NS.ahead and NS.ahead.index == 5)
level = 5

-- A step whose quest name RestedXP fills in later.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(5, 5), accept(777) }),
})
tick()
check("label: *quest* filled with the quest name", NS.ahead and NS.ahead.label == "Accept Quest Name 777", NS.ahead and NS.ahead.label)

-- A travel step whose only text is on its Go to.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(5, 5, { text = "Travel north-west to Agamand Mills", textOnly = false, radius = 30 }) }),
    step({ goto(6, 6) }),
})
tick()
check("label: text on a Go to is used when there's no other line", NS.ahead and NS.ahead.label == "Travel north-west to Agamand Mills", NS.ahead and NS.ahead.label)
RXP.progress = 2
tick()
check("label: a bare Go to falls back to the step number", NS.ahead and NS.ahead.label == "Step 3", NS.ahead and NS.ahead.label)
RXP.progress = 1

-- Moving on: progress changes the target and the pins.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(0, 50), text("Second") }),
    step({ goto(0, -50), text("Third") }),
})
tick()
check("progress: step 2 next", NS.ahead and NS.ahead.index == 2)
RXP.progress = 2
tick()
check("progress: after RestedXP moves on, step 3 next", NS.ahead and NS.ahead.index == 3)
check("progress: pins moved (not added twice)", #pins.world == 1 and pins.world[1].y == -50)
check("progress: arrow text refreshed", arrow.text.text == "Next: Third\n(50yd)", arrow.text.text)
RXP.progress = 3
tick()
check("progress: last step has nothing after it", NS.ahead == nil and not arrow.shown)
RXP.progress = 1

-- Elsewhere: the next step on another continent.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(0, 50, { instance = 1 }), text("Over the sea") }),
})
tick()
check("elsewhere: arrow dimmed and still", arrow.tex.alpha == 0.25 and arrow.tex.rotation == 0)
check("elsewhere: text says so", arrow.text.text == "Next: Over the sea\n(elsewhere)", arrow.text.text)

-- Position not available (secret values / instance): no error, dimmed.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(0, 50), text("Here") }),
})
local realPos = HBD.GetPlayerWorldPosition
HBD.GetPlayerWorldPosition = function() error("secret") end
local ok = pcall(tick)
check("no position: no Lua error", ok)
check("no position: dimmed", arrow.tex.alpha == 0.25)
HBD.GetPlayerWorldPosition = realPos
tick(0.016)
check("position back: full alpha", arrow.tex.alpha == 1)

-- RestedXP hidden, or in an instance: hide.
RXP.settings.profile.showEnabled = false
tick()
check("RestedXP hidden: arrow hidden", not arrow.shown and #pins.world == 0)
RXP.settings.profile.showEnabled = true
inInstance = true
tick()
check("instance: arrow hidden", not arrow.shown)
inInstance = false
tick()
check("back outside: arrow back", arrow.shown and #pins.world == 1)

-- Tooltip on the pin.
pins.world[1].icon.scripts.OnEnter(pins.world[1].icon)
check("pin tooltip", GameTooltip.title == "Next: step 2" and GameTooltip.lines[1] == "Here", GameTooltip.title)

-- Commands.
slash("off")
check("/rxpe off", RXPEnhancedDB.enabled == false)
tick()
check("off: arrow and pins hidden", not arrow.shown and #pins.world == 0 and #pins.mini == 0)
slash("on")
tick()
check("on: back", arrow.shown and #pins.world == 1)
slash("arrow")
tick()
check("arrow off: arrow hidden, pin stays", not arrow.shown and #pins.world == 1)
slash("arrow")
slash("pins")
tick()
check("pins off: pins gone, arrow stays", arrow.shown and #pins.world == 0)
slash("pins")
tick()
check("pins on again", #pins.world == 1)
slash("scale 1.2")
check("scale", arrow.scale == 1.2 and RXPEnhancedDB.scale == 1.2)
slash("scale 9")
check("scale out of range is refused", RXPEnhancedDB.scale == 1.2)
slash("color ff8800")
check("colour", math.abs(arrow.tex.color[1] - 1) < 1e-6 and math.abs(arrow.tex.color[2] - 0x88 / 255) < 1e-6)
tick()
check("colour reaches the pins", math.abs(pins.world[1].icon.tex.color[2] - 0x88 / 255) < 1e-6)
arrow.scripts.OnMouseDown(arrow, "LeftButton")
check("drag: unlocked moves", arrow.moving)
arrow.scripts.OnMouseUp(arrow)
check("drag: position saved", RXPEnhancedDB.point and RXPEnhancedDB.point[1] == "CENTER" and RXPEnhancedDB.point[3] == 400)
slash("lock")
arrow.scripts.OnMouseDown(arrow, "LeftButton")
check("lock: no drag", not arrow.moving)
slash("unlock")
slash("reset")
check("reset: position, scale, colour", RXPEnhancedDB.point == nil and RXPEnhancedDB.scale == 1 and math.abs(arrow.tex.color[1] - 0xe8 / 255) < 1e-6 and arrow.points[1][2] == RXPG_ARROW)
printed = {}
slash("status")
check("status prints", #printed == 2 and printed[2]:find("next: step 2") ~= nil, printed[2])
printed = {}
slash("bogus")
check("help for unknown command", #printed == 1 and printed[1]:find("/rxpe") ~= nil)

-- ---------------------------------------------------------------- settings window
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function hexOf(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
tick()
check("options: registered under AddOns", #categories >= 1 and categories[#categories].name == "RXP Enhanced")
local opt = categories[#categories].frame
check("options: hidden until picked", not opt.shown)
check("options: has the controls", opt.panel and opt.panel.checks.enabled and opt.panel.sliders.scale and #opt.panel.swatches == 12)
check("options: Defaults and Refresh hooks", type(opt.OnDefault) == "function" and type(opt.OnRefresh) == "function")
slash("")
local win = RXPEnhancedSettings
check("window: /rxpe opens it (Blizzard's look without the cards' file)", win and win.shown and win.look == "blizzard"
    and win.chrome.template == "DefaultPanelTemplate" and win.chrome.title == "RXP Enhanced")
check("window: Escape closes it", UISpecialFrames[#UISpecialFrames] == "RXPEnhancedSettings")
check("window: sized to its controls", win.h and win.h > 300 and win.h < 620, win.h)
local wp, op = win.panel, opt.panel
check("window: status shows the next step", wp.statusText.text == "Next: step 2 · Here", wp.statusText.text)
check("window: checkboxes match settings", wp.checks.enabled.checked and wp.checks.arrow.checked and wp.checks.mapPin.checked and not wp.checks.locked.checked)
check("window: default colour ringed", wp.swatches[6].ring.shown and not wp.swatches[2].ring.shown)
check("window: preview tinted like the arrow", wp.preview.color and near(wp.preview.color[1], 0xe8 / 255) and wp.preview.desaturated)
slash("settings")
check("window: /rxpe again closes it", not win.shown)
slash("")

-- Checkboxes.
wp.checks.arrow.checked = false; wp.checks.arrow:Click()
tick()
check("arrow box off: arrow hidden, pins stay", RXPEnhancedDB.arrow == false and not arrow.shown and #pins.world == 1)
check("arrow box off: Options copy unticked too", op.checks.arrow.checked == false)
check("arrow box off: the label box greys out", wp.checks.label.enabled == false and op.checks.label.enabled == false)
wp.checks.arrow.checked = true; wp.checks.arrow:Click()
tick()
check("arrow box on: back", arrow.shown and wp.checks.label.enabled == true)
wp.checks.label.checked = false; wp.checks.label:Click()
check("label box off: text under the arrow hidden", RXPEnhancedDB.label == false and not arrow.text.shown)
wp.checks.label.checked = true; wp.checks.label:Click()
check("label box on: text back", arrow.text.shown)
wp.checks.mapPin.checked = false; wp.checks.mapPin:Click()
tick()
check("map pin off: minimap pin only", #pins.world == 0 and #pins.mini == 1)
wp.checks.minimapPin.checked = false; wp.checks.minimapPin:Click()
check("minimap pin off: no pins", #pins.world == 0 and #pins.mini == 0)
op.checks.mapPin.checked = true; op.checks.mapPin:Click()
op.checks.minimapPin.checked = true; op.checks.minimapPin:Click()
check("pins on from the Options copy: both back, window copy ticked", #pins.world == 1 and #pins.mini == 1 and wp.checks.mapPin.checked and wp.checks.minimapPin.checked)
wp.checks.enabled.checked = false; wp.checks.enabled:Click()
tick()
check("master off: everything hidden", not arrow.shown and #pins.world == 0 and #pins.mini == 0)
check("master off: the boxes under it grey out, Arrow section doesn't", not wp.checks.arrow.enabled and not wp.checks.mapPin.enabled and wp.checks.locked.enabled)
check("master off: status says so", wp.statusText.text == "Turned off.")
wp.checks.enabled.checked = true; wp.checks.enabled:Click()
tick()
check("master on: back", arrow.shown and #pins.world == 1 and wp.checks.arrow.enabled)
wp.checks.locked.checked = true; wp.checks.locked:Click()
arrow.scripts.OnMouseDown(arrow, "LeftButton")
check("lock box: no drag", RXPEnhancedDB.locked == true and not arrow.moving)
wp.checks.locked.checked = false; wp.checks.locked:Click()
check("clicks make the checkbox sound", sounds[#sounds] == SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)

-- Sliders.
wp.sliders.scale:SetValue(1.23)
check("size slider: snaps to 0.05 and applies", RXPEnhancedDB.scale == 1.25 and arrow.scale == 1.25, RXPEnhancedDB.scale)
check("size slider: Options copy follows", op.sliders.scale.value == 1.25)
check("size slider: shows the value", wp.sliders.scale.valueText == "1.25", wp.sliders.scale.valueText)
check("size slider: range 0.4 to 2.5", wp.sliders.scale.min == 0.4 and wp.sliders.scale.max == 2.5 and wp.sliders.scale.steps == 42)
op.sliders.alpha:SetValue(0.5)
check("opacity slider: applies", RXPEnhancedDB.alpha == 0.5 and arrow.alpha == 0.5 and wp.sliders.alpha.value == 0.5)
check("opacity slider: shows percent", op.sliders.alpha.valueText == "50%", op.sliders.alpha.valueText)
check("opacity: preview too", wp.preview.alpha == 0.5)

-- Colours.
wp.swatches[2]:Click()
tick()
check("swatch: light blue picked", hexOf(RXPEnhancedDB.color) == "6ec6ff" and near(arrow.tex.color[1], 0x6e / 255))
check("swatch: ring moves, in both copies", wp.swatches[2].ring.shown and not wp.swatches[6].ring.shown and op.swatches[2].ring.shown)
check("swatch: pins recoloured", near(pins.world[1].icon.tex.color[1], 0x6e / 255))
wp.custom:Click()
local info = ColorPickerFrame.info
check("custom: picker opens on the current colour", info and near(info.r, 0x6e / 255) and info.hasOpacity == false)
ColorPickerFrame.rgb = { 0.2, 0.4, 0.6 }
info.swatchFunc()
check("custom: dragging recolours live", near(arrow.tex.color[2], 0.4) and near(RXPEnhancedDB.color[3], 0.6))
check("custom: no preset ringed", not wp.swatches[1].ring.shown and not wp.swatches[2].ring.shown)
info.cancelFunc({ r = info.r, g = info.g, b = info.b })
check("custom: cancel puts the old colour back", hexOf(RXPEnhancedDB.color) == "6ec6ff")

-- Buttons.
arrow.scripts.OnMouseDown(arrow, "LeftButton"); arrow.scripts.OnMouseUp(arrow)
check("dragged somewhere", RXPEnhancedDB.point ~= nil)
wp.resetPosition:Click()
check("Reset position: back under RestedXP's arrow, colour kept", RXPEnhancedDB.point == nil and arrow.points[1][2] == RXPG_ARROW and hexOf(RXPEnhancedDB.color) == "6ec6ff")
RXPEnhancedDB.mapPin = false
wp.resetAll:Click()
check("Reset all: defaults", hexOf(RXPEnhancedDB.color) == "e8e8e8" and RXPEnhancedDB.scale == 1 and RXPEnhancedDB.alpha == 0.9 and RXPEnhancedDB.mapPin == true and arrow.alpha == 0.9)
check("Reset all: controls follow", wp.sliders.scale.value == 1 and wp.swatches[6].ring.shown and op.checks.mapPin.checked)
RXPEnhancedDB.scale = 2
opt.OnDefault()
check("Options Defaults button resets too", RXPEnhancedDB.scale == 1 and op.sliders.scale.value == 1)

-- Preview turns and the status keeps up while open.
setGuide({
    step({ goto(100, 0), accept(1) }),
    step({ goto(0, 50), text("Somewhere new") }),
})
tick()
for _, f in ipairs(frames) do
    if f.scripts.OnUpdate and f ~= driver then f.scripts.OnUpdate(f, 0.6) end
end
check("status line keeps up", wp.statusText.text == "Next: step 2 · Somewhere new", wp.statusText.text)
check("preview turns", wp.preview.rotation ~= 0)

-- New commands.
slash("pins")
tick()
check("/rxpe pins: both off", RXPEnhancedDB.mapPin == false and RXPEnhancedDB.minimapPin == false and #pins.world == 0 and #pins.mini == 0)
check("/rxpe pins: window follows", wp.checks.mapPin.checked == false)
slash("pins")
check("/rxpe pins: both on", RXPEnhancedDB.mapPin and RXPEnhancedDB.minimapPin)
slash("opacity 80")
check("/rxpe opacity 80", RXPEnhancedDB.alpha == 0.8 and arrow.alpha == 0.8 and wp.sliders.alpha.value == 0.8)
slash("opacity 5")
check("/rxpe opacity out of range refused", RXPEnhancedDB.alpha == 0.8)
slash("label")
check("/rxpe label", RXPEnhancedDB.label == false and not arrow.text.shown)
slash("label")
slash("color 6ec6ff")
check("/rxpe color: window ring follows", wp.swatches[2].ring.shown)
slash("reset")

-- Saved settings survive a reload: a second load with the saved table.
local saved = RXPEnhancedDB
saved.scale = 1.5
frames = {}
chunk("RXPEnhanced")
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then driver = f end end
arrow = RXPEnhancedArrow
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
check("reload: settings kept", RXPEnhancedArrow.scale == 1.5)

-- Settings saved by 1.0.0: light blue becomes the new default, one pins switch becomes two.
RXPEnhancedDB = { enabled = true, arrow = true, pins = false, locked = true, scale = 1.1, color = { 0.43, 0.78, 1.0 } }
frames = {}
chunk("RXPEnhanced")
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then driver = f end end
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
check("1.0.0 settings: light blue becomes today's default", math.abs(RXPEnhancedDB.color[1] - 0xe8 / 255) < 1e-6 and math.abs(RXPEnhancedArrow.tex.color[1] - 0xe8 / 255) < 1e-6)
check("1.0.0 settings: pins off carries to both pins", RXPEnhancedDB.mapPin == false and RXPEnhancedDB.minimapPin == false and RXPEnhancedDB.pins == nil)
check("1.0.0 settings: the rest kept, new ones filled in", RXPEnhancedDB.locked == true and RXPEnhancedDB.scale == 1.1 and RXPEnhancedDB.alpha == 0.9 and RXPEnhancedDB.label == true)
RXPEnhancedDB = { color = { 1, 0.5, 0 } }
frames = {}
chunk("RXPEnhanced")
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then driver = f end end
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
check("a colour you picked yourself is kept", RXPEnhancedDB.color[1] == 1 and RXPEnhancedDB.color[2] == 0.5)

-- No RestedXP: a message, no errors.
rxpLoaded = false
frames = {}
RXPEnhancedDB = nil
printed = {}
local okLoad = pcall(function()
    chunk("RXPEnhanced")
    for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then driver = f end end
    driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
end)
check("no RestedXP: loads without error", okLoad)
check("no RestedXP: says so", printed[1] and printed[1]:find("isn't loaded") ~= nil, printed[1])
check("no RestedXP: stays idle", not driver.shown)

print(("%d passed, %d failed"):format(passed, failed))
io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

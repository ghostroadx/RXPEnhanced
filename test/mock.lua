-- A mock WoW client for RXP Next Step's guide-card tests: frames, textures and font strings that
-- remember what they were told, text measured with Inter's real character widths, and a dump of
-- the card's layout that tools/render_card.py can draw.
local M = {}
local metrics = dofile("metrics.lua")
unpack = unpack or table.unpack

M.frames = {}
M.printed = {}
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    M.printed[#M.printed + 1] = table.concat(t, " ")
end

M.now = 0
function GetTime() return M.now end
M.facing = 0
function GetPlayerFacing() return M.facing end
M.level, M.xp, M.xpMax = 5, 1200, 2800
function UnitLevel() return M.level end
function UnitXP() return M.xp end
function UnitXPMax() return M.xpMax end
M.inInstance = false
function IsInInstance() return M.inInstance end
function PlaySound() end
M.shift = false
function IsShiftKeyDown() return M.shift end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
SlashCmdList = {}
UISpecialFrames = {}
HBD_PINS_WORLDMAP_SHOW_CONTINENT = 2
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 }, Event = { OnValueChanged = "OnValueChanged" } }

-- ---------------------------------------------------------------- text measuring

local function weightOf(path)
    path = path or ""
    if path:find("SemiBold") then return "semibold" end
    if path:find("Medium") then return "medium" end
    return "regular"
end

local function strip(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "))
end

function M.measure(text, weight, size)
    local w, tbl = 0, metrics[weight] or metrics.regular
    local s = strip(text)
    for i = 1, #s do
        local v = tbl[s:byte(i) - 31] or 0.6
        w = w + v * size
    end
    return w
end

function M.wrap(text, weight, size, width, maxLines, wordWrap)
    local lines = {}
    for para in (text .. "\n"):gmatch("(.-)\n") do
        if wordWrap == false or not width or width <= 0 then
            lines[#lines + 1] = para
        else
            local line = ""
            for word in para:gmatch("%S+") do
                local try = line == "" and word or (line .. " " .. word)
                if line ~= "" and M.measure(try, weight, size) > width then
                    lines[#lines + 1] = line
                    line = word
                else
                    line = try
                end
            end
            lines[#lines + 1] = line
        end
    end
    if maxLines and maxLines > 0 and #lines > maxLines then
        local kept = {}
        for i = 1, maxLines do kept[i] = lines[i] end
        kept[maxLines] = kept[maxLines] .. "..."
        lines = kept
    end
    return lines
end

-- ---------------------------------------------------------------- widgets

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function newObject(kind, name, parent)
    local o = { kind = kind, name = name, parent = parent, shown = true, scripts = {}, points = {}, events = {},
        alpha = 1, scale = 1, regions = {}, children = {} }
    function o:SetSize(w, h) self.w, self.h = w, h end
    function o:SetWidth(w) self.w = w end
    function o:SetHeight(h) self.h = h end
    function o:GetWidth() return self.w or 0 end
    function o:GetHeight() return self.h or 0 end
    function o:SetFrameStrata(s) self.strata = s end
    function o:GetFrameStrata() return self.strata or "MEDIUM" end
    function o:SetClampedToScreen() end
    function o:SetMovable() end
    function o:EnableMouse(e) self.mouse = e end
    function o:SetToplevel() end
    function o:RegisterForDrag() end
    function o:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function o:Hide() self.shown = false end
    function o:SetShown(s) if s then self:Show() else self:Hide() end end
    function o:IsShown() return self.shown end
    function o:IsVisible()
        local f = self
        while f do if not f.shown then return false end f = f.parent end
        return true
    end
    function o:SetScript(k, f) self.scripts[k] = f end
    function o:GetScript(k) return self.scripts[k] end
    function o:HookScript(k, f) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end f(...) end end
    function o:RegisterEvent(e) self.events[e] = true end
    function o:UnregisterEvent(e) self.events[e] = nil end
    function o:UnregisterAllEvents() self.events = {} end
    function o:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function o:ClearAllPoints() self.points = {} end
    function o:SetAllPoints(rel) self.points = { { "TOPLEFT", rel or self.parent, "TOPLEFT", 0, 0 } }; self.allPoints = rel or self.parent end
    function o:GetPoint()
        local p = self.points[1]
        if not p then return end
        if type(p[2]) == "table" then return p[1], p[2], p[3], p[4], p[5] end
        return p[1], nil, p[2], p[3], p[4]
    end
    function o:SetAlpha(a) self.alpha = a end
    function o:GetAlpha() return self.alpha end
    function o:SetScale(s) self.scale = s end
    function o:GetScale() return self.scale end
    function o:GetEffectiveScale() return self.scale * (self.parent and self.parent.GetEffectiveScale and self.parent:GetEffectiveScale() or 1) end
    function o:GetLeft() return self.left end
    function o:GetTop() return self.top end
    function o:StartMoving() self.moving = true end
    function o:StopMovingOrSizing() self.moving = false; self.points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 500, 600 } } end
    function o:EnableMouseWheel(e) self.wheel = e end
    function o:CreateTexture(_, layer, _, sublevel)
        local t = newObject("Texture", nil, self)
        t.layer = layer or "ARTWORK"
        t.sublevel = sublevel or 0
        t.rotation = 0
        self.regions[#self.regions + 1] = t
        return t
    end
    function o:CreateFontString(_, layer, template)
        local t = newObject("FontString", nil, self)
        t.layer = layer or "ARTWORK"
        if template then t.fontPath, t.fontSize = template, 12 end
        self.regions[#self.regions + 1] = t
        return t
    end
    -- textures
    function o:SetTexture(t) self.texture = t; self.colorTexture = nil end
    function o:GetTexture() return self.texture end
    function o:SetTexCoord(...) self.coords = { ... } end
    function o:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a or 1 }; self.texture = nil end
    function o:SetDesaturated(d) self.desaturated = d end
    function o:SetVertexColor(r, g, b, a) self.color = { r, g, b, a or 1 }; self.gradient = nil end
    function o:SetGradient(orientation, minColor, maxColor)
        self.gradient = { orientation, { minColor.r, minColor.g, minColor.b, minColor.a }, { maxColor.r, maxColor.g, maxColor.b, maxColor.a } }
    end
    function o:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function o:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
    function o:SetRotation(r) self.rotation = r end
    function o:SetBlendMode() end
    -- font strings
    function o:SetFont(path, size, flags) self.fontPath, self.fontSize = path, size; return true end
    function o:GetFont() return self.fontPath, self.fontSize end
    function o:SetFontObject(f) self.fontObject = f end
    function o:SetText(t)
        if t and self.maxBytes and self.maxBytes > 0 then t = t:sub(1, self.maxBytes) end
        self.text = t
        if self.fontString then self.fontString:SetText(t) end
        if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function o:GetText() return self.text end
    function o:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
    function o:SetJustifyH(j) self.justifyH = j end
    function o:SetJustifyV() end
    function o:SetWordWrap(w) self.wordWrap = w end
    function o:SetMaxLines(n) self.maxLines = n end
    function o:SetSpacing(s) self.spacing = s end
    function o:Lines()
        return M.wrap(self.text or "", weightOf(self.fontPath), self.fontSize or 12, self.w, self.maxLines, self.wordWrap)
    end
    function o:LineHeight() return (self.fontSize or 12) * 1.21 end
    function o:GetStringHeight()
        local n = #self:Lines()
        return n * self:LineHeight() + (n - 1) * (self.spacing or 0)
    end
    function o:GetStringWidth()
        local w = 0
        for _, line in ipairs(self:Lines()) do w = math.max(w, M.measure(line, weightOf(self.fontPath), self.fontSize or 12)) end
        return w
    end
    function o:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
    function o:GetShadowOffset() return unpack(self.shadowOffset or { 0, 0 }) end
    function o:GetObjectType() return self.kind end
    function o:GetFrameLevel() return self.level or 1 end
    function o:SetFrameLevel(l) self.level = l end
    function o:SetIgnoreParentAlpha() end
    -- edit boxes and scroll frames
    function o:SetMultiLine(m) self.multiLine = m end
    function o:SetAutoFocus() end
    function o:SetMaxBytes(n) self.maxBytes = n end
    function o:SetFocus() self.focused = true; if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end end
    function o:ClearFocus() self.focused = false; if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
    function o:SetScrollChild(c) self.scrollChild = c end
    function o:GetVerticalScrollRange() return 0 end
    function o:GetVerticalScroll() return 0 end
    function o:SetVerticalScroll(v) self.vscroll = v end
    -- backdrops (RestedXP's windows)
    function o:ClearBackdrop() self.backdrop = nil end
    function o:SetBackdrop(b) self.backdrop = b end
    function o:SetBackdropColor(...) self.backdropColor = { ... } end
    function o:GetNormalTexture() return self.normal end
    function o:SetNormalTexture(t) self.normal = self.normal or newObject("Texture", nil, self); self.normal.texture = t end
    -- buttons
    function o:SetFontString(fs) self.fontString = fs end
    function o:GetFontString() return self.fontString end
    function o:SetHitRectInsets(l, r, t, b) self.hitInsets = { l, r, t, b } end
    -- sliders: SetValue clamps and fires OnValueChanged like the game; the thumb sits at the value.
    function o:SetOrientation(v) self.orientation = v end
    function o:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function o:GetMinMaxValues() return self.min, self.max end
    function o:SetValueStep(v) self.step = v end
    function o:SetObeyStepOnDrag(v) self.obeyStep = v end
    function o:SetThumbTexture(t) self.thumbTexture = t end
    function o:GetThumbTexture() return self.thumbTexture end
    function o:SetValue(v)
        if self.min and self.max then v = math.max(self.min, math.min(self.max, v)) end
        local old = self.value
        self.value = v
        local thumb = self.thumbTexture
        if thumb and self.min and self.max > self.min then
            thumb.points = { { "CENTER", self, "LEFT", (v - self.min) / (self.max - self.min) * (self.w or 0), 0 } }
        end
        if self.kind == "Slider" and old ~= v and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
    end
    function o:GetValue() return self.value end
    function o:SetEnabled(e) self.enabled = e end
    function o:SetChecked(c) self.checked = c end
    function o:GetChecked() return self.checked end
    function o:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end
    return o
end
M.newObject = newObject

-- Pasting into an edit box: the box keeps what fits (SetMaxBytes) and every character also goes
-- through OnChar. dropNewlines: OnChar skips line breaks (to test the fallback).
function M.paste(eb, text, dropNewlines)
    local keep = text
    if eb.maxBytes and eb.maxBytes > 0 then keep = text:sub(1, eb.maxBytes) end
    eb.text = (eb.text or "") .. keep
    if eb.scripts.OnChar then
        for ch in text:gmatch(".") do
            if not (dropNewlines and ch == "\n") then eb.scripts.OnChar(eb, ch) end
        end
    end
    if eb.scripts.OnTextChanged then eb.scripts.OnTextChanged(eb, true) end
    M.now = M.now + 0.2
    if eb.scripts.OnUpdate then eb.scripts.OnUpdate(eb, 0.2) end
end

if not hooksecurefunc then
    function hooksecurefunc(obj, method, fn)
        if type(obj) == "string" then obj, method, fn = _G, obj, method end
        local orig = obj[method]
        obj[method] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end
end

local templates = {}
function templates.UICheckButtonTemplate(f) f.Text = f:CreateFontString(nil, "ARTWORK"); f.checked = false; f.enabled = true end
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
function templates.UIPanelButtonTemplate() end
function templates.UIPanelCloseButtonDefaultAnchors() end
function templates.DefaultPanelTemplate(f) function f:SetTitle(t) self.title = t end end

function CreateFrame(kind, name, parent, template)
    local f = newObject(kind or "Frame", name, parent)
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    if template then
        assert(templates[template], "unknown template " .. tostring(template))
        templates[template](f)
        f.template = template
    end
    M.frames[#M.frames + 1] = f
    if name then _G[name] = f end
    return f
end

UIParent = newObject("Frame", "UIParent")
GameTooltip = newObject("Frame", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {}; self.title = nil end
function GameTooltip:SetText(t) self.title = t end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:Hide() self.shown = false end
function GameTooltip:Show() self.shown = true end

M.categories = {}
Settings = {}
function Settings.RegisterCanvasLayoutCategory(frame, name) return { frame = frame, name = name }, {} end
function Settings.RegisterAddOnCategory(c) M.categories[#M.categories + 1] = c end
ColorPickerFrame = { rgb = { 0, 0, 0 } }
function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info end
function ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end

-- ---------------------------------------------------------------- quests and the world

M.quests = { on = {}, done = {}, complete = {}, objectives = {}, names = {} }
M.logCount, M.logMax = 5, 25
C_QuestLog = {}
function C_QuestLog.GetQuestObjectives(id) return M.quests.objectives[id] end
function C_QuestLog.GetTitleForQuestID(id) return M.quests.names[id] or ("Quest #" .. id) end
function C_QuestLog.GetNumQuestLogEntries() return M.logCount + 2, M.logCount end
function C_QuestLog.GetMaxNumQuestsCanAccept() return M.logMax end

M.player = { x = 0, y = 0, instance = 0 }
local HBD = {}
function HBD:GetPlayerWorldPosition() return M.player.x, M.player.y, M.player.instance end
function HBD:GetWorldVector(instance, ox, oy, dx, dy)
    local vx, vy = dx - ox, dy - oy
    return math.atan2(vy, vx) % (2 * math.pi), math.sqrt(vx * vx + vy * vy)
end
M.pins = { world = {}, mini = {} }
local HBDPins = {}
function HBDPins:AddWorldMapIconWorld(ref, icon, inst, x, y) M.pins.world[#M.pins.world + 1] = { icon = icon, x = x, y = y } end
function HBDPins:AddMinimapIconWorld(ref, icon, inst, x, y) M.pins.mini[#M.pins.mini + 1] = { icon = icon, x = x, y = y } end
function HBDPins:RemoveAllWorldMapIcons() M.pins.world = {} end
function HBDPins:RemoveAllMinimapIcons() M.pins.mini = {} end
M.HBD = HBD

-- ---------------------------------------------------------------- a mock RestedXP

local RXP = {
    settings = { profile = { showEnabled = true, windowScale = 1.1 } },
    font = "Fonts\\FRIZQT__.TTF",
    guideTextColors = { default = { RXP_FRIENDLY_ = "FF00FF25", RXP_ENEMY_ = "FFFF5722", RXP_LOOT_ = "FF00BCD4", RXP_WARN_ = "FFFCDC00", RXP_PICK_ = "FFDB2EEF", RXP_BUY_ = "FF0E8312" } },
    locale = { Get = function(t) return t end },
    progress = 1,
    setStepCalls = {},
}
for k, v in pairs(RXP.guideTextColors.default) do RXP.guideTextColors[k] = v end
RXP.RXPFrame = newObject("Frame", "RXPFrame", UIParent)
RXP.RXPFrame.left, RXP.RXPFrame.top = 20, 620
RXP.RXPFrame.scale = 1.1
RXP.RXPFrame.activeSteps = {}
function RXP.RXPFrame.DropDownMenu() RXP.menuOpened = true end
M.RXP = RXP

local function colorize(t)
    return (t:gsub("RXP_(%u+)_", function(k) return RXP.guideTextColors["RXP_" .. k .. "_"] end))
end

-- Like RestedXP's SetStep: the step and any #completewith steps before it become active.
function RXP.SetStep(n)
    RXP.setStepCalls[#RXP.setStepCalls + 1] = n
    local steps = RXP.currentGuide.steps
    while steps[n] and steps[n].sticky and n < #steps do n = n + 1 end
    RXP.progress = n
    local active = RXP.RXPFrame.activeSteps
    for i = #active, 1, -1 do active[i] = nil end
    for i = 1, n - 1 do
        local s = steps[i]
        if s.sticky and not s.stickyDone then active[#active + 1] = s end
    end
    active[#active + 1] = steps[n]
    for _, s in ipairs(steps) do s.active = nil end
    for _, s in ipairs(active) do s.active = true end
end
function RXP.GetGuideProgress() return RXP.progress end
function RXP.IsOnQuest(id) return M.quests.on[id] or false end
function RXP.IsQuestTurnedIn(id) return M.quests.done[id] or false end
function RXP.IsQuestComplete(id) return M.quests.complete[id] or false end
function RXP.GetQuestName(id) return M.quests.names[id] end
function RXP.ReplaceNpcIds(t) return t end
function RXP.UpdateMap() RXP.mapUpdates = (RXP.mapUpdates or 0) + 1 end

M.rxpLoaded = true
local libs = {
    ["AceAddon-3.0"] = { GetAddon = function(_, name) return M.rxpLoaded and name == "RXPGuides" and RXP or nil end },
    ["HereBeDragons-2.0"] = HBD,
    ["HereBeDragons-Pins-2.0"] = HBDPins,
}
function LibStub(name) return libs[name] end

RXPG_ARROW = newObject("Frame", "RXPG_ARROW", UIParent)
RXPG_ARROW.texture = newObject("Texture")
RXPG_ARROW.texture.texture = "Interface/AddOns/RXPGuides/Textures/rxp_navigation_arrow-1"

-- Guide building, the way RestedXP's parser leaves elements (colour codes already replaced).
function M.goto(wx, wy, opts)
    local e = { tag = "goto", wx = wx, wy = wy, instance = 0, textOnly = true, arrow = true }
    for k, v in pairs(opts or {}) do e[k] = v end
    if e.text then e.text = colorize(e.text) end
    return e
end
function M.text(t) return { text = colorize(t), textOnly = true } end
function M.check(t) return { text = colorize(t) } end -- a "+" line: a manual checkbox
function M.accept(id, t) return { tag = "accept", questId = id, text = colorize(t or "Accept *quest*") } end
function M.turnin(id, t) return { tag = "turnin", questId = id, text = colorize(t or "Turn in *quest*") } end
function M.complete(id, obj, t) return { tag = "complete", questId = id, obj = obj, text = t or " " } end
function M.train(id, t) return { tag = "train", id = id, text = t } end
function M.collect(id, t) return { tag = "collect", id = id, text = t } end
function M.xp(level, t) return { tag = "xp", level = level, text = t } end
function M.vendor(id, t) return { tag = "vendor", id = id, text = t } end
function M.guard(tag, ids, extra) local e = { tag = tag, questIds = ids, textOnly = true } for k, v in pairs(extra or {}) do e[k] = v end return e end
function M.step(elements, extra)
    local s = { elements = elements }
    for k, v in pairs(extra or {}) do s[k] = v end
    for _, e in ipairs(elements) do e.step = s end
    return s
end
function M.setGuide(steps, name)
    for i, s in ipairs(steps) do s.index = i end
    RXP.currentGuide = { name = name or "01-13 UD Paladin Launch Route", group = "My Guides", key = "My Guides|" .. (name or "launch"), steps = steps }
    RXP.SetStep(1)
end

-- ---------------------------------------------------------------- layout dump for the renderer

local function rectOf(o, cache)
    if cache[o] then return unpack(cache[o]) end
    local parent = o.parent
    local px, py, pw, ph = 0, 0, 0, 0
    if parent and parent ~= UIParent and parent.parent ~= nil and not o.isRoot then
        px, py, pw, ph = rectOf(parent, cache)
    end
    local w = o.w or 0
    local h = o.h or 0
    if o.kind == "FontString" then
        h = o:GetStringHeight()
        if w == 0 then w = o:GetStringWidth() end -- no width set: as wide as its text
    end
    local x, y = px, py
    local p = o.points[1]
    if o.isRoot then
        x, y = 0, 0
    elseif o.allPoints then
        local ax, ay, aw, ah = rectOf(o.allPoints, cache)
        x, y, w, h = ax, ay, aw, ah
    elseif p and o.points[2] and (w == 0 or h == 0) then
        -- Sized by its anchors (only for what has no size of its own along that side).
        local function anchorOf(q)
            local point, rel, relPoint, ox, oy = q[1], q[2], q[3], q[4], q[5]
            if type(rel) ~= "table" then rel, relPoint, ox, oy = parent, point, q[2], q[3] end
            local rx, ry, rw, rh = px, py, pw, ph
            if rel and rel ~= parent then rx, ry, rw, rh = rectOf(rel, cache) end
            local ax = (relPoint:find("LEFT") and rx) or (relPoint:find("RIGHT") and rx + rw) or (rx + rw / 2)
            local ay = (relPoint:find("TOP") and ry) or (relPoint:find("BOTTOM") and ry + rh) or (ry + rh / 2)
            return ax + (ox or 0), ay - (oy or 0)
        end
        local lx, rx, cx, ty, by, cy
        for _, q in ipairs(o.points) do
            local ax, ay = anchorOf(q)
            if q[1]:find("LEFT") then lx = ax elseif q[1]:find("RIGHT") then rx = ax else cx = ax end
            if q[1]:find("TOP") then ty = ay elseif q[1]:find("BOTTOM") then by = ay else cy = ay end
        end
        if w == 0 and lx and rx then w = rx - lx end
        if h == 0 and ty and by then h = by - ty end
        x = lx or (rx and rx - w) or (cx and cx - w / 2) or px
        y = ty or (by and by - h) or (cy and cy - h / 2) or py
    elseif p then
        local point, rel, relPoint, ox, oy = p[1], p[2], p[3], p[4], p[5]
        if type(rel) ~= "table" then rel, relPoint, ox, oy = parent, point, p[2], p[3] end
        ox, oy = ox or 0, oy or 0
        local rx, ry, rw, rh = px, py, pw, ph
        if rel and rel ~= parent then rx, ry, rw, rh = rectOf(rel, cache) end
        local ax = (relPoint:find("LEFT") and rx) or (relPoint:find("RIGHT") and rx + rw) or (rx + rw / 2)
        local ay = (relPoint:find("TOP") and ry) or (relPoint:find("BOTTOM") and ry + rh) or (ry + rh / 2)
        ax, ay = ax + ox, ay - oy
        x = (point:find("LEFT") and ax) or (point:find("RIGHT") and ax - w) or (ax - w / 2)
        y = (point:find("TOP") and ay) or (point:find("BOTTOM") and ay - h) or (ay - h / 2)
    end
    cache[o] = { x, y, w, h }
    return x, y, w, h
end

-- Draw operations for everything shown under root, back to front (dx, dy: where root goes).
function M.dump(root, dx, dy, ops)
    root.isRoot = true
    ops = ops or {}
    local cache = {}
    local first = #ops + 1
    local function visit(f)
        if not f.shown then return end
        local slices = {}
        for _, ns in ipairs(f.nineSlices or {}) do
            if ns.parts[1].layer ~= "HIGHLIGHT" then slices[#slices + 1] = ns end
        end
        local order = {}
        for i, ns in ipairs(slices) do order[ns] = i end
        table.sort(slices, function(a, b)
            local la, lb = LAYERS[a.parts[1].layer] or 3, LAYERS[b.parts[1].layer] or 3
            if la ~= lb then return la < lb end
            local sa, sb = a.parts[1].sublevel or 0, b.parts[1].sublevel or 0
            if sa ~= sb then return sa < sb end
            return order[a] < order[b]
        end)
        for _, ns in ipairs(slices) do
            local p1 = ns.parts[1]
            if p1.shown and p1.color then
                local x, y, w, h = rectOf((ns.box and ns.box ~= f) and ns.box or f, cache)
                local op = { type = ns.file:find("border") and "ring" or "rect", x = x, y = y, w = w, h = h, color = p1.color, corner = p1.w, file = ns.file }
                if ns.gradient then op.top, op.bottom = ns.gradient[1], ns.gradient[2] end
                ops[#ops + 1] = op
            end
        end
        local regions = {}
        for _, r in ipairs(f.regions) do
            local inSlice = false
            for _, ns in ipairs(f.nineSlices or {}) do for _, part in ipairs(ns.parts) do if part == r then inSlice = true end end end
            if not inSlice and r.shown and r.layer ~= "HIGHLIGHT" then regions[#regions + 1] = r end
        end
        table.sort(regions, function(a, b) return (LAYERS[a.layer] or 3) < (LAYERS[b.layer] or 3) end)
        for _, r in ipairs(regions) do
            local x, y, w, h = rectOf(r, cache)
            if r.kind == "Texture" then
                if r.colorTexture then
                    ops[#ops + 1] = { type = "fill", x = x, y = y, w = w, h = h, color = r.colorTexture }
                elseif r.texture then
                    ops[#ops + 1] = { type = "tex", x = x, y = y, w = w, h = h, file = r.texture, coords = r.coords, color = r.color or { 1, 1, 1, 1 } }
                end
            elseif r.kind == "FontString" and r.text and r.text ~= "" then
                ops[#ops + 1] = { type = "text", x = x, y = y, w = w, lines = r:Lines(), size = r.fontSize, weight = weightOf(r.fontPath),
                    color = r.textColor or { 1, 1, 1, 1 }, lineHeight = r:LineHeight() + (r.spacing or 0),
                    justify = r.justifyH or "LEFT",
                    shadow = (r.shadowOffset and r.shadowOffset[1] ~= 0 and not (r.shadowColor and r.shadowColor[4] == 0)) or false }
            end
            if r.kind == "Texture" and r.rotation and r.rotation ~= 0 and ops[#ops] and ops[#ops].type == "tex" then
                ops[#ops].rotation = r.rotation
            end
        end
        for _, c in ipairs(f.children) do visit(c) end
    end
    visit(root)
    for i = first, #ops do ops[i].x = ops[i].x + (dx or 0); ops[i].y = ops[i].y + (dy or 0) end
    return ops
end

local function json(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for _, x in ipairs(v) do out[#out + 1] = json(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = string.format("%q", tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(out, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\031", "") .. '"'
    elseif t == "number" then
        return string.format("%.3f", v)
    elseif t == "boolean" then
        return tostring(v)
    end
    return "null"
end
M.json = json

return M

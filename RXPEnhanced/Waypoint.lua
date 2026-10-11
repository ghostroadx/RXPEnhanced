-- RXP Enhanced: an in-world waypoint marker where RestedXP's arrow points, in place of a separate
-- waypoint addon.
--
-- WoW only tells addons where a point in the world is on screen for the one thing being
-- "super-tracked" (C_Navigation.GetFrame() follows it). So each time RestedXP's arrow moves to a
-- new spot, this sets the game's own map waypoint there and super-tracks it, then draws its marker
-- on the navigation frame. RestedXP super-tracks quests of its own now and then; those are taken
-- back. A quest you pick yourself is left alone, and the marker steps aside until RestedXP's
-- arrow moves on.
--
-- Markers: Pin (the default), Gold ring (spins, breaks apart when you arrive) or Beacon (a column
-- of light). Off screen, an arrow on the screen's edge points the way. Blizzard's own diamond is
-- hidden while ours shows.

local ADDON_NAME = ...
local NS = _G.RXPEnhanced
if not (NS and NS.private) then return end
local P = NS.private
local WP = {}
NS.Waypoint = WP

local floor, min, max, sin, cos, pi, sqrt, abs, random = math.floor, math.min, math.max, math.sin, math.cos, math.pi, math.sqrt, math.abs, math.random
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local MEDIA = "Interface\\AddOns\\" .. (ADDON_NAME or "RXPEnhanced") .. "\\Media\\"
local RING = MEDIA .. "Ring\\"
local ICON_FILE = MEDIA .. "icons"
local FONT = MEDIA .. "Inter-Medium.ttf"

WP.STYLES = {
    { key = "pin", name = "Pin", tip = "A map pin standing on the spot, in the marker colour. The default." },
    { key = "ring", name = "Gold ring", tip = "A gold ring that spins over the spot and breaks apart when you get there." },
    { key = "beacon", name = "Beacon", tip = "A column of light rising from the spot, in the marker colour." },
}
WP.SOUNDS = {
    { key = "glass", name = "Glass shimmer", file = MEDIA .. "RingBreak.ogg" }, -- made for the ring
    { key = "azerite", name = "Azerite shimmer", kit = "UI_80_AZERITEARMOR_REFORGE", id = 114992 },
    { key = "crystal", name = "Crystal socket", kit = "UI_70_CHALLENGE_MODE_SOCKET_PAGE_SOCKET", id = 74431 },
    { key = "chime", name = "Waypoint chime", kit = "UI_MAP_WAYPOINT_SUPER_TRACK_ON", id = 170270 },
    { key = "ping", name = "Map ping", kit = "MAP_PING", id = 3175 },
}
local NEW_TICK = { kit = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", id = 170269 }

-- Ring art: 1024 x 1024 sheets, 4 x 4 grids of 256 px frames. Ring1/Ring2 hold 32 frames of half a
-- turn; RingBreak1-4 hold 16 break frames from four starting angles, on a canvas twice the size.
local GRID, PER_SHEET, RING_FRAMES, BREAK_FRAMES, BREAK_ANGLES = 4, 16, 32, 16, 4
local SPIN_PERIOD = 1.1
local RING_RADIUS = 1 / 1.28
-- Size follows real perspective: PERSPECTIVE / (yards + camera zoom), with a floor far away. About
-- 92 UI px at 10 yd with the camera ~12 yd out; it settles near 18 px far away.
local PERSPECTIVE, MIN_SIZE, DEFAULT_ZOOM = 1985, 18, 12
local ARRIVE_EFFECT = 0.55
local REARM_EXTRA = 15 -- walk this much further than the arrive distance and the marker comes back

local db, rxp, HBD
local state = { target = nil, point = nil, lastDist = nil, arrived = false, reclaim = false }
local navFrame
local root, marker, edge, label, burst, plateAnchor

local function ready()
    db = P.db()
    rxp = P.getRXP()
    HBD = P.hbd()
    return db ~= nil and rxp ~= nil
end

-- ---------------------------------------------------------------- sounds

local function playKit(entry)
    local id = (SOUNDKIT and SOUNDKIT[entry.kit]) or entry.id
    if id then pcall(PlaySound, id, "SFX") end
end

function WP.PlaySound(key)
    local s
    for _, entry in ipairs(WP.SOUNDS) do if entry.key == key then s = entry end end
    s = s or WP.SOUNDS[1]
    if s.file then
        -- If the file can't play (no PlaySoundFile on this client, or the game hasn't been
        -- restarted since it was added), use the Azerite shimmer rather than stay silent.
        local ok, willPlay = false, false
        if type(PlaySoundFile) == "function" then ok, willPlay = pcall(PlaySoundFile, s.file, "SFX") end
        if not (ok and willPlay) then playKit(WP.SOUNDS[2]) end
    else
        playKit(s)
    end
end

local function arrivalSound()
    if db.wpSounds then WP.PlaySound(db.wpSound) end
end

-- ---------------------------------------------------------------- the game's waypoint

local function near(a, b) return abs(a - b) < 0.002 end

-- Map and position (0-1) for an element of RestedXP's: its zone and coordinates, else converted
-- from world coordinates.
local function canSetOn(mapID)
    if not (C_Map and C_Map.CanSetUserWaypointOnMap) then return true end
    return P.call(C_Map.CanSetUserWaypointOnMap, mapID) and true or false
end

local function zoneCoords(el, mapID)
    if not (HBD and el.wx and el.wy and mapID) then return nil end
    local ok, x, y = pcall(HBD.GetZoneCoordinatesFromWorld, HBD, el.wx, el.wy, mapID)
    if ok and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- Maps and positions (0-1) to try for an element of RestedXP's, best first: its own zone and
-- coordinates (RestedXP keeps those 0-100), then the map you're on, then the map above either
-- (some maps, like cities, don't take waypoints).
local function mapPointsOf(el)
    local out, seen = {}, {}
    local function add(mapID, x, y)
        if not (mapID and x and y) or seen[mapID] then return end
        seen[mapID] = true
        if canSetOn(mapID) then out[#out + 1] = { mapID, x, y } end
    end
    local zone = tonumber(el.zone)
    local x, y = el.x, el.y
    if not (x and y) and el.zx and el.zy then x, y = el.zx, el.zy end -- in-game waypoints use zx/zy
    if zone and x and y then add(zone, x / 100, y / 100) end
    local here = C_Map and P.call(C_Map.GetBestMapForUnit, "player")
    if here then add(here, zoneCoords(el, here)) end
    for _, mapID in ipairs({ zone or false, here or false }) do
        local info = mapID and P.call(C_Map.GetMapInfo, mapID)
        local parent = info and info.parentMapID
        if parent and parent > 0 then add(parent, zoneCoords(el, parent)) end
    end
    return out
end
WP.MapPointsOf = mapPointsOf

local function isOurs()
    local p = state.point
    if not p or not (C_Map and C_Map.HasUserWaypoint and P.call(C_Map.HasUserWaypoint)) then return false end
    local w = P.call(C_Map.GetUserWaypoint)
    if not (w and w.uiMapID == p.mapID and w.position) then return false end
    local wx, wy = w.position.x, w.position.y
    if type(w.position.GetXY) == "function" then wx, wy = w.position:GetXY() end
    return near(wx, p.x) and near(wy, p.y)
end
WP.IsOurs = isOurs

-- Places the game's waypoint for el and super-tracks it. Tries each candidate map until the game
-- takes one; state.fail says why when none did (for /rxpe debug).
local function setWaypoint(el)
    state.point = nil
    local candidates = mapPointsOf(el)
    if #candidates == 0 then
        state.fail = "no map here takes a waypoint for this spot"
        return false
    end
    if not (UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint) then
        state.fail = "the game's waypoint functions are missing"
        return false
    end
    for _, c in ipairs(candidates) do
        local mapID, x, y = c[1], c[2], c[3]
        local point = P.call(UiMapPoint.CreateFromCoordinates, mapID, x, y)
        local ok, wasSet = false, nil
        if point then ok, wasSet = pcall(C_Map.SetUserWaypoint, point) end
        if ok and wasSet ~= false and P.call(C_Map.HasUserWaypoint) then
            -- The game rounds the position a little; remember what it actually kept.
            local kept = P.call(C_Map.GetUserWaypointPositionForMap, mapID)
            if kept and kept.x then x, y = kept.x, kept.y end
            state.point = { mapID = mapID, x = x, y = y }
            state.fail = nil
            P.call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            return true
        end
        state.fail = ok and ("the game turned down a waypoint on map " .. mapID) or ("setting a waypoint on map " .. mapID .. " failed")
    end
    return false
end

local function clearOurs()
    if isOurs() then P.call(C_Map.ClearUserWaypoint) end
    state.point = nil
end

-- Quests RestedXP is working on right now (it super-tracks these by itself).
local function guideQuest(questID)
    local active = rxp.RXPFrame and rxp.RXPFrame.activeSteps
    for _, step in ipairs(type(active) == "table" and active or {}) do
        for _, el in ipairs(step.elements or {}) do
            if el.questId and tonumber(el.questId) == questID then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------- what the marker points at
-- RestedXP's arrow target, as a map waypoint at its coordinates, the way Waypoint UI's RestedXP
-- support did it (Code/SupportedAddons/RestedXP.lua: polled every 0.25 s, RestedXP's arrow always
-- wins the game's tracking). Two extras:
--  - The step's NPC in view (its nameplate on screen; the step's .target names): the marker
--    stands on the NPC itself. Setting wpOnNpc, on by default.
--  - Quest steps can use the game's own quest navigation instead (the turn-in NPC, or the
--    objective's area). Setting wpQuest, off by default.
-- Hidden path points (RestedXP's arrow routing around something) always use the coordinates.

-- The quest the arrow's step is about, if the game can navigate to it.
local function stepQuest(el)
    if not (db.wpQuest and el and not el.hidePin and type(el.step) == "table") then return nil end
    local turnin, objective
    for _, e in ipairs(el.step.elements or {}) do
        local q = tonumber(e.questId)
        if q and not e.completed and not e.skip then
            if (e.tag == "turnin" or e.tag == "dailyturnin") and P.onQuest(q) and P.questComplete(q) then
                turnin = turnin or q
            elseif e.tag == "complete" and P.onQuest(q) and not P.questComplete(q) then
                objective = objective or q
            end
        end
    end
    return turnin or objective
end
WP.StepQuest = stepQuest

local function trackedQuest()
    local q = P.call(C_SuperTrack.GetSuperTrackedQuestID)
    return type(q) == "number" and q > 0 and q or nil
end

-- Whether the game is tracking what we want it to.
local function onGoal()
    if state.quest then return trackedQuest() == state.quest end
    return state.point and P.call(C_SuperTrack.IsSuperTrackingUserWaypoint) and isOurs() or false
end

-- The step's NPC names (its .target lines).
local function stepNPCs(el)
    local names
    for _, e in ipairs(type(el.step) == "table" and el.step.elements or {}) do
        for _, n in ipairs(type(e.targets) == "table" and e.targets or {}) do
            if type(n) == "string" and n ~= "" then
                names = names or {}
                names[n] = true
            end
        end
    end
    return names
end

-- The nameplate of the step's NPC, if it's on screen.
local function npcPlate(el)
    local nearby = NS.Card and NS.Card.Nearby
    if not (db.wpOnNpc ~= false and nearby and el and not el.hidePin) then return nil end
    local names = stepNPCs(el)
    if not names then return nil end
    for unit, name in pairs(nearby.plates) do
        if names[name] then
            local plate = C_NamePlate and P.call(C_NamePlate.GetNamePlateForUnit, unit)
            if plate and plate.IsVisible and plate:IsVisible() then return plate, name end
        end
    end
end
WP.NpcPlate = npcPlate

function WP.OnSuperTrackingChanged()
    if not (ready() and db.wpEnabled and state.target) then return end
    -- Anything else took the game's tracking (a quest RestedXP or you tracked, another pin):
    -- RestedXP's arrow wins while it has somewhere to go, as with Waypoint UI.
    if not onGoal() then state.reclaim = true end
end

-- ---------------------------------------------------------------- the game's navigation option
-- The game only puts a waypoint on screen (C_Navigation.GetFrame) while its "In-Game Navigation"
-- option is on (Options > Interface > Display; the showInGameNavigation setting). Forever has it
-- off by default. Waypoint UI turns it on for each session, which is why the marker only showed
-- with Waypoint UI installed. While the marker is on, this does the same, and puts the option back
-- the way it was at logout or reload, or when the marker is turned off.
local NAV_OPTION = "showInGameNavigation"
local navOptionWas -- its value before this turned it on; nil when this didn't change it

local function optionGet(name)
    if C_CVar and C_CVar.GetCVar then return P.call(C_CVar.GetCVar, name) end
end

local function optionSet(name, value)
    if C_CVar and C_CVar.SetCVar then return P.call(C_CVar.SetCVar, name, value) end
end

function WP.UseNavigation(on)
    if on then
        local now = optionGet(NAV_OPTION)
        if now == nil or now == "1" then return end -- not on this client, or already on
        navOptionWas = navOptionWas or now
        optionSet(NAV_OPTION, "1")
        -- Track our waypoint again so the game makes its navigation point now.
        if state.point and P.call(C_SuperTrack.IsSuperTrackingUserWaypoint) then
            P.call(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
            P.call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    elseif navOptionWas ~= nil then
        optionSet(NAV_OPTION, navOptionWas)
        navOptionWas = nil
    end
end
WP.NavigationTurnedOn = function() return navOptionWas ~= nil end

-- ---------------------------------------------------------------- Blizzard's diamond

local hidingBlizzard, hookedBlizzard = false, false

local function hideBlizzard()
    local f = _G.SuperTrackedFrame
    if not f then return end
    if not hookedBlizzard then
        hookedBlizzard = true
        hooksecurefunc(f, "Show", function(self) if hidingBlizzard then self:Hide() end end)
        hooksecurefunc(f, "SetShown", function(self, shown) if hidingBlizzard and shown then self:Hide() end end)
    end
    hidingBlizzard = true
    if f:IsShown() then f:Hide() end
end

local function restoreBlizzard()
    if not hidingBlizzard then return end
    hidingBlizzard = false
    local f = _G.SuperTrackedFrame
    if f and f.navFrame and P.call(C_SuperTrack.IsSuperTrackingAnything) then f:Show() end
end
WP.IsHidingBlizzard = function() return hidingBlizzard end

-- ---------------------------------------------------------------- drawing helpers

local function setCell(tex, cell)
    local col, row = cell % GRID, floor(cell / GRID)
    tex:SetTexCoord(col / GRID, (col + 1) / GRID, row / GRID, (row + 1) / GRID)
end

local function cameraZoom()
    if type(GetCameraZoom) ~= "function" then return DEFAULT_ZOOM end
    local ok, zoom = pcall(GetCameraZoom)
    if not ok or type(zoom) ~= "number" then return DEFAULT_ZOOM end
    return min(max(zoom, 2), 40)
end

local function screenSize(dist)
    if type(dist) ~= "number" or dist < 0 then dist = 1000 end
    local p = PERSPECTIVE / (dist + cameraZoom())
    return sqrt(p * p + MIN_SIZE * MIN_SIZE) * (db.wpScale or 1)
end
WP.ScreenSize = function(d) return screenSize(d) end

local function backOut(x) -- overshoots a little, then settles at 1
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function colour() return db.wpColor or { 0.95, 0.78, 0.36 } end

-- ---------------------------------------------------------------- markers
-- Each marker: frame anchored to the navigation frame, :Draw(size, t) every frame, :PopIn(), and
-- :Arrive(x, y, size) to play its arrival where the spot is on screen right now.

local function newRing(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(64, 64)
    m.glow = m:CreateTexture(nil, "BACKGROUND")
    m.glow:SetTexture(RING .. "Glow")
    m.glow:SetBlendMode("ADD")
    m.glow:SetPoint("CENTER")
    m.tex = m:CreateTexture(nil, "ARTWORK")
    m.tex:SetTexture(RING .. "Ring1")
    m.tex:SetAllPoints()
    m.sheet, m.frameIndex, m.theta = 1, -1, 0
    m.sparkles = {}
    for i = 1, 3 do
        local s = m:CreateTexture(nil, "OVERLAY")
        s:SetTexture(RING .. "Sparkle")
        s:SetBlendMode("ADD")
        s:SetAlpha(0)
        m.sparkles[i] = { tex = s, born = 0, life = 0, wait = i * 0.35, phi = 0, spin = 0 }
    end
    function m:Draw(size, t, elapsed, nav)
        local phase = (t / SPIN_PERIOD * 2) % 1
        self.theta = phase * pi
        local index = floor(phase * RING_FRAMES) % RING_FRAMES
        if index ~= self.frameIndex then
            self.frameIndex = index
            local sheet = floor(index / PER_SHEET) + 1
            if sheet ~= self.sheet then
                self.sheet = sheet
                self.tex:SetTexture(RING .. "Ring" .. sheet)
            end
            setCell(self.tex, index % PER_SHEET)
        end
        self:SetSize(size, size)
        self.glow:SetSize(size * 1.7, size * 1.7)
        self.glow:SetAlpha(0.28 + 0.08 * sin(t * 3))
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", nav, "CENTER", 0, size * (0.08 + sin(t * 2.4) * 0.04))
        -- Sparkles around the rim.
        local radius = size * 0.5 * RING_RADIUS
        local squash = abs(cos(self.theta))
        for _, sp in ipairs(self.sparkles) do
            if sp.life <= 0 then
                sp.wait = sp.wait - elapsed
                if sp.wait <= 0 then
                    sp.born, sp.life, sp.phi, sp.spin = t, 0.35 + random() * 0.3, random() * 2 * pi, (random() - 0.5) * 3
                end
                sp.tex:SetAlpha(0)
            else
                local a = (t - sp.born) / sp.life
                if a >= 1 then
                    sp.life, sp.wait = 0, 0.15 + random() * 0.6
                    sp.tex:SetAlpha(0)
                else
                    local k = sin(pi * a)
                    local s = max(1, size * 0.42 * k)
                    sp.tex:SetSize(s, s)
                    sp.tex:ClearAllPoints()
                    sp.tex:SetPoint("CENTER", self, "CENTER", cos(sp.phi) * radius * squash, sin(sp.phi) * radius)
                    sp.tex:SetRotation(sp.spin * a)
                    sp.tex:SetAlpha(k)
                end
            end
        end
    end
    function m:Arrive(x, y, size)
        burst:Play("ring", x, y + size * 0.58, size, self.theta)
    end
    return m
end

local function newBeacon(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(32, 96)
    m.beam = m:CreateTexture(nil, "ARTWORK")
    m.beam:SetTexture(MEDIA .. "beam")
    m.beam:SetBlendMode("ADD")
    m.beam:SetAllPoints()
    m.base = m:CreateTexture(nil, "BACKGROUND")
    m.base:SetTexture(RING .. "Glow")
    m.base:SetBlendMode("ADD")
    function m:Draw(size, t, elapsed, nav)
        local c = colour()
        local w, h = size * 0.55, size * 3.2
        self:SetSize(w, h)
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", nav, "CENTER", 0, -size * 0.06)
        self.beam:SetVertexColor(c[1], c[2], c[3], 0.78 + 0.14 * sin(t * 2.2))
        self.base:SetVertexColor(c[1], c[2], c[3], 0.9)
        self.base:ClearAllPoints()
        self.base:SetPoint("CENTER", self, "BOTTOM", 0, size * 0.06)
        self.base:SetSize(size * 1.1, size * 0.55)
    end
    function m:Arrive(x, y, size)
        burst:Play("beacon", x, y, size)
    end
    return m
end

local function newPin(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(32, 32)
    m.shadow = m:CreateTexture(nil, "BACKGROUND")
    m.shadow:SetTexture(MEDIA .. "shadow")
    m.pin = m:CreateTexture(nil, "ARTWORK")
    m.pin:SetTexture(MEDIA .. "markerpin")
    m.pin:SetAllPoints()
    function m:Draw(size, t, elapsed, nav)
        local c = colour()
        local s = size * 0.62
        local bob = s * (0.10 + 0.06 * sin(t * 2.6))
        self:SetSize(s, s)
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", nav, "CENTER", 0, bob)
        self.pin:SetVertexColor(c[1], c[2], c[3], 1)
        self.shadow:ClearAllPoints()
        self.shadow:SetPoint("CENTER", nav, "CENTER", 0, 0)
        self.shadow:SetSize(s * 0.7, s * 0.28)
        self.shadow:SetAlpha(0.55 - bob / s)
    end
    function m:Arrive(x, y, size)
        burst:Play("pin", x, y, size)
    end
    return m
end

-- One-shot arrival effects, pinned to where the spot was on screen.
local function newBurst(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetFrameStrata("LOW")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.flash = b:CreateTexture(nil, "OVERLAY")
    b.flash:SetTexture(RING .. "Sparkle")
    b.flash:SetBlendMode("ADD")
    b.flash:SetPoint("CENTER")
    b:Hide()
    function b:Play(kind, x, y, size, theta)
        self.kind, self.t, self.size, self.frame = kind, 0, size, -1
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local c = colour()
        if kind == "ring" then
            local angle = floor((theta or 0) / (pi / BREAK_ANGLES) + 0.5) % BREAK_ANGLES
            self.tex:SetTexture(RING .. "RingBreak" .. (angle + 1))
            self.tex:SetBlendMode("BLEND")
            self.tex:SetVertexColor(1, 1, 1, 1)
            self:SetSize(size * 2, size * 2)
        elseif kind == "beacon" then
            self.tex:SetTexture(MEDIA .. "beam")
            self.tex:SetTexCoord(0, 1, 0, 1)
            self.tex:SetBlendMode("ADD")
            self.tex:SetVertexColor(c[1], c[2], c[3], 1)
            self:SetSize(size * 0.55, size * 3.2)
        else
            self.tex:SetTexture(MEDIA .. "markerpin")
            self.tex:SetTexCoord(0, 1, 0, 1)
            self.tex:SetBlendMode("BLEND")
            self.tex:SetVertexColor(c[1], c[2], c[3], 1)
            self:SetSize(size * 0.62, size * 0.62)
        end
        self.flash:SetVertexColor(1, 1, 1, 0)
        self:SetAlpha(1)
        self:Show()
    end
    b:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local a = self.t / ARRIVE_EFFECT
        if a >= 1 then
            self:Hide()
            return
        end
        local size = self.size
        if self.kind == "ring" then
            local f = floor(a * BREAK_FRAMES)
            if f ~= self.frame then
                self.frame = f
                setCell(self.tex, f)
            end
        elseif self.kind == "beacon" then
            -- The light shoots up and fades.
            self:SetSize(size * 0.55 * (1 - a * 0.5), size * 3.2 * (1 + a * 0.8))
            self:SetAlpha(1 - a)
        else
            local s = size * 0.62 * (1 + a * 0.6)
            self:SetSize(s, s)
            self:SetAlpha(1 - a)
        end
        local k = sin(pi * min(1, a * 1.6))
        self.flash:SetSize(size * 1.2 * k + 1, size * 1.2 * k + 1)
        self.flash:SetVertexColor(1, 1, 1, k)
    end)
    return b
end

local makers = { ring = newRing, beacon = newBeacon, pin = newPin }

local function build()
    root = CreateFrame("Frame", "RXPEnhancedWaypoint", UIParent)
    root:SetFrameStrata("LOW")
    root:SetAllPoints(UIParent)
    root:EnableMouse(false)
    WP.markers = {}
    for key, make in pairs(makers) do
        local m = make(root)
        m:Hide()
        WP.markers[key] = m
    end
    burst = newBurst(root)
    WP.burst = burst
    -- Off screen: an arrow on an ellipse around the middle of the screen, pointing the way.
    edge = CreateFrame("Frame", nil, root)
    edge:SetSize(28, 28)
    edge.icon = edge:CreateTexture(nil, "ARTWORK")
    edge.icon:SetAllPoints()
    edge.icon:SetTexture(ICON_FILE)
    local i = 39 -- "navigation" in icons.tga (points up and to the right)
    local col, row = i % 8, floor(i / 8)
    edge.icon:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8)
    edge.text = edge:CreateFontString(nil, "OVERLAY")
    edge:Hide()
    WP.edge = edge
    label = root:CreateFontString(nil, "OVERLAY")
    WP.label = label
    plateAnchor = CreateFrame("Frame", nil, root)
    plateAnchor:SetSize(1, 1)
    WP.plateAnchor = plateAnchor
end

local function setFont(fs, size)
    if fs.rxnSize == size then return end -- only when it changes, not every frame
    local ok, success = pcall(fs.SetFont, fs, FONT, size, "")
    if ok and success ~= false then
        fs.rxnSize = size
    else
        fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.85)
end

local function hideMarkers()
    for _, m in pairs(WP.markers) do if m:IsShown() then m:Hide() end end
    if edge:IsShown() then edge:Hide() end
    if label:IsShown() then label:Hide() end
end

local function getNav()
    if navFrame then return navFrame end
    if C_Navigation and C_Navigation.GetFrame then navFrame = P.call(C_Navigation.GetFrame) end
    return navFrame
end

function WP.OnNavFrame(created, frame)
    navFrame = created and (frame or P.call(C_Navigation.GetFrame)) or nil
end

-- The step RestedXP's arrow is on, for the label.
local function targetLabel(el)
    local step = el.step
    local text = step and P.labelOf(step, 48) or ""
    return text
end

local function arriveRadius(el)
    return max(db.wpArrive or 10, tonumber(el and el.radius) or 0)
end

local function distanceTo(el)
    if HBD and el.wx and el.wy then
        local ok, d = pcall(function()
            local x, y, instance = HBD:GetPlayerWorldPosition()
            if not (x and y and instance == el.instance) then return nil end
            local _, dist = HBD:GetWorldVector(instance, x, y, el.wx, el.wy)
            return dist
        end)
        if ok and type(d) == "number" then return d end
    end
    if state.point and C_Navigation and C_Navigation.GetDistance then
        local d = P.call(C_Navigation.GetDistance)
        if type(d) == "number" and d > 0 then return d end
    end
end

-- Which way the spot is from the way you face (radians, 0 = straight ahead, turning left as it
-- grows), from RestedXP's world coordinates, the way RestedXP turns its own arrow.
local function bearingTo(el)
    if not (HBD and el.wx and el.wy) then return nil end
    local ok, angle = pcall(function()
        local x, y, instance = HBD:GetPlayerWorldPosition()
        if not (x and y and instance == el.instance) then return nil end
        return (HBD:GetWorldVector(instance, x, y, el.wx, el.wy))
    end)
    local facing = GetPlayerFacing and P.call(GetPlayerFacing)
    if ok and type(angle) == "number" and type(facing) == "number" then return angle - facing end
end

-- The off-screen arrow on an ellipse around the middle of the screen. angle: the way to point on
-- screen (radians from the right, counter-clockwise).
local function showEdge(angle, c, dtext)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if not (W and H and W > 0 and H > 0) then return false end
    for _, m in pairs(WP.markers) do if m:IsShown() then m:Hide() end end
    if label:IsShown() then label:Hide() end
    local rx, ry = W * 0.40, H * 0.36
    edge:ClearAllPoints()
    edge:SetPoint("CENTER", UIParent, "CENTER", cos(angle) * rx, sin(angle) * ry)
    edge.icon:SetRotation(angle - pi / 4) -- the icon points up and right
    edge.icon:SetVertexColor(c[1], c[2], c[3], 1)
    setFont(edge.text, 12)
    edge.text:SetTextColor(1, 1, 1, 1)
    edge.text:SetText(dtext or "")
    edge.text:ClearAllPoints()
    edge.text:SetPoint("TOP", edge, "BOTTOM", 0, -2)
    edge:SetAlpha(0.95)
    edge:Show()
    return true
end

local function navScreenPos(nav)
    local x, y = nav:GetCenter()
    if not (x and y) then return nil end
    local s = (nav:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return x * s, y * s
end

local function playArrival()
    local nav = getNav()
    local m = WP.markers[db.wpStyle]
    if nav and m and m:IsShown() then
        local x, y = navScreenPos(nav)
        if x then m:Arrive(x, y, m.lastSize or screenSize(state.lastDist)) end
    end
    arrivalSound()
    if NS.Toast and NS.Toast.Arrived then NS.Toast.Arrived(state.target) end
end
WP.PlayArrival = playArrival

-- ---------------------------------------------------------------- every frame

local t = 0

-- Something went wrong for a while: say so once, and where to look.
function WP.CheckHint()
    if WP.hinted then return end
    local problem
    if state.fail then
        state.failCount = (state.failCount or 0) + 1
        if state.failCount >= 5 then problem = state.fail end
    else
        state.failCount = 0
    end
    if not problem and state.noNavSince and t - state.noNavSince > 8 then
        problem = "the game isn't giving its position on screen"
        if optionGet(NAV_OPTION) == "0" then problem = problem .. " (its In-Game Navigation option is off)" end
    end
    if problem then
        WP.hinted = true
        print("|cffd1706bRXP Enhanced:|r the waypoint marker can't show: " .. problem .. ". Type /rxpe debug for details.")
    end
end

-- Once a second: put the waypoint back if it's gone (an earlier try failed, or something cleared
-- it), and take super-tracking back from RestedXP's quests. A map pin or quest you picked yourself
-- is left alone.
function WP.Ensure(el)
    if state.quest then
        if trackedQuest() ~= state.quest then P.call(C_SuperTrack.SetSuperTrackedQuestID, state.quest) end
    elseif not (state.point and isOurs()) then
        if setWaypoint(el) then WP.PopIn() end -- gone, or replaced by another pin: put it back
    elseif not P.call(C_SuperTrack.IsSuperTrackingUserWaypoint) then
        P.call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    WP.CheckHint()
end

function WP.Update(elapsed)
    if not root then return end
    t = t + (elapsed or 0)
    if not (ready() and db.wpEnabled) then
        if state.point then clearOurs() end
        state.target = nil
        hideMarkers()
        restoreBlizzard()
        if navOptionWas ~= nil then WP.UseNavigation(false) end
        return
    end
    local profile = rxp.settings and rxp.settings.profile
    local af = _G.RXPG_ARROW
    local el = af and af.element
    -- The same arrow targets Waypoint UI's RestedXP support followed (its GetLiveArrowElement): a
    -- spot with a zone and map coordinates (corpse and spirit healer points are left to the game),
    -- not reached or hidden, on an active step, whose line isn't done.
    if type(el) ~= "table" or type(el.zone) ~= "number" or type(el.x) ~= "number" or type(el.y) ~= "number"
        or el.skip or el.hidden
        or type(el.step) ~= "table" or not el.step.active
        or (type(el.parent) == "table" and (el.parent.completed or el.parent.skip) and not el.parent.textOnly)
        or (profile and profile.showEnabled == false) then
        el = nil
    end

    local quest = el and stepQuest(el) or nil
    if el ~= state.target or quest ~= state.quest then
        local old = state.target
        local newTarget = el ~= old
        -- Got there: RestedXP moved on while you stood at the old spot (not for hidden path points).
        if newTarget and old and not old.hidePin and not state.arrived and state.lastDist and state.lastDist <= arriveRadius(old) + 5 then
            playArrival()
        end
        if newTarget then state.arrived, state.lastDist = false, nil end
        state.target, state.quest = el, quest
        if el and quest then
            -- The game's quest navigation: on the turn-in NPC, or the objective's area.
            clearOurs()
            state.fail = nil
            if trackedQuest() ~= quest then P.call(C_SuperTrack.SetSuperTrackedQuestID, quest) end
            if newTarget then WP.PopIn() end
        elseif el then
            if setWaypoint(el) and newTarget then
                WP.PopIn()
                if db.wpSounds and db.wpNewSound then playKit(NEW_TICK) end
            end
        else
            clearOurs()
        end
    elseif el and state.reclaim then
        state.reclaim = false
        if state.quest then
            P.call(C_SuperTrack.SetSuperTrackedQuestID, state.quest)
        elseif isOurs() then
            P.call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        else
            setWaypoint(el)
        end
    end
    if el and t - (state.lastCheck or -10) >= 0.25 then -- Waypoint UI's polling rate
        state.lastCheck = t
        WP.Ensure(el)
    end

    local nav = getNav()
    local tracking = el and onGoal()
    if tracking and not nav then
        state.noNavSince = state.noNavSince or t
    else
        state.noNavSince = nil
    end
    -- The step's NPC in view: the marker stands on it, whatever the game is tracking.
    local plate, plateName = nil, nil
    if el then plate, plateName = npcPlate(el) end
    state.onNpc = plateName
    -- Someone else's waypoint or quest is up (for a moment, until ours is put back): theirs shows.
    if not el or (nav and not tracking and not plate) then
        hideMarkers()
        restoreBlizzard()
        if el then state.lastDist = distanceTo(el) end
        return
    end
    hideBlizzard()

    local d
    if tracking and nav and state.quest then d = P.call(C_Navigation.GetDistance) end -- to the quest's NPC or area
    if type(d) ~= "number" or d <= 0 then d = distanceTo(el) end
    state.lastDist = d
    if d and not state.arrived and d <= arriveRadius(el) and not el.hidePin then
        playArrival()
        state.arrived = true
    elseif state.arrived and d and d > arriveRadius(el) + REARM_EXTRA then
        state.arrived = false
        WP.PopIn()
    end
    if state.arrived then
        hideMarkers()
        return
    end

    local c = colour()
    local text = db.wpLabel and targetLabel(el) or nil
    local dtext = d and ("%d yd"):format(floor(d + 0.5)) or nil
    local navState = not plate and nav and C_Navigation.GetTargetState and P.call(C_Navigation.GetTargetState)
    local valid = plate or (nav and not (C_Navigation.HasValidScreenPosition and P.call(C_Navigation.HasValidScreenPosition) == false))
    state.edgeFrom = nil
    if not plate and (not valid or navState == 0 or navState == 3) then
        -- No place on screen from the game (no navigation point, or none it will draw): point the
        -- way from where you face instead, as RestedXP's own arrow does.
        local bearing = bearingTo(el)
        if bearing and showEdge(atan2(cos(bearing), -sin(bearing)), c, dtext) then
            state.edgeFrom = "facing"
        else
            hideMarkers()
        end
        return
    end
    local alpha = navState == 1 and 0.6 or 1 -- behind something

    if not plate then
        -- Off screen: the game holds its point at the screen's edge, so point the way from the
        -- middle. A point off the screen that isn't held there (or none at all) can't be trusted
        -- for a direction: then point the way from where you face.
        local clamped = P.call(C_Navigation.WasClampedToScreen)
        local x, y = navScreenPos(nav)
        local W, H = UIParent:GetWidth(), UIParent:GetHeight()
        local outside = not x or (W and H and (x < 0 or x > W or y < 0 or y > H))
        if clamped or outside then
            local bearing = bearingTo(el)
            if clamped and x and W and H then
                showEdge(atan2(y - H / 2, x - W / 2), c, dtext)
                state.edgeFrom = "navigation"
            elseif bearing and showEdge(atan2(cos(bearing), -sin(bearing)), c, dtext) then
                state.edgeFrom = "facing"
            else
                hideMarkers()
            end
            return
        end
    end
    if edge:IsShown() then edge:Hide() end

    -- On the NPC: a point just above its nameplate stands in for the navigation point.
    local anchor = nav
    if plate then
        plateAnchor:ClearAllPoints()
        plateAnchor:SetPoint("BOTTOM", plate, "TOP", 0, 4)
        anchor = plateAnchor
    end
    local m = WP.markers[db.wpStyle] or WP.markers.ring
    for key, other in pairs(WP.markers) do if other ~= m and other:IsShown() then other:Hide() end end
    local size = screenSize(d)
    if m.popStart then
        local x = (t - m.popStart) / 0.35
        if x >= 1 then m.popStart = nil else size = size * max(0.01, backOut(x)) end
    end
    m.lastSize = size
    m:Draw(size, t, elapsed or 0, anchor)
    m:SetAlpha(alpha)
    if not m:IsShown() then m:Show() end

    if db.wpLabel and (text or dtext) then
        setFont(label, 12)
        label:SetTextColor(1, 1, 1, alpha)
        label:SetText(text and dtext and (text .. "  ·  " .. dtext) or text or dtext)
        label:ClearAllPoints()
        label:SetPoint("TOP", anchor, "CENTER", 0, -8)
        label:Show()
    elseif label:IsShown() then
        label:Hide()
    end
end

function WP.PopIn()
    for _, m in pairs(WP.markers or {}) do m.popStart = t end
end

-- Settings changed.
function WP.Apply()
    if not root then return end
    if db and db.wpEnabled then WP.UseNavigation(true) end
    WP.Update(0)
end

-- ---------------------------------------------------------------- another waypoint addon

-- Returns the folder name and the name to show of a waypoint addon that draws its own marker.
local OTHERS = { { "WaypointUI", "Waypoint UI" } }
function WP.OtherWaypointAddon()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return nil end
    for _, other in ipairs(OTHERS) do
        if P.call(C_AddOns.IsAddOnLoaded, other[1]) then return other[1], other[2] end
    end
end

function WP.DisableOther()
    local name = WP.OtherWaypointAddon()
    if name and C_AddOns.DisableAddOn then
        P.call(C_AddOns.DisableAddOn, name)
        WP.otherDisabled = true
    end
end

function WP.Init()
    if not ready() then return end
    if not root then build() end
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(_, elapsed) WP.Update(elapsed) end)
    f:RegisterEvent("SUPER_TRACKING_CHANGED")
    f:RegisterEvent("NAVIGATION_FRAME_CREATED")
    f:RegisterEvent("NAVIGATION_FRAME_DESTROYED")
    f:RegisterEvent("PLAYER_LOGOUT")
    pcall(f.RegisterEvent, f, "ADDONS_UNLOADING") -- logout and /reload
    f:SetScript("OnEvent", function(_, event, a)
        if event == "SUPER_TRACKING_CHANGED" then
            WP.OnSuperTrackingChanged()
        elseif event == "NAVIGATION_FRAME_CREATED" then
            WP.OnNavFrame(true, a)
        elseif event == "NAVIGATION_FRAME_DESTROYED" then
            WP.OnNavFrame(false)
        elseif event == "PLAYER_LOGOUT" then
            clearOurs() -- don't leave a stale waypoint on the map for next time
            WP.UseNavigation(false)
        elseif event == "ADDONS_UNLOADING" then
            WP.UseNavigation(false) -- the game saves its options as it closes: leave this one as it was
        end
    end)
    WP.driver = f
    if db.wpEnabled then WP.UseNavigation(true) end
    local _, other = WP.OtherWaypointAddon()
    if db.wpEnabled and other then
        print(("|cffd1706bRXP Enhanced:|r %s is running too, so you'll see two markers. Turn it off in /rxpe → Waypoint."):format(other))
    end
end

-- /rxpe debug: each link in the chain from RestedXP's arrow to the marker on screen.
function WP.Debug(out)
    out = out or print
    if not ready() then
        out("waypoint: RestedXP or the settings aren't loaded")
        return
    end
    if not root then
        out("waypoint: not started (the game needs a full restart after installing a new version)")
        return
    end
    local function yes(v) return v and "yes" or "no" end
    out(("waypoint: on %s, marker %s, size %.2f, label %s"):format(yes(db.wpEnabled), tostring(db.wpStyle),
        db.wpScale or 1, yes(db.wpLabel)))
    local af = _G.RXPG_ARROW
    local el = af and af.element
    if type(el) ~= "table" then
        out("  RestedXP's arrow: no target")
    else
        local step = el.step
        out(("  RestedXP's arrow: step %s, zone %s, x %s, y %s, world %s/%s (continent %s)"):format(
            tostring(step and step.index), tostring(el.zone), tostring(el.x), tostring(el.y),
            el.wx and floor(el.wx) or "-", el.wy and floor(el.wy) or "-", tostring(el.instance)))
        local why = {}
        if not (el.wx or el.zone) then why[#why + 1] = "no position" end
        if rxp.hideArrow then why[#why + 1] = "RestedXP hid its arrow" end
        if el.skip then why[#why + 1] = "already reached" end
        if el.hidden then why[#why + 1] = "hidden" end
        if step and not step.active then why[#why + 1] = "its step isn't active" end
        if type(el.parent) == "table" and (el.parent.completed or el.parent.skip) then why[#why + 1] = "its line is done" end
        local profile = rxp.settings and rxp.settings.profile
        if profile and profile.showEnabled == false then why[#why + 1] = "RestedXP's guide is hidden" end
        out("  followed: " .. (#why == 0 and "yes" or ("no (" .. table.concat(why, ", ") .. ")")))
        local cands = {}
        for _, c in ipairs(mapPointsOf(el)) do cands[#cands + 1] = ("%d (%.3f, %.3f)"):format(c[1], c[2], c[3]) end
        out("  maps that take it: " .. (#cands > 0 and table.concat(cands, ", ") or "none"))
    end
    out("  pointing at: " .. (state.onNpc and ("the NPC " .. state.onNpc .. " (its nameplate)")
        or state.quest and ("quest " .. state.quest .. " through the game's quest navigation")
        or "RestedXP's coordinates"))
    local p = state.point
    out(("  our waypoint: %s%s"):format(p and ("map " .. p.mapID .. (" (%.3f, %.3f)"):format(p.x, p.y)) or "none",
        state.fail and ("; last try: " .. state.fail) or ""))
    local w = P.call(C_Map.GetUserWaypoint)
    local wx, wy
    if w and w.position then
        wx, wy = w.position.x, w.position.y
        if type(w.position.GetXY) == "function" then wx, wy = w.position:GetXY() end
    end
    out(("  game's waypoint: %s, ours %s"):format(w and ("map " .. tostring(w.uiMapID) .. (" (%.3f, %.3f)"):format(wx or -1, wy or -1)) or "none", yes(isOurs())))
    local q = P.call(C_SuperTrack.GetSuperTrackedQuestID)
    out(("  super-tracking: waypoint %s, anything %s, quest %s"):format(yes(P.call(C_SuperTrack.IsSuperTrackingUserWaypoint)),
        yes(P.call(C_SuperTrack.IsSuperTrackingAnything)), tostring(q)))
    out(("  the game's In-Game Navigation option: %s%s"):format(tostring(optionGet(NAV_OPTION)),
        navOptionWas ~= nil and " (turned on by RXP Enhanced for this session)" or ""))
    local nav = getNav()
    local x, y
    if nav then x, y = nav:GetCenter() end
    out(("  navigation frame: %s%s, state %s, on screen %s, at edge %s, %s yd"):format(yes(nav),
        x and (" at %d,%d"):format(x, y) or "", tostring(C_Navigation and P.call(C_Navigation.GetTargetState)),
        tostring(C_Navigation and P.call(C_Navigation.HasValidScreenPosition)), tostring(C_Navigation and P.call(C_Navigation.WasClampedToScreen)),
        tostring(C_Navigation and P.call(C_Navigation.GetDistance) and floor(P.call(C_Navigation.GetDistance)))))
    local shown = {}
    for key, m in pairs(WP.markers or {}) do if m:IsShown() then shown[#shown + 1] = key end end
    if edge and edge:IsShown() then shown[#shown + 1] = "edge arrow (from " .. tostring(state.edgeFrom) .. ")" end
    out(("  drawn: %s; Blizzard's diamond hidden by us: %s"):format(#shown > 0 and table.concat(shown, ", ") or "nothing", yes(hidingBlizzard)))
    local others = {}
    for _, name in ipairs({ "WaypointUI", "TomTom" }) do
        if C_AddOns and P.call(C_AddOns.IsAddOnLoaded, name) then others[#others + 1] = name end
    end
    if #others > 0 then out("  other waypoint addons running: " .. table.concat(others, ", ")) end
end

WP.state = state -- for the tests

-- Offline checks for RXP Enhanced's waypoint marker, the second-arrow switch on the Waypoint tab,
-- and docking the along-the-way card. lua5.1 test_waypoint.lua
local M = dofile("mock.lua")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "") .. "\n") end
end

-- ---------------------------------------------------------------- the game's navigation, mocked
UIParent.w, UIParent.h = 1366, 768
function hooksecurefunc(obj, method, fn)
    local orig = obj[method]
    obj[method] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end
local nav = M.newObject("Frame", "NavFrame", UIParent)
nav.cx, nav.cy = 683, 300
function nav:GetCenter() return self.cx, self.cy end
local navState = { clamped = false, state = 2, valid = true, distance = 50 }
-- Forever: the game's In-Game Navigation option starts off, and there's no navigation point
-- without it.
local cvars = { showInGameNavigation = "0" }
local cvarSets = 0
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value; cvarSets = cvarSets + 1; return true end,
}
C_Navigation = {
    GetFrame = function() return cvars.showInGameNavigation == "1" and nav or nil end,
    WasClampedToScreen = function() return navState.clamped end,
    GetTargetState = function() return navState.state end,
    HasValidScreenPosition = function() return navState.valid end,
    GetDistance = function() return navState.distance end,
}
local userWP, superTrack = nil, { userWaypoint = false, quest = 0 }
local mapCalls = { set = 0, clear = 0 }
local noWaypointMaps = {}
C_Map = {
    SetUserWaypoint = function(point) userWP = { uiMapID = point.uiMapID, position = { x = point.position.x, y = point.position.y } }; mapCalls.set = mapCalls.set + 1 end,
    GetUserWaypoint = function() return userWP end,
    HasUserWaypoint = function() return userWP ~= nil end,
    ClearUserWaypoint = function() userWP = nil; mapCalls.clear = mapCalls.clear + 1 end,
    CanSetUserWaypointOnMap = function(id) return not noWaypointMaps[id] end,
    GetUserWaypointPositionForMap = function(id) return userWP and userWP.uiMapID == id and { x = userWP.position.x, y = userWP.position.y } or nil end,
    GetMapInfo = function(id) return { mapID = id, parentMapID = 1415 } end,
    GetBestMapForUnit = function() return 1420 end,
}
C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(on) superTrack.userWaypoint = on; if on then superTrack.quest = 0 end end,
    IsSuperTrackingUserWaypoint = function() return superTrack.userWaypoint end,
    GetSuperTrackedQuestID = function() return superTrack.quest end,
    SetSuperTrackedQuestID = function(q) superTrack.quest = q; superTrack.userWaypoint = false end,
    IsSuperTrackingAnything = function() return superTrack.userWaypoint or superTrack.quest > 0 end,
}
function CreateVector2D(x, y) return { x = x, y = y } end
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = CreateVector2D(x, y) } end }
SuperTrackedFrame = M.newObject("Frame", "SuperTrackedFrame", UIParent)
SuperTrackedFrame.navFrame = nav
SuperTrackedFrame.shown = true
local addons = { WaypointUI = true }
local disabled = {}
C_AddOns = {
    IsAddOnLoaded = function(name) return addons[name] or false end,
    DisableAddOn = function(name) disabled[name] = true end,
}
local reloads = 0
function ReloadUI() reloads = reloads + 1 end
local sounds, files = {}, {}
function PlaySound(id) sounds[#sounds + 1] = id end
local fileWorks = true
function PlaySoundFile(path) files[#files + 1] = path; return fileWorks end
local zoom = 12
function GetCameraZoom() return zoom end
M.HBD.GetZoneCoordinatesFromWorld = function(_, wx, wy, mapID) return 0.5, 0.5 end

-- ---------------------------------------------------------------- a guide
local RXP, Q = M.RXP, M.quests
local goto, text, accept, turnin, complete, step = M.goto, M.text, M.accept, M.turnin, M.complete, M.step
Q.names = { [363] = "Rude Awakening", [364] = "The Mindless Ones" }
local g1 = goto(100, 0, { zone = 1420, x = 30.84, y = 66.20 })
local g2 = goto(0, 100, { zone = 1420, x = 33.00, y = 61.00, radius = 25 })
local path = goto(50, 50, { zone = 1420, x = 31.5, y = 64.0, hidePin = true, radius = 20 })
M.setGuide({
    step({ g1, text("Talk to |cRXP_FRIENDLY_Shadow Priest Sarvis|r"), turnin(363, "Turn in Rude Awakening") }),
    step({ path, g2, text("Kill |cRXP_ENEMY_Mindless Zombies|r"), complete(364, 1, "Mindless Zombie slain: 0/8") }),
    step({ goto(10, 10, { zone = 1420, x = 40, y = 40 }), text("Run on") }),
})
RXP.hideArrow = false
RXPG_ARROW.element = g1

assert(loadfile("../RXPEnhanced/RXPEnhanced.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Card.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Waypoint.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Toast.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Log.lua"))("RXPEnhanced")
local NS, WP = RXPEnhanced, RXPEnhanced.Waypoint
local driver
for _, f in ipairs(M.frames) do if f.events.PLAYER_LOGIN then driver = f end end
M.printed = {}
-- Settings saved by 1.4, still on its defaults (the gold ring, the along card below).
-- The checks below were written against the defaults before 1.6.1 (and a 1.4 user's ring and dock).
RXPEnhancedDB = { wpStyle = "ring", alongDock = "bottom", wpSound = "glass", wpNewSound = false, wpScale = 1,
    wpColor = { 0xf2 / 255, 0xc7 / 255, 0x5c / 255 }, color = { 0xd1 / 255, 0x70 / 255, 0x6b / 255 }, scale = 0.85,
    nextCount = 4, cardTextSize = 13, cardWidth = 300, cardTheme = "dark" }
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
local db = RXPEnhancedDB
local function frame(dt)
    M.now = M.now + (dt or 0.05)
    WP.driver.scripts.OnUpdate(WP.driver, dt or 0.05)
    if WP.burst.shown then WP.burst.scripts.OnUpdate(WP.burst, dt or 0.05) end
end
-- RestedXP's arrow always points into an active step.
local function aim(el)
    if el.step and not el.step.active then RXP.SetStep(el.step.index) end
    RXPG_ARROW.element = el
end
local function event(e, ...) WP.driver.scripts.OnEvent(WP.driver, e, ...) end

check("login: says Waypoint UI is running too", (function() for _, l in ipairs(M.printed) do if l:find("Waypoint UI is running too") then return true end end end)())
check("1.5 defaults: the pin, and the along card on the right, also for settings left on 1.4's defaults", db.wpStyle == "pin" and db.alongDock == "right" and db.defaults15)
check("defaults: marker on, sounds on with the glass shimmer", db.wpEnabled and db.wpSounds and db.wpSound == "glass" and db.arrow)
check("login: the game's In-Game Navigation option turned on (it's off on Forever)", cvars.showInGameNavigation == "1" and WP.NavigationTurnedOn())
db.wpStyle = "ring" -- the checks below start with the ring

-- ---------------------------------------------------------------- setting the waypoint
M.player.x, M.player.y = 0, 0
frame()
check("waypoint set where RestedXP's arrow points", userWP and userWP.uiMapID == 1420 and math.abs(userWP.position.x - 0.3084) < 1e-6 and math.abs(userWP.position.y - 0.662) < 1e-6)
check("and super-tracked", superTrack.userWaypoint == true)
check("ours", WP.IsOurs())
frame()
local ring = WP.markers.ring
check("gold ring shown on the spot", ring.shown and ring.points[1] and ring.points[1][2] == nav and ring.points[1][3] == "CENTER")
check("Blizzard's diamond hidden", not SuperTrackedFrame.shown and WP.IsHidingBlizzard())
check("label: step and distance", WP.label.shown and WP.label.text == "Talk to Shadow Priest Sarvis  ·  100 yd", WP.label.text)
local far = ring.w
M.player.x = 60
frame()
check("bigger as you get closer", ring.w > far, ring.w)
check("ring frame picked from the sheet", ring.tex.coords ~= nil)
zoom = 30
frame()
local zoomed = ring.w
zoom = 12
frame()
check("camera zoom shrinks it like a world object", zoomed < ring.w)
SuperTrackedFrame:Show()
check("Blizzard's diamond stays hidden when the game shows it", not SuperTrackedFrame.shown)

-- ---------------------------------------------------------------- arriving
sounds, files = {}, {}
local toasted = {}
local realArrived = RXPEnhanced.Toast.Arrived
RXPEnhanced.Toast.Arrived = function(el) toasted[#toasted + 1] = el; return realArrived(el) end
M.player.x = 95
frame()
RXPEnhanced.Toast.Arrived = realArrived
check("arrive: the toast hears about it", #toasted == 1 and toasted[1] == WP.state.target, #toasted)
check("arrive: break effect where the spot is", WP.burst.shown and WP.burst.kind == "ring" and WP.burst.tex.texture:find("RingBreak"))
check("arrive: glass shimmer plays", #files == 1 and files[1]:find("RingBreak.ogg"), files[1])
check("arrive: marker gone", not ring.shown and WP.state.arrived)
frame(0.6)
check("break effect finishes", not WP.burst.shown)
frame()
check("no repeat while you stand there", #files == 1)
M.player.x = 60
frame()
check("walk away and it comes back", ring.shown and not WP.state.arrived)

db.wpSound = "azerite"
M.player.x = 95
frame()
check("other sounds: Azerite shimmer", sounds[#sounds] == 114992)
M.player.x = 50
frame()
fileWorks = false
db.wpSound = "glass"
sounds = {}
M.player.x = 95
frame()
check("glass shimmer can't play: falls back to the Azerite shimmer", sounds[#sounds] == 114992)
fileWorks = true
M.player.x = 50
frame()
db.wpSounds = false
sounds, files = {}, {}
M.player.x = 95
frame()
check("sounds off: silent", #sounds == 0 and #files == 0)
db.wpSounds = true
M.player.x = 50
frame()

-- ---------------------------------------------------------------- RestedXP moves on
db.wpNewSound = true
sounds = {}
M.player.x = 92
RXP.SetStep(2)
RXPG_ARROW.element = path
frame()
check("next spot: waypoint moves", math.abs(userWP.position.x - 0.315) < 1e-6)
check("RestedXP moved on while you stood at the old spot: arrival plays", WP.burst.shown or (function() for _, s in ipairs(sounds) do if s == 114992 then return true end end end)() or #files > 0)
check("new waypoint tick", (function() for _, s in ipairs(sounds) do if s == 170269 then return true end end end)())
db.wpNewSound = false
files = {}
M.player.x, M.player.y = 50, 50
frame()
RXPG_ARROW.element = g2
frame()
check("hidden path points don't play an arrival", #files == 0)
check("then on to the step's spot", math.abs(userWP.position.x - 0.33) < 1e-6)

-- ---------------------------------------------------------------- on screen and off
M.player.x, M.player.y = 0, 0
frame()
navState.clamped = true
nav.cx, nav.cy = 1300, 700
frame()
check("off screen: arrow at the edge, marker hidden", WP.edge.shown and not ring.shown and not WP.label.shown)
check("off screen: shows the distance", WP.edge.text.text == "100 yd", WP.edge.text.text)
check("off screen: points toward it", WP.edge.icon.rotation ~= 0)
check("off screen: the way from the game's point at the edge", WP.state.edgeFrom == "navigation")
navState.clamped = false
nav.cx, nav.cy = 683, 300
navState.state = 1
frame()
check("behind something: dimmed", ring.shown and ring.alpha == 0.6)
navState.state = 0
frame()
check("nowhere to show it: hidden", not ring.shown)
-- No usable place on screen from the game: the edge arrow points the way from where you face,
-- like RestedXP's own arrow.
local spot = WP.state.target
local facingWas = M.facing
local ahead = LibStub("HereBeDragons-2.0"):GetWorldVector(0, M.player.x, M.player.y, spot.wx, spot.wy)
M.facing = ahead
frame()
check("the game gives no place for it: edge arrow from your facing", WP.edge.shown and WP.state.edgeFrom == "facing" and not ring.shown, WP.state.edgeFrom)
check("straight ahead: at the top of the screen", math.abs(WP.edge.points[1][4]) < 1e-6 and WP.edge.points[1][5] > 0)
check("with the distance", WP.edge.text.text == "100 yd", WP.edge.text.text)
M.facing = ahead + math.pi
frame()
check("behind you: at the bottom", math.abs(WP.edge.points[1][4]) < 1e-6 and WP.edge.points[1][5] < 0)
M.facing = ahead - math.pi / 2
frame()
check("to your left: on the left", WP.edge.points[1][4] < 0)
navState.state = 2
navState.valid = false
frame()
check("no screen position: from your facing too", WP.edge.shown and WP.state.edgeFrom == "facing")
navState.valid = true
nav.cx, nav.cy = -400, 300
frame()
check("a point off the screen that isn't held at its edge: from your facing", WP.edge.shown and WP.state.edgeFrom == "facing")
nav.cx, nav.cy = 683, 300
cvars.showInGameNavigation = "0"
WP.OnNavFrame(false)
frame()
check("no navigation point at all: the edge arrow still points the way", WP.edge.shown and WP.state.edgeFrom == "facing")
cvars.showInGameNavigation = "1"
WP.OnNavFrame(true, nav)
M.facing = facingWas
frame()
check("back on screen: the marker again", ring.shown and not WP.edge.shown)

-- ---------------------------------------------------------------- styles
db.wpStyle = "beacon"
frame()
check("beacon", WP.markers.beacon.shown and not ring.shown and WP.markers.beacon.beam.color[1] > 0.9)
db.wpColor = { 0.2, 0.6, 1 }
frame()
check("beacon in the marker colour", math.abs(WP.markers.beacon.beam.color[3] - 1) < 1e-6)
db.wpStyle = "pin"
frame()
check("pin", WP.markers.pin.shown and not WP.markers.beacon.shown)
M.player.x, M.player.y = 0, 95
frame()
check("pin arrival pops the pin", WP.burst.shown and WP.burst.kind == "pin")
M.player.x, M.player.y = 0, 0
frame(0.6)
M.printed = {}
SlashCmdList.RXPENHANCED("marker blizzard")
check("Blizzard's own diamond is no longer a choice", db.wpStyle == "pin" and table.concat(M.printed, " "):find("marker takes pin, ring or beacon"))
db.wpStyle = "ring"
frame()

-- ---------------------------------------------------------------- RestedXP or you super-tracking a quest
C_SuperTrack.SetSuperTrackedQuestID(364)
event("SUPER_TRACKING_CHANGED")
frame()
check("RestedXP tracking one of its quests: taken back", superTrack.userWaypoint == true and ring.shown)
C_SuperTrack.SetSuperTrackedQuestID(9999)
event("SUPER_TRACKING_CHANGED")
frame()
check("a quest you picked: RestedXP's arrow wins, as with Waypoint UI", superTrack.userWaypoint == true and superTrack.quest == 0 and ring.shown)
aim(g1)
frame()
check("RestedXP's next spot: tracked again", superTrack.userWaypoint and WP.IsOurs())
frame()

-- Something else replaces the waypoint.
userWP = { uiMapID = 1420, position = { x = 0.9, y = 0.9 } }
frame(0.3)
check("someone else's waypoint: RestedXP's arrow takes it back within a quarter second", WP.IsOurs() and superTrack.userWaypoint)
aim(g2)
frame()
check("the guide's next spot replaces it", WP.IsOurs())

-- Nowhere to go: RestedXP's arrow target belongs to a step that's no longer active.
g2.step.active = false
local clears = mapCalls.clear
frame()
check("RestedXP's arrow has nowhere to go: our waypoint cleared", mapCalls.clear == clears + 1 and userWP == nil and not ring.shown)
g2.step.active = true
frame()
check("and back", WP.IsOurs())

-- A map that doesn't take waypoints.
noWaypointMaps[1458] = true
local city = goto(5, 5, { zone = 1458, x = 50, y = 50 })
city.step = g2.step
RXPG_ARROW.element = city
frame()
check("city map: the waypoint goes on the map you're on instead", userWP and userWP.uiMapID == 1420, userWP and userWP.uiMapID)
noWaypointMaps[1420] = true
local city2 = goto(6, 6, { zone = 1458, x = 51, y = 51 })
city2.step = g2.step
RXPG_ARROW.element = city2
frame()
check("and if that map won't take it either, the map above", userWP and userWP.uiMapID == 1415, userWP and userWP.uiMapID)
noWaypointMaps[1420] = nil
aim(g1)
frame()

-- ---------------------------------------------------------------- settings
NS.OpenSettings()
local wp = RXPEnhancedSettings.panel
check("settings window fits on a 768-high screen", RXPEnhancedSettings.h < 740, RXPEnhancedSettings.h)
io.stdout:write("settings window height " .. tostring(RXPEnhancedSettings.h) .. "\n")
-- lua5.1 test_waypoint.lua <dir>: also writes the settings window in both looks with today's
-- defaults, for tools/render_card.py.
if arg and arg[1] then
    local saved = {}
    for k, v in pairs(db) do saved[k] = v end
    RXPEnhancedSettings.panel.resetAll:Click()
    for _, look in ipairs({ "glass", "dark" }) do
        db.cardTheme = look
        RXPEnhanced.SettingsChanged()
        for _, tabName in ipairs({ "arrow", "waypoint", "card", "general" }) do
            RXPEnhanced.OpenSettings(tabName)
            local win = RXPEnhancedSettings
            local fh = assert(io.open(arg[1] .. "/settings_" .. look .. "_" .. tabName .. ".json", "w"))
            fh:write(M.json({ w = win.w, h = win.h, ops = M.dump(win, 0, 0) }))
            fh:close()
        end
    end
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(saved) do db[k] = v end
    RXPEnhanced.SettingsChanged()
end
wp.tabs[2]:Click()
check("Waypoint tab", wp.sections.waypoint.shown and not wp.sections.arrow.shown)
local function radio(key, value) for _, r in ipairs(wp.radios) do if r.key == key and r.value == value then return r end end end
check("three marker choices", radio("wpStyle", "ring") and radio("wpStyle", "beacon") and radio("wpStyle", "pin") and not radio("wpStyle", "blizzard"))
check("five sounds", radio("wpSound", "glass") and radio("wpSound", "azerite") and radio("wpSound", "crystal") and radio("wpSound", "chime") and radio("wpSound", "ping"))
radio("wpStyle", "beacon"):Click()
check("pick beacon", db.wpStyle == "beacon" and radio("wpStyle", "beacon").checked and not radio("wpStyle", "ring").checked)
sounds = {}
radio("wpSound", "chime"):Click()
check("picking a sound plays it", db.wpSound == "chime" and sounds[#sounds] == 170270)
-- The second arrow is a switch here too, in step with the Arrow & pins tab.
local arrowHere
for _, cb in ipairs(wp.extraChecks) do if cb.key == "arrow" then arrowHere = cb end end
check("second-arrow switch on the Waypoint tab, on by default", arrowHere and arrowHere.checked)
arrowHere.checked = false; arrowHere:Click()
check("off from the Waypoint tab: arrow off, Arrow & pins tab follows", db.arrow == false and wp.checks.arrow.checked == false)
arrowHere.checked = true; arrowHere:Click()
check("on again", db.arrow == true and wp.checks.arrow.checked)
-- Sounds greyed out when off
wp.checks.wpSounds.checked = false; wp.checks.wpSounds:Click()
check("sounds off: sound choices grey out", radio("wpSound", "glass").enabled == false and wp.checks.wpNewSound.enabled == false)
wp.checks.wpSounds.checked = true; wp.checks.wpSounds:Click()
-- Waypoint UI
check("Waypoint UI offer shown", wp.otherButton.shown and wp.otherButton.text == "Turn off Waypoint UI")
wp.otherButton:Click()
check("turns it off for the next reload", disabled.WaypointUI and wp.otherButton.text == "Reload now")
wp.otherButton:Click()
check("then reloads", reloads == 1)
-- Marker off
wp.checks.wpEnabled.checked = false; wp.checks.wpEnabled:Click()
frame()
check("marker off: waypoint cleared, nothing drawn, Blizzard's diamond back", userWP == nil and not WP.markers.beacon.shown and not WP.IsHidingBlizzard())
check("marker off: its options grey out", radio("wpStyle", "ring").enabled == false and wp.checks.wpLabel.enabled == false)
wp.checks.wpEnabled.checked = true; wp.checks.wpEnabled:Click()
frame()
check("marker on again", WP.IsOurs() and WP.markers.beacon.shown)
wp.checks.wpLabel.checked = false; wp.checks.wpLabel:Click()
frame()
check("label off", not WP.label.shown)
wp.checks.wpLabel.checked = true; wp.checks.wpLabel:Click()

-- Slash commands
SlashCmdList.RXPENHANCED("marker ring")
check("/rxpe marker ring", db.wpStyle == "ring")
SlashCmdList.RXPENHANCED("marker nope")
check("/rxpe marker refuses unknown styles", db.wpStyle == "ring")
SlashCmdList.RXPENHANCED("sound off")
check("/rxpe sound off", db.wpSounds == false)
SlashCmdList.RXPENHANCED("sound on")
SlashCmdList.RXPENHANCED("sound crystal")
check("/rxpe sound crystal", db.wpSound == "crystal" and sounds[#sounds] == 74431)
SlashCmdList.RXPENHANCED("waypoint")
check("/rxpe waypoint toggles", db.wpEnabled == false)
SlashCmdList.RXPENHANCED("waypoint")

-- ---------------------------------------------------------------- keeping the waypoint in place
aim(g1)
frame()
check("set before the checks below", WP.IsOurs() and superTrack.userWaypoint)
userWP = nil -- something cleared the game's waypoint
frame(1.1)
check("cleared by something else: put back within a second", WP.IsOurs() and superTrack.userWaypoint)
superTrack.quest, superTrack.userWaypoint = 363, false -- RestedXP super-tracked its quest, no event seen
frame(1.1)
check("RestedXP's quest took the beam: taken back on the next check", superTrack.userWaypoint == true and superTrack.quest == 0)
superTrack.quest, superTrack.userWaypoint = 9999, false -- a quest you picked
frame(1.1)
check("your own quest: RestedXP's arrow wins (Waypoint UI's auto replace)", superTrack.userWaypoint == true and superTrack.quest == 0)
superTrack.quest = 0
frame(1.1)
check("nothing tracked at all: our waypoint tracked again", superTrack.userWaypoint == true)

-- A spot with only world coordinates (RestedXP's corpse point) is left to the game, as Waypoint UI did.
local corpse = { wx = 7, wy = 7, instance = 0, step = g1.step }
RXPG_ARROW.element = corpse
frame()
check("world-only spot (corpse): not followed", WP.state.target == nil and not WP.IsOurs())
-- RestedXP keeps an arrow target it has already reached or hidden: not followed.
g1.skip = true
aim(g1)
frame()
check("a reached spot isn't followed", userWP == nil or not WP.IsOurs() or WP.state.target ~= g1)
g1.skip = nil
aim(g1)
frame()

-- The game won't take a waypoint anywhere: say so once, after a few tries.
local realSet = C_Map.SetUserWaypoint
C_Map.SetUserWaypoint = function() return false end
userWP = nil
M.printed = {}
aim(g2)
for _ = 1, 8 do frame(1.1) end
local hints = 0
for _, l in ipairs(M.printed) do if l:find("waypoint marker can't show") then hints = hints + 1 end end
check("waypoint refused: one hint pointing at /rxpe debug", hints == 1 and WP.state.fail ~= nil, hints)
C_Map.SetUserWaypoint = realSet
frame(1.1)
check("and it's placed once the game takes it", WP.IsOurs())

-- /rxpe debug walks the chain.
M.printed = {}
SlashCmdList.RXPENHANCED("debug")
local dbg = table.concat(M.printed, "\n")
check("debug: RestedXP's arrow, maps, our waypoint, super-tracking, navigation frame", dbg:find("RestedXP's arrow: step") and dbg:find("maps that take it: 1420")
    and dbg:find("our waypoint: map 1420") and dbg:find("super%-tracking: waypoint yes") and dbg:find("navigation frame: yes"), dbg)
check("debug: says which files loaded", dbg:find("files loaded: card") ~= nil)

-- The label's font is set once, not every frame.
local sets = 0
local realSetFont = WP.label.SetFont
WP.label.SetFont = function(self, ...) sets = sets + 1 return realSetFont(self, ...) end
for _ = 1, 5 do frame() end
check("label font not reset every frame", sets == 0, sets)
WP.label.SetFont = realSetFont

-- ---------------------------------------------------------------- the navigation option
SlashCmdList.RXPENHANCED("waypoint")
check("marker off: the navigation option back as it was", db.wpEnabled == false and cvars.showInGameNavigation == "0" and not WP.NavigationTurnedOn())
SlashCmdList.RXPENHANCED("waypoint")
frame()
check("marker on again: the option on again", db.wpEnabled and cvars.showInGameNavigation == "1")
M.printed = {}
SlashCmdList.RXPENHANCED("debug")
check("debug shows the option", table.concat(M.printed, "\n"):find("In%-Game Navigation option: 1 %(turned on by RXP Enhanced"))
event("ADDONS_UNLOADING")
check("logout or reload: the option put back", cvars.showInGameNavigation == "0" and not WP.NavigationTurnedOn())
WP.Apply()
check("and on again when the addon loads", cvars.showInGameNavigation == "1")
-- Someone who has the option on already: never touched.
WP.UseNavigation(false)
cvars.showInGameNavigation = "1"
local sets = cvarSets
WP.Apply()
event("ADDONS_UNLOADING")
check("already on: left alone, also at logout", cvars.showInGameNavigation == "1" and cvarSets == sets)
frame()

-- ---------------------------------------------------------------- on the NPC itself
local plateFrame = M.newObject("Frame", "NamePlate1", UIParent)
function plateFrame:IsVisible() return self.shown end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function(unit) return unit == "nameplate1" and plateFrame or nil end }
table.insert(g1.step.elements, { tag = "target", targets = { "Shadow Priest Sarvis" }, textOnly = true, step = g1.step })
db.wpStyle = "pin"
aim(g1)
frame()
local pin = WP.markers.pin
check("NPC not in view: the marker stands on RestedXP's spot", pin.shown and pin.points[1][2] == nav)
NS.Card.Nearby.plates.nameplate1 = "Shadow Priest Sarvis"
frame()
check("the step's NPC in view: the marker stands on the NPC", pin.shown and pin.points[1][2] == WP.plateAnchor
    and WP.plateAnchor.points[1][2] == plateFrame and WP.plateAnchor.points[1][3] == "TOP")
check("its label goes with it", WP.label.points[1][2] == WP.plateAnchor)
M.printed = {}
SlashCmdList.RXPENHANCED("debug")
check("debug: pointing at the NPC", table.concat(M.printed, "\n"):find("pointing at: the NPC Shadow Priest Sarvis"))
navState.clamped = true
frame()
check("on the NPC, the edge arrow isn't used", pin.shown and not WP.edge.shown)
navState.clamped = false
db.wpOnNpc = false
frame()
check("setting off: back on RestedXP's spot", pin.points[1][2] == nav)
db.wpOnNpc = true
NS.Card.Nearby.plates.nameplate1 = nil
frame()
check("NPC out of view: back on RestedXP's spot", pin.points[1][2] == nav)

-- ---------------------------------------------------------------- quest navigation (optional)
check("quest navigation off by default, like Waypoint UI", db.wpQuest == false and WP.state.quest == nil)
Q.on[363], Q.complete[363] = true, true
db.wpQuest = true
frame()
check("on: a ready turn-in uses the game's quest navigation", WP.state.quest == 363 and superTrack.quest == 363 and userWP == nil)
frame()
check("drawn on the game's point for it, with its distance", pin.shown and WP.label.text:find("50 yd"), WP.label.text)
C_SuperTrack.SetSuperTrackedQuestID(9999)
event("SUPER_TRACKING_CHANGED")
frame()
check("taken back from another quest", superTrack.quest == 363)
db.wpQuest = false
frame()
check("off again: RestedXP's coordinates", WP.state.quest == nil and WP.IsOurs())
Q.on[363], Q.complete[363] = nil, nil
db.wpStyle = "ring"
frame()

-- Logout leaves no stale waypoint.
frame()
event("PLAYER_LOGOUT")
check("logout clears our waypoint", userWP == nil)

-- ---------------------------------------------------------------- docking the along-the-way card
local Card = NS.Card
local card, along = RXPEnhancedCard, RXPEnhancedAlongCard
local sticky = step({ M.check("|cRXP_WARN_Not Well Fed?|r") }, { sticky = true })
table.insert(RXP.currentGuide.steps, 1, sticky)
for i, s in ipairs(RXP.currentGuide.steps) do s.index = i end
RXP.SetStep(3)
M.now = M.now + 10
Card.Update()
check("along card shown, on the right by default", along.shown and along.points[1][2] == card and along.points[1][1] == "TOPLEFT" and along.points[1][3] == "TOPRIGHT")
wp.tabs[3]:Click()
radio("alongDock", "top"):Click()
check("above", along.points[1][1] == "BOTTOMLEFT" and along.points[1][3] == "TOPLEFT" and along.points[1][5] == 8)
radio("alongDock", "left"):Click()
check("left", along.points[1][1] == "TOPRIGHT" and along.points[1][3] == "TOPLEFT" and along.points[1][4] == -8)
radio("alongDock", "right"):Click()
check("right", along.points[1][1] == "TOPLEFT" and along.points[1][3] == "TOPRIGHT" and along.points[1][4] == 8)
along.left, along.top = 900, 500
radio("alongDock", "free"):Click()
check("free: stays where it is", db.alongDock == "free" and along.points[1][2] == UIParent and along.points[1][4] == 900 and along.points[1][5] == 500)
radio("alongDock", "bottom"):Click()
check("back below", along.points[1][2] == card and along.points[1][3] == "BOTTOMLEFT")
local header
for _, f in ipairs(M.frames) do if f.parent == along and f.h == 34 then header = f end end
header.scripts.OnMouseDown(header, "LeftButton")
header.scripts.OnMouseUp(header)
check("dragging it makes it free", db.alongDock == "free" and db.alongPoint and radio("alongDock", "free").checked)
wp.resetCard:Click()
check("reset positions: on the right again", db.alongDock == "right" and along.points[1][2] == card and along.points[1][3] == "TOPRIGHT")

print(("%d passed, %d failed"):format(passed, failed))
io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

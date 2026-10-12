-- Offline checks for RXP Enhanced's timing log (Log.lua): off by default, step times, kill times,
-- NPC visits, flights, deaths, XP, a /reload carrying the session on, a relog starting a new one,
-- the settings and commands, the row cap and secret values. lua5.1 test_log.lua [dump.lua]
-- With a file name, it also writes the log as WoW would save it, for tools/timing_log.py's tests.
local M = dofile("mock.lua")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "") .. "\n") end
end
local function near(a, b, tol) return type(a) == "number" and math.abs(a - b) <= (tol or 0.25) end

-- ---------------------------------------------------------------- the game, mocked
M.units = {}
M.inCombat, M.taxi, M.playerDead, M.ghost, M.afk, M.mounted, M.group = false, false, false, false, false, false, 0
M.server = 1791800000
M.zone = "Tirisfal Glades"
local PLAYER_GUID = "Player-5826-0ABCDEF1"
local function U(u) return M.units[u] end
function UnitExists(u) return u == "player" or U(u) ~= nil end
function UnitGUID(u) if u == "player" then return PLAYER_GUID end return U(u) and U(u).guid end
function UnitName(u) if u == "player" then return "Ryan" end return U(u) and U(u).name end
function UnitLevel(u) if u == nil or u == "player" then return M.level end return U(u) and U(u).level end
M.pxp = 1200 -- the player's XP (the mock's M.xp builds guide lines)
function UnitXP() return M.pxp end
function UnitXPMax() return M.xpMax end
function UnitIsPlayer(u) return u == "player" end
function UnitPlayerControlled(u) return u == "player" or (U(u) and U(u).pet) or false end
function UnitCanAttack(_, u) return U(u) ~= nil and not U(u).friendly end
function UnitThreatSituation(_, u) return U(u) and U(u).threat or nil end
function UnitIsUnit(a, b) return false end
function UnitIsDead(u) if u == "player" then return M.playerDead end return U(u) and U(u).dead or false end
function UnitClassification(u) return U(u) and (U(u).cls or "normal") end
function UnitIsTapDenied(u) return U(u) and U(u).tapDenied or false end
function UnitAffectingCombat(u) if u == "player" then return M.inCombat end return U(u) ~= nil end
function UnitOnTaxi() return M.taxi end
function UnitIsDeadOrGhost() return M.playerDead or M.ghost end
function UnitIsGhost() return M.ghost end
function UnitIsAFK() return M.afk end
function GetServerTime() return M.server + math.floor(M.now) end
function GetRealmName() return "Forever" end
function GetBuildInfo() return "1.60.1", "70291", "Oct 1 2026", 16001 end
function UnitRace() return "Undead", "Scourge", 5 end
function UnitClass() return "Paladin", "PALADIN", 2 end
function UnitFactionGroup() return "Horde", "Horde" end
function IsMounted() return M.mounted end
function GetNumGroupMembers() return M.group end
function GetRealZoneText() return M.zone end
C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "1.8.0" or nil end }
C_NamePlate = { GetNamePlates = function() return {} end }

-- ---------------------------------------------------------------- a guide
local RXP, Q = M.RXP, M.quests
local goto, text, accept, turnin, complete, step = M.goto, M.text, M.accept, M.turnin, M.complete, M.step
Q.names = { [363] = "Rude Awakening", [364] = "The Mindless Ones", [400] = "Fresh Meat", [401] = "Gordo's Task" }
local s1 = step({ goto(100, 0, { zone = 1420, x = 30.84, y = 66.20 }), text("Talk to |cRXP_FRIENDLY_Shadow Priest Sarvis|r"), accept(363, "Accept Rude Awakening") })
local s2 = step({ goto(0, 100, { zone = 1420, x = 33.00, y = 61.00, radius = 25 }), text("Kill |cRXP_ENEMY_Mindless Zombies|r"), complete(364, 1, "Mindless Zombie slain: 0/8") })
local s3 = step({ turnin(364, "Turn in The Mindless Ones") })
local s4 = step({ text("Read the sign") })
local s5 = step({ accept(400, "Accept Fresh Meat") })
local s6 = step({ accept(401, "Accept Gordo's Task") })
local s7 = step({ turnin(401, "Turn in Gordo's Task"), M.xp(21.5, "Grind") })
local s8 = step({ accept(402, "Accept Supplies for Brill") })
local s9 = step({ accept(403, "Accept Deaths in the Family") })
M.setGuide({ s1, s2, s3, s4, s5, s6, s7, s8, s9 })
RXP.hideArrow = false
RXPG_ARROW.element = s1.elements[1]
M.player.x, M.player.y, M.player.instance = 0, 0, 0

local function loadAddon()
    RXPEnhanced = nil
    assert(loadfile("../RXPEnhanced/RXPEnhanced.lua"))("RXPEnhanced")
    assert(loadfile("../RXPEnhanced/Card.lua"))("RXPEnhanced")
    assert(loadfile("../RXPEnhanced/Waypoint.lua"))("RXPEnhanced")
    assert(loadfile("../RXPEnhanced/Toast.lua"))("RXPEnhanced")
    assert(loadfile("../RXPEnhanced/Log.lua"))("RXPEnhanced")
    local NS = RXPEnhanced
    local driver
    for i = #M.frames, 1, -1 do
        local f = M.frames[i]
        if f.events.PLAYER_LOGIN and f.scripts.OnEvent then driver = f break end
    end
    driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
    return NS, NS.Log
end

-- C_NavigationFrame etc. aren't needed: the waypoint marker stays off in these tests.
RXPEnhancedDB = { wpEnabled = false, toast = false }
M.printed = {}
local NS, Log = loadAddon()
local db = RXPEnhancedDB

local function fire(e, ...) Log.events.scripts.OnEvent(Log.events, e, ...) end
-- Runs the game for some seconds, 0.2 s at a time; each(i) runs before each look.
local function run(seconds, each)
    for i = 1, math.floor(seconds / 0.2 + 0.5) do
        M.now = M.now + 0.2
        if each then each(i) end
        if Log.driver.shown then Log.driver.scripts.OnUpdate(Log.driver, 0.2) end -- hidden frames don't update
    end
end
-- Walks in a straight line at speed yards a second.
local function walk(seconds, dx, dy)
    local n = math.floor(seconds / 0.2 + 0.5)
    run(seconds, function()
        M.player.x = M.player.x + dx / n
        M.player.y = M.player.y + dy / n
    end)
end
local function printedHas(pat)
    for _, l in ipairs(M.printed) do if l:find(pat) then return true end end
    return false
end
local function cols(kind)
    local t = {}
    for c in RXPEnhancedLog.columns[kind]:gmatch("%S+") do t[#t + 1] = c end
    return t
end
local function split(row)
    local t = {}
    for f in (row .. "\t"):gmatch("(.-)\t") do t[#t + 1] = f end
    return t
end
-- A row as a table keyed by column name.
local function rec(kind, row)
    local names, f = cols(kind), split(row)
    local r = {}
    for i, n in ipairs(names) do
        local v = f[i]
        r[n] = tonumber(v) or v
    end
    r._n = #f
    return r
end
local function session() return RXPEnhancedLog.sessions[#RXPEnhancedLog.sessions] end
local function lastRow(kind) local s = session(); local list = s[kind .. "s"]; return list[#list] and rec(kind, list[#list]) end
local function rows(kind) local out = {} for _, r in ipairs(session()[kind .. "s"]) do out[#out + 1] = rec(kind, r) end return out end
local function events(code)
    local out = {}
    for _, r in ipairs(session().events) do
        local e = rec("event", r)
        if e.code == code then out[#out + 1] = e end
    end
    return out
end

-- ---------------------------------------------------------------- off by default
check("off by default", db.logTimes == false and not Log.IsOn())
check("off: no events listened to, nothing ticking", next(Log.events.events) == nil and not Log.driver.shown)
check("off: the log is set up but empty", type(RXPEnhancedLog) == "table" and RXPEnhancedLog.format == 1 and #RXPEnhancedLog.sessions == 0)
check("off: the log's columns are written down for the reader", RXPEnhancedLog.columns.step:find("^g idx sig label t0 t1 how") and RXPEnhancedLog.columns.kill:find("fight seq pull"))
check("off: nothing said at login about logging", not printedHas("logging step and kill times"))
check("files all loaded: no restart notice", not printedHas("restart WoW"))
run(2)
check("off: a guide step goes by without a session", RXPEnhancedLog.sessions[1] == nil)

-- The switch on the General tab.
NS.OpenSettings("general")
local win = RXPEnhancedSettings
local p = win.panel
local logCheck = p.checks.logTimes
check("settings: the switch is on the General tab, unticked", logCheck and not logCheck.checked and logCheck.parent == p.sections.general, logCheck and tostring(logCheck.checked))
check("settings: says nothing's logged yet", p.logStatus.text == "Off. Nothing logged yet.", p.logStatus.text)
check("settings: window still fits on a 768-high screen", win.h < 740, win.h)
logCheck.checked = true
logCheck:Click()
check("settings: ticking it turns logging on", db.logTimes == true and Log.IsOn())
check("on: listening for the game's events", Log.events.events.UNIT_DIED and Log.events.events.PARTY_KILL and Log.events.events.CHAT_MSG_COMBAT_XP_GAIN and Log.events.events.PLAYER_REGEN_DISABLED)
check("on: ticking", Log.driver.shown)
local s = session()
check("session: who and what", s and s.char == "Ryan-Forever" and s.race == "Scourge" and s.class == "PALADIN" and s.faction == "Horde")
check("session: game build and addon version", s.build == "1.60.1.70291" and s.addon == "1.8.0", tostring(s.build) .. " " .. tostring(s.addon))
check("session: started when you turned it on", s.started == M.server + math.floor(M.now) and #events("ON") == 1)
check("settings: status says it's logging", p.logStatus.text:find("^Logging, 0 min into this session"), p.logStatus.text)

-- ---------------------------------------------------------------- step 1: walk, talk, accept
run(0.2)
check("step 1 opened", s.open and s.open.idx == 1 and s.open.sig == "A363" and s.open.part, s.open and s.open.sig)
check("step 1: label as the guide shows it", s.open.label == "Talk to Shadow Priest Sarvis", s.open.label)
check("step 1: the place it leads to", s.open.tinst == 0 and s.open.tx == 100 and s.open.ty == 0)
walk(10, 50, 0) -- 5 yd a second
M.player.x = 50
fire("GOSSIP_SHOW")
run(1)
fire("GOSSIP_CLOSED")
fire("QUEST_DETAIL")
run(2)
M.quests.on[363] = true
fire("QUEST_ACCEPTED", 363)
fire("QUEST_FINISHED")
s1.elements[3].completed = true
run(0.2)
RXP.SetStep(2)
run(0.2)
local r1 = lastRow("step")
check("step 1 logged when RestedXP moved on", r1 and r1.idx == 1 and r1.how == "done" and r1.part == 1, r1 and r1.how)
check("step 1: every column", r1._n == #cols("step"), r1._n)
check("step 1: signature and label", r1.sig == "A363" and r1.label == "Talk to Shadow Priest Sarvis")
check("step 1: time on it", near(r1.t1 - r1.t0, 13.6, 0.3), r1.t1 - r1.t0)
check("step 1: 10 s walking, 50 yards", near(r1.move, 10, 0.3) and near(r1.yd, 50, 1), r1.move .. " " .. r1.yd)
check("step 1: 3 s at the NPC", near(r1.dialog, 3.0, 0.3), r1.dialog)
check("step 1: the rest standing still, no fighting", near(r1.still, 0.6, 0.3) and r1.combat == 0, r1.still)
check("step 1: the time adds up", near(r1.move + r1.combat + r1.still + r1.dialog + r1.taxi + r1.dead + r1.afk + r1.load, r1.t1 - r1.t0, 0.3))
check("step 1: start, end and target", r1.inst0 == 0 and r1.x0 == 0 and r1.x1 == 50 and r1.tx == 100 and r1.direct == 100)
check("step 1: level with its fraction", near(r1.pl0, 5 + 1200 / 2800, 0.01) and r1.passed == 0 and r1.kills == 0)
run(1.2)
local w = events("W")[1]
check("NPC visit logged once the windows close: quest, 3 s, one quest", w and w.a == "quest" and near(w.b, 3.0, 0.3) and w.c == 1, w and (w.a .. " " .. w.b .. " " .. w.c))
check("quest accepted logged", events("A")[1] and events("A")[1].a == 363)
check("guide named once", #events("GD") == 1 and events("GD")[1].b == "My Guides|launch" and s.guides[1] == "My Guides|launch")

-- ---------------------------------------------------------------- kills on step 2
local ZOMBIE = "Creature-0-5826-0-12-1501-00004A2B01"
local ZOMBIE2 = "Creature-0-5826-0-12-1501-00004A2B02"
M.units.target = { guid = ZOMBIE, name = "Mindless Zombie", level = 2, threat = 1 }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
check("kill: engaged at the pull", Log.S.mobs[ZOMBIE] and Log.S.mobs[ZOMBIE].engaged == Log.S.combat.start)
run(12)
M.units.target.dead = true
fire("UNIT_DIED", ZOMBIE)
check("kill: seen dying (UNIT_DIED)", #Log.S.pending == 1 and Log.S.pending[1].src == "d")
M.pxp = M.pxp + 70
fire("CHAT_MSG_COMBAT_XP_GAIN", "Mindless Zombie dies, you gain 70 experience. (+35 exp Rested bonus)")
check("kill: XP line matched to it", Log.S.pending[1].xp == 70 and Log.S.pending[1].rested == 35)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
fire("LOOT_OPENED", true)
run(1)
fire("LOOT_CLOSED")
run(4)
M.units.target = nil
check("kill: row waits for what comes after it", #session().kills == 0 and Log.S.pending[1].loot and near(Log.S.pending[1].still, 5, 0.3), Log.S.pending[1].still)
walk(4, 0, 20)
-- The next mob, seen by its nameplate.
M.units.nameplate1 = { guid = ZOMBIE2, name = "Mindless Zombie", level = 3, threat = 1 }
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
local k1 = lastRow("kill")
check("kill 1 written when the next pull starts", k1 and k1.npc == 1501 and k1.name == "Mindless Zombie" and k1.ml == 2 and k1.cls == "n")
check("kill 1: every column", k1._n == #cols("kill"), k1._n)
check("kill 1: 12 s from pull to death", near(k1.fight, 12, 0.3) and near(k1.seq, 12, 0.3) and k1.pull == 1, k1.fight)
check("kill 1: XP, rested, ours, solo", k1.xp == 70 and k1.rested == 35 and k1.tap == 1 and k1.grp == 1)
check("kill 1: looted a second after, then stood 5 s", near(k1.loot, 1.0, 0.3) and near(k1.still, 5, 0.3), k1.loot .. " " .. k1.still)
check("kill 1: first kill, so no gap before it", k1.gap == -1)
check("kill 1: on step 2, guide 1, where it was", k1.step == 2 and k1.g == 1 and k1.inst == 0 and k1.x == 50 and k1.y == 0, k1.step)
check("kill 1: how its death was seen", k1.src == "d")
check("kill 1: player level when it started", near(k1.pl, 5 + 1200 / 2800, 0.01), k1.pl)
local m2 = Log.S.mobs[ZOMBIE2]
check("kill 2: gap since the last death, 4 s of it walking 20 yd", m2 and near(m2.gap, 9, 0.4) and near(m2.gmove, 4, 0.3) and near(m2.gyd, 20, 1) and near(m2.gother, 0, 0.01), m2 and m2.gap)
run(15)
M.units.nameplate1.dead = true
run(0.2)
check("kill 2: seen dead on its nameplate (no UNIT_DIED)", Log.S.pending[1] and Log.S.pending[1].src == "u" and near(Log.S.pending[1].fight, 15.2, 0.3), Log.S.pending[1] and Log.S.pending[1].fight)
M.pxp = M.pxp + 80
fire("CHAT_MSG_COMBAT_XP_GAIN", "Mindless Zombie dies, you gain 80 experience.")
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
M.units.nameplate1 = nil
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
run(2)

-- Two at once: one on target, one on a nameplate.
local A = "Creature-0-5826-0-12-1502-00004A2B03"
local B = "Creature-0-5826-0-12-1502-00004A2B04"
M.units.target = { guid = A, name = "Rattlecage Skeleton", level = 4, threat = 1 }
M.units.nameplate2 = { guid = B, name = "Rattlecage Skeleton", level = 4, threat = 0 }
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
local k2 = lastRow("kill")
check("kill 2 written at the next pull, with its gap", k2 and k2.src == "u" and near(k2.gap, 9, 0.4) and near(k2.gmove, 4, 0.3) and k2.xp == 80 and k2.ml == 3, k2 and k2.gap)
check("pull of two: both engaged", Log.S.mobs[A] and Log.S.mobs[B] and Log.S.combat.engaged == 2)
run(10)
M.units.target.dead = true
fire("UNIT_DIED", A)
M.units.target = nil
run(8)
fire("PARTY_KILL", PLAYER_GUID, B)
M.units.nameplate2.dead = true
fire("UNIT_DIED", B)
check("pull of two: two kills, not three", #Log.S.pending == 2 and Log.S.pending[2].src == "k", #Log.S.pending)
check("pull of two: second took 8 s after the first", near(Log.S.pending[2].seq, 8, 0.3) and near(Log.S.pending[2].fight, 18, 0.3) and Log.S.pending[2].pull == 2)
check("pull of two: first", near(Log.S.pending[1].seq, 10, 0.3) and Log.S.pending[1].pull == 2)

-- A kill nobody saw (no target, no nameplate): its XP line, then its killing blow.
M.units.nameplate2 = nil
fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
run(3)
local X = "Creature-0-5826-0-12-1508-00004A2B05"
M.pxp = M.pxp + 50
fire("CHAT_MSG_COMBAT_XP_GAIN", "Scavenger dies, you gain 50 experience.")
fire("PARTY_KILL", PLAYER_GUID, X)
check("unseen kill: logged from its XP line once", #Log.S.pending == 3 and Log.S.pending[3].src == "x" and Log.S.pending[3].xp == 50 and Log.S.pending[3].name == "Scavenger")
check("unseen kill: its killing blow gives it an NPC id, not a second row", Log.S.pending[3].npc == 1508 and #Log.S.pending == 3)
check("unseen kill: no engage time, but 3 s after the kill before it", Log.S.pending[3].fight == nil and near(Log.S.pending[3].seq, 3, 0.3) and Log.S.pending[3].pull == 3, Log.S.pending[3].seq)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
run(2)

-- Someone else's mob.
local T = "Creature-0-5826-0-12-1501-00004A2B06"
M.units.target = { guid = T, name = "Mindless Zombie", level = 2, threat = 2, tapDenied = true }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
run(3)
M.units.target.dead = true
fire("UNIT_DIED", T)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
M.units.target = nil
check("someone else's tag: not yours", Log.S.pending[#Log.S.pending].tap == 0)
run(61)
local kills = rows("kill")
check("kills written within a minute of their death", #kills == 6 and #Log.S.pending == 0, #kills)
check("tagged kill: no XP", kills[6].tap == 0 and kills[6].xp == 0)
check("kills in order of death", kills[3].t < kills[4].t and kills[4].t < kills[5].t)

-- A mob that got away: dropped once combat is over.
local E = "Creature-0-5826-0-12-1501-00004A2B07"
M.units.target = { guid = E, name = "Mindless Zombie", level = 2, threat = 1 }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
run(2)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
M.units.target = nil
run(4)
check("evaded mob dropped, no kill", Log.S.mobs[E] == nil and #rows("kill") == 6)

-- Step 2 done.
s2.elements[3].completed = true
RXP.SetStep(3)
run(0.2)
local r2 = lastRow("step")
check("step 2: done, its kills and XP", r2.idx == 2 and r2.how == "done" and r2.kills == 6 and r2.xp == 200 and r2.part == 0, r2.kills .. " kills, xp " .. r2.xp)
check("step 2: fighting time", near(r2.combat, 12 + 15.2 + 18 + 3 + 3 + 2 + 0.4, 1.5), r2.combat)
check("step 2: the time adds up", near(r2.move + r2.combat + r2.still + r2.dialog + r2.taxi + r2.dead + r2.afk + r2.load, r2.t1 - r2.t0, 0.3))

-- ---------------------------------------------------------------- how steps end
NS.Card.Skip()
run(0.2)
check("Skip on the card: skip", lastRow("step").idx == 3 and lastRow("step").how == "skip")
RXP.SetStep(5)
run(0.2)
check("a step of notes: note", lastRow("step").idx == 4 and lastRow("step").how == "note")
NS.Card.Back()
run(0.2)
check("Back: back", lastRow("step").idx == 5 and lastRow("step").how == "back")
RXP.SetStep(5)
run(0.2)
s5.elements[1].skip = true -- ticked off by hand
RXP.SetStep(6)
run(0.2)
check("ticked off: tick", lastRow("step").idx == 5 and lastRow("step").how == "tick")

-- ---------------------------------------------------------------- level-up, flight, death on step 6
M.pxp = 2700
run(0.2)
M.level, M.pxp, M.xpMax = 6, 50, 3600
fire("PLAYER_LEVEL_UP", 6)
run(0.2)
check("level-up logged", events("L")[1] and events("L")[1].a == 6)
check("XP across a ding: the rest of the old level plus the new", session().open and session().xpTotal - session().open.xp0 == (2700 - (1200 + 200)) + 100 + 50, session().xpTotal - session().open.xp0)
M.taxi = true
run(10)
M.taxi = false
run(0.2)
local f = events("F")
check("flight: start and end with its time", #f == 2 and f[1].a == 1 and f[2].a == 0 and near(f[2].b, 10, 0.3), #f)
M.playerDead = true
fire("PLAYER_DEAD")
run(5)
M.playerDead, M.ghost = false, true
fire("PLAYER_ALIVE") -- released: a ghost
run(10)
M.ghost = false
fire("PLAYER_UNGHOST")
fire("PLAYER_ALIVE")
run(0.2)
check("death and getting back up, with the time dead", #events("D") == 1 and #events("G") == 1 and near(events("G")[1].a, 15, 0.3), #events("G"))
M.afk = true
fire("PLAYER_FLAGS_CHANGED", "player")
run(3)
M.afk = false
fire("PLAYER_FLAGS_CHANGED", "player")
check("AFK on and off", #events("AFK") == 2)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8690)
fire("LOADING_SCREEN_ENABLED")
M.now = M.now + 6
fire("LOADING_SCREEN_DISABLED")
run(0.2)
check("hearth and its loading screen", #events("H") == 1 and events("LS")[1] and near(events("LS")[1].a, 6, 0.1))
M.zone = "Brill"
fire("ZONE_CHANGED_NEW_AREA")
check("zone change", events("Z")[1] and events("Z")[1].a == "Brill")
fire("TIME_PLAYED_MSG", 5000, 300)
check("/played lined up with the session clock", session().played0 == math.floor(5000 - Log.Now() + 0.5))

-- ---------------------------------------------------------------- a /reload in the middle of step 6
local nSessions = #RXPEnhancedLog.sessions
local openBefore = session().open
fire("PLAYER_LOGOUT")
check("logout: the step you're on stays open for after the reload", session().open == openBefore and openBefore.idx == 6)
M.now = M.now + 20 -- the reload
M.printed = {}
NS, Log = loadAddon()
check("reload: logging back on by itself, with a line in chat", Log.IsOn() and printedHas("logging step and kill times"))
check("reload: same session", #RXPEnhancedLog.sessions == nSessions and session() == RXPEnhancedLog.sessions[nSessions])
check("reload: time away logged", events("R")[1] and near(events("R")[1].a, 20, 1.5), events("R")[1] and events("R")[1].a)
run(1)
check("reload: still on step 6", session().open and session().open.idx == 6 and not session().open.resumed)
s6.elements[1].completed = true
RXP.SetStep(7)
run(0.2)
local r6 = lastRow("step")
check("step 6 across the reload: one row, with the reload as loading time", r6.idx == 6 and r6.how == "done" and r6.load >= 20 + 6 - 1.5 and r6.taxi >= 9.8 and r6.dead >= 14.8 and r6.afk >= 2.8, r6.load)
check("step 6: the time adds up", near(r6.move + r6.combat + r6.still + r6.dialog + r6.taxi + r6.dead + r6.afk + r6.load, r6.t1 - r6.t0, 1.2), (r6.t1 - r6.t0) .. " vs parts")
check("step 6: level 5 to 6", math.floor(r6.pl0) == 5 and math.floor(r6.pl1) == 6)

-- RestedXP still loading just after a reload: the open step waits for it.
fire("PLAYER_LOGOUT")
M.now = M.now + 10
local saved = RXP.currentGuide
RXP.currentGuide = { empty = true }
NS, Log = loadAddon()
run(2)
check("reload with the guide not loaded yet: step 7 kept open", session().open and session().open.idx == 7)
RXP.currentGuide = saved
run(1)
check("guide back: step 7 carries on", session().open and session().open.idx == 7 and not session().open.resumed)

-- ---------------------------------------------------------------- a relog much later: a new session
fire("PLAYER_LOGOUT")
M.now = M.now + 20 * 60
NS, Log = loadAddon()
check("relog after 20 min: a new session", #RXPEnhancedLog.sessions == nSessions + 1)
local old = RXPEnhancedLog.sessions[nSessions]
local oldLast = rec("step", old.steps[#old.steps])
check("relog: the old session's open step ends there", old.open == nil and oldLast.idx == 7 and oldLast.how == "end")
run(1)
check("relog: the step you're on starts again, marked partial", session().open and session().open.idx == 7 and session().open.part)

-- ---------------------------------------------------------------- commands
SlashCmdList.RXPENHANCED("log status")
check("/rxpe log status", printedHas("Logging, 0 min into this session"))
M.printed = {}
SlashCmdList.RXPENHANCED("log off")
check("/rxpe log off", db.logTimes == false and not Log.IsOn() and printedHas("timing log |cffff5555off"))
local stopped = rec("step", session().steps[#session().steps])
check("off: the open step ends, unfinished", stopped.idx == 7 and stopped.how == "end" and session().open == nil)
check("off: logged, and no longer listening", events("OFF")[1] and next(Log.events.events) == nil and not Log.driver.shown)
local n = #session().events
run(5)
check("off: nothing more logged", #session().events == n)
SlashCmdList.RXPENHANCED("log")
check("/rxpe log turns it back on, same session", Log.IsOn() and #RXPEnhancedLog.sessions == nSessions + 1)
run(6)
RXP.SetStep(9)
run(0.2)
local r7 = lastRow("step") or {}
check("RestedXP passing over a step: counted, and the step left undone is a skip", r7.idx == 7 and r7.passed == 1 and r7.how == "skip" and r7.part == 1, ("%s %s %s %s"):format(tostring(r7.idx), tostring(r7.passed), tostring(r7.how), tostring(r7.part)))
SlashCmdList.RXPENHANCED("log new")
check("/rxpe log new: a new session", #RXPEnhancedLog.sessions == nSessions + 2)
M.printed = {}
SlashCmdList.RXPENHANCED("log clear")
check("/rxpe log clear asks first", printedHas("log clear yes") and #RXPEnhancedLog.sessions == nSessions + 2)

-- ---------------------------------------------------------------- every row's columns, and the dump for the reader
local bad = 0
for _, ss in ipairs(RXPEnhancedLog.sessions) do
    for kind, list in pairs({ step = ss.steps, kill = ss.kills, event = ss.events }) do
        for _, r in ipairs(list) do
            if #split(r) ~= #cols(kind) then bad = bad + 1 end
        end
    end
end
check("every row has its columns", bad == 0, bad)

-- Written as WoW writes SavedVariables, for tools/timing_log.py's tests.
local function serialize(v, indent, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = string.format("%q", v)
    elseif t == "number" then out[#out + 1] = tostring(v)
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{\n"
        local n = #v
        for i = 1, n do
            out[#out + 1] = indent .. "\t"
            serialize(v[i], indent .. "\t", out)
            out[#out + 1] = ", -- [" .. i .. "]\n"
        end
        local keys = {}
        for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "] = "
            serialize(v[k], indent .. "\t", out)
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    else out[#out + 1] = "nil" end
end
if arg and arg[1] then
    local out = { "\nRXPEnhancedDB = " }
    serialize({ logTimes = true, cardTheme = "glass" }, "", out)
    out[#out + 1] = "\nRXPEnhancedLog = "
    serialize(RXPEnhancedLog, "", out)
    out[#out + 1] = "\n"
    local fh = assert(io.open(arg[1], "w"))
    fh:write(table.concat(out))
    fh:close()
end

SlashCmdList.RXPENHANCED("log clear yes")
check("/rxpe log clear yes: gone, and a fresh session going", #RXPEnhancedLog.sessions == 1 and Log.IsOn() and #session().steps == 0)

-- The Clear log button wants two clicks.
NS.OpenSettings("general")
p = RXPEnhancedSettings.panel
run(3)
p.logClear:Click()
check("Clear log: first click asks", p.logClear.text == "Click to confirm", p.logClear.text)
check("Clear log: first click deletes nothing", #RXPEnhancedLog.sessions == 1)
M.now = M.now + 5
p:SyncLog()
check("Clear log: asks again after a few seconds", p.logClear.text == "Clear log", p.logClear.text)
p.logClear:Click()
p.logClear:Click()
check("Clear log: second click clears", #RXPEnhancedLog.sessions == 1 and #session().events == 1 and printedHas("timing log cleared"))

-- ---------------------------------------------------------------- the row cap
M.printed = {}
Log.S.rows = Log.LIMITS.maxRows - 1
Log.Event("TEST")
check("cap: the last row fits", events("TEST")[1] ~= nil)
Log.Event("TEST")
check("cap: then nothing more, and a word in chat", #events("TEST") == 1 and printedHas("timing log is full"))
check("cap: settings say so", Log.StatusText():find("^Log full"))
SlashCmdList.RXPENHANCED("log clear yes")
check("cap: clearing makes room", not Log.Stats().full and Log.S.rows < 5)

-- ---------------------------------------------------------------- secret values
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
M.units.target = { guid = SECRET, name = SECRET, level = 2, threat = 1 }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
run(1)
check("secret GUID: no mob tracked, no error", next(Log.S.mobs) == nil)
fire("UNIT_DIED", SECRET)
fire("CHAT_MSG_COMBAT_XP_GAIN", SECRET)
check("secret death and XP line: ignored", #Log.S.pending == 0)
M.units.target = { guid = "Creature-0-5826-0-12-1501-00004A2B09", name = SECRET, level = 2, threat = 1 }
run(0.4)
local sm = Log.S.mobs["Creature-0-5826-0-12-1501-00004A2B09"]
check("secret name: tracked without one", sm and sm.name == nil and sm.npc == 1501)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
issecretvalue = nil

-- ---------------------------------------------------------------- more fights
-- Two mobs of the same name; the XP line comes before either death has been seen.
local Z1, Z2 = "Creature-0-5826-0-12-1501-0000AAAA01", "Creature-0-5826-0-12-1501-0000AAAA02"
M.units.target = { guid = Z1, name = "Mindless Zombie", level = 2, threat = 1 }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
check("a new fight drops mobs left from the last one", Log.S.mobs["Creature-0-5826-0-12-1501-00004A2B09"] == nil)
run(1)
M.units.nameplate3 = { guid = Z2, name = "Mindless Zombie", level = 2, threat = 1 }
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
run(5)
M.units.nameplate3.dead = true -- the one that joined later dies first
fire("CHAT_MSG_COMBAT_XP_GAIN", "Mindless Zombie dies, you gain 40 experience.")
local pz = Log.S.pending[#Log.S.pending]
check("same names: the XP goes to the one lying dead", pz and pz.guid == Z2 and pz.xp == 40 and pz.src == "u" and not Log.S.mobs[Z1].dead, pz and pz.guid)
fire("UNIT_DIED", Z2)
check("same names: its UNIT_DIED doesn't count it again", #Log.S.pending == 1, #Log.S.pending)
M.units.nameplate3 = nil
fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
M.units.target = nil -- out of view
run(4)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Mindless Zombie dies, you gain 40 experience.")
check("same names, nothing in view: the XP line takes the mob of that name", Log.S.mobs[Z1].dead and Log.S.pending[2] and Log.S.pending[2].guid == Z1 and Log.S.pending[2].src == "x")
fire("UNIT_DIED", Z1)
check("and its UNIT_DIED is ignored", #Log.S.pending == 2)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
-- A mob that ran off, and a new fight straight after: the new pull still gets its gap.
local Z3, Z4 = "Creature-0-5826-0-12-1501-0000AAAA03", "Creature-0-5826-0-12-1501-0000AAAA04"
run(2)
M.units.target = { guid = Z3, name = "Mindless Zombie", level = 2, threat = 1 }
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
run(1)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
M.units.target = { guid = Z4, name = "Mindless Zombie", level = 2, threat = 1 }
run(1)
M.inCombat = true
fire("PLAYER_REGEN_DISABLED")
check("the mob that ran off doesn't block the next pull's gap", Log.S.mobs[Z3] == nil and Log.S.mobs[Z4] and near(Log.S.mobs[Z4].gap, 4, 0.5), Log.S.mobs[Z4] and Log.S.mobs[Z4].gap)
M.inCombat = false
fire("PLAYER_REGEN_ENABLED")
M.units.target = nil

-- Logging out with an NPC window open.
fire("GOSSIP_SHOW")
run(2)
local ok = pcall(fire, "PLAYER_LOGOUT")
check("logout with an NPC window open: no error, the visit logged", ok and events("W")[1] and events("W")[1].a == "gossip" and near(events("W")[1].b, 2, 0.3))
check("logout: kills waiting are written", #Log.S.pending == 0 and #rows("kill") == 2, #rows("kill"))
fire("GOSSIP_CLOSED")

-- The guide's last step done, and RestedXP moves on to the next guide.
s9.elements[1].completed = true
M.setGuide({ step({ accept(500, "Accept A New Guide") }), step({ accept(501) }) }, "next")
run(0.4)
local last = lastRow("step")
check("a guide's last step, then the next guide: done", last and last.idx == 9 and last.how == "done", last and last.how)
check("the next guide's first step opens, not partial", session().open and session().open.idx == 1 and not session().open.part and session().open.g == 2)
check("both guides named", session().guides[2] == "My Guides|next")

-- ---------------------------------------------------------------- signatures, as the engine makes them
check("signature: quests, objectives, level", Log.Signature(step({ accept(363), complete(364, 1), { tag = "xp", level = 21.5, reverseLogic = true } })) == "A363 C364.1 Y21")
check("signature: trainer, bind, hearth, flight path", Log.Signature(step({ { tag = "trainer" }, { tag = "home" }, { tag = "hs" }, { tag = "fp" } })) == "R H S F")
check("signature: #completewith steps have none", Log.Signature(step({ accept(363) }, { sticky = true })) == "")

-- Reset all: logging goes back off.
SlashCmdList.RXPENHANCED("reset")
check("Reset all turns logging off (its default)", db.logTimes == false and not Log.IsOn())

io.stdout:write(passed .. " passed, " .. failed .. " failed\n")
if failed > 0 then os.exit(1) end

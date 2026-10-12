-- RXP Enhanced: a timing log for the route engine. Off by default: /rxpe log, or General > Timing
-- log in the settings.
--
-- While it's on it records:
--  - every guide step you're on: when RestedXP moved to it and when it moved on, how it ended (done,
--    ticked off, skipped, back...), where the time went (moving, fighting, standing still, talking
--    to NPCs, flying, dead, AFK, loading screens), the yards you ran, kills and XP;
--  - every kill: from engaging the mob to its death, the time since the kill before and how much of
--    it was walking, then the loot and rest after it, the mob's level and the XP;
--  - in between: level-ups, deaths, quests accepted and turned in, time at NPCs, flights, hearths.
-- It's kept in RXPEnhancedLog, in the same SavedVariables file as the settings, which WoW writes when
-- you log out or reload. tools/timing_log.py reads it and works out the route engine's numbers.
--
-- Forever (Midnight's API) keeps the combat log from addons, so kills are seen through units: the
-- target, nameplates, soft target, mouseover and focus. A mob counts as engaged once you're on its
-- threat list or it targets you while you're in combat; its death comes from UNIT_DIED or PARTY_KILL,
-- UnitIsDead, or the kill's XP line, whichever comes first.

local ADDON_NAME = ...
local NS = _G.RXPEnhanced
if not (NS and NS.private) then return end
local P = NS.private
local Log = {}
NS.Log = Log

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local format, concat = string.format, table.concat

local FORMAT = 1 -- the log's layout; the reader checks it
local TICK = 0.2 -- seconds between looks
local MAX_ROWS = 50000 -- steps, kills and events over every session kept
local RESUME = 15 * 60 -- seconds: logging in again this soon carries on the last session
local SETTLE = 5 -- seconds after a guide shows up when RestedXP may still jump to your saved step
local GAP_MAX = 300 -- seconds: a pull this long after the last kill has no gap
local PENDING_MAX = 60 -- seconds: a kill's row is written this long after its death at the latest
local XP_WINDOW = 3 -- seconds between a death and its XP line, either way round
local MOB_FORGET = 3 -- seconds after combat ends that unkilled mobs are dropped (they evaded)
local TELEPORT = 60 -- yards in one look: a teleport, not running
local MOVE_MIN = 0.25 -- yards in one look that count as moving
local TALK_GAP = 1.0 -- seconds between NPC windows that still make one visit
local HEARTHSTONE = 8690

Log.COLUMNS = {
    step = "g idx sig label t0 t1 how passed part move combat still dialog taxi dead afk load yd kills xp pl0 pl1 inst0 x0 y0 inst1 x1 y1 tinst tx ty direct mount",
    kill = "t g step npc name ml cls pl fight seq pull xp rested tap grp inst x y gap gmove gyd gother loot still src",
    event = "t code a b c",
}
Log.LIMITS = { tick = TICK, maxRows = MAX_ROWS, resume = RESUME, settle = SETTLE, gapMax = GAP_MAX, pendingMax = PENDING_MAX, xpWindow = XP_WINDOW }
local CATS = { "move", "combat", "still", "dialog", "taxi", "dead", "afk", "load" }
local OTHER = { "dialog", "taxi", "dead", "afk", "load" } -- a kill gap's time that isn't hunting
local CLASS_CODE = { normal = "n", elite = "e", rare = "r", rareelite = "R", worldboss = "b", minus = "m", trivial = "t" }
local TALK_RANK = { gossip = 1, quest = 2, taxi = 3, trainer = 4, vendor = 5 } -- what a visit is called
local WINDOW_EVENTS = {
    GOSSIP_SHOW = { "gossip", true }, GOSSIP_CLOSED = { "gossip", false },
    QUEST_GREETING = { "quest", true }, QUEST_DETAIL = { "quest", true }, QUEST_PROGRESS = { "quest", true },
    QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
    MERCHANT_SHOW = { "vendor", true }, MERCHANT_CLOSED = { "vendor", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
}
local EVENTS = {
    "PLAYER_LOGOUT", "TIME_PLAYED_MSG", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_COMBAT", "UNIT_DIED",
    "PARTY_KILL", "CHAT_MSG_COMBAT_XP_GAIN", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA",
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_FLAGS_CHANGED",
}
for e in pairs(WINDOW_EVENTS) do EVENTS[#EVENTS + 1] = e end

local db, rxp, HBD
local S = { on = false, rows = 0, bytes = 0, mobs = {}, pending = {}, plates = {}, windows = {} }
Log.S = S -- for the tests

-- ---------------------------------------------------------------- small helpers

local function secret(v)
    local f = _G.issecretvalue
    if not f then return false end
    local ok, r = pcall(f, v)
    return ok and r and true or false
end

-- The first value fn returns, or nil when it errors or the value is secret.
local function get(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok or secret(a) then return nil end
    return a
end

local function get2(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) or secret(b) then return nil end
    return a, b
end

local function msg(text) print("|cffd1706bRXP Enhanced:|r " .. text) end

local function n1(v) return v ~= nil and format("%.1f", v) or "" end
local function n2(v) return v ~= nil and format("%.2f", v) or "" end
local function int(v) return v ~= nil and format("%d", floor(v + 0.5)) or "" end
local function clean(s) return s ~= nil and (tostring(s):gsub("[\t\r\n]", " ")) or "" end

local function copyAcc(a)
    local c = {}
    for k, v in pairs(a) do c[k] = v end
    return c
end

local function newAcc()
    local a = { yd = 0, mount = 0 }
    for _, c in ipairs(CATS) do a[c] = 0 end
    return a
end

-- ---------------------------------------------------------------- the clock and the session

function Log.Now()
    return (S.clockBase or 0) + (GetTime() - (S.clockAt or GetTime()))
end
local now = Log.Now

local function epoch()
    return get(GetServerTime) or get(time) or 0
end

local function playerLevel()
    local lvl = get(UnitLevel, "player") or 0
    local xp, mx = get(UnitXP, "player"), get(UnitXPMax, "player")
    if xp and mx and mx > 0 then return lvl + xp / mx end
    return lvl
end

local function character()
    local name = get(UnitName, "player") or "?"
    local realm = get(GetRealmName) or ""
    return name .. (realm ~= "" and ("-" .. realm) or ""), name, realm
end

local function store()
    RXPEnhancedLog = type(RXPEnhancedLog) == "table" and RXPEnhancedLog or {}
    local L = RXPEnhancedLog
    L.format = FORMAT
    L.columns = L.columns or {}
    for k, v in pairs(Log.COLUMNS) do L.columns[k] = v end
    L.sessions = type(L.sessions) == "table" and L.sessions or {}
    return L
end

local function countRows()
    local L = store()
    local rows, bytes = 0, 0
    for _, s in ipairs(L.sessions) do
        for _, list in ipairs({ s.steps or {}, s.kills or {}, s.events or {} }) do
            rows = rows + #list
            for _, r in ipairs(list) do bytes = bytes + #r + 4 end
        end
    end
    S.rows, S.bytes = rows, bytes
    S.full = rows >= MAX_ROWS
end

local function addRow(list, fields)
    if S.rows >= MAX_ROWS then
        if not S.full then
            S.full = true
            msg(("the timing log is full (%d rows). Read it with tools/timing_log.py, then clear it: /rxpe log clear."):format(MAX_ROWS))
        end
        return
    end
    for i = 1, #fields do fields[i] = fields[i] == nil and "" or tostring(fields[i]) end
    local row = concat(fields, "\t")
    list[#list + 1] = row
    S.rows = S.rows + 1
    S.bytes = S.bytes + #row + 4
end

local function event(code, a, b, c)
    if not S.session then return end
    addRow(S.session.events, { n1(now()), code, clean(a), clean(b), clean(c) })
end
Log.Event = event

local function newSession(started)
    local key, name, realm = character()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and get(C_AddOns.GetAddOnMetadata, ADDON_NAME or "RXPEnhanced", "Version")
    local buildVersion, buildNumber = get2(GetBuildInfo)
    local _, race = get2(UnitRace, "player")
    local _, class = get2(UnitClass, "player")
    return {
        id = format("%s-%d", key, started), char = key, name = name, realm = realm,
        race = race, class = class, faction = get(UnitFactionGroup, "player"),
        build = buildVersion and format("%s.%s", tostring(buildVersion), tostring(buildNumber or "")) or nil,
        addon = version, started = started, lastEpoch = started, clockEnd = 0,
        level0 = playerLevel(),
        guides = {}, acc = newAcc(), xpTotal = 0, killTotal = 0,
        steps = {}, kills = {}, events = {},
    }
end

-- ---------------------------------------------------------------- guide steps

-- A step's signature, the same as Route Splits' and the engine's make_splits.py: a letter and a number
-- for each line that's a quest, objective, level, trainer, hearth bind, hearth or flight path.
local QUEST_TAG = { accept = "A", turnin = "T", abandon = "B" }
local SIMPLE_TAG = { trainer = "R", home = "H", hs = "S", fp = "F" }
function Log.Signature(step)
    if type(step) ~= "table" or step.sticky or step.completewith or step.tip then return "" end
    local t = {}
    for _, e in ipairs(step.elements or {}) do
        local tag = e.tag
        if QUEST_TAG[tag] then
            local q = tag == "abandon" and e.ids and e.ids[1] or e.questId
            q = tonumber(q)
            if q then t[#t + 1] = QUEST_TAG[tag] .. math.abs(q) end
        elseif tag == "complete" then
            local q, k = tonumber(e.questId), tonumber(e.obj)
            if q and k then t[#t + 1] = "C" .. math.abs(q) .. "." .. k end
        elseif tag == "xp" then
            local lvl = tonumber(e.level)
            if lvl then t[#t + 1] = (e.reverseLogic and "Y" or "X") .. floor(math.abs(lvl)) end
        elseif SIMPLE_TAG[tag] then
            t[#t + 1] = SIMPLE_TAG[tag]
        end
    end
    return concat(t, " ")
end

local function guideIndex(key)
    local s = S.session
    for i, k in ipairs(s.guides) do
        if k == key then return i end
    end
    s.guides[#s.guides + 1] = key
    event("GD", #s.guides, key)
    return #s.guides
end

local function posOf()
    local p = S.pos
    if p then return p.inst, p.x, p.y end
end

local function dist(i1, x1, y1, i2, x2, y2)
    if not (i1 and i2 and x1 and x2) or i1 ~= i2 then return nil end
    return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local function openStep(guide, key, index, part)
    local step = guide.steps[index]
    local s = S.session
    local inst, x, y = posOf()
    local place = type(step) == "table" and P.placeOf(step) or nil
    S.openStep = step -- the step itself (kept out of the saved log)
    s.open = {
        key = key, g = guideIndex(key), idx = index,
        sig = Log.Signature(step), label = type(step) == "table" and P.labelOf(step, 60) or "",
        t0 = now(), acc = copyAcc(s.acc), xp0 = s.xpTotal, k0 = s.killTotal, pl0 = playerLevel(),
        inst0 = inst, x0 = x, y0 = y, part = part or nil,
        tinst = place and place.instance, tx = place and place.wx, ty = place and place.wy,
    }
end

-- How a step you've left ended, from what's ticked on it: done (RestedXP saw everything done),
-- tick (you ticked something off: a checkbox, Done, a line on the card), skip (moved on with
-- things left: Skip, RestedXP's menu), jump (the card's Shift-click), note (nothing to do on it).
local function howEnded(step)
    if S.manual and GetTime() - S.manualAt <= 3 then
        local m = S.manual
        if m == "skip" or m == "jump" then return m end
    end
    local n, completed, ticked = 0, 0, 0
    for _, el in ipairs(type(step) == "table" and step.elements or {}) do
        if not el.textOnly and not el.optional then
            n = n + 1
            if el.skip then ticked = ticked + 1 elseif el.completed then completed = completed + 1 end
        end
    end
    if n == 0 then return "note" end
    if ticked > 0 then return "tick" end
    if completed >= n then return "done" end
    return "skip"
end

local function closeStep(how, passed)
    local s = S.session
    local o = s and s.open
    if not o then return end
    s.open = nil
    -- RestedXP jumping to your saved step just after a guide shows up isn't a step you did.
    if o.part and now() - o.t0 < SETTLE and how ~= "end" then return end
    local a, a0 = s.acc, o.acc
    local inst, x, y = posOf()
    local plEnd = S.on and playerLevel() or s.plNow or playerLevel()
    local row = { o.g, o.idx, clean(o.sig), clean(o.label), n1(o.t0), n1(now()), how, passed or 0, o.part and 1 or 0 }
    for _, c in ipairs(CATS) do row[#row + 1] = n1((a[c] or 0) - (a0[c] or 0)) end
    row[#row + 1] = int(a.yd - (a0.yd or 0))
    row[#row + 1] = s.killTotal - o.k0
    row[#row + 1] = int(s.xpTotal - o.xp0)
    row[#row + 1] = n2(o.pl0)
    row[#row + 1] = n2(plEnd)
    local where = { o.inst0 or "", n1(o.x0), n1(o.y0), inst or "", n1(x), n1(y), o.tinst or "", n1(o.tx), n1(o.ty) }
    for i = 1, 9 do row[#row + 1] = where[i] end
    local direct = dist(o.inst0, o.x0, o.y0, o.tinst, o.tx, o.ty)
    row[#row + 1] = direct and int(direct) or -1
    row[#row + 1] = n1(a.mount - (a0.mount or 0))
    addRow(s.steps, row)
end
Log.CloseStep = closeStep

local function watchSteps()
    local s = S.session
    rxp = rxp or P.getRXP()
    local guide = rxp and rxp.currentGuide
    local cur = rxp and P.call(rxp.GetGuideProgress)
    if type(guide) ~= "table" or guide.empty or type(guide.steps) ~= "table" or type(cur) ~= "number" then
        local o = s.open
        local settling = o and o.resumed and GetTime() - (S.startedAt or 0) < SETTLE
        if o and not settling and (S.guideSeen or o.resumed) then
            closeStep(S.openStep and howEnded(S.openStep) == "done" and "done" or "guide")
        end
        return
    end
    local key = guide.key or guide.name
    local o = s.open
    -- Just after a reload RestedXP may still be loading the guide or jumping to your saved step:
    -- a step carried over from before the reload waits for it.
    local settling = o and o.resumed and GetTime() - (S.startedAt or 0) < SETTLE
    if o and o.key ~= key then
        if settling then return end
        closeStep(S.openStep and howEnded(S.openStep) == "done" and "done" or "guide")
        o = nil
    end
    if o and o.idx == cur then
        S.guideSeen = true
        o.resumed = nil
        S.openStep = guide.steps[cur]
        return
    end
    if settling then return end
    local part = not S.guideSeen -- the first step seen since logging started: you may be halfway through it
    if o then
        if cur > o.idx then
            closeStep(howEnded(guide.steps[o.idx]), cur - o.idx - 1)
        else
            closeStep("back")
        end
        part = false
    end
    S.manual = nil
    S.guideSeen = true
    openStep(guide, key, cur, part)
end

-- The card's Skip, Back and Shift-click jump say so here, since RestedXP can't tell them apart.
function Log.Manual(kind)
    S.manual, S.manualAt = kind, GetTime()
end

-- ---------------------------------------------------------------- where the time goes

local function onTaxi() return get(UnitOnTaxi, "player") and true or false end
local function playerDead() return get(UnitIsDeadOrGhost, "player") and true or false end

local function afk()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and get(C_ChatInfo.InChatMessagingLockdown) then return false end
    return get(UnitIsAFK, "player") and true or false
end

local function readPosition()
    if not (HBD and HBD.GetPlayerWorldPosition) then return nil end
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if ok and type(x) == "number" and type(y) == "number" and not secret(x) and not secret(y) then return x, y, inst end
end

-- One look: what you're doing, how far you moved, and the XP you gained since the last look.
local function sample(dt)
    local s = S.session
    local a = s.acc
    local x, y, inst = readPosition()
    local d, moved = 0, false
    if x then
        local p = S.pos
        if p and p.x and p.inst == inst then
            d = sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2)
            if d > TELEPORT then d = 0 end
        end
        s.pos = s.pos or {}
        S.pos = s.pos
        S.pos.x, S.pos.y, S.pos.inst = x, y, inst
        moved = d >= MOVE_MIN
    else
        local speed = get(GetUnitSpeed, "player") -- no position (an instance): the speed will do
        if speed and speed > 0 then
            moved, d = true, speed * dt
        end
    end
    local cat
    if S.loading or S.loadEnded then
        cat = "load"
        S.loadEnded = nil
    elseif onTaxi() then
        cat = "taxi"
    elseif playerDead() then
        cat = "dead"
    elseif S.inCombat then
        cat = "combat"
    elseif afk() then
        cat = "afk"
    elseif moved then
        cat = "move"
    elseif next(S.windows) then
        cat = "dialog"
    else
        cat = "still"
    end
    a[cat] = a[cat] + dt
    if cat == "move" then
        a.yd = a.yd + d
        if get(IsMounted) then a.mount = a.mount + dt end
    end
    S.cat = cat
    -- An NPC window whose closing went unseen: walking away for a few seconds ends the visit.
    if moved and next(S.windows) then
        S.walkedOff = (S.walkedOff or 0) + dt
        if S.walkedOff >= 3 then
            S.windows = {}
            if S.talk then S.talk.closing = now() end
        end
    else
        S.walkedOff = 0
    end
    -- Rest after a kill: standing still until you move on.
    for _, k in ipairs(S.pending) do
        if not k.stillDone then
            if cat == "still" then k.still = k.still + dt else k.stillDone = true end
        end
    end
    -- Flights.
    local taxi = cat == "taxi"
    if taxi ~= (S.taxi ~= nil) then
        if taxi then
            S.taxi = now()
            event("F", 1)
        else
            event("F", 0, n1(now() - S.taxi))
            S.taxi = nil
        end
    end
    -- XP gained, read each look so the order of the game's XP and level events doesn't matter.
    local lvl, xp, mx = get(UnitLevel, "player"), get(UnitXP, "player"), get(UnitXPMax, "player")
    if lvl and xp and mx then
        if S.lvl then
            if lvl == S.lvl and xp < S.xp and GetTime() - (S.xpDropAt or GetTime()) < 3 then
                S.xpDropAt = S.xpDropAt or GetTime() -- a ding the level hasn't caught up with yet
                return
            end
            if lvl == S.lvl and xp > S.xp then
                s.xpTotal = s.xpTotal + (xp - S.xp)
            elseif lvl > S.lvl then
                s.xpTotal = s.xpTotal + (S.mx - S.xp) + xp + (lvl - S.lvl - 1) * (S.mx + mx) / 2
            end
        end
        S.lvl, S.xp, S.mx, S.xpDropAt = lvl, xp, mx, nil
    end
end

-- ---------------------------------------------------------------- NPC visits

local function talkEnd()
    local t = S.talk
    if not t then return end
    S.talk = nil
    event("W", t.kind, n1((t.closing or now()) - t.start), t.quests)
end

local function window(kind, open)
    if open then
        S.windows[kind] = true
        local t = S.talk
        if not t then
            t = { start = now(), kind = kind, quests = 0 }
            S.talk = t
        end
        t.closing = nil
        if (TALK_RANK[kind] or 0) > (TALK_RANK[t.kind] or 0) then t.kind = kind end
    else
        S.windows[kind] = nil
        if S.talk and not next(S.windows) then S.talk.closing = now() end
    end
end

-- ---------------------------------------------------------------- kills

local function groupSize()
    local n = GetNumGroupMembers and get(GetNumGroupMembers) or 0
    return max(1, n or 0)
end

local function guidOf(unit)
    local g = get(UnitGUID, unit)
    return type(g) == "string" and g or nil
end

local function npcOf(guid)
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return kind, tonumber(id)
end

-- The unit's GUID when it's an NPC you could fight.
local function hostileNpc(unit)
    if not get(UnitExists, unit) then return nil end
    if get(UnitIsPlayer, unit) or get(UnitPlayerControlled, unit) then return nil end
    if not get(UnitCanAttack, "player", unit) then return nil end
    local guid = guidOf(unit)
    if not guid then return nil end
    local kind = npcOf(guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return guid
end

local function onThreatList(unit)
    if get(UnitThreatSituation, "player", unit) ~= nil then return true end
    return get(UnitIsUnit, unit .. "target", "player") and true or false
end

local function unitTokens()
    local list = { "target", "softenemy", "focus", "mouseover" }
    for token in pairs(S.plates) do list[#list + 1] = token end
    return list
end

local function aliveEngaged()
    for _, m in pairs(S.mobs) do
        if not m.dead then return true end
    end
    return false
end

local function finalizeKill(k)
    local s = S.session
    addRow(s.kills, {
        n1(k.t), k.g, k.step, k.npc or 0, clean(k.name), k.ml or "", k.cls or "", n2(k.pl),
        k.fight and n1(k.fight) or -1, k.seq and n1(k.seq) or -1, k.pull or 1,
        k.xp or (k.tap == 0 and 0 or -1), k.rested or 0, k.tap, k.grp,
        k.inst or "", n1(k.x), n1(k.y),
        k.gap and n1(k.gap) or -1, k.gap and n1(k.gmove) or "", k.gap and int(k.gyd) or "", k.gap and n1(k.gother) or "",
        k.loot and n1(k.loot) or -1, n1(k.still), k.src,
    })
end

local function finalizePending(before)
    local keep = {}
    for _, k in ipairs(S.pending) do
        if not before or k.t <= before then finalizeKill(k) else keep[#keep + 1] = k end
    end
    S.pending = keep
end
Log.FinalizePending = finalizePending

local function engage(guid, unit)
    local t = now()
    local c = S.combat
    local first = c and c.engaged == 0
    local fresh = not aliveEngaged()
    if fresh then finalizePending(t) end
    local m = {
        guid = guid, engaged = (first and c.start) or t, combat = c and c.id,
        pl = playerLevel(), grp = groupSize(),
    }
    local _, npc = npcOf(guid)
    m.npc = npc
    m.name = get(UnitName, unit)
    m.ml = get(UnitLevel, unit)
    local cls = get(UnitClassification, unit)
    m.cls = cls and (CLASS_CODE[cls] or cls) or nil
    m.tap = get(UnitIsTapDenied, unit) and 0 or 1
    m.inst, m.x, m.y = posOf()
    if fresh and S.lastDeath and m.engaged - S.lastDeath.t <= GAP_MAX then
        local a, a0 = S.session.acc, S.lastDeath.acc
        m.gap = max(0, m.engaged - S.lastDeath.t)
        m.gmove = a.move - a0.move
        m.gyd = a.yd - a0.yd
        local other = 0
        for _, cat in ipairs(OTHER) do other = other + (a[cat] - a0[cat]) end
        m.gother = other
    end
    if c then c.engaged = c.engaged + 1 end
    S.mobs[guid] = m
    return m
end

-- A kill: its row waits a little for the XP line, the loot and the rest after it.
local function killed(m, src, unit)
    local t = now()
    local s = S.session
    m.dead, m.diedAt = true, GetTime()
    if unit then
        local tap = get(UnitIsTapDenied, unit)
        if tap ~= nil then m.tap = tap and 0 or 1 end
    end
    local c = S.combat
    local seq
    if c and m.combat == c.id then
        seq = t - max(c.start, c.lastDeath or c.start)
        c.lastDeath = t
    end
    local open = s.open
    local k = {
        guid = m.guid, t = t, g = open and open.g or 0, step = open and open.idx or 0,
        npc = m.npc, name = m.name, ml = m.ml, cls = m.cls, pl = m.pl or playerLevel(),
        fight = m.engaged and (t - m.engaged) or nil, seq = seq, pull = c and m.combat == c.id and c.engaged or 1,
        tap = m.tap or 1, grp = m.grp or groupSize(), inst = m.inst, x = m.x, y = m.y,
        gap = m.gap, gmove = m.gmove, gyd = m.gyd, gother = m.gother,
        still = 0, src = src, xp = m.xp, rested = m.rested,
    }
    S.pending[#S.pending + 1] = k
    s.killTotal = s.killTotal + 1
    S.lastDeath = { t = t, acc = copyAcc(s.acc) }
    return k
end

local function died(guid, src, unit)
    local m = guid and S.mobs[guid]
    if not m or m.dead then return end
    return killed(m, src, unit)
end

-- A kill nobody saw engaged (one hit, no nameplate): from what the game said about it.
local function adopt(guid, name)
    local m = { guid = guid, name = name, pl = playerLevel(), grp = groupSize() }
    local c = S.combat
    if c and (not c.ended or now() - c.ended < XP_WINDOW) then
        m.combat = c.id
        if c.engaged == 0 then m.engaged = c.start end
        c.engaged = c.engaged + 1
    end
    m.inst, m.x, m.y = posOf()
    if guid then
        local _, npc = npcOf(guid)
        m.npc = npc
        S.mobs[guid] = m
    end
    return m
end

-- Engaged mobs come into view as targets and nameplates; check each one you can see.
local function scan()
    for _, unit in ipairs(unitTokens()) do
        local guid = hostileNpc(unit)
        if guid then
            local m = S.mobs[guid]
            if m and not m.dead then
                local tap = get(UnitIsTapDenied, unit)
                if tap ~= nil then m.tap = tap and 0 or 1 end
                if get(UnitIsDead, unit) then died(guid, "u", unit) end
            elseif not m and S.inCombat and not get(UnitIsDead, unit) and onThreatList(unit) then
                engage(guid, unit)
            end
        end
    end
end
Log.Scan = scan

local function xpLine(text)
    if type(text) ~= "string" or secret(text) then return end
    local name = text:match("^(.-) dies")
    if not name then return end -- quest and exploration XP: logged with their own events
    local xp = tonumber(text:match("(%d+) experience"))
    local rested = tonumber(text:match("%+(%d+)")) or 0
    local t = now()
    scan() -- a corpse in view settles which mob it was
    -- A kill already seen, waiting for its XP (one seen only by its GUID has no name yet).
    for i = #S.pending, 1, -1 do
        local k = S.pending[i]
        if not k.xp and (k.name == name or k.name == nil) and t - k.t <= XP_WINDOW then
            k.xp, k.rested = xp, rested
            k.name = k.name or name
            return
        end
    end
    -- A mob you're fighting that hasn't been seen dying yet: the one engaged first.
    local pick
    for _, m in pairs(S.mobs) do
        if not m.dead and m.name == name and (not pick or (m.engaged or t) < (pick.engaged or t)) then pick = m end
    end
    if pick then
        pick.xp, pick.rested = xp, rested
        died(pick.guid, "x")
        return
    end
    local m = adopt(nil, name)
    m.xp, m.rested = xp, rested
    killed(m, "x")
end
Log.XPLine = xpLine

-- ---------------------------------------------------------------- the driver

local driver = CreateFrame("Frame")
driver:Hide()
Log.driver = driver

local function tick()
    if not S.on then return end
    local t = GetTime()
    local dt = t - (S.lastTick or t)
    S.lastTick = t
    local s = S.session
    if not s then return end
    if dt > 0 then sample(dt) end
    watchSteps()
    if S.inCombat or next(S.mobs) then scan() end
    -- Mobs that got away (evaded, or you ran), and dead ones done with.
    local c = S.combat
    for guid, m in pairs(S.mobs) do
        if m.dead then
            if t - m.diedAt > PENDING_MAX then S.mobs[guid] = nil end
        elseif not S.inCombat and c and c.ended and now() - c.ended > MOB_FORGET then
            S.mobs[guid] = nil
        end
    end
    local keep = {}
    for _, k in ipairs(S.pending) do
        if now() - k.t > PENDING_MAX then finalizeKill(k) else keep[#keep + 1] = k end
    end
    S.pending = keep
    if S.talk and S.talk.closing and now() - S.talk.closing >= TALK_GAP then talkEnd() end
    s.clockEnd = now()
    s.lastEpoch = epoch()
    s.plNow = playerLevel()
end
Log.Tick = tick

local sinceTick = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + (elapsed or 0)
    if sinceTick >= TICK - 1e-6 then
        sinceTick = 0
        tick()
    end
end)

local handlers = {}

function handlers.PLAYER_LOGOUT()
    finalizePending()
    talkEnd()
    local s = S.session
    if s then
        s.clockEnd = now()
        s.lastEpoch = epoch()
    end
    -- The step you're on stays open: after a reload the log carries on with it.
end

function handlers.TIME_PLAYED_MSG(total)
    total = tonumber(total)
    local s = S.session
    if total and s and not s.played0 then s.played0 = floor(total - now() + 0.5) end
end

function handlers.PLAYER_REGEN_DISABLED()
    for guid, m in pairs(S.mobs) do
        if not m.dead then S.mobs[guid] = nil end
    end
    S.inCombat = true
    S.combatId = (S.combatId or 0) + 1
    S.combat = { id = S.combatId, start = now(), engaged = 0 }
    scan()
end

function handlers.PLAYER_REGEN_ENABLED()
    scan() -- the last mob's death, if it's still showing
    S.inCombat = false
    if S.combat then S.combat.ended = now() end
end

function handlers.PLAYER_TARGET_CHANGED() if S.inCombat then scan() end end
function handlers.UNIT_THREAT_LIST_UPDATE() if S.inCombat then scan() end end

local lastCombatScan = 0
function handlers.UNIT_COMBAT()
    if not S.inCombat then return end
    local t = GetTime()
    if t - lastCombatScan < 0.05 then return end
    lastCombatScan = t
    scan()
end

function handlers.NAME_PLATE_UNIT_ADDED(token)
    if type(token) ~= "string" then return end
    S.plates[token] = true
    if S.inCombat then scan() end
end

function handlers.NAME_PLATE_UNIT_REMOVED(token)
    if type(token) ~= "string" then return end
    local guid = hostileNpc(token)
    if guid and S.mobs[guid] and get(UnitIsDead, token) then died(guid, "u", token) end
    S.plates[token] = nil
end

function handlers.UNIT_DIED(guid)
    if type(guid) == "string" and not secret(guid) then died(guid, "d") end
end

function handlers.PARTY_KILL(attacker, target)
    if type(target) ~= "string" or secret(target) then return end
    if S.mobs[target] then
        died(target, "k")
        return
    end
    -- Your killing blow on something nobody saw engaged.
    local me = guidOf("player")
    if not (me and attacker == me) then return end
    local kind, npc = npcOf(target)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    -- Its XP line may have come first and logged it already.
    local t = now()
    for i = #S.pending, 1, -1 do
        local k = S.pending[i]
        if not k.guid and k.src == "x" and t - k.t <= XP_WINDOW then
            k.guid, k.npc = target, npc
            S.mobs[target] = { guid = target, dead = true, diedAt = GetTime() }
            return
        end
    end
    local name
    for _, unit in ipairs(unitTokens()) do
        if guidOf(unit) == target then name = get(UnitName, unit) end
    end
    killed(adopt(target, name), "k")
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text) xpLine(text) end

function handlers.LOOT_OPENED(_, isFromItem)
    if not isFromItem then S.lootOpen = true end
end

function handlers.LOOT_CLOSED()
    if not S.lootOpen then return end
    S.lootOpen = nil
    local t = now()
    for _, k in ipairs(S.pending) do
        if not k.loot then
            k.loot = t - k.t
            return
        end
    end
end

function handlers.QUEST_ACCEPTED(a, b)
    local q = tonumber(b) or tonumber(a) -- (questID) on Forever, (logIndex, questID) on older clients
    if not q then return end
    event("A", q)
    if S.talk then S.talk.quests = S.talk.quests + 1 end
end

function handlers.QUEST_TURNED_IN(q, xp)
    event("T", tonumber(q), tonumber(xp) or 0)
    if S.talk then S.talk.quests = S.talk.quests + 1 end
end

function handlers.PLAYER_LEVEL_UP(level) event("L", tonumber(level)) end

function handlers.PLAYER_DEAD()
    if S.deadAt then return end
    S.deadAt = now()
    event("D")
    for guid, m in pairs(S.mobs) do
        if not m.dead then S.mobs[guid] = nil end
    end
end

-- Back on your feet: resurrected where you died, at your corpse, or by the spirit healer.
local function revived()
    if not S.deadAt or get(UnitIsDeadOrGhost, "player") then return end
    event("G", n1(now() - S.deadAt))
    S.deadAt = nil
end
handlers.PLAYER_ALIVE = revived
handlers.PLAYER_UNGHOST = revived

function handlers.ZONE_CHANGED_NEW_AREA()
    local z = get(GetRealZoneText)
    if z and z ~= "" then event("Z", z) end
end

function handlers.LOADING_SCREEN_ENABLED()
    S.loading = true
    S.loadingAt = now()
end

function handlers.LOADING_SCREEN_DISABLED()
    if S.loading then event("LS", n1(now() - (S.loadingAt or now()))) end
    S.loading = false
    S.loadEnded = true
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if unit == "player" and not secret(spellID) and spellID == HEARTHSTONE then event("H") end
end

function handlers.PLAYER_FLAGS_CHANGED(unit)
    if unit ~= "player" then return end
    local a = afk()
    if a ~= (S.afk or false) then
        S.afk = a
        event("AFK", a and 1 or 0)
    end
end

local events = CreateFrame("Frame")
Log.events = events
events:SetScript("OnEvent", function(_, e, ...)
    local w = WINDOW_EVENTS[e]
    if w then
        window(w[1], w[2])
    elseif handlers[e] then
        handlers[e](...)
    end
end)

-- ---------------------------------------------------------------- on and off

local function startSession()
    local L = store()
    local key = character()
    local t = epoch()
    local last = L.sessions[#L.sessions]
    if last and last.char == key and last.lastEpoch and t - last.lastEpoch <= RESUME and not S.forceNew then
        -- Carry on, after a reload or a quick relog: the time away counts as a loading screen.
        S.session = last
        S.clockBase, S.clockAt = t - last.started, GetTime()
        local away = max(0, Log.Now() - (last.clockEnd or 0))
        last.acc.load = (last.acc.load or 0) + away
        last.acc.yd, last.acc.mount = last.acc.yd or 0, last.acc.mount or 0
        for _, c in ipairs(CATS) do last.acc[c] = last.acc[c] or 0 end
        if last.open then last.open.resumed = true end -- it carries on if RestedXP is still on it
        S.pos = last.pos
        event("R", n1(away))
    else
        -- A step left open by the last session ends where that session did.
        if last and last.open then
            local wasOn = S.on
            S.on = false
            S.session, S.pos = last, last.pos
            S.clockBase, S.clockAt = last.clockEnd or 0, GetTime()
            closeStep("end")
            S.on = wasOn
        end
        local s = newSession(t)
        L.sessions[#L.sessions + 1] = s
        S.session = s
        S.clockBase, S.clockAt = 0, GetTime()
        S.pos = nil
    end
    S.guideSeen = false
    S.startedAt = GetTime()
    S.forceNew = nil
    S.lvl, S.lastTick, S.lastDeath = nil, GetTime(), nil
    S.mobs, S.pending, S.windows, S.talk, S.taxi = {}, {}, {}, nil, nil
    S.combat, S.inCombat = nil, get(UnitAffectingCombat, "player") and true or false
    if S.inCombat then
        S.combatId = (S.combatId or 0) + 1
        S.combat = { id = S.combatId, start = now(), engaged = 0 }
    end
    S.afk = afk()
end

function Log.Start()
    if S.on then return end
    db = P.db()
    HBD = P.hbd()
    rxp = P.getRXP()
    if not db then return end
    countRows()
    startSession()
    S.on = true
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = get(C_NamePlate.GetNamePlates) or {}
        for _, plate in ipairs(plates) do
            local token = plate.namePlateUnitToken or plate.unitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if type(token) == "string" then S.plates[token] = true end
        end
    end
    event("ON")
    sinceTick = 0
    driver:Show()
end

-- reason "end": the open step is left unfinished in the log.
function Log.Stop()
    if not S.on then return end
    finalizePending()
    talkEnd()
    closeStep("end")
    event("OFF")
    local s = S.session
    if s then
        s.clockEnd = now()
        s.lastEpoch = epoch()
    end
    S.on = false
    events:UnregisterAllEvents()
    driver:Hide()
end

function Log.IsOn() return S.on end

-- Settings changed: start or stop with the switch.
function Log.Apply()
    db = P.db()
    if not db then return end
    if db.logTimes and not S.on then
        Log.Start()
    elseif not db.logTimes and S.on then
        Log.Stop()
    end
end

-- Starts a new session now (a fresh character, or a run you want kept apart).
function Log.NewSession()
    local was = S.on
    if was then Log.Stop() end
    S.forceNew = true
    if was then
        Log.Start()
    else
        S.session = nil
    end
end

-- Deletes everything logged. Logging carries on (in a new session) if it was on.
function Log.Clear()
    local was = S.on
    if was then
        events:UnregisterAllEvents()
        driver:Hide()
        S.on = false
    end
    local L = store()
    L.sessions = {}
    S.session = nil
    countRows()
    S.full = false
    if was then
        S.forceNew = true
        Log.Start()
    end
end

function Log.Stats()
    local L = store()
    local st = { sessions = #L.sessions, steps = 0, kills = 0, events = 0, rows = S.rows, bytes = S.bytes, full = S.full }
    for _, s in ipairs(L.sessions) do
        st.steps = st.steps + #(s.steps or {})
        st.kills = st.kills + #(s.kills or {})
        st.events = st.events + #(s.events or {})
    end
    st.pending = #S.pending
    st.clock = S.on and Log.Now() or nil
    return st
end

local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

function Log.StatusText()
    local st = Log.Stats()
    local saved = ("%s, %s in %s (%.0f KB)"):format(plural(st.steps, "step"), plural(st.kills + st.pending, "kill"),
        plural(st.sessions, "session"), st.bytes / 1024)
    if st.full then return "Log full: read it with tools/timing_log.py, then clear it. " .. saved .. "." end
    if S.on then
        local m = floor((st.clock or 0) / 60)
        local into = m < 60 and ("%d min"):format(m) or ("%d h %02d min"):format(floor(m / 60), m % 60)
        return ("Logging, %s into this session. Saved: %s."):format(into, saved)
    end
    if st.sessions == 0 then return "Off. Nothing logged yet." end
    return "Off. Saved: " .. saved .. "."
end

function Log.Debug()
    local st = Log.Stats()
    msg(("timing log %s · %s"):format(S.on and "|cff00ff00on|r" or "|cffff5555off|r", Log.StatusText()))
    if S.on then
        local o = S.session and S.session.open
        msg(("now: %s · in combat %s · mobs engaged %d · kills waiting %d · step %s"):format(tostring(S.cat or "?"),
            tostring(S.inCombat), (function() local n = 0 for _ in pairs(S.mobs) do n = n + 1 end return n end)(),
            st.pending, o and tostring(o.idx) or "none"))
    end
end

function Log.Init()
    db = P.db()
    if not db then return end
    store()
    countRows()
    if db.logTimes then
        Log.Start()
        msg("logging step and kill times for the route engine (/rxpe log to stop). " .. Log.StatusText())
    end
end

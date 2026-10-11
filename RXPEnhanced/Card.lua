-- RXP Enhanced: the guide card. A compact, clean view of RestedXP's current step that can stand in
-- for RestedXP's own window.
--
-- RestedXP keeps doing all the work: tracking quests, completing steps, its arrow, and its item and
-- targeting buttons. The card only reads RestedXP's state. The few things it does to RestedXP go
-- through RestedXP's own paths: Back, Skip and Jump call its SetStep (what its "Go to step" menu
-- does), and ticking a line does what RestedXP's checkboxes do.
--
-- RestedXP's window can't simply be hidden: hiding it pauses RestedXP (its OnHide handler marks it
-- hidden, and its step checks run on that window's scripts). So the card shrinks it to nothing and
-- makes it invisible instead, and puts it back when the card goes away.

local ADDON_NAME = ...
local NS = _G.RXPEnhanced
if not (NS and NS.private) then return end
local P = NS.private
local Card = {}
NS.Card = Card

local floor, max, min = math.floor, math.max, math.min
local MEDIA = "Interface\\AddOns\\" .. (ADDON_NAME or "RXPEnhanced") .. "\\Media\\"
local FONTS = {
    regular = MEDIA .. "Inter-Regular.ttf",
    medium = MEDIA .. "Inter-Medium.ttf",
    semibold = MEDIA .. "Inter-SemiBold.ttf",
}
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local ICON_FILE = MEDIA .. "icons"
local PANEL_FILE = MEDIA .. "panel"
local BORDER_FILE = MEDIA .. "border"
local LOOKBACK_SKIPS = 15 -- a jump further than this is someone picking a step, not RestedXP skipping
local SETTLE_SECONDS = 5 -- RestedXP moves to your saved step just after a guide loads: not a skip
local NOTICE_SECONDS = 45

-- Positions in icons.tga (an 8 x 8 grid), in the order tools/make_assets.py draws them.
local ICON_ORDER = {
    "accept", "turnin", "complete", "goto", "talk", "fly", "fp", "hs",
    "home", "train", "vendor", "buy", "xp", "use", "collect", "abandon",
    "tip", "warn", "check", "circle", "left", "right", "up", "down",
    "settings", "eye", "eyeoff", "info", "close", "skip", "menu", "checkcircle",
    "dashed", "footprints", "lock", "hand", "scroll", "hourglass", "undo", "navigation",
}
local ICON_INDEX = {}
for i, name in ipairs(ICON_ORDER) do ICON_INDEX[name] = i - 1 end

local rgb = P.hexToRGB
-- Two looks. Dark: a quiet surface with three text levels (primary 17:1, secondary 8:1, tertiary
-- 4.8:1 against it). Glass: white at 10% over the world, as in the Figma frame. WoW can't blur what's
-- behind a frame, so a light dark layer underneath stands in for the blur and keeps text readable
-- over busy scenery; the edge is brighter and text gets a soft shadow.
local THEMES = {
    dark = {
        corner = 8,
        layers = { { color = { 0.067, 0.075, 0.090, 0.94 } } },
        border = { 1, 1, 1, 0.09 },
        divider = { 1, 1, 1, 0.07 },
        hover = { 1, 1, 1, 0.06 },
        text1 = rgb("f2f4f6"), text2 = rgb("a9b0b8"), text3 = rgb("7d848c"),
    },
    glass = {
        corner = 12,
        layers = {
            { color = { 0.02, 0.03, 0.04, 0.24 } },
            { color = { 1, 1, 1, 0.12 }, top = { 1, 1, 1, 0.19 }, bottom = { 1, 1, 1, 0.09 } },
        },
        border = { 1, 1, 1, 0.22 },
        divider = { 1, 1, 1, 0.14 },
        hover = { 1, 1, 1, 0.12 },
        text1 = rgb("ffffff"), text2 = rgb("e3e7ec"), text3 = rgb("bcc3cb"),
        shadow = true,
    },
}
Card.THEMES = THEMES
local T = THEMES.dark -- the current look, picked on each draw
local C = { success = rgb("6fd08c"), warn = rgb("f2c75c") }
local TINT = {
    quest = rgb("f2c75c"), combat = rgb("f0806a"), travel = rgb("7fb8f0"), talk = rgb("6fd08c"),
    trade = rgb("c9ced4"), xp = rgb("b58cff"),
}
-- RestedXP element tag -> icon and tint.
local TAG = {
    accept = { "accept", "quest" }, daily = { "accept", "quest" },
    turnin = { "turnin", "quest" }, dailyturnin = { "turnin", "quest" },
    complete = { "complete", "combat" }, combat = { "complete", "combat" }, reputation = { "complete", "combat" },
    ["goto"] = { "goto", "travel" }, waypoint = { "goto", "travel" },
    fly = { "fly", "travel" }, fp = { "fp", "travel" }, hs = { "hs", "travel" }, home = { "home", "travel" },
    train = { "train", "trade" }, trainer = { "train", "trade" },
    vendor = { "vendor", "trade" }, buy = { "buy", "trade" },
    collect = { "collect", "trade" }, collectmultiple = { "collect", "trade" }, equip = { "collect", "trade" },
    use = { "use", "trade" }, xp = { "xp", "xp" }, abandon = { "abandon", "trade" },
}
-- Colours for RestedXP's text codes (friendly NPC, enemy, loot, warning, pick-up, buy).
local PALETTES = {
    card = { FRIENDLY = "6fd08c", ENEMY = "f0806a", LOOT = "5cc8e0", WARN = "f2c75c", PICK = "d08cf0", BUY = "8fcb6b" },
    -- Okabe-Ito hues, lightened for a dark background: friendly and enemy differ for every kind
    -- of colour blindness.
    safe = { FRIENDLY = "56b4e9", ENEMY = "f07e3a", LOOT = "3cc2a0", WARN = "f0e442", PICK = "e58fc0", BUY = "d9d9d9" },
}
local COLOR_KEYS = { "FRIENDLY", "ENEMY", "LOOT", "WARN", "PICK", "BUY" }
Card.PALETTES = PALETTES

local db, rxp
local function ready()
    db = P.db()
    rxp = P.getRXP()
    return db ~= nil and rxp ~= nil
end

-- ---------------------------------------------------------------- reading RestedXP

local function recolor(text)
    local palette = PALETTES[db.cardPalette]
    if not palette then return text end -- "rxp": RestedXP's own colours
    local gtc = type(rxp.guideTextColors) == "table" and rxp.guideTextColors or {}
    local byHex = {}
    for _, key in ipairs(COLOR_KEYS) do
        local code = "RXP_" .. key .. "_"
        local current, default = gtc[code], type(gtc.default) == "table" and gtc.default[code]
        if type(current) == "string" then byHex[current:upper()] = key end
        if type(default) == "string" then byHex[default:upper()] = key end
    end
    text = text:gsub("|cRXP_(%u+)_", function(key)
        return "|cff" .. (palette[key] or "f2f4f6")
    end)
    text = text:gsub("|c(%x%x%x%x%x%x%x%x)", function(hex)
        local key = byHex[hex:upper()]
        if key then return "|cff" .. palette[key] end
    end)
    return text
end

-- An element's text as RestedXP shows it, or nil when RestedXP shows nothing for it.
local function guideText(el)
    local t = el and el.text
    if type(t) ~= "string" or t == "" or t == " " then return nil end
    local L = type(rxp.locale) == "table" and rxp.locale.Get
    if type(L) == "function" then
        local ok, r = pcall(L, t)
        if ok and type(r) == "string" then t = r end
    end
    if type(rxp.ReplaceNpcIds) == "function" then
        local ok, r = pcall(rxp.ReplaceNpcIds, t, el)
        if ok and type(r) == "string" then t = r end
    end
    t = t:gsub("\\n", "\n"):gsub("^%s*>>%s*", "")
    if not el.tag and not el.textOnly then t = t:gsub("^%+", "") end
    if t:match("^%s*$") then return nil end
    return recolor(t)
end

local function isDone(el) return el.completed or el.skip end

local function questName(id)
    if not id then return "that quest" end
    local name = P.call(rxp.GetQuestName, id)
    if type(name) ~= "string" or name == "" then
        name = C_QuestLog and P.call(C_QuestLog.GetTitleForQuestID, id)
    end
    return (type(name) == "string" and name ~= "") and name or ("quest " .. tostring(id))
end

local function commas(n)
    local s = tostring(floor(n))
    while true do
        local done
        s, done = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if done == 0 then return s end
    end
end

local function questLogFull()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetMaxNumQuestsCanAccept) then return false end
    local _, numQuests = P.call(C_QuestLog.GetNumQuestLogEntries)
    local maxQuests = P.call(C_QuestLog.GetMaxNumQuestsCanAccept)
    if type(numQuests) == "number" and type(maxQuests) == "number" and maxQuests > 0 and numQuests >= maxQuests then
        return true, numQuests, maxQuests
    end
    return false
end

local function distanceTo(el)
    local HBD = P.hbd()
    if not (HBD and type(el) == "table" and el.wx and el.wy) then return nil end
    local ok, d = pcall(function()
        local x, y, instance = HBD:GetPlayerWorldPosition()
        if not (x and y and instance == el.instance) then return nil end
        local _, dist = HBD:GetWorldVector(instance, x, y, el.wx, el.wy)
        return dist
    end)
    if ok and type(d) == "number" then return floor(d + 0.5) end
end

-- Why an element isn't done yet. The second value is true for things that block it outright
-- (they're also shown on the card as a warning).
local function reasonFor(el)
    local tag, q = el.tag, el.questId
    if tag == "accept" or tag == "daily" then
        if P.onQuest(q) or P.turnedIn(q) then return nil end
        local full, n, m = questLogFull()
        if full then return ("Your quest log is full (%d/%d). Finish or abandon a quest first."):format(n, m), true end
        return "Not picked up yet. Talk to the quest giver."
    elseif tag == "turnin" or tag == "dailyturnin" then
        if P.turnedIn(q) then return nil end
        if not P.onQuest(q) then return ("%s isn't in your quest log."):format(questName(q)), true end
        if not P.questComplete(q) then return ("%s isn't finished yet."):format(questName(q)) end
        return "Ready. Talk to the quest giver to turn it in."
    elseif tag == "complete" then
        if P.turnedIn(q) then return nil end
        if not P.onQuest(q) then
            if el.skipIfMissing then return nil end
            return ("You don't have %s."):format(questName(q)), true
        end
        local list = C_QuestLog and C_QuestLog.GetQuestObjectives and P.call(C_QuestLog.GetQuestObjectives, q)
        local o = type(list) == "table" and list[tonumber(el.obj) or 0]
        if type(o) == "table" then
            if o.finished then return nil end
            if type(o.text) == "string" and o.text ~= "" then return o.text end
        end
        if P.questComplete(q) then return nil end
        return "Objective not done yet."
    elseif tag == "goto" or tag == "waypoint" then
        local d, r = distanceTo(el), tonumber(el.radius)
        if d and r then return ("%d yd away. It ticks off within %d yd."):format(d, r) end
        if d then return ("%d yd away."):format(d) end
        return "In another zone. Follow the arrow."
    elseif tag == "xp" then
        local target, level = tonumber(el.level), UnitLevel("player") or 0
        if target and not el.reverseLogic then
            if level >= target then return nil end
            if level == target - 1 then
                local xp, maxXP = P.call(UnitXP, "player"), P.call(UnitXPMax, "player")
                if type(xp) == "number" and type(maxXP) == "number" and maxXP > xp then
                    return ("Level %d: %s XP to level %d."):format(level, commas(maxXP - xp), target)
                end
            end
            return ("Level %d of %d."):format(level, target)
        end
    elseif not tag then
        return "Tick it off when it's done."
    end
    return "Not done yet."
end
Card.reasonFor = reasonFor

local function textIcon(text, step)
    local lower = (text or ""):lower()
    if lower:find("^talk") or lower:find("^speak") then return "talk", "talk" end
    if lower:find("^kill") or lower:find("^slay") or lower:find("^grind") then return "complete", "combat" end
    if lower:find("^loot") or lower:find("^collect") or lower:find("^pick up") then return "collect", "trade" end
    if step and P.placeOf(step) then return "footprints", "travel" end
    return "navigation", "travel"
end

-- The icon for a whole step: its first tagged line, else a guess from its text.
local function stepIcon(step)
    for _, el in ipairs(step.elements or {}) do
        local t = el.tag and TAG[el.tag]
        if t and el.tag ~= "goto" and el.tag ~= "waypoint" and guideText(el) then return t[1], t[2] end
    end
    for _, el in ipairs(step.elements or {}) do
        local s = guideText(el)
        if s then return textIcon(P.plain(s), step) end
    end
    return textIcon("", step)
end

local function iconFor(item, step)
    local t = item.el.tag and TAG[item.el.tag]
    if t then return t[1], t[2] end
    return textIcon(P.plain(item.text), step)
end

-- What the card shows for RestedXP's current step.
local function buildCurrent(model, step)
    local items = {}
    if not (step.hidewindow or step.hidetip) then
        for _, el in ipairs(step.elements or {}) do
            local text = guideText(el)
            if text then items[#items + 1] = { el = el, text = text } end
        end
    end
    -- The step's instruction (">>Talk to ..."), and the first thing still to do.
    local instruction, todo
    for _, it in ipairs(items) do
        local tag = it.el.tag
        if not instruction and it.el.textOnly and tag ~= "goto" and tag ~= "waypoint" then instruction = it end
        if not todo and not it.el.textOnly and not isDone(it.el) and tag ~= "goto" and tag ~= "waypoint" then todo = it end
    end
    -- An objective step reads best led by its instruction ("Kill ...") with the counts under it;
    -- anything else is led by the next thing to do ("Turn in ..."), with the instruction as context.
    local headline, context
    local objective = todo and (todo.el.tag == "complete" or todo.el.tag == "combat")
    if todo and not objective then
        headline, context = todo, instruction
    elseif instruction then
        headline = instruction
    else
        headline = todo or items[1]
    end
    if headline then
        model.headline = headline.text
        local leader = (headline == instruction and todo) or headline
        model.icon, model.tint = iconFor(leader, step)
    else
        model.headline = step.title or ("Step " .. tostring(step.index or "?"))
        model.icon, model.tint = stepIcon(step)
    end
    model.context = context and context.text

    -- Distance: to where RestedXP's arrow points if that's this step, else this step's place.
    local arrowTarget = _G.RXPG_ARROW and _G.RXPG_ARROW.element
    local target = (type(arrowTarget) == "table" and arrowTarget.step == step) and arrowTarget or nil
    if not target then
        for _, el in ipairs(step.elements or {}) do
            if el.wx and el.wy and not isDone(el) and not el.hidePin then target = el break end
        end
    end
    target = target or P.placeOf(step)
    model.target = target
    model.distance = target and distanceTo(target)

    model.rows, model.reasons, model.warnings = {}, {}, {}
    for _, it in ipairs(items) do
        local el = it.el
        if it ~= headline and it ~= context then
            model.rows[#model.rows + 1] = {
                text = it.text, el = el,
                plainLine = el.textOnly and true or false,
                done = (not el.textOnly) and isDone(el) and true or false,
                clickable = not el.textOnly and not el.optional,
            }
        end
        if not el.textOnly and not isDone(el) then
            local reason, blocking = reasonFor(el)
            if reason then
                model.reasons[#model.reasons + 1] = { what = P.plain(it.text), why = reason }
                if blocking then model.warnings[#model.warnings + 1] = reason end
            end
        end
    end
    model.headlineEl = headline and not headline.el.textOnly and headline.el or nil
end

-- Steps RestedXP has on the go besides the current one: the open #completewith steps ("along the
-- way"), each with all of its lines, and RestedXP's tip last.
local function buildAlong(model, current)
    model.along = {}
    local active = rxp.RXPFrame and rxp.RXPFrame.activeSteps
    if type(active) ~= "table" then return end
    local tips = {}
    for _, step in ipairs(active) do
        if step ~= current and not step.hidewindow and not step.hidetip then
            local block = { rows = {}, tip = step.tip and true or false, index = step.index }
            for _, el in ipairs(step.elements or {}) do
                local text = guideText(el)
                if text then
                    if el.textOnly and not block.title and el.tag ~= "goto" and el.tag ~= "waypoint" then
                        block.title = text
                    else
                        block.rows[#block.rows + 1] = {
                            text = text, el = el,
                            plainLine = el.textOnly and true or false,
                            done = (not el.textOnly) and isDone(el) and true or false,
                            clickable = not el.textOnly and not el.optional,
                        }
                    end
                end
            end
            if block.title or #block.rows > 0 then
                local lead
                for _, r in ipairs(block.rows) do
                    if not r.plainLine and r.el.tag then lead = r break end
                end
                if block.tip then
                    block.icon, block.tint = "tip", "quest"
                elseif lead then
                    block.icon, block.tint = iconFor(lead, step)
                else
                    block.icon, block.tint = textIcon(P.plain(block.title or block.rows[1].text), step)
                end
                if block.tip then tips[#tips + 1] = block else model.along[#model.along + 1] = block end
            end
        end
    end
    for _, b in ipairs(tips) do model.along[#model.along + 1] = b end
end

-- The steps coming up, as RestedXP's step list would show them, minus the ones it will skip.
local UPCOMING_MAX = 30
local function buildUpcoming(model, guide, cur)
    model.upcoming = {}
    local target = NS.FindNext() -- where the second arrow and the pins point
    model.arrowIndex = target and target.index
    for i = cur + 1, min(#guide.steps, cur + 80) do
        local step = guide.steps[i]
        if type(step) == "table" and not step.sticky and not step.tip and not step.hidewindow and not P.willSkip(step) then
            local icon, tint = stepIcon(step)
            local place = P.placeOf(step)
            local distance = place and distanceTo(place)
            model.upcoming[#model.upcoming + 1] = {
                index = step.index or i, step = step, label = P.labelOf(step, 140),
                icon = icon, tint = tint, distance = distance,
                place = distance and place or nil, -- only when it's on this continent: the row gets a little arrow
            }
            if #model.upcoming >= UPCOMING_MAX then break end
        end
    end
end

-- ---------------------------------------------------------------- steps already behind you

-- Steps you skipped (with Skip, or by jumping past them), per guide. RestedXP doesn't remember
-- which steps were skipped and which were done, so the card keeps its own note.
local SKIPLOG_MAX = 400

local function guideKey(guide) return guide and (guide.key or guide.name) or nil end

local function skipLog(guide, create)
    local key = guideKey(guide)
    if not (key and db) then return nil end
    db.skipLog = type(db.skipLog) == "table" and db.skipLog or {}
    local log = db.skipLog[key]
    if not log and create then
        log = {}
        db.skipLog[key] = log
    end
    return log
end

local function trim(log)
    local n, lowest = 0, nil
    for i in pairs(log) do
        n = n + 1
        if not lowest or i < lowest then lowest = i end
    end
    if n > SKIPLOG_MAX and lowest then log[lowest] = nil end
end

local doneLog

function Card.NoteSkipped(guide, index)
    local log = index and skipLog(guide, true)
    if not log then return end
    log[index] = true
    trim(log)
    local dones = doneLog(guide)
    if dones then dones[index] = nil end
end

-- Steps you finished with Done (or by ticking off their last line), per guide: they count as done
-- in Earlier steps even when the game can't tell (a quest you never really picked up, say).
function doneLog(guide, create)
    local key = guideKey(guide)
    if not (key and db) then return nil end
    db.doneLog = type(db.doneLog) == "table" and db.doneLog or {}
    local log = db.doneLog[key]
    if not log and create then
        log = {}
        db.doneLog[key] = log
    end
    return log
end

function Card.NoteDone(guide, index)
    local log = index and doneLog(guide, true)
    if not log then return end
    log[index] = true
    trim(log)
    local skips = skipLog(guide)
    if skips then skips[index] = nil end
end

-- Going back to a step: it and everything after it count as not done yet.
function Card.ForgetSkipsFrom(guide, index)
    for _, log in ipairs({ skipLog(guide) or {}, doneLog(guide) or {} }) do
        for i in pairs(log) do
            if i >= index then log[i] = nil end
        end
    end
end

-- "done" or "skipped" for a step behind you: skipped when you skipped it, or when something on it
-- still isn't done (a quest never picked up, an objective never finished, a turn-in never made).
-- Lines the card can't judge (getting somewhere, a checkbox) count as done.
local function pastDone(el)
    local tag, q = el.tag, el.questId
    -- Stricter than for steps ahead: a turn-in RestedXP passed over because the quest was missing
    -- wasn't done.
    if tag == "turnin" or tag == "dailyturnin" then return P.turnedIn(q) and true or false end
    if tag == "complete" then
        if P.turnedIn(q) then return true end
        if not P.onQuest(q) then return false end
    end
    return P.elementDone(el)
end

function Card.PastStatus(step, guide)
    local log = skipLog(guide)
    if log and log[step.index] then return "skipped" end
    local dones = doneLog(guide)
    if dones and dones[step.index] then return "done" end
    for _, el in ipairs(step.elements or {}) do
        -- A line you ticked off counts as done, as it does for RestedXP.
        if not el.textOnly and not el.completed and not el.skip and pastDone(el) == false then return "skipped" end
    end
    return "done"
end

local PAST_MAX = 30
local function buildPast(model, guide, cur)
    model.past = {}
    for i = cur - 1, 1, -1 do
        local step = guide.steps[i]
        if type(step) == "table" and not step.sticky and not step.tip and not step.hidewindow then
            local icon, tint = stepIcon(step)
            table.insert(model.past, 1, {
                index = step.index or i, step = step, label = P.labelOf(step, 140),
                icon = icon, tint = tint, status = Card.PastStatus(step, guide),
            })
            if #model.past >= PAST_MAX then break end
        end
    end
end

-- ---------------------------------------------------------------- skips and jumps

local progress = { guide = nil, index = nil }
Card.notice = nil

-- Why RestedXP passed over a step, in a few words.
local function skipReason(step)
    local profile = rxp.settings and rxp.settings.profile
    if not (profile and profile.disableAutoSkip) then
        for _, el in ipairs(step.elements or {}) do
            if P.guardSkips(el) then
                local tag = el.tag
                local id = el.questId or (type(el.questIds) == "table" and el.questIds[1])
                local name = questName(id)
                if tag == "isNotOnQuest" or (tag == "isOnQuest" and el.reverse) then
                    return ("you're on %s"):format(name)
                elseif tag == "isOnQuest" then
                    return ("you're not on %s"):format(name)
                elseif tag == "isQuestTurnedIn" then
                    return ("%s isn't turned in"):format(name)
                elseif tag == "isQuestAvailable" then
                    return ("%s is already done"):format(name)
                elseif tag == "isQuestComplete" or tag == "isQuestNotComplete" then
                    return el.reverse and ("%s is already complete"):format(name) or ("%s isn't complete"):format(name)
                end
                return "a quest check didn't pass"
            end
        end
    end
    for _, el in ipairs(step.elements or {}) do
        if not el.textOnly and P.elementDone(el) then
            local tag = el.tag
            if tag == "accept" then return ("you already have %s"):format(questName(el.questId)) end
            if tag == "turnin" then return ("you already turned in %s"):format(questName(el.questId)) end
            if tag == "complete" then return ("%s's objective was already done"):format(questName(el.questId)) end
            if tag == "xp" then return ("you're already level %s"):format(tostring(el.level)) end
        end
    end
    return "RestedXP found it already done"
end
Card.skipReason = skipReason

function Card.CheckProgress()
    local guide = rxp.currentGuide
    local cur = P.call(rxp.GetGuideProgress)
    if type(guide) ~= "table" or type(cur) ~= "number" then return end
    local key = guide.key or guide.name
    if progress.guide ~= key then
        progress.guide, progress.index, progress.since = key, cur, GetTime()
        Card.notice, Card.manual = nil, nil
        return
    end
    local last = progress.index
    if cur == last then return end
    progress.index = cur
    Card.offset = 0
    if cur < last then Card.ForgetSkipsFrom(guide, cur) end -- went back: those steps are to do again
    local manual = Card.manual
    Card.manual = nil
    if manual == "back" then
        Card.notice = { kind = "info", text = ("Back to step %d."):format(cur), time = GetTime() }
        return
    elseif manual then
        Card.notice = nil
        return
    end
    -- A notice belongs to the step it was about.
    if Card.notice and Card.notice.kind ~= "jump" then Card.notice = nil end
    local settling = progress.since and GetTime() - progress.since < SETTLE_SECONDS
    if cur > last + 1 and cur - last <= LOOKBACK_SKIPS and not settling then
        local skipped = {}
        for i = last + 1, cur - 1 do
            local s = guide.steps[i]
            if type(s) == "table" and not s.sticky and not s.tip and not s.hidewindow then
                skipped[#skipped + 1] = { index = s.index or i, label = P.labelOf(s), why = skipReason(s) }
            end
        end
        if #skipped == 1 then
            Card.notice = { kind = "skip", steps = skipped, time = GetTime(),
                text = ("Skipped step %d: %s."):format(skipped[1].index, skipped[1].why) }
        elseif #skipped > 1 then
            Card.notice = { kind = "skip", steps = skipped, time = GetTime(),
                text = ("Skipped %d steps RestedXP found already done. Hover for why."):format(#skipped) }
        end
    end
    if Card.notice and Card.notice.kind == "jump" and Card.notice.index <= cur then Card.notice = nil end
end

-- You picked up a quest the guide only gets to later: offer to jump there.
function Card.OnQuestAccepted(questId)
    if not (ready() and db.card) then return end
    questId = tonumber(questId)
    local guide = rxp.currentGuide
    local cur = P.call(rxp.GetGuideProgress)
    if not (questId and type(guide) == "table" and type(guide.steps) == "table" and type(cur) == "number") then return end
    local active = rxp.RXPFrame and rxp.RXPFrame.activeSteps
    for _, step in ipairs(type(active) == "table" and active or {}) do
        for _, el in ipairs(step.elements or {}) do
            if el.tag == "accept" and tonumber(el.questId) == questId then return end
        end
    end
    for i = cur + 2, min(#guide.steps, cur + 80) do
        local step = guide.steps[i]
        if type(step) == "table" and not step.sticky then
            for _, el in ipairs(step.elements or {}) do
                if el.tag == "accept" and tonumber(el.questId) == questId then
                    Card.notice = { kind = "jump", index = step.index or i, time = GetTime(),
                        text = ("You picked up %s. The guide gets to it at step %d."):format(questName(questId), step.index or i) }
                    Card.dirty = true
                    return
                end
            end
        end
    end
end

-- Undo ticks on a step, so going back to it means doing it again.
local function untick(step)
    for _, el in ipairs(step.elements or {}) do
        if el.skip and not el.completed then el.skip = nil end
    end
end

function Card.Back()
    if not ready() then return end
    local guide, cur = rxp.currentGuide, P.call(rxp.GetGuideProgress)
    if type(guide) ~= "table" or type(cur) ~= "number" then return end
    for i = cur - 1, 1, -1 do
        local step = guide.steps[i]
        if type(step) == "table" and not step.sticky and not step.tip then
            untick(step)
            Card.ForgetSkipsFrom(guide, step.index or i)
            Card.manual = "back"
            P.call(rxp.SetStep, step.index or i)
            Card.dirty = true
            return
        end
    end
end

function Card.Skip()
    if not ready() then return end
    local cur = P.call(rxp.GetGuideProgress)
    if type(cur) ~= "number" then return end
    Card.NoteSkipped(rxp.currentGuide, cur)
    Card.manual = "skip"
    P.call(rxp.SetStep, cur + 1)
    Card.dirty = true
end

function Card.Jump(index)
    if not (ready() and index) then return end
    local guide, cur = rxp.currentGuide, P.call(rxp.GetGuideProgress)
    if type(guide) == "table" and type(cur) == "number" and type(guide.steps) == "table" then
        if index > cur then
            -- Jumping ahead skips what's in between, unless it's already done.
            for i = cur, index - 1 do
                local step = guide.steps[i]
                if type(step) == "table" and not step.sticky and not P.objectivesDone(step) then
                    Card.NoteSkipped(guide, step.index or i)
                end
            end
        elseif index < cur then
            local step = guide.steps[index]
            if type(step) == "table" then untick(step) end
            Card.ForgetSkipsFrom(guide, index)
        end
    end
    Card.manual = "jump"
    Card.notice = nil
    P.call(rxp.SetStep, index)
    Card.dirty = true
end

-- Done: tick off everything left on the step you're on, as if you'd ticked each of RestedXP's
-- checkboxes, so RestedXP counts the step as complete and moves on by itself.
function Card.Complete()
    if not ready() then return end
    local guide, cur = rxp.currentGuide, P.call(rxp.GetGuideProgress)
    if type(guide) ~= "table" or type(cur) ~= "number" or type(guide.steps) ~= "table" then return end
    local step = guide.steps[cur]
    if type(step) ~= "table" then return end
    local ticked = 0
    for _, el in ipairs(step.elements or {}) do
        if not el.textOnly and not el.optional and not el.completed and not el.skip then
            if el.OnComplete then pcall(el.OnComplete, el) end
            el.skip = true
            if el.frame and el.frame.button then pcall(el.frame.button.SetChecked, el.frame.button, true) end
            ticked = ticked + 1
        end
    end
    Card.NoteDone(guide, step.index or cur)
    Card.manual = "done"
    rxp.updateSteps = true
    P.call(rxp.UpdateMap)
    -- Nothing left to tick (a step of notes only, or RestedXP hasn't caught up): move on.
    if ticked == 0 then P.call(rxp.SetStep, cur + 1) end
    Card.dirty = true
end

-- Ticking a line: what RestedXP's checkbox for it does (GuideWindow.lua ActiveStepElementPostClick).
function Card.Toggle(el)
    if not (ready() and type(el) == "table") or el.textOnly or el.optional then return end
    local skip = not el.skip
    if el.OnComplete and skip and not el.skip then pcall(el.OnComplete, el) end
    el.skip = skip
    local step = el.step
    if skip and type(step) == "table" and step.index and step.index == P.call(rxp.GetGuideProgress) then
        local open = false
        for _, other in ipairs(step.elements or {}) do
            if not other.textOnly and not other.optional and not other.completed and not other.skip then open = true end
        end
        if not open then Card.NoteDone(rxp.currentGuide, step.index) end
    end
    rxp.updateSteps = true
    P.call(rxp.UpdateMap)
    if el.frame and el.frame.button then pcall(el.frame.button.SetChecked, el.frame.button, skip or el.completed) end
    Card.dirty = true
end

-- ---------------------------------------------------------------- RestedXP's own window

local faded = false

local function fadeRXP(fade, quiet)
    local f = rxp and rxp.RXPFrame
    if not f then return end
    if fade then
        if f:GetAlpha() > 0 then f:SetAlpha(0) end
        if f:GetScale() > 0.011 then f:SetScale(0.01) end -- a dot: nothing left to catch clicks
        faded = true
    elseif faded then
        faded = false
        f:SetAlpha(1)
        local profile = rxp.settings and rxp.settings.profile
        f:SetScale(profile and tonumber(profile.windowScale) or 1)
        if quiet then return end
        -- Lay it out again at full size, the way RestedXP does after its window is resized.
        local cur = P.call(rxp.GetGuideProgress)
        if type(cur) == "number" then P.call(rxp.SetStep, cur) end
    end
end
Card.FadeRXP = fadeRXP
function Card.IsRXPFaded() return faded end

-- ---------------------------------------------------------------- drawing

local card, along, ui

local function setIcon(tex, name)
    local i = ICON_INDEX[name] or ICON_INDEX.navigation
    local col, row = i % 8, floor(i / 8)
    tex:SetTexture(ICON_FILE)
    tex:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8)
end

local function tint(tex, c, a) tex:SetVertexColor(c[1], c[2], c[3], a or 1) end

-- Fonts. The game reads a font file from disk the first time something uses it, and text drawn
-- before then can come out blank until it's set again. So the three Inter files are touched as
-- this file loads, the card checks its texts after each draw (a text with no width came out
-- blank) and draws again, and it redraws a few times in the first seconds after login.
do
    local warm = CreateFrame("Frame", nil, UIParent)
    warm:SetSize(1, 1)
    warm:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    warm:SetAlpha(0)
    for _, file in pairs(FONTS) do
        local fs = warm:CreateFontString(nil, "ARTWORK")
        pcall(fs.SetFont, fs, file, 12, "")
        fs:SetPoint("TOPLEFT")
        fs:SetText("Aa 0123")
    end
end

local function setFont(fs, weight, size)
    local file = FONTS[weight] or FONTS.regular
    if fs.rxnFile == file and fs.rxnSize == size and not Card.refont then return end
    local ok, success = pcall(fs.SetFont, fs, file, size, "")
    if ok and success ~= false then
        fs.rxnFile, fs.rxnSize = file, size
    else
        fs:SetFont(FALLBACK_FONT, size, "")
        fs.rxnFile, fs.rxnSize = nil, nil -- try Inter again next time
        Card.blank = true
    end
end
Card.SetFont = setFont

local function lineHeight(size) return floor(size * 1.21 + 0.5) end

local function setShadow(fs)
    local shadow = T.shadow and true or false
    if fs.rxnShadow == shadow then return end
    fs.rxnShadow = shadow
    fs:SetShadowOffset(1, -1)
    -- A clear shadow rather than no offset, for the dark look.
    fs:SetShadowColor(0, 0, 0, shadow and 0.7 or 0)
end

-- Sets a text and returns its height. maxLines 0 = no limit.
local function setText(fs, weight, size, color, width, text, maxLines, justify)
    setFont(fs, weight, size)
    fs:SetSpacing(floor(size * 0.22 + 0.5))
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetMaxLines(maxLines or 0)
    setShadow(fs)
    fs:SetText(text or "")
    fs:SetTextColor(color[1], color[2], color[3], 1) -- after the text, so nothing resets it
    fs:Show()
    if text and text ~= "" and (fs:GetStringWidth() or 0) <= 0 then Card.blank = true end
    return max(fs:GetStringHeight() or size, size)
end

-- A rounded rectangle from 9 pieces of a 64 x 64 texture with 16-texel corners. The pieces belong
-- to frame; box (frame by default) is the area they cover.
local function nineSlice(frame, file, layer, corner, sublevel, box)
    box = box or frame
    local parts = {}
    local c = 0.25
    local coords = {
        { 0, c, 0, c }, { c, 1 - c, 0, c }, { 1 - c, 1, 0, c },
        { 0, c, c, 1 - c }, { c, 1 - c, c, 1 - c }, { 1 - c, 1, c, 1 - c },
        { 0, c, 1 - c, 1 }, { c, 1 - c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 },
    }
    for i = 1, 9 do
        local t = frame:CreateTexture(nil, layer, nil, sublevel or 0)
        t:SetTexture(file)
        t:SetTexCoord(unpack(coords[i]))
        parts[i] = t
    end
    local tl, t, tr, l, m, r, bl, b, br = unpack(parts)
    tl:SetPoint("TOPLEFT", box)
    tr:SetPoint("TOPRIGHT", box)
    bl:SetPoint("BOTTOMLEFT", box)
    br:SetPoint("BOTTOMRIGHT", box)
    t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    local obj = { parts = parts, file = file, box = box }
    function obj:SetCorner(size)
        self.corner = size
        for _, p in ipairs({ tl, tr, bl, br }) do p:SetSize(size, size) end
    end
    function obj:SetColor(cr, cg, cb, ca)
        self.gradient = nil
        for _, p in ipairs(parts) do p:SetVertexColor(cr, cg, cb, ca or 1) end
    end
    -- Lighter at the top, like light catching glass.
    function obj:SetGradient(top, bottom)
        self.gradient = { top, bottom }
        for _, i in ipairs({ 1, 2, 3 }) do parts[i]:SetVertexColor(top[1], top[2], top[3], top[4]) end
        for _, i in ipairs({ 7, 8, 9 }) do parts[i]:SetVertexColor(bottom[1], bottom[2], bottom[3], bottom[4]) end
        local lo = CreateColor(bottom[1], bottom[2], bottom[3], bottom[4])
        local hi = CreateColor(top[1], top[2], top[3], top[4])
        for _, i in ipairs({ 4, 5, 6 }) do parts[i]:SetGradient("VERTICAL", lo, hi) end
    end
    function obj:SetShown(shown)
        for _, p in ipairs(parts) do if shown then p:Show() else p:Hide() end end
    end
    obj:SetCorner(corner)
    frame.nineSlices = frame.nineSlices or {}
    table.insert(frame.nineSlices, obj)
    return obj
end

local function showTooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    for _, line in ipairs(lines or {}) do
        if type(line) == "table" then
            GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 0.82, line[4] or 0, true)
        else
            GameTooltip:AddLine(line, 1, 0.82, 0, true)
        end
    end
    GameTooltip:Show()
end

local function iconButton(parent, icon, onClick, tooltipTitle, tooltipText)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.bg = nineSlice(b, PANEL_FILE, "BACKGROUND", 6)
    b.bg:SetShown(false)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("CENTER")
    setIcon(b.icon, icon)
    tint(b.icon, T.text3)
    b.tooltipTitle, b.tooltipText = tooltipTitle, tooltipText
    b:SetScript("OnEnter", function(self)
        self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4] + 0.03)
        self.bg:SetShown(true)
        tint(self.icon, T.text1)
        local title = type(self.tooltipTitle) == "function" and self.tooltipTitle() or self.tooltipTitle
        if title then showTooltip(self, title, self.tooltipText and { self.tooltipText } or nil) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetShown(false)
        tint(self.icon, T.text3)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A text button: "ghost" (quiet until hovered) or "accent" (tinted with the next-step colour).
local function textButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(80, 24)
    b.bg = nineSlice(b, PANEL_FILE, "BACKGROUND", 6)
    b.text = b:CreateFontString(nil, "ARTWORK")
    b.iconLeft = b:CreateTexture(nil, "ARTWORK")
    b.iconRight = b:CreateTexture(nil, "ARTWORK")
    for _, t in ipairs({ b.iconLeft, b.iconRight }) do t:SetSize(12, 12) end
    function b:Setup(label, left, right, style, size)
        self.style = style
        local color = style == "accent" and db.color or T.text2
        setText(self.text, "medium", size, color, 300, label, 1)
        local w = self.text:GetStringWidth() or (#label * size * 0.55)
        local x = 10
        self.iconLeft:ClearAllPoints()
        self.iconRight:ClearAllPoints()
        if left then
            setIcon(self.iconLeft, left)
            self.iconLeft:SetPoint("LEFT", self, "LEFT", 8, 0)
            self.iconLeft:Show()
            x = 24
        else
            self.iconLeft:Hide()
        end
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", self, "LEFT", x, 0)
        self.text:SetWidth(w + 2)
        local width = x + w + 10
        if right then
            setIcon(self.iconRight, right)
            self.iconRight:SetPoint("LEFT", self, "LEFT", x + w + 4, 0)
            self.iconRight:Show()
            width = x + w + 4 + 12 + 8
        else
            self.iconRight:Hide()
        end
        tint(self.iconLeft, color)
        tint(self.iconRight, color)
        self:SetSize(floor(width + 0.5), 24)
        self:Paint(false)
    end
    function b:Paint(hover)
        if self.style == "accent" then
            local c = db.color
            self.bg:SetColor(c[1], c[2], c[3], hover and 0.32 or 0.20)
            self.bg:SetShown(true)
        else
            self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4] + 0.02)
            self.bg:SetShown(hover)
            local color = hover and T.text1 or T.text2
            self.text:SetTextColor(color[1], color[2], color[3], 1)
            tint(self.iconLeft, color)
            tint(self.iconRight, color)
        end
    end
    b:SetScript("OnEnter", function(self)
        self:Paint(true)
        if self.tooltipTitle then showTooltip(self, self.tooltipTitle, self.tooltipText and { self.tooltipText }) end
    end)
    b:SetScript("OnLeave", function(self) self:Paint(false) GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A line on a card: a status or tag icon and a text. Pooled.
local function newRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.bg = nineSlice(r, PANEL_FILE, "BACKGROUND", 6)
    r.bg:SetShown(false)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(12, 12)
    r.text = r:CreateFontString(nil, "ARTWORK")
    r:SetScript("OnEnter", function(self)
        if self.clickable then
            self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4])
            self.bg:SetShown(true)
        end
        if self.tipTitle then showTooltip(self, self.tipTitle, self.tipLines) end
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetShown(false)
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if self.clickable and self.element then Card.Toggle(self.element) end
    end)
    return r
end

local function acquire(pool, i, parent, make)
    local r = pool[i]
    if not r then
        r = (make or newRow)(parent)
        pool[i] = r
    end
    r:Show()
    return r
end

local function hideFrom(pool, n)
    for i = n, #pool do pool[i]:Hide() end
end

local function divider(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    return t
end

local function placeDivider(t, parent, x, y, width)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetWidth(width)
    t:SetColorTexture(T.divider[1], T.divider[2], T.divider[3], T.divider[4])
    t:Show()
end

local function rowAt(r, parent, x, y, width, icon, iconTint, text, weight, size, color, maxLines)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local textX = icon and 26 or 6
    local h = setText(r.text, weight, size, color, width - textX - 6, text, maxLines)
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", textX, -3)
    if icon then
        setIcon(r.icon, icon)
        tint(r.icon, iconTint)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -3 - floor((lineHeight(size) - 12) / 2))
        r.icon:Show()
    else
        r.icon:Hide()
    end
    r:SetSize(width, h + 6)
    return h + 6
end

-- An objective-style row: open circle, or a tick once done; plain notes get no icon.
local function objectiveRow(r, parent, x, y, width, row, size)
    r.clickable, r.element = row.clickable, row.el
    r.tipTitle = row.clickable and (row.done and "Done (click to untick)" or "Click to tick it off") or nil
    local tip = type(row.el.tooltip) == "string" and row.el.tooltip or nil
    r.tipLines = tip and { tip } or nil
    if not r.tipTitle and tip then r.tipTitle = P.plain(row.text) end
    local icon, iconTint, color
    if row.plainLine then
        icon, color = nil, T.text2
    elseif row.done then
        icon, iconTint, color = "check", C.success, T.text3
    else
        icon, iconTint, color = "circle", T.text3, T.text1
    end
    return rowAt(r, parent, x, y, width, icon, iconTint, row.text, "regular", size, color, 0)
end

local function newPanel(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetSize(300, 120)
    f:Hide()
    f.layers = { nineSlice(f, PANEL_FILE, "BACKGROUND", 8, -7), nineSlice(f, PANEL_FILE, "BACKGROUND", 8, -6) }
    f.edge = nineSlice(f, BORDER_FILE, "BORDER", 8)
    return f
end

local function paintPanel(f)
    for i, ns in ipairs(f.layers) do
        local layer = T.layers[i]
        if layer then
            ns:SetCorner(T.corner)
            if layer.top then ns:SetGradient(layer.top, layer.bottom) else ns:SetColor(unpack(layer.color)) end
            ns:SetShown(true)
        else
            ns:SetShown(false)
        end
    end
    f.edge:SetCorner(T.corner)
    f.edge:SetColor(T.border[1], T.border[2], T.border[3], T.border[4])
end

-- For Toast.lua and the settings window: the cards' drawing pieces and looks.
Card.UI = {
    nineSlice = nineSlice, setText = setText, setFont = setFont, setIcon = setIcon, tint = tint,
    lineHeight = lineHeight, newPanel = newPanel, paintPanel = paintPanel, THEMES = THEMES, TINT = TINT, C = C,
    PANEL_FILE = PANEL_FILE, BORDER_FILE = BORDER_FILE, CONTROLS_FILE = MEDIA .. "controls",
    -- The look to draw in (the cards pick theirs on each draw too).
    SetTheme = function(name) T = THEMES[name] or THEMES.dark; return T end,
}
Card.StepIcon = stepIcon

-- The top row of a card: its label, its buttons, and the handle for dragging it.
local function newHeader(f, onDragStart, onDragStop, tooltip)
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    h:SetHeight(34)
    h:EnableMouse(true)
    h:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not db.cardLocked then onDragStart() end
    end)
    h:SetScript("OnMouseUp", function() onDragStop() end)
    h:SetScript("OnEnter", function(self)
        local title = tooltip(self)
        if title then showTooltip(self, title, { db.cardLocked and "Locked in place." or "Drag here to move the card." }) end
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h.text = h:CreateFontString(nil, "ARTWORK")
    return h
end

local function headerAt(h, f, pad, W, text, buttons)
    for i, b in ipairs(buttons) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", W - pad + 4 - i * 22, -8)
        b:Show()
    end
    setText(h.text, "medium", db.cardTextSize - 3, T.text3, W - pad * 2 - #buttons * 22 - 4, text, 1)
    h.text:ClearAllPoints()
    h.text:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -14)
    h:SetWidth(W - #buttons * 22 - pad)
end

local function savePoint(f, key)
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then db[key] = { point, relPoint, x, y } end
end

function Card.Place()
    if not card then return end
    card:ClearAllPoints()
    local p = db.cardPoint
    if p then
        card:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        -- First time: where RestedXP's window is.
        local f = rxp and rxp.RXPFrame
        local left, top = f and f:GetLeft(), f and f:GetTop()
        if left and top and not faded then
            local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * s, top * s)
        else
            card:SetPoint("TOPLEFT", UIParent, "LEFT", 20, 160)
        end
    end
    Card.PlaceAlong()
end

-- The along-the-way card against the main card (above, below, left, right), or free.
local DOCKS = {
    bottom = { "TOPLEFT", "BOTTOMLEFT", 0, -8 },
    top = { "BOTTOMLEFT", "TOPLEFT", 0, 8 },
    left = { "TOPRIGHT", "TOPLEFT", -8, 0 },
    right = { "TOPLEFT", "TOPRIGHT", 8, 0 },
}
function Card.PlaceAlong()
    if not along then return end
    along:ClearAllPoints()
    local a = db.alongPoint
    if db.alongDock == "free" and a then
        along:SetPoint(a[1], UIParent, a[2], a[3], a[4])
    else
        local d = DOCKS[db.alongDock] or DOCKS.bottom
        along:SetPoint(d[1], card, d[2], d[3], d[4])
    end
end

-- Switching to "free": it stays where it is now.
function Card.FreeAlong()
    if not along then return end
    local l, t = along:GetLeft(), along:GetTop()
    if l and t then db.alongPoint = { "TOPLEFT", "BOTTOMLEFT", l, t } end
end

local function openRXPMenu()
    local f = rxp and rxp.RXPFrame
    if f and type(f.DropDownMenu) == "function" then pcall(f.DropDownMenu) end
end

function Card.Scroll(steps)
    Card.offset = (Card.offset or 0) + steps
    Card.dirty = true
    Card.Update()
end

local function newNextRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.bg = nineSlice(r, PANEL_FILE, "BACKGROUND", 6)
    r.bg:SetShown(false)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.num = r:CreateFontString(nil, "ARTWORK")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.text = r:CreateFontString(nil, "ARTWORK")
    r.dist = r:CreateFontString(nil, "ARTWORK")
    -- Which way the step is from where you're facing (turned every frame by Card.TurnArrows).
    r.dir = r:CreateTexture(nil, "ARTWORK")
    r.dir:SetSize(11, 11)
    setIcon(r.dir, "navigation")
    r.dir:Hide()
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) Card.Scroll(-delta) end)
    r:SetScript("OnEnter", function(self)
        self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4] + (self.pinned and 0.04 or 0))
        self.bg:SetShown(true)
        local u = self.upcoming
        if not u then return end
        local lines = {}
        for _, el in ipairs(u.step.elements or {}) do
            local t = guideText(el)
            if t then lines[#lines + 1] = { P.plain(t), 1, 1, 1 } end
        end
        if u.distance then lines[#lines + 1] = { ("%d yd away"):format(u.distance), T.text3[1], T.text3[2], T.text3[3] } end
        local title = ("Step %d"):format(u.index)
        if u.status == "done" then
            title = title .. "  ·  Done"
            lines[#lines + 1] = { "Shift-click to go back to this step.", 0.6, 0.6, 0.6 }
        elseif u.status == "skipped" then
            title = title .. "  ·  Skipped"
            lines[#lines + 1] = { "Shift-click to go back to this step.", 0.6, 0.6, 0.6 }
        elseif u.status == "current" then
            title = title .. "  ·  You're here"
        else
            lines[#lines + 1] = { "Shift-click to go to this step.", 0.6, 0.6, 0.6 }
        end
        showTooltip(self, title, lines)
    end)
    r:SetScript("OnLeave", function(self)
        if self.pinned then
            self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4])
        else
            self.bg:SetShown(false)
        end
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        local u = self.upcoming
        if u and u.status ~= "current" and IsShiftKeyDown() then
            Card.Jump(u.index)
            Card.Update()
        end
    end)
    return r
end

-- A row in the step list: number, icon, what it is, how far and which way. u.status is nil for a
-- step coming up, "current" for the step you're on, "done" or "skipped" for one behind you.
local function nextRowAt(r, x, y, width, u, isTarget, base)
    local accent = db.color
    local status = u.status
    r.upcoming = u
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
    local textX, distW = 48, 50
    local lh = lineHeight(base)
    local textColor, numColor, iconName, iconTint, iconAlpha, weight = T.text2, T.text3, u.icon, TINT[u.tint] or T.text2, 0.85, "regular"
    if status == "done" then
        textColor, numColor, iconName, iconTint, iconAlpha = C.success, C.success, "check", C.success, 1
    elseif status == "skipped" then
        textColor, numColor, iconName, iconTint, iconAlpha = T.text3, T.text3, "skip", T.text3, 1
    elseif status == "current" then
        textColor, numColor, iconAlpha, weight = T.text1, T.text1, 1, "medium"
    elseif isTarget then
        textColor, numColor, iconTint, iconAlpha, weight = T.text1, accent, accent, 1, "medium"
    end
    local h = setText(r.text, weight, base, textColor, width - textX - distW, u.label, 2)
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", textX, -4)
    local small = base - 3
    local smallDrop = floor((lh - lineHeight(small)) / 2 + 0.5)
    setText(r.num, "medium", small, numColor, 22, tostring(u.index), 1, "RIGHT")
    r.num:ClearAllPoints()
    r.num:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -4 - smallDrop)
    setIcon(r.icon, iconName)
    tint(r.icon, iconTint, iconAlpha)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -4 - floor((lh - 14) / 2))
    local behind = status == "done" or status == "skipped"
    local dist = (not behind and u.distance) and (u.distance .. " yd") or ""
    setText(r.dist, "medium", small, T.text3, distW - 8, dist, 1, "RIGHT")
    r.dist:ClearAllPoints()
    r.dist:SetPoint("TOPLEFT", r, "TOPLEFT", width - distW, -4 - smallDrop)
    -- A small arrow under the distance, for steps with somewhere to go on this continent.
    r.place = (not behind and u.place) or nil
    if r.place then
        local sw = r.dist:GetStringWidth() or 0
        local dirTop = smallDrop + lineHeight(small) + 3
        r.dir:ClearAllPoints()
        r.dir:SetPoint("TOP", r, "TOPLEFT", floor(width - 8 - sw / 2 + 0.5), -4 - dirTop)
        tint(r.dir, (isTarget and not status) and accent or T.text3)
        r.dir:Show()
        h = max(h, dirTop + 11 + 1)
    else
        r.dir:Hide()
    end
    r.bar:ClearAllPoints()
    if isTarget and not status then
        r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -4)
        r.bar:SetSize(2, h)
        r.bar:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
        r.bar:Show()
    else
        r.bar:Hide()
    end
    -- The step you're on stays lit, so the list reads past, here, ahead.
    r.pinned = status == "current"
    if r.pinned then
        r.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4])
        r.bg:SetShown(true)
    else
        r.bg:SetShown(false)
    end
    r:SetSize(width, h + 8)
    return h + 8
end

-- Turns the little arrows on the step list to where each step is from the way you're facing.
function Card.TurnArrows()
    if not ui then return end
    local HBD = P.hbd()
    local x, y, instance, facing
    if HBD then
        local ok, px, py, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
        if ok then x, y, instance = px, py, inst end
        local okF, f = pcall(GetPlayerFacing)
        if okF and type(f) == "number" then facing = f end
    end
    for _, r in ipairs(ui.next) do
        local place = r:IsShown() and r.place
        if place then
            local angle
            if x and y and facing and instance == place.instance then
                local ok, a = pcall(HBD.GetWorldVector, HBD, instance, x, y, place.wx, place.wy)
                if ok and type(a) == "number" then angle = a end
            end
            if angle then
                -- The icon points up and to the right, so it's turned an eighth less.
                r.dir:SetRotation(angle - facing + math.pi / 4)
                if not r.dir:IsShown() then r.dir:Show() end
            elseif r.dir:IsShown() then
                r.dir:Hide()
            end
        end
    end
end

local function createCards()
    ui = { rows = {}, warnings = {}, next = {}, alongRows = {}, alongDividers = {} }
    card = newPanel("RXPEnhancedCard")
    along = newPanel("RXPEnhancedAlongCard")

    ui.header = newHeader(card, function() card:StartMoving() end, function()
        card:StopMovingOrSizing()
        savePoint(card, "cardPoint")
    end, function(self) return self.guideName end)
    ui.collapse = iconButton(card, "up", function()
        db.cardCollapsed = not db.cardCollapsed
        Card.dirty = true
        Card.Update()
    end, function() return db.cardCollapsed and "Show everything" or "Show less" end)
    ui.settings = iconButton(card, "settings", function() NS.OpenSettings() end, "RXP Enhanced settings")
    ui.eye = iconButton(card, "eye", function()
        db.cardHidesRXP = not db.cardHidesRXP
        Card.dirty = true
        if NS.SettingsChanged then NS.SettingsChanged() else Card.Update() end
    end, function() return db.cardHidesRXP and "Show RestedXP's window" or "Hide RestedXP's window" end)
    ui.menu = iconButton(card, "menu", openRXPMenu, "RestedXP menu", "Pick another guide, reload it, and RestedXP's other options.")

    ui.icon = card:CreateTexture(nil, "ARTWORK")
    ui.icon:SetSize(18, 18)
    ui.headline = card:CreateFontString(nil, "ARTWORK")
    -- The headline's own line can be ticked off like the others: a hover area under it.
    ui.headTick = CreateFrame("Button", nil, card)
    ui.headTick.bg = nineSlice(ui.headTick, PANEL_FILE, "BACKGROUND", 6)
    ui.headTick.bg:SetShown(false)
    ui.headTick:SetScript("OnEnter", function(self)
        self.bg:SetColor(T.hover[1], T.hover[2], T.hover[3], T.hover[4])
        self.bg:SetShown(true)
        showTooltip(self, "Click to tick it off", { "Ticking off every line counts the step as done, as RestedXP's checkboxes do. Done below ticks them all." })
    end)
    ui.headTick:SetScript("OnLeave", function(self)
        self.bg:SetShown(false)
        GameTooltip:Hide()
    end)
    ui.headTick:SetScript("OnClick", function(self)
        if self.element then Card.Toggle(self.element) Card.Update() end
    end)
    ui.help = CreateFrame("Button", nil, card)
    ui.help:SetSize(18, 18)
    ui.help.icon = ui.help:CreateTexture(nil, "ARTWORK")
    ui.help.icon:SetSize(14, 14)
    ui.help.icon:SetPoint("CENTER")
    setIcon(ui.help.icon, "info")
    ui.help:SetScript("OnEnter", function(self)
        tint(self.icon, T.text1)
        local lines = {}
        for _, r in ipairs(Card.model and Card.model.reasons or {}) do
            lines[#lines + 1] = { r.what, 1, 1, 1 }
            lines[#lines + 1] = { r.why, 0.66, 0.69, 0.72 }
        end
        showTooltip(self, "Still to do", lines)
    end)
    ui.help:SetScript("OnLeave", function(self) tint(self.icon, T.text3) GameTooltip:Hide() end)
    ui.context = card:CreateFontString(nil, "ARTWORK")

    ui.divNext = divider(card)
    ui.nextLabel = card:CreateFontString(nil, "ARTWORK")
    ui.nextCount = card:CreateFontString(nil, "ARTWORK")
    ui.nextEmpty = card:CreateFontString(nil, "ARTWORK")
    ui.nextArea = CreateFrame("Frame", nil, card) -- catches the mouse wheel between rows
    ui.nextArea:EnableMouseWheel(true)
    ui.nextArea:SetScript("OnMouseWheel", function(_, delta) Card.Scroll(-delta) end)
    -- "Back to up next", when you've scrolled back to earlier steps.
    ui.nowButton = CreateFrame("Button", nil, card)
    ui.nowButton:SetScript("OnEnter", function() ui.nextCount:SetTextColor(T.text1[1], T.text1[2], T.text1[3], 1) end)
    ui.nowButton:SetScript("OnLeave", function() ui.nextCount:SetTextColor(T.text2[1], T.text2[2], T.text2[3], 1) end)
    ui.nowButton:SetScript("OnClick", function()
        Card.offset = 0
        Card.dirty = true
        Card.Update()
    end)
    ui.nowButton:Hide()
    -- The little arrows on the step list follow you as you turn.
    card:SetScript("OnUpdate", function() Card.TurnArrows() end)

    ui.divNotice = divider(card)
    ui.notice = CreateFrame("Frame", nil, card)
    ui.notice:EnableMouse(true)
    ui.notice.icon = ui.notice:CreateTexture(nil, "ARTWORK")
    ui.notice.icon:SetSize(13, 13)
    ui.notice.text = ui.notice:CreateFontString(nil, "ARTWORK")
    ui.notice:SetScript("OnEnter", function(self)
        local n = Card.notice
        if n and n.steps then
            local lines = {}
            for _, s in ipairs(n.steps) do
                lines[#lines + 1] = { ("Step %d: %s"):format(s.index, s.label), 1, 1, 1 }
                lines[#lines + 1] = { (s.why:gsub("^%l", string.upper)), 0.66, 0.69, 0.72 }
            end
            showTooltip(self, "Skipped", lines)
        end
    end)
    ui.notice:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.noticeClose = iconButton(card, "close", function()
        Card.notice = nil
        Card.dirty = true
        Card.Update()
    end, "Dismiss")
    ui.jump = textButton(card, function()
        if Card.notice and Card.notice.index then Card.Jump(Card.notice.index) end
        Card.Update()
    end)

    ui.divFooter = divider(card)
    ui.back = textButton(card, function() Card.Back() Card.Update() end)
    ui.back.tooltipTitle, ui.back.tooltipText = "Back", "Go back to the step before this one."
    ui.skip = textButton(card, function() Card.Skip() Card.Update() end)
    ui.skip.tooltipTitle, ui.skip.tooltipText = "Skip", "Move on without finishing this step. It shows as skipped under Earlier steps; Done counts it as complete."
    ui.done = textButton(card, function() Card.Complete() Card.Update() end)
    ui.done.tooltipTitle, ui.done.tooltipText = "Done", "Tick off everything left on this step, as if you'd ticked each of RestedXP's checkboxes. RestedXP counts it as complete and moves on, and it shows as done under Earlier steps."

    -- The along-the-way card.
    ui.alongHeader = newHeader(along, function()
        -- Let go of the main card before moving on its own.
        local l, t = along:GetLeft(), along:GetTop()
        if l and t then
            along:ClearAllPoints()
            along:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        along:StartMoving()
    end, function()
        along:StopMovingOrSizing()
        savePoint(along, "alongPoint")
        db.alongDock = "free" -- dragged: it stays where you put it
        if NS.SettingsChanged then NS.SettingsChanged() end
    end, function() return "Along the way" end)
    ui.alongCollapse = iconButton(along, "up", function()
        db.alongCollapsed = not db.alongCollapsed
        Card.dirty = true
        Card.Update()
    end, function() return db.alongCollapsed and "Show everything" or "Show less" end)
end

function Card.Render(m)
    T = THEMES[db.cardTheme] or THEMES.dark
    local W = db.cardWidth
    local base = db.cardTextSize
    local pad = 14
    local inner = W - pad * 2
    local collapsed = db.cardCollapsed
    local accent = db.color
    card:SetWidth(W)
    paintPanel(card)

    -- Header: where you are in the guide, and the card's buttons.
    setIcon(ui.collapse.icon, collapsed and "down" or "up")
    setIcon(ui.eye.icon, db.cardHidesRXP and "eyeoff" or "eye") -- the state RestedXP's window is in
    local buttons = { ui.collapse, ui.settings, ui.eye, ui.menu }
    for _, b in ipairs(buttons) do tint(b.icon, T.text3) end
    headerAt(ui.header, card, pad, W, m.header, buttons)
    ui.header.guideName = m.guideName
    local y = -36

    -- The current step. Long instructions get a size smaller, never cut off.
    local long = #P.plain(m.headline) > 70
    local headSize = long and base + 1 or base + 2
    setIcon(ui.icon, m.icon)
    tint(ui.icon, TINT[m.tint] or T.text2)
    ui.icon:ClearAllPoints()
    ui.icon:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y - floor((lineHeight(headSize) - 18) / 2))
    ui.icon:Show()
    local hasReasons = #m.reasons > 0
    local h = setText(ui.headline, long and "medium" or "semibold", headSize, T.text1, inner - 26 - (hasReasons and 22 or 0), m.headline, 0)
    ui.headline:ClearAllPoints()
    ui.headline:SetPoint("TOPLEFT", card, "TOPLEFT", pad + 26, y)
    local tickable = m.headlineEl and not m.headlineEl.optional and m.headlineEl or nil
    ui.headTick.element = tickable
    if tickable then
        ui.headTick:ClearAllPoints()
        ui.headTick:SetPoint("TOPLEFT", card, "TOPLEFT", pad - 6, y + 4)
        ui.headTick:SetSize(inner + 6 - (hasReasons and 22 or 0), h + 8)
        ui.headTick:Show()
    else
        ui.headTick:Hide()
    end
    if hasReasons then
        ui.help:ClearAllPoints()
        ui.help:SetPoint("TOPLEFT", card, "TOPLEFT", W - pad - 18, y + 1)
        tint(ui.help.icon, T.text3)
        ui.help:Show()
    else
        ui.help:Hide()
    end
    y = y - h - 3

    local contextText = m.context
    if m.distance then
        local d = ("%d yd"):format(m.distance)
        local hex = P.rgbToHex(T.text3)
        contextText = contextText and (contextText .. "  |cff" .. hex .. "·  " .. d .. "|r") or d
    end
    if contextText then
        h = setText(ui.context, "regular", base - 1, T.text2, inner - 26, contextText, 0)
        ui.context:ClearAllPoints()
        ui.context:SetPoint("TOPLEFT", card, "TOPLEFT", pad + 26, y)
        y = y - h
    else
        ui.context:Hide()
    end
    y = y - 8

    local nWarn, nRow = 0, 0
    if not collapsed then
        for _, text in ipairs(m.warnings) do
            nWarn = nWarn + 1
            local r = acquire(ui.warnings, nWarn, card)
            r.clickable, r.element, r.tipTitle, r.tipLines = false, nil, nil, nil
            y = y - rowAt(r, card, pad + 20, y, inner - 20, "warn", C.warn, text, "regular", base - 1, C.warn, 0)
        end
        for _, row in ipairs(m.rows) do
            nRow = nRow + 1
            y = y - objectiveRow(acquire(ui.rows, nRow, card), card, pad + 20, y, inner - 20, row, base)
        end
    end
    hideFrom(ui.warnings, nWarn + 1)
    hideFrom(ui.rows, nRow + 1)

    -- Up next: the steps coming up, scrollable. The one the second arrow points at is marked in
    -- the arrow's colour. Scrolling up goes past the step you're on to the steps behind you: done
    -- ones in green with a tick, skipped ones grey.
    y = y - 6
    placeDivider(ui.divNext, card, pad, y, inner)
    y = y - 11
    local list = m.upcoming
    local past = m.past or {}
    local k = #past
    local seq = {} -- past steps, the step you're on, then the steps coming up
    for _, u in ipairs(past) do seq[#seq + 1] = u end
    seq[#seq + 1] = m.current
    for _, u in ipairs(list) do seq[#seq + 1] = u end
    local count = collapsed and 1 or db.nextCount
    -- Offset 0 starts the list at the first step coming up; below 0 is going back in time.
    local offset = max(-(k + 1), min(Card.offset or 0, max(0, #list - count)))
    Card.offset = offset
    local first = k + 2 + offset
    local lastRow = min(#seq, first + count - 1)
    local looking = first <= k -- the top row is a step behind you
    h = setText(ui.nextLabel, "medium", base - 3, T.text3, inner / 2, looking and "EARLIER STEPS" or "UP NEXT", 1)
    ui.nextLabel:ClearAllPoints()
    ui.nextLabel:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
    ui.nowButton:Hide()
    if offset < 0 then
        -- Scrolled back: a way back to the steps coming up.
        setText(ui.nextCount, "medium", base - 3, T.text2, inner / 2, "BACK TO UP NEXT", 1, "RIGHT")
        ui.nextCount:ClearAllPoints()
        ui.nextCount:SetPoint("TOPLEFT", card, "TOPLEFT", pad + inner / 2, y)
        local w = (ui.nextCount:GetStringWidth() or 60) + 8
        ui.nowButton:ClearAllPoints()
        ui.nowButton:SetPoint("TOPLEFT", card, "TOPLEFT", pad + inner - w + 4, y + 4)
        ui.nowButton:SetSize(w, h + 8)
        ui.nowButton:Show()
    elseif #list > count then
        setText(ui.nextCount, "medium", base - 3, T.text3, inner / 2, ("%d–%d OF %d"):format(offset + 1, min(#list, offset + count), #list), 1, "RIGHT")
        ui.nextCount:ClearAllPoints()
        ui.nextCount:SetPoint("TOPLEFT", card, "TOPLEFT", pad + inner / 2, y)
    else
        ui.nextCount:Hide()
    end
    y = y - h - 4
    local listTop = y
    local nNext = 0
    for i = first, lastRow do
        local u = seq[i]
        if u then
            nNext = nNext + 1
            y = y - nextRowAt(acquire(ui.next, nNext, card, newNextRow), pad - 6, y, inner + 12, u, not u.status and u.index == m.arrowIndex, base)
        end
    end
    hideFrom(ui.next, nNext + 1)
    if nNext == 0 then
        h = setText(ui.nextEmpty, "regular", base - 1, T.text3, inner, "Nothing else in this guide.", 1)
        ui.nextEmpty:ClearAllPoints()
        ui.nextEmpty:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y - 2)
        y = y - h - 4
    else
        ui.nextEmpty:Hide()
    end
    ui.nextArea:ClearAllPoints()
    ui.nextArea:SetPoint("TOPLEFT", card, "TOPLEFT", 0, listTop + 18)
    ui.nextArea:SetSize(W, listTop - y + 18)
    ui.nextArea:Show()

    -- A notice: steps RestedXP skipped, or an offer to jump ahead.
    local notice = not collapsed and Card.notice or nil
    if notice then
        y = y - 8
        placeDivider(ui.divNotice, card, pad, y, inner)
        y = y - 11
        local jump = notice.kind == "jump"
        setIcon(ui.notice.icon, jump and "skip" or (notice.kind == "skip" and "info" or "undo"))
        tint(ui.notice.icon, jump and accent or T.text3)
        h = setText(ui.notice.text, "regular", base - 1, T.text2, inner - 20 - 22, notice.text, 3)
        ui.notice:ClearAllPoints()
        ui.notice:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
        ui.notice:SetSize(inner - 22, h)
        ui.notice.icon:ClearAllPoints()
        ui.notice.icon:SetPoint("TOPLEFT", ui.notice, "TOPLEFT", 0, -floor((lineHeight(base - 1) - 13) / 2))
        ui.notice.text:ClearAllPoints()
        ui.notice.text:SetPoint("TOPLEFT", ui.notice, "TOPLEFT", 20, 0)
        ui.notice:Show()
        ui.noticeClose:ClearAllPoints()
        ui.noticeClose:SetPoint("TOPLEFT", card, "TOPLEFT", W - pad - 18, y + 4)
        tint(ui.noticeClose.icon, T.text3)
        ui.noticeClose:Show()
        y = y - h
        if jump then
            y = y - 8
            ui.jump:Setup(("Jump to step %d"):format(notice.index), nil, "skip", "accent", base - 1)
            ui.jump:ClearAllPoints()
            ui.jump:SetPoint("TOPLEFT", card, "TOPLEFT", pad + 20, y)
            ui.jump:Show()
            y = y - 24
        else
            ui.jump:Hide()
        end
    else
        ui.divNotice:Hide()
        ui.notice:Hide()
        ui.noticeClose:Hide()
        ui.jump:Hide()
    end

    -- Footer: Back and Skip.
    if not collapsed then
        y = y - 10
        placeDivider(ui.divFooter, card, pad, y, inner)
        y = y - 9
        ui.back:Setup("Back", "left", nil, "ghost", base - 1)
        ui.back:ClearAllPoints()
        ui.back:SetPoint("TOPLEFT", card, "TOPLEFT", pad - 8, y)
        ui.back:Show()
        ui.skip:Setup("Skip", nil, "right", "ghost", base - 1)
        ui.skip:ClearAllPoints()
        ui.skip:SetPoint("TOPLEFT", card, "TOPLEFT", W - pad + 8 - ui.skip:GetWidth(), y)
        ui.skip:Show()
        ui.done:Setup("Done", "check", nil, "ghost", base - 1)
        ui.done:ClearAllPoints()
        ui.done:SetPoint("TOPLEFT", card, "TOPLEFT", floor((W - ui.done:GetWidth()) / 2 + 0.5), y)
        ui.done:Show()
        y = y - 24
    else
        ui.divFooter:Hide()
        ui.back:Hide()
        ui.skip:Hide()
        ui.done:Hide()
    end
    card:SetHeight(-y + 10)
end

-- The along-the-way card: every open #completewith step with all its lines.
function Card.RenderAlong(m)
    local blocks = m.along
    if not db.along or #blocks == 0 then
        along:Hide()
        return
    end
    local W = db.cardWidth
    local base = db.cardTextSize
    local pad = 14
    local inner = W - pad * 2
    along:SetWidth(W)
    paintPanel(along)
    setIcon(ui.alongCollapse.icon, db.alongCollapsed and "down" or "up")
    tint(ui.alongCollapse.icon, T.text3)
    local open = 0
    for _, b in ipairs(blocks) do if not b.tip then open = open + 1 end end
    headerAt(ui.alongHeader, along, pad, W, open > 0 and ("ALONG THE WAY  ·  %d"):format(open) or "ALONG THE WAY", { ui.alongCollapse })
    local y = -36
    local nRow, nDiv = 0, 0
    if not db.alongCollapsed then
        for bi, b in ipairs(blocks) do
            if bi > 1 then
                y = y - 4
                nDiv = nDiv + 1
                ui.alongDividers[nDiv] = ui.alongDividers[nDiv] or divider(along)
                placeDivider(ui.alongDividers[nDiv], along, pad, y, inner)
                y = y - 9
            end
            local indent = 0
            if b.title then
                nRow = nRow + 1
                local r = acquire(ui.alongRows, nRow, along)
                r.clickable, r.element = false, nil
                r.tipTitle = b.tip and "Tip" or (b.index and ("Step %d"):format(b.index)) or nil
                r.tipLines = { P.plain(b.title) }
                y = y - rowAt(r, along, pad - 6, y, inner + 6, b.icon, TINT[b.tint] or T.text2, b.title, "regular", base - 1, T.text2, 0)
                indent = 20
            end
            for _, row in ipairs(b.rows) do
                nRow = nRow + 1
                y = y - objectiveRow(acquire(ui.alongRows, nRow, along), along, pad - 6 + indent, y, inner + 6 - indent, row, base - 1)
            end
        end
    end
    hideFrom(ui.alongRows, nRow + 1)
    for i = nDiv + 1, #ui.alongDividers do ui.alongDividers[i]:Hide() end
    along:SetHeight(-y + 8)
    Card.PlaceAlong()
    along:Show()
end

-- ---------------------------------------------------------------- keeping up

local function signature(m)
    local parts = {
        m.header, m.headline, m.icon, m.context or "", tostring(m.distance), #m.warnings, #m.rows,
        db.cardWidth, db.cardTextSize, db.cardPalette, db.cardTheme, db.nextCount, tostring(db.cardCollapsed),
        tostring(db.alongCollapsed), tostring(db.along), tostring(db.alongDock), tostring(db.cardHidesRXP), P.rgbToHex(db.color),
        tostring(Card.offset), tostring(m.arrowIndex),
    }
    for _, w in ipairs(m.warnings) do parts[#parts + 1] = w end
    for _, r in ipairs(m.rows) do parts[#parts + 1] = r.text .. (r.done and "+" or "-") end
    for _, b in ipairs(m.along) do
        parts[#parts + 1] = (b.title or "") .. "|"
        for _, r in ipairs(b.rows) do parts[#parts + 1] = r.text .. (r.done and "+" or "-") end
    end
    for _, u in ipairs(m.upcoming) do parts[#parts + 1] = u.index .. u.label .. tostring(u.distance) .. tostring(u.place ~= nil) end
    for _, u in ipairs(m.past or {}) do parts[#parts + 1] = u.index .. u.status end
    local notice = Card.notice
    parts[#parts + 1] = notice and (notice.kind .. notice.text) or "-"
    return table.concat(parts, "\031")
end

function Card.BuildModel()
    local guide = rxp.currentGuide
    local cur = P.call(rxp.GetGuideProgress)
    local step = type(cur) == "number" and guide.steps[cur]
    if type(step) ~= "table" then return nil end
    local m = {}
    local name = P.plain(tostring(guide.displayname or guide.name or ""))
    m.guideName = name
    m.header = ("Step %d of %d"):format(step.index or cur, #guide.steps):upper()
    if name ~= "" then m.header = m.header .. "  ·  " .. name:upper() end
    buildCurrent(m, step)
    buildAlong(m, step)
    buildUpcoming(m, guide, cur)
    buildPast(m, guide, cur)
    -- The step you're on, as a row in the step list (seen when you scroll back).
    m.current = {
        index = step.index or cur, step = step, label = P.plain(m.headline or ""), icon = m.icon, tint = m.tint,
        status = "current", distance = m.distance, place = m.distance and m.target or nil,
    }
    m.next = m.upcoming[1]
    return m
end

local function shouldShow()
    if not ready() or not db.card then return false end
    local profile = rxp.settings and rxp.settings.profile
    if profile and (profile.showEnabled == false or profile.hideGuideWindow) then return false end
    local guide = rxp.currentGuide
    return type(guide) == "table" and not guide.empty and type(guide.steps) == "table"
end

local function hideAll()
    if card:IsShown() then card:Hide() end
    if along:IsShown() then along:Hide() end
end

function Card.Update()
    if not card then return end
    if not shouldShow() then
        hideAll()
        if rxp then fadeRXP(false) end
        return
    end
    Card.CheckProgress()
    local notice = Card.notice
    if notice and notice.time and GetTime() - notice.time > NOTICE_SECONDS then Card.notice = nil end
    local m = Card.BuildModel()
    if not m then
        hideAll()
        fadeRXP(false)
        return
    end
    Card.model = m
    local sig = signature(m)
    if Card.dirty or sig ~= Card.lastSignature then
        Card.dirty = false
        Card.blank = false
        Card.Render(m)
        Card.RenderAlong(m)
        Card.refont = false
        Card.lastSignature = signature(m) -- the offset may have been clamped while drawing
        if Card.blank then
            -- A text came out blank (its font wasn't ready): set the fonts again on the next tick.
            Card.blankRetries = (Card.blankRetries or 0) + 1
            if Card.blankRetries <= 40 then
                Card.dirty, Card.refont = true, true
            end
        end
    end
    if not card:IsShown() then card:Show() end
    fadeRXP(db.cardHidesRXP)
end

-- Settings changed: redraw, and move the cards if their positions were reset.
function Card.Apply()
    if not card then return end
    Card.dirty = true
    if ready() and (not db.cardPoint or not db.alongPoint) then Card.Place() end
    Card.Update()
    if Card.Skin then Card.Skin.ApplyAll() end
end

function Card.Init()
    if not ready() then return end
    if not card then createCards() end
    Card.Place()
    local ticker = CreateFrame("Frame")
    local elapsed, sinceScan = 0, 1
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        sinceScan = sinceScan + dt
        if elapsed >= 0.25 then
            elapsed = 0
            Card.Update()
        end
        if sinceScan >= 1 then
            sinceScan = 0
            if Card.Skin then Card.Skin.Scan() end -- RestedXP makes some of its windows later on
        end
    end)
    ticker:RegisterEvent("QUEST_ACCEPTED")
    ticker:RegisterEvent("PLAYER_LOGOUT")
    ticker:SetScript("OnEvent", function(_, event, a, b)
        if event == "QUEST_ACCEPTED" then
            -- Forever passes (questID); older clients pass (logIndex, questID).
            Card.OnQuestAccepted(b or a)
        elseif event == "PLAYER_LOGOUT" then
            fadeRXP(false, true) -- leave RestedXP's window as it was, whatever gets saved
        end
    end)
    Card.ticker = ticker
    Card.Update()
    if Card.Nearby then Card.Nearby.Init() end
    -- Draw again, fonts and all, a few times while the game finishes loading.
    if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 1, 3, 8 }) do
            C_Timer.After(delay, function()
                Card.dirty, Card.refont = true, true
                Card.Update()
            end)
        end
    end
end

-- /rxpe debug: what the card's texts look like to the game, for when something doesn't show.
function Card.Debug(out)
    out = out or print
    if not card then
        out("card: not built (RestedXP or the card is off)")
        return
    end
    out(("card: shown %s, visible %s, alpha %.2f, scale %.2f, size %dx%d, theme %s"):format(
        tostring(card:IsShown()), tostring(card:IsVisible()), card:GetAlpha() or 0, card:GetEffectiveScale() or 0,
        floor(card:GetWidth() or 0), floor(card:GetHeight() or 0), tostring(db and db.cardTheme)))
    local function fsLine(name, fs)
        if not fs then return end
        local file, size = fs:GetFont()
        local r, g, b, a = fs:GetTextColor()
        local sx, sy = fs:GetShadowOffset()
        local text = fs:GetText() or ""
        out(("  %s: \"%s\" font %s %s, colour %.2f %.2f %.2f %.2f, shadow %s,%s, width %d, shown %s/%s"):format(
            name, P.plain(text):sub(1, 24), tostring(file and file:match("[^\\/]+$")), tostring(size),
            r or -1, g or -1, b or -1, a or -1, tostring(sx), tostring(sy),
            floor(fs:GetStringWidth() or 0), tostring(fs:IsShown()), tostring(fs:IsVisible())))
    end
    fsLine("header", ui.header.text)
    fsLine("headline", ui.headline)
    fsLine("row 1", ui.rows[1] and ui.rows[1].text)
    fsLine("up next", ui.nextLabel)
    fsLine("next row", ui.next[1] and ui.next[1].text)
    fsLine("back", ui.back.text)
    out(("  redraws for blank text: %d"):format(Card.blankRetries or 0))
    if Card.Nearby then
        local names = Card.Nearby.Names()
        out(("active targets nearby: %s (highlight %s)"):format(#names > 0 and table.concat(names, ", ") or "none seen",
            db and db.targetGlow and "on" or "off"))
    end
end

-- ---------------------------------------------------------------- RestedXP's other windows
-- Active items, active targets and level splits get the cards' look. Only how they look changes:
-- their buttons are RestedXP's own (secure item and targeting buttons) and stay untouched, and
-- RestedXP keeps placing and sizing everything. Each time RestedXP redraws one of them, the look
-- goes back on.

local Skin = {}
Card.Skin = Skin

-- top/left/right/bottom: how far the card-style panel reaches past the window (RestedXP's title
-- tab sits above it, and level splits' text runs close to its edges).
-- header: lay the title row out like the cards' (cog, then the label, inside the panel).
-- hideBG: RestedXP's own "hide the background" setting for that window, which is kept.
Skin.WINDOWS = {
    { name = "RXPItemFrame", top = 10, hideBG = "activeItemHideBG", sizeTitle = true, cropButtons = true },
    { name = "RXPTargetFrame", top = 8, hideBG = "hideActiveTargetsBackground", sizeTitle = true },
    { name = "RXPLevelSplits", top = 22, left = -6, right = 8, bottom = -8, hideBG = "hideSplitsBackground", cog = true, header = true },
}

local function skinOf(f, spec)
    local s = f.rxnSkin
    if s then return s end
    -- An empty frame that only marks the area to cover: the window plus its title tab.
    local box = CreateFrame("Frame", nil, f)
    box:EnableMouse(false)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", spec.left or 0, spec.top or 0)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", spec.right or 0, spec.bottom or 0)
    -- The pieces are the window's own textures, so RestedXP's buttons (its children) draw on top.
    s = {
        box = box,
        layers = { nineSlice(f, PANEL_FILE, "BACKGROUND", 8, -7, box), nineSlice(f, PANEL_FILE, "BACKGROUND", 8, -6, box) },
        edge = nineSlice(f, BORDER_FILE, "BORDER", 8, nil, box),
    }
    for _, l in ipairs(s.layers) do l:SetShown(false) end
    s.edge:SetShown(false)
    f.rxnSkin = s
    return s
end

local function iconCoords(name)
    local i = ICON_INDEX[name] or 0
    local col, row = i % 8, floor(i / 8)
    return col / 8, (col + 1) / 8, row / 8, (row + 1) / 8
end

local function restore(spec, f, s)
    s.on = false
    for _, l in ipairs(s.layers) do l:SetShown(false) end
    s.edge:SetShown(false)
    local title = f.title
    local text = title and title.text
    if text and s.titleText then
        text:SetText(s.titleText)
        text.rxnFile, text.rxnShadow = nil, nil
        if rxp.font then pcall(text.SetFont, text, rxp.font, 9, "") end
        text:SetShadowColor(0, 0, 0, 0)
    end
    if spec.cropButtons then
        for _, btn in ipairs(f.buttonList or {}) do
            if btn.icon then btn.icon:SetTexCoord(0, 1, 0, 1) end
        end
    end
    if spec.header and title and s.moved then
        -- RestedXP's own layout (LevelingTracker.lua CreateLevelSplits).
        s.moved = false
        title:ClearAllPoints()
        title:SetPoint("TOP", f, "TOP", 0, 5)
        title:SetHeight(17)
        if text then
            text:ClearAllPoints()
            text:SetPoint("CENTER", title, "CENTER", 0, 1)
            text:SetJustifyH("CENTER")
        end
        if title.cog then
            title.cog:ClearAllPoints()
            title.cog:SetSize(18, 18)
            title.cog:SetPoint("LEFT", title, "LEFT", -9, 0)
        end
    end
    if spec.cog and title and title.cog and s.cogDone then
        s.cogDone = false
        local file = type(rxp.GetV1Texture) == "function" and P.call(rxp.GetV1Texture, "rxp_cog-32")
        if file then pcall(title.cog.SetNormalTexture, title.cog, file) end
        local tex = title.cog:GetNormalTexture()
        if tex then tex:SetTexCoord(0, 1, 0, 1) tex:SetVertexColor(1, 1, 1, 1) end
    end
    -- RestedXP's own look back.
    Skin.busy = true
    if type(f.UpdateVisuals) == "function" then
        pcall(f.UpdateVisuals, f)
    elseif spec.name == "RXPLevelSplits" then
        if rxp.tracker and type(rxp.tracker.RenderSplitsBackground) == "function" then
            pcall(rxp.tracker.RenderSplitsBackground, rxp.tracker)
        end
        local backdrop = rxp.RXPFrame and rxp.RXPFrame.backdrop
        if title and title.SetBackdrop and backdrop and backdrop.edge then
            pcall(title.SetBackdrop, title, backdrop.edge)
            if type(rxp.colors) == "table" and type(rxp.colors.background) == "table" then
                pcall(title.SetBackdropColor, title, unpack(rxp.colors.background))
            end
        end
        local tc = rxp.activeTheme and rxp.activeTheme.textColor
        if text and type(tc) == "table" then text:SetTextColor(unpack(tc)) end
    end
    Skin.busy = false
end

function Skin.Apply(spec, f)
    if Skin.busy or not (f and ready()) then return end
    local s = skinOf(f, spec)
    if not (db.card and db.skinRXP) then -- the enhanced UI off, or just this part of it
        if s.on then restore(spec, f, s) end
        return
    end
    s.on = true
    T = THEMES[db.cardTheme] or THEMES.dark
    local profile = rxp.settings and rxp.settings.profile or {}

    -- RestedXP's own background and title tab go; the card-style panel takes their place.
    local v2 = rxp.ui and rxp.ui.v2
    if f.v2 and v2 and type(v2.SetFrameBackdropShown) == "function" then
        pcall(v2.SetFrameBackdropShown, v2, f, false)
        if f.title then pcall(v2.SetFrameBackdropShown, v2, f.title, false) end
    end
    if f.ClearBackdrop then pcall(f.ClearBackdrop, f) end
    if f.title and f.title.ClearBackdrop then pcall(f.title.ClearBackdrop, f.title) end
    if spec.hideBG and profile[spec.hideBG] then
        for _, l in ipairs(s.layers) do l:SetShown(false) end
        s.edge:SetShown(false)
    else
        paintPanel(s)
        s.edge:SetShown(true)
    end

    -- The title as a quiet label, like the cards' top rows.
    local title = f.title
    local text = title and title.text
    if text then
        s.titleText = s.titleText or text:GetText()
        text.rxnFile, text.rxnShadow = nil, nil -- RestedXP may have set its own font since
        setFont(text, "medium", 10)
        setShadow(text)
        text:SetText(tostring(s.titleText or ""):upper())
        text:SetTextColor(T.text3[1], T.text3[2], T.text3[3], 1)
        if spec.sizeTitle then title:SetSize(floor((text:GetStringWidth() or 60) + 10.5), 19) end
    end
    -- A title row inside the panel, like the cards': the cog at the left edge, then the label.
    if spec.header and title then
        s.moved = true
        local pad = 12
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", s.box, "TOPLEFT", 0, 0)
        title:SetHeight(spec.top or 20)
        local textX = pad + (title.cog and 20 or 0)
        title:SetWidth(max(title:GetWidth() or 0, floor((text and text:GetStringWidth() or 60) + textX + pad + 0.5)))
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", title, "LEFT", textX, 0)
            text:SetJustifyH("LEFT")
        end
        if title.cog then
            title.cog:ClearAllPoints()
            title.cog:SetSize(14, 14)
            title.cog:SetPoint("LEFT", title, "LEFT", pad, 0)
        end
    end
    if spec.cog and title and title.cog then
        local cog = title.cog
        if not s.cogDone then
            s.cogDone = true
            pcall(cog.SetNormalTexture, cog, ICON_FILE)
        end
        local tex = cog:GetNormalTexture()
        if tex then
            tex:SetTexCoord(iconCoords("settings"))
            tex:SetVertexColor(T.text3[1], T.text3[2], T.text3[3], 1)
        end
    end
    -- Item icons without the game's built-in border.
    if spec.cropButtons then
        for _, btn in ipairs(f.buttonList or {}) do
            if btn.icon then btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
    end
end

local function hookWindow(spec, f)
    if f.rxnHooked then return end
    f.rxnHooked = true
    local function again() Skin.Apply(spec, f) end
    if type(f.UpdateVisuals) == "function" then hooksecurefunc(f, "UpdateVisuals", again) end
    if type(f.UpdateFrame) == "function" then hooksecurefunc(f, "UpdateFrame", again) end
    if spec.name == "RXPItemFrame" and type(rxp.UpdateItemFrame) == "function" then
        hooksecurefunc(rxp, "UpdateItemFrame", again)
    elseif spec.name == "RXPTargetFrame" and type(rxp.targeting) == "table"
        and type(rxp.targeting.RenderTargetFrameBackground) == "function" then
        hooksecurefunc(rxp.targeting, "RenderTargetFrameBackground", again)
    elseif spec.name == "RXPLevelSplits" and type(rxp.tracker) == "table"
        and type(rxp.tracker.RenderSplitsBackground) == "function" then
        hooksecurefunc(rxp.tracker, "RenderSplitsBackground", again)
    end
    f:HookScript("OnShow", again)
end

-- Finds RestedXP's windows (some are made later on) and skins any new ones.
function Skin.Scan()
    if not ready() then return end
    for _, spec in ipairs(Skin.WINDOWS) do
        local f = _G[spec.name]
        if type(f) == "table" and f.GetObjectType and not f.rxnHooked then
            hookWindow(spec, f)
            Skin.Apply(spec, f)
        end
    end
end

-- Settings changed: the look, the theme, or skinning turned on or off.
function Skin.ApplyAll()
    if not ready() then return end
    for _, spec in ipairs(Skin.WINDOWS) do
        local f = _G[spec.name]
        if type(f) == "table" and f.rxnHooked then Skin.Apply(spec, f) end
    end
    Skin.Scan()
end

-- ---------------------------------------------------------------- active targets that are nearby
-- RestedXP's Active targets window holds a button per NPC the step wants. Each one whose NPC is
-- near you gets a soft green ring, even if you haven't targeted or moused over it. Nearby means:
-- its nameplate is on screen (the game hands addons the units with nameplates; names are readable
-- out in the world), or RestedXP's own proximity scan just found it (when "show targets on
-- proximity" is on in RestedXP: it calls TargetUnit(name), which the game blocks only when that
-- unit is close, and this listens for those blocks). RestedXP's buttons are secure and stay
-- untouched: the rings are separate frames drawn under them.

local Nearby = { plates = {}, hits = {}, glows = {} }
Card.Nearby = Nearby
local HIT_SECONDS = 5 -- RestedXP's own window for a proximity hit
local RESCAN_SECONDS = 0.5

local function unitName(unit)
    local ok, name = pcall(UnitName, unit)
    if not ok or name == nil then return nil end
    if issecretvalue and issecretvalue(name) then return nil end -- hidden in instances and fights
    return type(name) == "string" and name or nil
end
Nearby.UnitName = unitName

function Nearby.Rescan()
    local plates = Nearby.plates
    for unit in pairs(plates) do plates[unit] = nil end
    local list = C_NamePlate and C_NamePlate.GetNamePlates and P.call(C_NamePlate.GetNamePlates)
    for _, plate in ipairs(type(list) == "table" and list or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        local name = unit and unitName(unit)
        if name then plates[unit] = name end
    end
end

function Nearby.IsNear(name)
    if type(name) ~= "string" then return false end
    for _, n in pairs(Nearby.plates) do
        if n == name then return true end
    end
    local t = Nearby.hits[name]
    return t ~= nil and GetTime() - t < HIT_SECONDS
end

-- Names near you right now, for /rxpe debug.
function Nearby.Names()
    local out, seen = {}, {}
    for _, n in pairs(Nearby.plates) do
        if not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    for n, t in pairs(Nearby.hits) do
        if not seen[n] and GetTime() - t < HIT_SECONDS then seen[n] = true; out[#out + 1] = n .. " (RestedXP's scan)" end
    end
    table.sort(out)
    return out
end

-- A ring behind a button: a rounded fill 2 px bigger than the icon, on a frame of the targets
-- window just under its buttons.
local function glowFor(f, btn)
    local g = Nearby.glows[btn]
    if g then return g end
    local box = CreateFrame("Frame", nil, f)
    box:EnableMouse(false)
    box:SetFrameLevel(f:GetFrameLevel())
    box:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    g = { box = box, fill = nineSlice(box, PANEL_FILE, "BACKGROUND", 6) }
    g.fill:SetColor(C.success[1], C.success[2], C.success[3], 1)
    box:Hide()
    Nearby.glows[btn] = g
    return g
end

local sinceScan = RESCAN_SECONDS
function Nearby.Update(elapsed)
    local f = _G.RXPTargetFrame
    local on = db and db.targetGlow and type(f) == "table" and f.IsShown and f:IsShown()
    if not on then
        for _, g in pairs(Nearby.glows) do if g.box:IsShown() then g.box:Hide() end end
        return
    end
    sinceScan = sinceScan + (elapsed or 0)
    if sinceScan >= RESCAN_SECONDS then
        sinceScan = 0
        Nearby.Rescan()
    end
    -- A slow pulse, so a found target draws the eye without flashing.
    local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 4))
    for _, list in ipairs({ f.enemyTargetButtons or {}, f.friendlyTargetButtons or {} }) do
        for _, btn in ipairs(list) do
            local data = btn.targetData
            local near = btn:IsShown() and type(data) == "table" and Nearby.IsNear(data.name)
            local g = (near or Nearby.glows[btn]) and glowFor(f, btn)
            if g then
                if near then
                    g.box:SetAlpha(pulse)
                    if not g.box:IsShown() then g.box:Show() end
                elseif g.box:IsShown() then
                    g.box:Hide()
                end
            end
        end
    end
end

function Nearby.Init()
    if Nearby.frame then return end
    local ev = CreateFrame("Frame")
    Nearby.frame = ev
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    pcall(ev.RegisterEvent, ev, "ADDON_ACTION_FORBIDDEN")
    local pendingHit = false
    ev:SetScript("OnEvent", function(_, event, a, b)
        if event == "NAME_PLATE_UNIT_ADDED" then
            local name = a and unitName(a)
            if name then Nearby.plates[a] = name end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if a then Nearby.plates[a] = nil end
        elseif event == "ADDON_ACTION_FORBIDDEN" then
            -- RestedXP's proximity scan: the game blocked its TargetUnit(name), so that unit is close.
            if a == "RXPGuides" and b == "TargetUnit()" then pendingHit = true end
        end
    end)
    -- The name it was scanning for: seen right after the blocked call returns.
    if type(TargetUnit) == "function" then
        hooksecurefunc("TargetUnit", function(name)
            if pendingHit and type(name) == "string" then Nearby.hits[name] = GetTime() end
            pendingHit = false
        end)
    end
    ev:SetScript("OnUpdate", function(_, elapsed) Nearby.Update(elapsed) end)
end

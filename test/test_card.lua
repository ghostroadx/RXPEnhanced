-- Offline checks for RXP Enhanced's guide card, with real steps from the 01-13 launch route.
-- lua5.1 test_card.lua [dumpdir]   (with a dump dir, writes the card's layout for tools/render_card.py)
local M = dofile("mock.lua")
local dumpDir = arg and arg[1]

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1 else failed = failed + 1; io.stdout:write("FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "") .. "\n") end
end

local RXP, Q = M.RXP, M.quests
local goto, text, accept, turnin, complete, step = M.goto, M.text, M.accept, M.turnin, M.complete, M.step
Q.names = { [363] = "Rude Awakening", [364] = "The Mindless Ones", [365] = "Fresh Meat", [91209] = "Continue Your Training", [376] = "The Damned" }

local wellFed = "|cRXP_WARN_Not Well Fed? If you have cooked food, sit and eat for 10 seconds before you start killing. In Forever, Well Fed also gives +5% XP from kills for 15 minutes.|r"
local function guide()
    return {
        step({ goto(100, 0), text("Talk to |cRXP_FRIENDLY_Undertaker Mordo|r"), accept(363, "Accept Rude Awakening"),
            { tag = "target" }, goto(90, 10, { hidePin = true, radius = 20 }) }),                                        -- 1
        step({ M.check(wellFed), { tag = "aura" } }, { sticky = true }),                                                 -- 2
        step({ M.xp(5, "Grind to level 5"), goto(60, 40) }),                                                              -- 3
        step({ M.vendor(2113, "Vendor trash"), goto(30, 50) }),                                                           -- 4
        step({ goto(32, 52), text("Talk to |cRXP_FRIENDLY_Margaret Weaver|r, the skinning trainer, right next to the vendor. Train Skinning and buy a Skinning Knife from her"),
            M.train(8613, "Train Skinning"), M.collect(7005, "Skinning Knife: 0/1") }),                                  -- 5
        step({ text("Talk to |cRXP_FRIENDLY_Aramis Hammerhand|r, the Paladin trainer"), accept(91209, "Accept Continue Your Training"),
            M.train(465, "Train Devotion Aura"), M.train(19740, "Train Blessing of Might"), M.train(20271, "Train Judgement"), goto(31, 66) }), -- 6
        step({ goto(30, 66), text("Talk to |cRXP_FRIENDLY_Shadow Priest Sarvis|r"), turnin(363, "Turn in Rude Awakening"),
            accept(364, "Accept The Mindless Ones") }),                                                                  -- 7
        step({ goto(-40, 80), text("Kill |cRXP_ENEMY_Mindless Zombies|r and |cRXP_ENEMY_Wretched Zombies|r around the graveyard"),
            complete(364, 1, "Mindless Zombie slain: 3/8"), complete(364, 2, "Wretched Zombie slain: 0/8") }),          -- 8
        step({ goto(5, 5), text("Talk to |cRXP_FRIENDLY_Novice Elreth|r"), accept(365, "Accept Fresh Meat") }),          -- 9
        step({ goto(30, 66), text("Talk to |cRXP_FRIENDLY_Shadow Priest Sarvis|r"), turnin(364, "Turn in The Mindless Ones"),
            accept(376, "Accept The Damned") }),                                                                         -- 10
        step({ goto(200, 200), text("Travel to Deathknell's east gate") }),                                             -- 11
    }
end

-- ---------------------------------------------------------------- load
M.setGuide(guide())
assert(loadfile("../RXPEnhanced/RXPEnhanced.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Card.lua"))("RXPEnhanced")
assert(loadfile("../RXPEnhanced/Toast.lua"))("RXPEnhanced")
local NS, Card = RXPEnhanced, RXPEnhanced.Card
local driver
for _, f in ipairs(M.frames) do if f.events.PLAYER_LOGIN then driver = f end end
-- The layout checks below were written against these settings (the defaults before 1.6.1).
local CLASSIC = { nextCount = 4, cardTextSize = 13, cardWidth = 300, cardTheme = "dark", scale = 0.85,
    color = { 0xd1 / 255, 0x70 / 255, 0x6b / 255 }, wpScale = 1, wpColor = { 0xf2 / 255, 0xc7 / 255, 0x5c / 255 },
    wpSound = "glass", wpNewSound = false }
RXPEnhancedDB = {}
for k, v in pairs(CLASSIC) do RXPEnhancedDB[k] = v end
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
local card = RXPEnhancedCard
local db = RXPEnhancedDB
local function update() M.now = M.now + 0.3; Card.Update() end
local function goStep(n) RXP.SetStep(n); update() end
local function find(t, pred) for _, v in ipairs(t or {}) do if pred(v) then return v end end end
local function shownRows(pool) local out = {} for _, r in ipairs(pool) do if r.shown then out[#out + 1] = r end end return out end
local ui = nil
local function dump(name)
    if not dumpDir then return end
    local along = RXPEnhancedAlongCard
    local ops = M.dump(card, 0, 0)
    local h = card.h
    if along.shown then
        M.dump(along, 0, card.h + 8, ops)
        h = card.h + 8 + along.h
    end
    local f = assert(io.open(dumpDir .. "/" .. name .. ".json", "w"))
    f:write(M.json({ w = card.w, h = h, ops = ops }))
    f:close()
end

check("card: built on login", card ~= nil and Card.ticker ~= nil)
check("card: starts where RestedXP's window was", card.points[1] and card.points[1][2] == UIParent and card.points[1][4] == 20 * 1.1 and card.points[1][5] == 620 * 1.1, card.points[1] and card.points[1][4])

-- ---------------------------------------------------------------- a turn-in step
Q.on[363], Q.complete[363] = true, true
M.player.x, M.player.y = 0, 0
goStep(7)
check("no skip notice for RestedXP moving to your saved step just after the guide loads", Card.notice == nil)
M.now = M.now + 10
local m = Card.model
check("shown", card.shown)
check("RestedXP's window shrunk away, not hidden", RXP.RXPFrame.alpha == 0 and RXP.RXPFrame.scale <= 0.011 and RXP.RXPFrame.shown)
check("header: step and guide", m.header == "STEP 7 OF 11  ·  01-13 UD PALADIN LAUNCH ROUTE", m.header)
check("headline: the next thing to do", m.headline == "Turn in Rude Awakening", m.headline)
check("headline icon: turn in", m.icon == "turnin" and m.tint == "quest")
check("context: the instruction, colours softened", m.context == "Talk to |cff6fd08cShadow Priest Sarvis|r", m.context)
check("distance to the step", m.distance == math.floor(math.sqrt(30 * 30 + 66 * 66) + 0.5), m.distance)
check("rows: the rest of the step", #m.rows == 1 and m.rows[1].text == "Accept The Mindless Ones" and not m.rows[1].done and m.rows[1].clickable)
check("along the way: the Well Fed reminder as a tickable line", #m.along == 1 and m.along[1].title == nil and m.along[1].rows[1].text:find("Not Well Fed") and m.along[1].rows[1].clickable, #m.along)
check("along the way: on its own card, to the right by default", RXPEnhancedAlongCard.shown and RXPEnhancedAlongCard.points[1][2] == card and RXPEnhancedAlongCard.points[1][3] == "TOPRIGHT")
check("up next: the kill step first", m.next and m.next.index == 8 and m.next.label:find("^Kill Mindless Zombies") and m.next.icon == "complete", m.next and m.next.label)
check("up next: the second arrow's target is marked", m.arrowIndex == 8)
local nextRows = {}
for _, f in ipairs(M.frames) do if f.parent == card and f.num then nextRows[#nextRows + 1] = f end end
local function shownNext() local out = {} for _, r in ipairs(nextRows) do if r.shown then out[#out + 1] = r end end return out end
check("up next: four steps shown", #shownNext() == 4 and shownNext()[1].upcoming.index == 8 and shownNext()[4].upcoming.index == 11, #shownNext())
check("up next: the first has the accent bar, the others don't", shownNext()[1].bar.shown and not shownNext()[2].bar.shown)
check("up next: distance in its own column", shownNext()[1].dist.text:find("^%d+ yd$") ~= nil, shownNext()[1].dist.text)
check("up next: step numbers", shownNext()[1].num.text == "8" and shownNext()[1].num.justifyH == "RIGHT")
check("reasons: what's left and why", #m.reasons == 2 and m.reasons[1].why:find("^Ready") and m.reasons[2].why:find("Not picked up"), #m.reasons)
check("no warnings when nothing blocks", #m.warnings == 0)
local ui_ = {}
for _, f in ipairs(M.frames) do if f.parent == card then ui_[#ui_ + 1] = f end end
check("help icon shown when something's left", find(ui_, function(f) return f.shown and f.scripts.OnEnter and f.w == 18 end) ~= nil)
dump("turnin")

-- Help tooltip
local help = find(ui_, function(f) return f.w == 18 and f.h == 18 end)
help.scripts.OnEnter(help)
check("help tooltip lists each thing and why", GameTooltip.title == "Still to do" and GameTooltip.lines[1] == "Turn in Rude Awakening" and GameTooltip.lines[2]:find("^Ready"), GameTooltip.lines[1])

-- Ticking a line does what RestedXP's checkbox does.
local rows = {}
for _, f in ipairs(M.frames) do if f.parent == card and f.kind == "Button" and f.text and f.icon and not f.num then rows[#rows + 1] = f end end
local alongRows = {}
for _, f in ipairs(M.frames) do if f.parent == RXPEnhancedAlongCard and f.kind == "Button" and f.text and f.icon then alongRows[#alongRows + 1] = f end end
local acceptRow = find(rows, function(r) return r.shown and r.element and r.element.questId == 364 end)
check("row for the accept", acceptRow ~= nil)
RXP.updateSteps = false
acceptRow:Click()
check("tick: element skipped, RestedXP told", acceptRow.element.skip == true and RXP.updateSteps == true and (RXP.mapUpdates or 0) > 0)
update()
check("tick: row shows done", Card.model.rows[1].done == true)
acceptRow:Click()
update()
check("untick", Card.model.rows[1].done == false and not acceptRow.element.skip)
local wellFedRow = find(alongRows, function(r) return r.shown and r.element and r.element.text and r.element.text:find("Well Fed") end)
check("along-the-way line can be ticked too", wellFedRow ~= nil and wellFedRow.clickable)
wellFedRow:Click()
update()
check("along-the-way tick shows", Card.model.along[1].rows[1].done)
wellFedRow:Click()
update()

-- Up next: scrolling and going to a step.
db.nextCount = 2
Card.Apply()
check("fewer shown when set", #shownNext() == 2)
local first = shownNext()[1]
first.scripts.OnMouseWheel(first, -1)
check("wheel down: list moves by one", Card.offset == 1 and shownNext()[1].upcoming.index == 9, Card.offset)
local countText
for _, r in ipairs(card.regions) do if r.kind == "FontString" and r.shown and r.text and r.text:find(" OF ") then countText = r.text end end
check("wheel: shows where you are in the list", countText == "2–3 OF 4", countText)
first.scripts.OnMouseWheel(first, -5)
check("wheel down: stops at the end", Card.offset == 2)
first.scripts.OnMouseWheel(first, 2)
check("wheel up: back to the top of up next", Card.offset == 0)

-- Scrolling on up: the step you're on, then the steps behind you.
first.scripts.OnMouseWheel(first, 1)
check("wheel up past the top: the step you're on", Card.offset == -1 and shownNext()[1].upcoming.status == "current" and shownNext()[1].upcoming.index == 7)
check("the step you're on stays lit", shownNext()[1].bg.parts[1].shown and shownNext()[1].pinned)
local function label(t) for _, r in ipairs(card.regions) do if r.kind == "FontString" and r.shown and r.text == t then return r end end end
check("still labelled up next while the top row isn't behind you", label("UP NEXT") ~= nil)
check("a way back to up next", label("BACK TO UP NEXT") ~= nil)
first.scripts.OnMouseWheel(first, 20)
local past = Card.model.past
check("earlier steps: the ones RestedXP shows, oldest first", #past == 5 and past[1].index == 1 and past[5].index == 6, #past)
check("wheel up: stops at the oldest", Card.offset == -6, Card.offset)
check("labelled earlier steps", label("EARLIER STEPS") ~= nil)
check("done: the accept you made, the level you reached", past[1].status == "done" and past[2].status == "done", past[1].status)
check("skipped: a quest never picked up", past[5].status == "skipped", past[5].status)
local doneRow = shownNext()[1]
check("done row: green text, green tick, green number", doneRow.upcoming.index == 1 and doneRow.text.textColor[2] > 0.8 and doneRow.text.textColor[1] < 0.5
    and doneRow.icon.color[2] > 0.8 and doneRow.icon.coords[1] == (18 % 8) / 8 and doneRow.num.textColor[2] > 0.8, doneRow.icon.coords and doneRow.icon.coords[1])
check("done row: no distance or arrow", doneRow.dist.text == "" and not doneRow.dir.shown)
first.scripts.OnMouseWheel(first, -4)
local skipRow = shownNext()[1]
check("skipped row: grey text and the skip icon", skipRow.upcoming.index == 6 and skipRow.upcoming.status == "skipped"
    and skipRow.icon.coords[1] == (29 % 8) / 8 and math.abs(skipRow.text.textColor[1] - skipRow.text.textColor[3]) < 0.1 and skipRow.text.textColor[1] < 0.6)
skipRow.scripts.OnEnter(skipRow)
check("skipped row tooltip says so", GameTooltip.title == "Step 6  ·  Skipped" and GameTooltip.lines[#GameTooltip.lines] == "Shift-click to go back to this step.", GameTooltip.title)
skipRow.scripts.OnLeave(skipRow)
local nowButton = find(M.frames, function(f) return f.parent == card and f.kind == "Button" and f.scripts.OnClick and not f.num and not f.icon and not f.text and f.shown and f.w and f.w > 30 and f.w < 200 end)
check("back to up next button", nowButton ~= nil)
nowButton:Click()
check("back to up next", Card.offset == 0 and shownNext()[1].upcoming.index == 8)
-- A picture of the list scrolled back: earlier steps, the step you're on, the steps ahead.
db.nextCount = 6
Card.offset = -3
Card.Apply()
M.facing = 0.3
card.scripts.OnUpdate(card, 0.016)
dump("earlier")
db.nextCount = 2
Card.offset = 0
Card.Apply()
M.facing = 0
first.scripts.OnMouseWheel(first, -1)
db.nextCount = 4
Card.Apply()
shownNext()[2].scripts.OnEnter(shownNext()[2])
check("up next hover: the step's lines and how to go there", GameTooltip.title == "Step 9" and GameTooltip.lines[1] == "Talk to Novice Elreth" and GameTooltip.lines[#GameTooltip.lines] == "Shift-click to go to this step.", GameTooltip.lines[1])
shownNext()[2].scripts.OnLeave(shownNext()[2])
shownNext()[2]:Click()
check("plain click doesn't move you", RXP.progress == 7)
M.shift = true
shownNext()[2]:Click()
M.shift = false
check("shift-click goes to that step", RXP.progress == 9)
check("the list goes back to the top on a new step", (update() or true) and Card.offset == 0)
update()
check("no skip notice for a step you picked", Card.notice == nil)
goStep(7)

-- ---------------------------------------------------------------- a kill step
Q.on[364] = true
Q.objectives[364] = { { text = "Mindless Zombie slain: 8/8", finished = true }, { text = "Wretched Zombie slain: 0/8", finished = false } }
local s8 = RXP.currentGuide.steps[8]
s8.elements[3].completed = true
s8.elements[3].text = "Mindless Zombie slain: 8/8"
goStep(8)
m = Card.model
check("kill step: led by its instruction", m.headline == "Kill |cfff0806aMindless Zombies|r and |cfff0806aWretched Zombies|r around the graveyard", m.headline)
check("kill step: kill icon", m.icon == "complete" and m.tint == "combat")
check("kill step: no context line", m.context == nil)
check("kill step: counts as rows, done one ticked", #m.rows == 2 and m.rows[1].done and not m.rows[2].done and m.rows[2].text == "Wretched Zombie slain: 0/8")
check("kill step: reason is the live count", m.reasons[1] and m.reasons[1].why == "Wretched Zombie slain: 0/8", m.reasons[1] and m.reasons[1].why)
dump("kill")

-- ---------------------------------------------------------------- RestedXP skips a step
Q.on[365] = true -- already have Fresh Meat: step 9 gets passed over
s8.elements[4].completed = true
goStep(10)
m = Card.model
check("skip notice", Card.notice and Card.notice.kind == "skip" and Card.notice.text == "Skipped step 9: you already have Fresh Meat.", Card.notice and Card.notice.text)
check("skip notice: details for the hover", Card.notice.steps[1].index == 9 and Card.notice.steps[1].label == "Talk to Novice Elreth")
dump("skip")
local noticeFrame = find(ui_, function(f) return f.kind == "Frame" and f.icon and f.text end)
noticeFrame.scripts.OnEnter(noticeFrame)
check("skip hover lists the step and why", GameTooltip.title == "Skipped" and GameTooltip.lines[1] == "Step 9: Talk to Novice Elreth" and GameTooltip.lines[2] == "You already have Fresh Meat", GameTooltip.lines[2])
M.now = M.now + 50
update()
check("skip notice fades after a while", Card.notice == nil)

-- Several steps at once
Q.on[365] = nil
goStep(3)
Q.done[363] = true
RXP.currentGuide.steps[6].elements[2].completed = true
Q.on[91209] = true
goStep(7)
check("several skipped: summary", Card.notice and Card.notice.text:find("^Skipped 3 steps"), Card.notice and Card.notice.text)
check("several skipped: each listed", #Card.notice.steps == 3 and Card.notice.steps[1].index == 4)

-- ---------------------------------------------------------------- jumping ahead
Card.notice = nil
Q.done[363], Q.on[91209] = nil, nil
RXP.currentGuide.steps[6].elements[2].completed = nil
goStep(3)
Card.OnQuestAccepted(364)
update()
check("jump offer when a later quest is picked up", Card.notice and Card.notice.kind == "jump" and Card.notice.index == 7 and Card.notice.text == "You picked up The Mindless Ones. The guide gets to it at step 7.", Card.notice and Card.notice.text)
dump("jump")
Card.OnQuestAccepted(9999)
check("no offer for quests the guide doesn't have", Card.notice.index == 7)
local jumpButton = find(ui_, function(f) return f.shown and f.Setup and f.style == "accent" end)
check("jump button shown in the accent colour", jumpButton ~= nil)
jumpButton:Click()
check("jump: RestedXP sent to step 7", RXP.progress == 7 and Card.notice == nil)
update()
check("jump: no skip notice for a jump you asked for", Card.notice == nil)
Card.OnQuestAccepted(364)
check("no offer for a quest in the current step", Card.notice == nil)

-- ---------------------------------------------------------------- blockers
Q.on[363], Q.complete[363] = false, false
goStep(1)
M.logCount = 25
update()
m = Card.model
check("quest log full: warning on the card", #m.warnings == 1 and m.warnings[1]:find("quest log is full %(25/25%)"), m.warnings[1])
dump("full")
M.logCount = 5
Q.on[363], Q.complete[363] = false, false
goStep(7)
m = Card.model
check("turn-in not in the log: warning", m.warnings[1] == "Rude Awakening isn't in your quest log.", m.warnings[1])
Q.on[363], Q.complete[363] = true, true

-- ---------------------------------------------------------------- Back and Skip
goStep(7)
local back = find(ui_, function(f) return f.shown and f.Setup and f.text and f.text.text == "Back" end)
local skip = find(ui_, function(f) return f.shown and f.Setup and f.text and f.text.text == "Skip" end)
check("footer buttons", back ~= nil and skip ~= nil)
local s6 = RXP.currentGuide.steps[6]
s6.elements[3].skip = true
back:Click()
check("back: RestedXP sent to step 6", RXP.progress == 6, RXP.progress)
check("back: ticks on that step undone", s6.elements[3].skip == nil)
update()
check("back: says so", Card.notice and Card.notice.text == "Back to step 6.", Card.notice and Card.notice.text)
skip:Click()
check("skip: RestedXP sent to the next step", RXP.progress == 7)
update()
check("skip: no notice", Card.notice == nil)

-- ---------------------------------------------------------------- the travel step and the guide's end
goStep(11)
m = Card.model
check("travel step: headline from its text", m.headline == "Travel to Deathknell's east gate" and m.icon == "footprints", m.headline)
check("last step: nothing after it", m.next == nil)
dump("travel")

-- ---------------------------------------------------------------- header buttons
goStep(7)
local function headerButton(icon)
    for _, f in ipairs(ui_) do
        if f.shown and f.icon and f.w == 22 and f.icon.coords then
            local i = ({ up = 22, down = 23, settings = 24, eye = 25, eyeoff = 26, menu = 30 })[icon]
            local col, row = i % 8, math.floor(i / 8)
            if math.abs(f.icon.coords[1] - col / 8) < 1e-6 and math.abs(f.icon.coords[3] - row / 8) < 1e-6 then return f end
        end
    end
end
local eye = headerButton("eyeoff")
check("eye button shows RestedXP's window is hidden", eye ~= nil)
local calls = #RXP.setStepCalls
eye:Click()
check("eye: RestedXP's window back at its own scale", RXP.RXPFrame.alpha == 1 and RXP.RXPFrame.scale == 1.1 and db.cardHidesRXP == false)
check("eye: RestedXP lays its window out again", #RXP.setStepCalls > calls)
update()
check("eye: card stays", card.shown)
eye = headerButton("eye")
eye:Click()
check("eye again: shrunk away", RXP.RXPFrame.alpha == 0 and RXP.RXPFrame.scale <= 0.011)
headerButton("menu"):Click()
check("menu: RestedXP's guide menu", RXP.menuOpened == true)
headerButton("up"):Click()
check("collapse: rows, along the way and buttons go", #shownRows(rows) == 0 and not back.shown and db.cardCollapsed)
check("collapse: headline and Then stay", card.shown and Card.model.next ~= nil)
dump("collapsed")
headerButton("down"):Click()
check("expand", back.shown and not db.cardCollapsed)
headerButton("settings"):Click()
check("settings: opens the window", RXPEnhancedSettings and RXPEnhancedSettings.shown)
NS.OpenSettings()

-- Header drag and tooltip
local header = find(ui_, function(f) return f.kind == "Frame" and f.h == 34 end)
header.scripts.OnEnter(header)
check("header tooltip: guide name", GameTooltip.title == "01-13 UD Paladin Launch Route")
header.scripts.OnMouseDown(header, "LeftButton")
header.scripts.OnMouseUp(header)
check("drag: position saved", db.cardPoint and db.cardPoint[3] == 500)
db.cardLocked = true
header.scripts.OnMouseDown(header, "LeftButton")
check("locked: no drag", not card.moving)
db.cardLocked = false

-- ---------------------------------------------------------------- settings
NS.OpenSettings()
local wp = RXPEnhancedSettings.panel
check("settings: four tabs", #wp.tabs == 4 and wp.tabs[2].id == "waypoint" and wp.tabs[3].id == "card" and wp.tabs[4].id == "general")
wp.tabs[3]:Click()
check("settings: card tab shows its section", wp.sections.card.shown and not wp.sections.arrow.shown and not wp.sections.waypoint.shown)
local safe = find(wp.radios, function(r) return r.value == "safe" end)
safe:Click()
update()
check("palette: colour-blind safe", db.cardPalette == "safe" and Card.model.context == "Talk to |cff56b4e9Shadow Priest Sarvis|r", Card.model.context)
check("palette: radios follow", safe.checked and not find(wp.radios, function(r) return r.value == "card" end).checked)
find(wp.radios, function(r) return r.value == "rxp" end):Click()
update()
check("palette: RestedXP's own", Card.model.context == "Talk to |cFF00FF25Shadow Priest Sarvis|r", Card.model.context)
find(wp.radios, function(r) return r.value == "card" end):Click()
wp.sliders.cardTextSize:SetValue(15)
check("text size", db.cardTextSize == 15)
wp.sliders.cardWidth:SetValue(357)
check("width snaps to 10", db.cardWidth == 360 and card.w == 360, db.cardWidth)
dump("large")
wp.checks.cardHidesRXP.checked = false; wp.checks.cardHidesRXP:Click()
check("settings: show RestedXP's window", RXP.RXPFrame.alpha == 1)
wp.checks.cardHidesRXP.checked = true; wp.checks.cardHidesRXP:Click()
wp.checks.card.checked = false; wp.checks.card:Click()
check("card off: card hidden, RestedXP's window back", not card.shown and RXP.RXPFrame.alpha == 1 and RXP.RXPFrame.scale == 1.1)
check("card off: its options grey out", wp.checks.cardHidesRXP.enabled == false and safe.enabled == false)
wp.checks.card.checked = true; wp.checks.card:Click()
check("card on again", card.shown and RXP.RXPFrame.alpha == 0)
wp.resetCard:Click()
check("reset card position", db.cardPoint == nil and card.points[1] and card.points[1][3] == "LEFT")
wp.resetAll:Click()
check("reset all: card settings too, to today's defaults", db.cardTextSize == 11 and db.cardWidth == 280 and db.cardTheme == "glass"
    and db.nextCount == 3 and db.cardPalette == "card" and db.card == true)
for k, v in pairs(CLASSIC) do db[k] = v end
NS.SettingsChanged()
NS.OpenSettings()

-- ---------------------------------------------------------------- RestedXP hidden, logout, slash
RXP.settings.profile.showEnabled = false
update()
check("RestedXP turned off: card hidden, window restored", not card.shown and RXP.RXPFrame.alpha == 1)
RXP.settings.profile.showEnabled = true
update()
check("back on", card.shown and RXP.RXPFrame.alpha == 0)
RXP.settings.profile.hideGuideWindow = true
update()
check("RestedXP's window turned off in its settings: card hidden too (RestedXP pauses)", not card.shown)
RXP.settings.profile.hideGuideWindow = nil
update()
calls = #RXP.setStepCalls
Card.ticker.scripts.OnEvent(Card.ticker, "PLAYER_LOGOUT")
check("logout: window restored without re-laying it out", RXP.RXPFrame.alpha == 1 and RXP.RXPFrame.scale == 1.1 and #RXP.setStepCalls == calls)
SlashCmdList.RXPENHANCED("card")
update()
check("/rxpe card: off", db.card == false and not card.shown)
SlashCmdList.RXPENHANCED("card")
SlashCmdList.RXPENHANCED("rxp")
update()
check("/rxpe rxp: shows RestedXP's window", db.cardHidesRXP == false and RXP.RXPFrame.alpha == 1)
SlashCmdList.RXPENHANCED("rxp")

-- Event wiring: QUEST_ACCEPTED's quest ID is its only argument on Forever.
goStep(3)
Card.notice = nil
Card.ticker.scripts.OnEvent(Card.ticker, "QUEST_ACCEPTED", 364)
check("QUEST_ACCEPTED wired", Card.notice and Card.notice.index == 7)
Card.notice = nil
Card.ticker.scripts.OnEvent(Card.ticker, "QUEST_ACCEPTED", 12, 364)
check("QUEST_ACCEPTED (log index, quest ID) wired", Card.notice and Card.notice.index == 7)

-- Hidden steps and lines RestedXP hasn't filled in yet.
RXP.currentGuide.steps[4].hidewindow = true
goStep(4)
check("a step RestedXP hides shows just its number", Card.model.headline == "Step 4" and #Card.model.rows == 0, Card.model.headline)
RXP.currentGuide.steps[4].hidewindow = nil
check("objective text not filled in yet is left out", (function()
    local e = complete(364, 3)
    e.step = RXP.currentGuide.steps[8]
    table.insert(RXP.currentGuide.steps[8].elements, e)
    goStep(8)
    for _, r in ipairs(Card.model.rows) do if r.el == e then return false end end
    return true
end)())

-- ---------------------------------------------------------------- several open steps (the Gordo stretch)
Q.names[5481], Q.names[5482], Q.names[357], Q.names[1359] = "Gordo's Task", "Doom Weed", "The Lich's Identity", "Zinge's Delivery"
Q.on = { [5481] = true, [357] = true, [5482] = true }
Q.done = {}
Q.objectives = {}
M.setGuide({
    step({ goto(0, 0), text("Talk to |cRXP_FRIENDLY_Executor Zygand|r"), accept(357, "Accept The Lich's Identity") }), -- 1
    step({ text("Watch for |cRXP_FRIENDLY_Gordo|r, a big abomination that walks the road past |cRXP_FRIENDLY_Deathguard Lizabetha|r. Talk to him to get him to stand still, then select \"I need a report for Executor Zygand\""),
        complete(357, 1, "0/1 Gordo's Report"), accept(5481, "Accept Gordo's Task") }, { sticky = true }),      -- 2
    step({ text("Loot |cRXP_LOOT_Darkhound Hides|r from |cRXP_ENEMY_Decrepit Darkhounds|r and |cRXP_LOOT_Duskbat Wing Membranes|r from |cRXP_ENEMY_Duskbats|r you kill along the way"),
        text("|cRXP_WARN_Keep the [Meaty Bat Wings] the duskbats drop. Don't sell them: you cook them into Crispy Bat Wings later|r"),
        complete(1359, 1, "0/6 Darkhound Hide"), complete(1359, 2, "0/8 Duskbat Wing Membrane") }, { sticky = true }), -- 3
    step({ text("Kill |cRXP_ENEMY_Decrepit Darkhounds|r along the road. Loot them for |cRXP_LOOT_Darkhound Blood|r"),
        complete(1360, 1, "0/5 Darkhound Blood") }, { sticky = true }),                                            -- 4
    step({ goto(300, 400), text("|cRXP_WARN_If you haven't met him yet:|r find |cRXP_FRIENDLY_Gordo|r, an abomination that walks this road between here and Brill"),
        text("|cRXP_WARN_Talk to him to get him to stand still. Select \"I need a report for Executor Zygand\", then accept his quest|r"),
        complete(357, 1, "0/1 Gordo's Report"), accept(5481, "Accept Gordo's Task") }),                           -- 5
    step({ goto(200, 600), text("Finish looting |cRXP_LOOT_Gloom Weed|r on the ground along the road"), complete(5482, 1, "3/10 Gloom Weed") }), -- 6
    step({ goto(250, 650), text("Kill |cRXP_ENEMY_Rattlecage Soldiers|r"), complete(5482, 2, "0/6 Rattlecage Soldier slain") }), -- 7
    step({ goto(260, 700), text("Talk to |cRXP_FRIENDLY_Apothecary Johaan|r"), turnin(5482, "Turn in Doom Weed") }),    -- 8
    step({ goto(270, 720), M.vendor(2118, "Vendor and repair") }),                                                        -- 9
    step({ goto(280, 730), text("Fly to the Undercity") , { tag = "fly", text = "Fly to Undercity" } }),                 -- 10
}, "01-13 UD Paladin Launch Route")
M.now = M.now + 10
Q.on[5481] = false
goStep(5)
m = Card.model
check("several open steps: one block each, none dropped", #m.along == 3 and #m.along[1].rows == 2 and #m.along[2].rows == 3 and #m.along[3].rows == 1, #m.along)
check("block: its instruction as the title, its lines under it", m.along[2].title:find("^Loot") and m.along[2].rows[2].text == "0/6 Darkhound Hide" and m.along[2].rows[3].text == "0/8 Duskbat Wing Membrane")
check("block: extra notes stay as plain lines", m.along[2].rows[1].plainLine)
check("block icons from their lines", m.along[1].icon == "complete" and m.along[3].icon == "complete")
local alongCard = RXPEnhancedAlongCard
check("along card header counts the open steps", (function()
    for _, f in ipairs(M.frames) do
        if f.parent == alongCard and f.text and f.text.text == "ALONG THE WAY  ·  3" then return true end
    end
end)())
check("a long instruction isn't cut off", (function()
    for _, r in ipairs(card.regions) do
        if r.kind == "FontString" and r.text == m.headline then return r.maxLines == 0 and r.fontSize == db.cardTextSize + 1 end
    end
end)(), m.headline)
dump("along")

-- Glass
local glassRadio = find(wp.radios, function(r) return r.value == "glass" end)
glassRadio:Click()
update()
check("glass: picked", db.cardTheme == "glass" and glassRadio.checked)
check("glass: white layer with a top-to-bottom gradient over a dark one", card.layers[2].gradient and card.layers[2].gradient[1][4] > card.layers[2].gradient[2][4] and card.layers[1].parts[5].color[4] < 0.5)
check("glass: rounder corners", card.layers[1].corner == 12 and alongCard.layers[1].corner == 12)
check("glass: text gets a shadow", (function()
    for _, r in ipairs(card.regions) do
        if r.kind == "FontString" and r.shown and r.text == m.headline then return r.shadowOffset[1] == 1 end
    end
end)())
check("glass: the along card too", alongCard.layers[2].gradient ~= nil)
dump("glass")
find(wp.radios, function(r) return r.value == "dark" end):Click()
update()
check("dark again: one solid layer, no shadow", not card.layers[2].parts[1].shown and card.layers[1].corner == 8 and (function()
    for _, r in ipairs(card.regions) do
        if r.kind == "FontString" and r.shown and r.text == Card.model.headline then return r.shadowColor[4] == 0 end
    end
end)())

-- Moving and hiding the along card
local alongHeader = find(M.frames, function(f) return f.parent == alongCard and f.h == 34 end)
alongHeader.scripts.OnMouseDown(alongHeader, "LeftButton")
alongHeader.scripts.OnMouseUp(alongHeader)
check("along card dragged on its own", db.alongPoint and db.alongPoint[3] == 500 and not alongCard.followsCard)
update()
Card.dirty = true
update()
check("stays where you put it", alongCard.points[1][2] == UIParent)
wp.resetCard:Click()
update()
check("reset positions: back under the main card", db.alongPoint == nil and alongCard.points[1][2] == card)
local alongCollapse = find(M.frames, function(f) return f.parent == alongCard and f.w == 22 end)
alongCollapse:Click()
check("along card collapses to its header", db.alongCollapsed and alongCard.h < 60, alongCard.h)
alongCollapse:Click()
wp.checks.along.checked = false; wp.checks.along:Click()
check("along card off", not alongCard.shown and card.shown)
wp.checks.along.checked = true; wp.checks.along:Click()
check("along card on", alongCard.shown)
db.card = false
update()
check("both cards go with the card setting", not alongCard.shown and not card.shown)
db.card = true
update()

-- ---------------------------------------------------------------- little arrows on the step list
M.player.x, M.player.y, M.facing = 0, 0, 0.5
Card.dirty = true
update()
card.scripts.OnUpdate(card, 0.016)
local arrowRow = find(shownNext(), function(r) return r.place ~= nil end)
check("up next: a step with somewhere to go gets a little arrow", arrowRow and arrowRow.dir.shown)
if arrowRow then
    local pl = arrowRow.place
    local angle = math.atan2(pl.wy - 0, pl.wx - 0) % (2 * math.pi)
    check("the arrow points at the step from the way you face", math.abs(arrowRow.dir.rotation - (angle - 0.5 + math.pi / 4)) < 1e-9, arrowRow.dir.rotation)
    check("the arrow sits under the distance", arrowRow.dir.points[1][1] == "TOP" and arrowRow.dir.points[1][5] < -10)
    M.player.instance = 5 -- another continent: no direction to give
    card.scripts.OnUpdate(card, 0.016)
    check("elsewhere: no arrow", not arrowRow.dir.shown)
    M.player.instance = 0
    card.scripts.OnUpdate(card, 0.016)
end
local noPlace = find(shownNext(), function(r) return not r.place end)
check("a step with nowhere to go has no arrow", noPlace == nil or not noPlace.dir.shown)

-- ---------------------------------------------------------------- blank text: drawn again
local realMeasure = M.measure
M.measure = function() return 0 end -- the font isn't ready: texts come out with no width
Card.blankRetries = 0
Card.dirty = true
update()
check("blank text: drawn again with its fonts set again", Card.dirty == true and Card.refont == true and Card.blankRetries == 1)
M.measure = realMeasure
update()
check("then settles", Card.dirty == false and Card.blankRetries == 1)
check("/rxpe debug runs", (function()
    M.printed = {}
    SlashCmdList.RXPENHANCED("debug")
    for _, l in ipairs(M.printed) do if l:find("headline:") then return true end end
end)())

-- ---------------------------------------------------------------- skipping, and what the list remembers
local cur = RXP.progress
local s = RXP.currentGuide.steps[cur]
Card.Skip()
update()
check("skip: noted as skipped", Card.PastStatus(s, RXP.currentGuide) == "skipped")
Card.Back()
update()
check("back: forgotten again", Card.PastStatus(s, RXP.currentGuide) ~= "skipped" or not db.skipLog[RXP.currentGuide.key][s.index])

-- ---------------------------------------------------------------- RestedXP's other windows
local items = CreateFrame("Frame", "RXPItemFrame", UIParent)
items.w, items.h = 120, 43
items:SetBackdrop({ edge = true })
items.title = CreateFrame("Frame", "RXPItemFrame_title", items)
items.title.text = items.title:CreateFontString(nil, "OVERLAY")
items.title.text:SetFont(RXP.font, 9, "")
items.title.text:SetText("Active Items")
items.title:SetBackdrop({ edge = true })
local itemButton = CreateFrame("Button", "RXPItemFrameButton1", items)
itemButton.icon = itemButton:CreateTexture(nil, "BACKGROUND")
items.buttonList = { itemButton }
function items:UpdateVisuals()
    self:SetBackdrop({ edge = true })
    self.title:SetBackdrop({ edge = true })
    self.title.text:SetFont(RXP.font, 9, "")
end
RXP.UpdateItemFrame = function() end
items.UpdateFrame = RXP.UpdateItemFrame
Card.Skin.Scan()
local sk = items.rxnSkin
check("active items: RestedXP's backdrop off, the card look on", items.backdrop == nil and items.title.backdrop == nil and sk and sk.layers[1].parts[5].shown and sk.edge.parts[1].shown)
check("active items: title as a quiet label", items.title.text.text == "ACTIVE ITEMS" and items.title.text.fontPath:find("Inter%-Medium") and items.title.w > 40)
check("active items: icons trimmed", itemButton.icon.coords and itemButton.icon.coords[1] == 0.08)
check("active items: the panel covers the title tab", sk.box.points[1][5] == 10)
items:UpdateVisuals()
check("RestedXP redraws it: the look goes back on", items.backdrop == nil and items.title.text.fontPath:find("Inter"))
RXP.settings.profile.activeItemHideBG = true
Card.Skin.ApplyAll()
check("RestedXP's hide-background setting kept", not sk.layers[1].parts[5].shown and not sk.edge.parts[1].shown)
RXP.settings.profile.activeItemHideBG = nil
db.skinRXP = false
Card.Skin.ApplyAll()
check("skin off: RestedXP's own look back", items.backdrop ~= nil and items.title.text.text == "Active Items" and items.title.text.fontPath == RXP.font
    and not sk.layers[1].parts[5].shown and itemButton.icon.coords[1] == 0)
db.skinRXP = true
Card.Skin.ApplyAll()
check("skin on again", items.backdrop == nil and items.title.text.text == "ACTIVE ITEMS")
-- Level splits: padding all round, and its cog inside the panel.
RXP.tracker = { RenderSplitsBackground = function() end }
local splits = CreateFrame("Frame", "RXPLevelSplits", UIParent)
splits.w, splits.h = 150, 180
splits.title = CreateFrame("Frame", "RXPLevelSplits_title", splits)
splits.title:SetPoint("TOP", splits, 0, 5)
splits.title:SetSize(80, 17)
splits.title.cog = CreateFrame("Button", "RXPLevelSplits_titleCogwheel", splits.title)
splits.title.cog:SetNormalTexture("Interface/AddOns/RXPGuides/Textures/rxp_cog-32")
splits.title.cog:SetPoint("LEFT", splits.title, "LEFT", -9, 0)
splits.title.text = splits.title:CreateFontString(nil, "OVERLAY")
splits.title.text:SetText("Level splits")
splits.title.text:SetPoint("CENTER", splits.title, 0, 1)
Card.Skin.ApplyAll()
local ss = splits.rxnSkin
check("level splits: panel padded past its text", ss and ss.box.points[1][4] == -6 and ss.box.points[1][5] == 22 and ss.box.points[2][4] == 8 and ss.box.points[2][5] == -8)
check("level splits: title row inside the panel", splits.title.points[1][1] == "TOPLEFT" and splits.title.points[1][2] == ss.box and splits.title.h == 22)
check("level splits: cog at the left edge, inside", splits.title.cog.points[1][1] == "LEFT" and splits.title.cog.points[1][4] == 12 and splits.title.cog.w == 14
    and splits.title.cog.normal.texture:find("RXPEnhanced"))
check("level splits: label after the cog", splits.title.text.points[1][4] == 32 and splits.title.text.text == "LEVEL SPLITS" and splits.title.text.justifyH == "LEFT")
db.skinRXP = false
Card.Skin.ApplyAll()
check("skin off: level splits laid out as RestedXP had it", splits.title.points[1][1] == "TOP" and splits.title.points[1][5] == 5 and splits.title.cog.points[1][4] == -9 and splits.title.text.justifyH == "CENTER")
db.skinRXP = true
Card.Skin.ApplyAll()

-- ---------------------------------------------------------------- active targets near you
local Nearby = Card.Nearby
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local unitNames = {}
function UnitName(unit) return unitNames[unit] end
function issecretvalue(v) return v == SECRET end
local plates = {}
C_NamePlate = { GetNamePlates = function() return plates end }
local targetCalls = {}
function TargetUnit(name) targetCalls[#targetCalls + 1] = name end
Nearby.frame = nil
Nearby.Init() -- again, now that the game's functions exist in this mock

local targets = CreateFrame("Frame", "RXPTargetFrame", UIParent)
targets.w, targets.h = 120, 40
local function targetButton(name)
    local b = CreateFrame("Button", nil, targets)
    b.w, b.h = 25, 25
    b.targetData = { name = name, kind = "friendly" }
    return b
end
local sarvis, elreth, zombie = targetButton("Shadow Priest Sarvis"), targetButton("Novice Elreth"), targetButton("Mindless Zombie")
targets.friendlyTargetButtons = { sarvis, elreth }
targets.enemyTargetButtons = { zombie }
local function tick(dt) M.now = M.now + (dt or 0.6); Nearby.frame.scripts.OnUpdate(Nearby.frame, dt or 0.6) end
local function ring(b) local g = Nearby.glows[b]; return g and g.box.shown end
db.targetGlow = true
tick()
check("nothing near: no rings", not ring(sarvis) and not ring(elreth) and not ring(zombie))
unitNames.nameplate3 = "Mindless Zombie"
plates[1] = { namePlateUnitToken = "nameplate3" }
tick()
check("a nameplate on screen: that target gets a ring", ring(zombie) and not ring(sarvis))
check("the ring sits under the button, around it", Nearby.glows[zombie].box.parent == targets and Nearby.glows[zombie].box.points[1][2] == zombie and Nearby.glows[zombie].box.points[1][4] == -2)
local a1 = Nearby.glows[zombie].box.alpha
tick(0.2)
check("it pulses", Nearby.glows[zombie].box.alpha ~= a1)
plates[1] = nil
tick()
check("nameplate gone: ring gone", not ring(zombie))
-- The nameplate events too, between rescans.
unitNames.nameplate5 = "Novice Elreth"
Nearby.frame.scripts.OnEvent(Nearby.frame, "NAME_PLATE_UNIT_ADDED", "nameplate5")
check("nameplate event: seen at once", Nearby.IsNear("Novice Elreth"))
Nearby.frame.scripts.OnEvent(Nearby.frame, "NAME_PLATE_UNIT_REMOVED", "nameplate5")
check("removed event: gone at once", not Nearby.IsNear("Novice Elreth"))
-- Names the game hides (instances, fights) are skipped, not errors.
unitNames.nameplate7 = SECRET
plates[1] = { namePlateUnitToken = "nameplate7" }
tick()
check("a hidden name is skipped", next(Nearby.plates) == nil and not ring(sarvis))
plates[1] = nil
-- RestedXP's proximity scan: TargetUnit(name) blocked = that NPC is close.
Nearby.frame.scripts.OnEvent(Nearby.frame, "ADDON_ACTION_FORBIDDEN", "RXPGuides", "TargetUnit()")
TargetUnit("Shadow Priest Sarvis")
TargetUnit("Novice Elreth") -- not blocked: not near
tick()
check("RestedXP's scan found one: ring on it only", ring(sarvis) and not ring(elreth), tostring(Nearby.hits["Novice Elreth"]))
Nearby.frame.scripts.OnEvent(Nearby.frame, "ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "TargetUnit()")
TargetUnit("Novice Elreth")
tick()
check("another addon's blocked call doesn't count", not ring(elreth))
for _ = 1, 9 do tick() end
check("a scan hit fades after 5 seconds without another", not ring(sarvis))
-- Setting off, window hidden.
unitNames.nameplate3 = "Mindless Zombie"
plates[1] = { namePlateUnitToken = "nameplate3" }
tick()
db.targetGlow = false
tick()
check("setting off: no rings", not ring(zombie))
db.targetGlow = true
targets:Hide()
tick()
check("targets window hidden: no rings", not ring(zombie))
targets:Show()
tick()
check("back", ring(zombie))
zombie:Hide()
tick()
check("a hidden button has no ring", not ring(zombie))
M.printed = {}
SlashCmdList.RXPENHANCED("debug")
check("debug lists who's near", table.concat(M.printed, "\n"):find("active targets nearby: Mindless Zombie"))
check("no secure button touched: rings are separate frames", Nearby.glows[zombie].box.parent == targets and zombie.regions[1] == nil)

-- ---------------------------------------------------------------- the toast
local Toast = NS.Toast
check("toast: on by default, running", db.toast == true and Toast and Toast.driver ~= nil)
local function ttick(dt)
    dt = dt or 0.1
    M.now = M.now + dt
    Toast.Tick(dt)
    if Toast.frame then Toast.Animate(dt) end
end
local function settle() for _ = 1, 60 do ttick(0.1) end end
-- A fresh guide: RestedXP jumping to your saved step isn't toasted.
M.setGuide(guide())
ttick()
RXP.SetStep(7)
for _ = 1, 5 do ttick() end
check("toast: none while a guide is loading", not (Toast.frame and Toast.frame.shown))
settle()
RXP.SetStep(9)
ttick(0.1)
check("toast: not straight away (gathering)", not (Toast.frame and Toast.frame.shown))
ttick(0.3)
local tf = Toast.frame
check("toast: next step shown", tf and tf.shown and tf.header.text == "NEXT STEP  ·  STEP 9 OF 11", tf and tf.header.text)
check("toast: the card's words for the step", tf.title.text == "Accept Fresh Meat" and tf.sub.text == "Talk to |cff6fd08cNovice Elreth|r", tf.title.text)
check("toast: starts low and see-through", tf.alpha < 0.5 and tf.points[1][5] < -170, tf.points[1][5])
for _ = 1, 4 do ttick(0.1) end
check("toast: risen into place, fully shown", Toast.anim.phase == "hold" and tf.alpha == 1 and tf.points[1][5] == -170)
check("toast: never takes the mouse", tf.mouse == false)
for _ = 1, 31 do ttick(0.1) end
check("toast: after about three seconds it fades", Toast.anim.phase == "out" and tf.alpha < 1)
check("toast: drifting up as it goes", tf.points[1][5] > -170)
for _ = 1, 6 do ttick(0.1) end
check("toast: gone", Toast.anim.phase == "hidden" and not tf.shown)
-- Reaching a spot: RestedXP marks it reached and its arrow moves on.
local s9 = RXP.currentGuide.steps[9]
local spot = s9.elements[1]
RXPG_ARROW.element = spot
ttick()
spot.skip = true
RXPG_ARROW.element = RXP.currentGuide.steps[10].elements[1]
ttick()
ttick(0.3)
check("toast: arrived", tf.shown and tf.header.text == "ARRIVED  ·  STEP 9 OF 11", tf.header.text)
check("toast: arrival in green", math.abs(tf.bar.colorTexture[2] - 0.816) < 0.01)
-- Arriving and moving on together: one toast, for the new step.
for _ = 1, 40 do ttick(0.1) end
spot.skip = nil
RXPG_ARROW.element = spot
ttick()
spot.skip = true
RXPG_ARROW.element = RXP.currentGuide.steps[10].elements[1]
RXP.SetStep(10)
ttick(0.1)
ttick(0.3)
check("toast: arrive and move on together makes one toast, for the new step", tf.header.text == "NEXT STEP  ·  STEP 10 OF 11", tf.header.text)
-- The same spot again soon: no second arrival.
for _ = 1, 40 do ttick(0.1) end
Toast.Arrived(spot)
ttick(0.4)
check("toast: the same spot isn't toasted twice in a row", not tf.shown)
-- Back a step.
RXP.SetStep(9)
ttick(0.1)
ttick(0.3)
check("toast: going back says so", tf.header.text == "BACK TO  ·  STEP 9 OF 11", tf.header.text)
for _ = 1, 40 do ttick(0.1) end
-- Turned off.
db.toast = false
RXP.SetStep(10)
ttick(0.1)
ttick(0.3)
check("toast: off means none", not tf.shown)
db.toast = true
-- Move mode from the settings.
NS.OpenSettings("waypoint")
local sp = RXPEnhancedSettings.panel
sp.toastMove:Click()
check("move: a sample stays up and can be dragged", Toast.IsMoving() and tf.shown and tf.alpha == 1 and tf.mouse == true and tf.header.text == "TOAST POSITION")
check("move: the button says Done moving", sp.toastMove.text == "Done moving")
for _ = 1, 50 do ttick(0.1) end
check("move: it doesn't fade while you place it", tf.shown and tf.alpha == 1)
tf.scripts.OnDragStart(tf)
tf.scripts.OnDragStop(tf)
check("move: the spot is saved", db.toastPoint and db.toastPoint[3] == 500)
RXP.SetStep(9)
ttick(0.1)
ttick(0.3)
check("move: no step toasts while placing it", tf.header.text == "TOAST POSITION")
sp.toastMove:Click()
check("move: done, sample gone, mouse off again", not Toast.IsMoving() and not tf.shown and tf.mouse == false and sp.toastMove.text == "Move toast")
sp.toastPreview:Click()
for _ = 1, 5 do ttick(0.1) end
check("preview: a sample toast where it was placed", tf.shown and tf.header.text == "NEXT STEP  ·  STEP 61 OF 209" and tf.points[1][5] == db.toastPoint[4])
if dumpDir then
    local ops = M.dump(tf, 0, 0)
    local fh = assert(io.open(dumpDir .. "/toast_dark.json", "w"))
    fh:write(M.json({ w = tf.w, h = tf.h, ops = ops }))
    fh:close()
end
for _ = 1, 40 do ttick(0.1) end
sp.toastReset:Click()
check("reset: back at the top", db.toastPoint == nil)
sp.toastMove:Click()
RXPEnhancedSettings:Hide()
if RXPEnhancedSettings.scripts.OnHide then RXPEnhancedSettings.scripts.OnHide(RXPEnhancedSettings) end
check("closing the settings ends move mode", not Toast.IsMoving() and not tf.shown)
-- Glass.
db.cardTheme = "glass"
Toast.Preview()
for _ = 1, 4 do ttick(0.1) end
check("toast: in the glass look too", tf.layers[2].gradient ~= nil and tf.title.shadowColor[4] > 0)
if dumpDir then
    local ops = M.dump(tf, 0, 0)
    local fh = assert(io.open(dumpDir .. "/toast_glass.json", "w"))
    fh:write(M.json({ w = tf.w, h = tf.h, ops = ops }))
    fh:close()
end
db.cardTheme = "dark"
for _ = 1, 40 do ttick(0.1) end
SlashCmdList.RXPENHANCED("toast")
check("/rxpe toast turns it off", db.toast == false)
SlashCmdList.RXPENHANCED("toast")

-- ---------------------------------------------------------------- the settings in the cards' look
local win = RXPEnhancedSettings
NS.OpenSettings("arrow")
local sp2 = win.panel
check("settings: drawn as a card, not Blizzard's panel", win.look == "card" and win.chrome.template == nil and win.chrome.layers and sp2.styled)
check("settings: the cards' small header", win.chrome.titleText.text == "RXP ENHANCED  ·  SETTINGS" and win.chrome.titleText.fontPath:find("Inter"))
local enabledBox = sp2.checks.enabled
check("settings: Inter labels", enabledBox.Text.fontPath:find("Inter%-Regular") and enabledBox.Text.text == "Show the next step")
check("settings: a ticked box is filled, with a tick", enabledBox.mark.shown and enabledBox.box.color[1] > 0.9)
db.cardTheme = "dark"
NS.SettingsChanged()
local darkPanel = win.chrome.layers[1].parts[5].color[4]
check("settings: dark look like the cards", #win.chrome.layers == 2 and win.chrome.layers[2].parts[1].shown == false and darkPanel > 0.9 and not (enabledBox.Text.shadowColor[4] > 0))
db.cardTheme = "glass"
NS.SettingsChanged()
check("settings: glass look follows the cards' setting", win.chrome.layers[2].parts[1].shown ~= false and win.chrome.layers[2].gradient ~= nil and enabledBox.Text.shadowColor[4] > 0)
db.cardTheme = "dark"
NS.SettingsChanged()
if dumpDir then
    for _, look in ipairs({ "dark", "glass" }) do
        db.cardTheme = look
        NS.SettingsChanged()
        for _, tabName in ipairs({ "arrow", "waypoint" }) do
            NS.OpenSettings(tabName)
            local fh = assert(io.open(dumpDir .. "/settings_" .. look .. "_" .. tabName .. ".json", "w"))
            fh:write(M.json({ w = win.w, h = win.h, ops = M.dump(win, 0, 0) }))
            fh:close()
        end
    end
    db.cardTheme = "dark"
    NS.OpenSettings("arrow")
    NS.SettingsChanged()
end
check("settings: sliders are the cards' own", sp2.sliders.scale.thumb ~= nil and sp2.sliders.scale.valueText == "0.85", sp2.sliders.scale.valueText)
sp2.sliders.scale.scripts.OnMouseWheel(sp2.sliders.scale, 1)
check("settings: the mouse wheel steps a slider", db.scale == 0.9 and sp2.sliders.scale.valueText == "0.90", db.scale)
sp2.sliders.scale:SetValue(0.85)
check("settings: label is part of the checkbox", enabledBox.hitInsets and enabledBox.hitInsets[2] < -50)
sp2.tabs[4]:Click()
check("General tab: the intro, the targets ring and the restyle", sp2.sections.general.shown and sp2.checks.skipIntro and sp2.checks.targetGlow and sp2.checks.skinRXP
    and sp2.checks.skipIntro.checked == true)
check("Save and reload sits by Reset all", sp2.saveReload and sp2.saveReload.text == "Save and reload" and sp2.saveReload.points[1][5] == sp2.resetAll.points[1][5])
local reloaded = 0
function ReloadUI() reloaded = reloaded + 1 end
sp2.saveReload:Click()
check("Save and reload reloads", reloaded == 1)
local wpTips = {}
for _, cb in pairs(sp2.checks) do
    if cb.scripts.OnEnter then cb.scripts.OnEnter(cb); wpTips[#wpTips + 1] = table.concat(GameTooltip.lines, " ") end
end
check("no setting describes itself by Waypoint UI", not table.concat(wpTips, " "):find("Waypoint UI"))

-- ---------------------------------------------------------------- the enhanced UI switch
NS.OpenSettings("card")
local cardPanel = win.panel
check("enhanced UI: the guide card switch is now called that", cardPanel.checks.card.Text.text == "Use enhanced UI")
local generalCopy = find(cardPanel.extraChecks, function(cb) return cb.key == "card" end)
check("enhanced UI: also on the General tab", generalCopy and generalCopy.Text.text == "Use enhanced UI")
Card.Skin.ApplyAll()
check("enhanced UI on: RestedXP's windows in the cards' look", items.backdrop == nil and items.title.text.text == "ACTIVE ITEMS")
cardPanel.checks.card.checked = false
cardPanel.checks.card:Click()
check("enhanced UI off: no cards", not card.shown and not RXPEnhancedAlongCard.shown)
check("enhanced UI off: RestedXP's own window back", RXP.RXPFrame.alpha == 1)
check("enhanced UI off: RestedXP's other windows in their own look", items.backdrop ~= nil and items.title.text.text == "Active Items")
check("enhanced UI off: the settings window in Blizzard's look, on the same tab", win.shown and win.look == "blizzard"
    and win.chrome.template == "DefaultPanelTemplate" and win.panel.tab == "card" and not win.looks.card.chrome.shown)
check("enhanced UI off: Blizzard's controls", win.panel.checks.card.template == "UICheckButtonTemplate" and not win.panel.styled)
check("enhanced UI off: the restyle switch greys out", win.panel.checks.skinRXP.enabled == false)
win:Hide()
NS.OpenSettings()
check("enhanced UI off: opens in Blizzard's look", win.shown and win.look == "blizzard")
SlashCmdList.RXPENHANCED("ui")
check("/rxpe ui turns it back on, and the window follows", db.card == true and win.look == "card" and card.shown and items.backdrop == nil)
win:Hide()

-- ---------------------------------------------------------------- the new-character intro
local introFrame
for _, f in ipairs(M.frames) do if f.events.CINEMATIC_START then introFrame = f end end
local stops = 0
function StopCinematic() stops = stops + 1 end
function InCinematic() return true end
local function cinematic(canCancel) introFrame.scripts.OnEvent(introFrame, "CINEMATIC_START", canCancel, 1) end
M.level, M.xp = 1, 0
M.printed = {}
cinematic(true)
check("intro: a new character's opening cinematic is skipped", stops == 1 and NS.introSkipped)
check("intro: says so", (function() for _, l in ipairs(M.printed) do if l:find("skipped the new%-character intro") then return true end end end)())
introFrame.scripts.OnEvent(introFrame, "PLAYER_ENTERING_WORLD", true, false)
cinematic(true)
check("intro: also just after the first loading screen", stops == 2)
cinematic(false)
check("intro: not a cinematic that can't be skipped", stops == 2)
M.now = M.now + 200
cinematic(true)
check("intro: not after the first two minutes", stops == 2)
M.now = M.now - 200
M.level = 2
cinematic(true)
check("intro: not past level 1", stops == 2)
M.level, M.xp = 1, 40
cinematic(true)
check("intro: not once you've earned XP", stops == 2)
M.xp = 0
db.skipIntro = false
cinematic(true)
check("intro: not with the setting off", stops == 2)
SlashCmdList.RXPENHANCED("intro")
check("/rxpe intro turns it back on", db.skipIntro == true)
M.level, M.xp = M.levelWas or 5, 0

-- ---------------------------------------------------------------- Done, and ticking the headline
M.quests.on[363], M.quests.complete[363], M.quests.done[363] = true, true, nil
local s7 = RXP.currentGuide.steps[7]
for _, el in ipairs(s7.elements) do el.skip = nil end
db.skipLog, db.doneLog = {}, {}
goStep(7)
local doneBtn = find(ui_, function(f) return f.shown and f.Setup and f.text and f.text.text == "Done" end)
local backBtn = find(ui_, function(f) return f.shown and f.Setup and f.text and f.text.text == "Back" end)
local skipBtn = find(ui_, function(f) return f.shown and f.Setup and f.text and f.text.text == "Skip" end)
check("footer: Done between Back and Skip", doneBtn and doneBtn.points[1][4] > backBtn.points[1][4] and doneBtn.points[1][4] < skipBtn.points[1][4])
local headTick = find(ui_, function(f) return f.shown and f.element and f.bg and not f.text end)
check("headline: its line can be ticked off too", headTick and headTick.element.tag == "turnin" and headTick.element.questId == 363)
headTick.scripts.OnEnter(headTick)
check("headline: says so on hover", GameTooltip.title == "Click to tick it off")
headTick:Click()
check("headline tick: what RestedXP's checkbox does", s7.elements[3].skip == true and RXP.updateSteps == true)
check("headline tick: the next thing leads now", Card.model.headline:find("Accept The Mindless Ones") ~= nil, Card.model.headline)
s7.elements[3].skip = nil
update()
RXP.updateSteps = false
doneBtn:Click()
check("Done: every line on the step ticked off", s7.elements[3].skip == true and s7.elements[4].skip == true and not s7.elements[1].skip)
check("Done: RestedXP told, so it counts the step complete", RXP.updateSteps == true)
RXP.SetStep(8) -- RestedXP moves on by itself once every line is ticked
update()
check("Done: shows as done under Earlier steps (the turn-in never really happened)", Card.PastStatus(s7, RXP.currentGuide) == "done")
skipBtn:Click()
update()
check("Skip: shows as skipped instead", Card.PastStatus(RXP.currentGuide.steps[8], RXP.currentGuide) == "skipped")
backBtn:Click()
update()
backBtn:Click()
update()
check("going back: Done is forgotten for that step", not (db.doneLog[RXP.currentGuide.key] or {})[7] and not s7.elements[4].skip)
local notesOnly = RXP.currentGuide.steps[11]
goStep(11)
local before = #RXP.setStepCalls
doneBtn:Click()
check("Done on a step of notes only: moves on", RXP.setStepCalls[before + 1] == 12 and RXP.progress == 12)

print(("%d passed, %d failed"):format(passed, failed))
io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
for _, line in ipairs(M.printed) do if line:find("Error") then io.stdout:write(line .. "\n") end end
os.exit(failed == 0 and 0 or 1)

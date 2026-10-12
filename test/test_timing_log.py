#!/usr/bin/env python3
"""Checks for tools/timing_log.py: the SavedVariables reader, the archive, the fits and the plan
comparison, on a log written by test_log.lua (needs lua5.1). Run from test/: python3 test_timing_log.py"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import timing_log as T  # noqa: E402

passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print(f"FAIL: {name}" + (f"  ({detail})" if detail is not None else ""))


# ---------------------------------------------------------------- the SavedVariables reader
sample = r'''
-- a comment
Foo = {
	["a"] = "tab\there \"quoted\" back\\slash \065\
next line",
	["n"] = -12.5,
	["big"] = 1e3,
	["list"] = {
		"one", -- [1]
		"two", -- [2]
	},
	["mixed"] = { 1, 2, x = true, [10] = false, ["nil"] = nil },
	["long"] = [==[
raw ]] text]==],
	[3] = 0x1F,
}
Bar = nil
'''
sv = T._Parser(sample).chunk()
f = sv["Foo"]
check("reader: escapes", f["a"] == 'tab\there "quoted" back\\slash A\nnext line', repr(f["a"]))
check("reader: numbers", f["n"] == -12.5 and f["big"] == 1000.0 and f[3] == 31)
check("reader: a list", f["list"] == ["one", "two"])
check("reader: a table with both", f["mixed"][1] == 1 and f["mixed"]["x"] is True and f["mixed"][10] is False)
check("reader: long string", f["long"] == "raw ]] text")
check("reader: nil", "Bar" in sv and sv["Bar"] is None)

# ---------------------------------------------------------------- a real log, from the Lua tests
tmp = tempfile.mkdtemp()
try:
    wtf = os.path.join(tmp, "WTF", "Account", "123#1", "SavedVariables")
    os.makedirs(wtf)
    svfile = os.path.join(wtf, "RXPEnhanced.lua")
    r = subprocess.run(["lua5.1", "test_log.lua", svfile], cwd=HERE, capture_output=True, text=True)
    check("the Lua tests ran and wrote a log", r.returncode == 0 and os.path.exists(svfile), r.stdout[-300:])
    plans = os.path.join(tmp, "Plans.lua")
    with open(plans, "w") as fh:
        fh.write('RouteSplitsPlans = RouteSplitsPlans or {}\n\nRouteSplitsPlans["launch"] = {\n  target = 10,\n  steps = {\n'
                 '    {"A363", 20, "Accept Rude Awakening"},\n    {"C364.1", 120, "Mindless Zombie slain"},\n'
                 '    {"T364", 140, "Turn in The Mindless Ones"},\n    {"A400", 150, "Accept Fresh Meat"},\n'
                 '    {"A401", 160, "Accept Gordo\'s Task"},\n  },\n}\n')
    out = os.path.join(tmp, "out")
    cal = T.main([os.path.join(tmp, "WTF"), "--out", out, "--plans", plans, "--quiet"])
    check("finds the file in a WTF folder", cal["sources"] == [svfile], cal["sources"])
    check("sessions, steps and kills", cal["sessions"] == 3 and cal["steps"] == 12 and cal["kills"] == 6, (cal["sessions"], cal["steps"], cal["kills"]))
    for name in ("steps.csv", "kills.csv", "events.csv", "calibration.json", "report.md", "steps_vs_plan.csv", "timing_archive.json"):
        check(f"wrote {name}", os.path.getsize(os.path.join(out, name)) > 0)
    steps, kills, events = T.flatten(T.load_sessions([svfile]))
    s1 = steps[0]
    check("step row: fields typed", s1["idx"] == 1 and s1["sig"] == "A363" and s1["how"] == "done" and abs(s1["move"] - 10) < 0.3 and s1["yd"] == 50, s1)
    check("step row: its guide named", s1["guide"] == "My Guides|launch")
    k1 = kills[0]
    check("kill row: fields typed", k1["npc"] == 1501 and k1["name"] == "Mindless Zombie" and k1["xp"] == 70 and k1["cls"] == "n" and abs(k1["fight"] - 12) < 0.3, k1)
    check("event rows: a zone name stays text, numbers are numbers", any(e["code"] == "Z" and e["a"] == "Brill" for e in events)
          and any(e["code"] == "L" and e["a"] == 6 for e in events))
    m = cal["measured"]
    check("fit: fight time at 4-5 from 5 kills, not used yet (needs 8)", m["fight_l45"]["n"] == 5 and "fight_l45" not in cal["P"], m["fight_l45"])
    check("fit: the engine's current values alongside", m["fight_l45"]["engine"] == 17.5 and m["run_speed"]["engine"] == 7.0)
    check("fit: run speed from the walk (5 yd/s)", abs(m["run_speed"]["value"] - 5.0) < 0.1, m["run_speed"])
    check("fit: time at an NPC per quest", abs(m["act_s"]["value"] - 3.0) < 0.3, m["act_s"])
    check("fit: hearth = cast + loading", abs(m["hearth_s"]["value"] - 16.0) < 0.3, m["hearth_s"])
    check("kills by level", cal["kills_by_level"]["5"]["kills"] == 5 if "5" in cal["kills_by_level"] else cal["kills_by_level"][5]["kills"] == 5)
    run = cal["runs"][0]
    check("runs: level 6 time and the death", 6 in run["level_times"] and run["deaths"] == 1, run)
    vs = [json.loads(json.dumps(r)) for r in T.versus_plan(steps, T.read_plans(plans))]
    check("plan: four steps line up by signature", [r["sig"] for r in vs] == ["A363", "C364.1", "A400", "A401"], [r["sig"] for r in vs])
    check("plan: planned time is the step's own share", vs[1]["planned_s"] == 100 and vs[0]["planned_s"] == 20)

    # Enough data: 8 more kills at level 5 make the fit count.
    many = [dict(k, seq=12.0, still=3.0, ml=5, pl=5.5, tap=1, cls="n", xp=70) for k in kills[:1] for _ in range(8)]
    P, meas, _ = T.fit(steps, kills + many, events)
    check("fit: with 8+ kills the band goes into P", "fight_l45" in P and 12 < P["fight_l45"] < 16, meas["fight_l45"])

    # The archive keeps sessions the game later loses.
    with open(svfile, encoding="utf-8") as fh:
        text = fh.read()
    cut = text.index('["sessions"] = {')
    with open(svfile, "w", encoding="utf-8") as fh:
        fh.write(text[:cut] + '["sessions"] = {\n},\n}\n')
    cal2 = T.main([svfile, "--out", out, "--quiet"])
    check("archive: a cleared log in game still reads as 3 sessions", cal2["sessions"] == 3 and cal2["kills"] == 6, cal2["sessions"])
    check("--char picks a character", T.main([svfile, "--out", out, "--char", "nobody", "--quiet"])["sessions"] == 0)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

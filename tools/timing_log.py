#!/usr/bin/env python3
"""Reads RXP Enhanced's timing log and works out the route engine's time numbers from it.

    python3 tools/timing_log.py <RXPEnhanced.lua | WTF folder> [--out DIR] [--archive FILE]
                                [--plans Plans.lua] [--char NAME]

The log is in WoW's SavedVariables: WTF/Account/<account>/SavedVariables/RXPEnhanced.lua, written when
you log out or reload. Give that file, or a WTF folder to read every account's.

Writes to --out (default ./timing_out):
  steps.csv, kills.csv, events.csv   every row, with the session and character on each
  calibration.json                   the engine's numbers: "P" holds values for route.py's P where there's
                                     enough data, "measured" every fit with its sample size and the engine's
                                     current value, plus kill times by level and each run's level times
  report.md                          the same, to read
  steps_vs_plan.csv                  with --plans (Route Splits' Plans.lua): each step's time against the plan
Every session read is also kept in --archive (default <out>/timing_archive.json), so a log WoW loses
(the Forever beta sometimes drops saved settings at login) or one you clear in game isn't lost here.

To use the numbers in the engine:   from route import P;  P.update(json.load(open("calibration.json"))["P"])

Python 3.8+, standard library only.
"""

import argparse
import csv
import json
import math
import os
import re
import statistics
import sys
from datetime import datetime, timezone

# ------------------------------------------------------------------------------------------ engine model
# Copied from the route engine's route.py (2026-10-12), to compare against and to normalise kill times.
ENGINE_P = dict(
    run_speed=7.0, path_factor=1.25, fight_l13=13.0, fight_l45=17.5, fight_mid=20.0, fight=22.5,
    act_s=8.0, elite_time=2.5, hearth_s=40.0, train_s=20.0, vendor_per_kill=1.5,
    open_world_next_s=6.0, grind_extra_mid=6.0,
)
BANDS = [("fight_l13", 1, 3), ("fight_l45", 4, 5), ("fight_mid", 6, 10), ("fight", 11, 99)]
MIN_KILLS = 8      # kills in a level band before its fight time goes into "P"
MIN_STEPS = 5      # steps before run speed and path factor do
MIN_VISITS = 5     # NPC visits before act_s / train_s do


def level_factor(d):
    """route.py kill_time: fight time scales with mob level minus player level."""
    for lim, f in ((3, 1.4), (2, 1.25), (1, 1.12), (0, 1.0), (-1, 0.93), (-2, 0.87), (-3, 0.82), (-4, 0.77)):
        if d >= lim:
            return f
    return 0.72


def zd(pl):
    for hi, v in [(7, 5), (9, 6), (11, 7), (15, 8), (19, 9), (29, 11), (39, 12)]:
        if pl <= hi:
            return v
    return 13


def gray_level(pl):
    if pl <= 5:
        return 0
    if pl <= 39:
        return pl - math.floor(pl / 10) - 5
    return pl - math.floor(pl / 5) - 1


def mob_xp(pl, ml):
    """route.py mob_xp for a whole mob level (Forever's rule for mobs below you)."""
    if ml <= gray_level(pl):
        return 0.0
    if ml >= pl:
        return (pl * 5 + 45) * (1 + 0.05 * min(ml - pl, 4))
    return (ml * 5 + 45) * (1 - (pl - ml) / zd(pl))


# ------------------------------------------------------------------------------------------ SavedVariables
_TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.|\\\n)*"|'(?:[^'\\]|\\.|\\\n)*')
  | (?P<long>\[(?P<eq>=*)\[.*?\](?P=eq)\])
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;])
""", re.S | re.X)

_ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = body[i + 1]
        if n.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1:])
            out.append(chr(int(m.group(0))))
            i += 1 + len(m.group(0))
        else:
            out.append(_ESC.get(n, n))
            i += 2
    return "".join(out)


def _tokens(text):
    pos = 0
    for m in _TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError(f"can't read the file near: {text[pos:pos + 40]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        if kind == "eq":
            kind = "long"
        v = m.group(0)
        if kind == "str":
            yield "str", _unescape(v[1:-1])
        elif kind == "long":
            body = v[len(m.group("eq")) + 2: -len(m.group("eq")) - 2]
            yield "str", body[1:] if body.startswith("\n") else body
        elif kind == "num":
            yield "num", (int(v, 16) if v.lower().startswith(("0x", "-0x")) else (float(v) if re.search(r"[.eE]", v) else int(v)))
        elif kind == "name":
            yield ("const", {"true": True, "false": False, "nil": None}[v]) if v in ("true", "false", "nil") else ("name", v)
        else:
            yield "op", v
    if pos != len(text):
        raise ValueError(f"can't read the file near: {text[pos:pos + 40]!r}")


class _Parser:
    def __init__(self, text):
        self.toks = list(_tokens(text))
        self.i = 0

    def peek(self, k=0):
        return self.toks[self.i + k] if self.i + k < len(self.toks) else (None, None)

    def take(self, kind=None, value=None):
        t = self.peek()
        if (kind and t[0] != kind) or (value is not None and t[1] != value):
            raise ValueError(f"expected {value or kind}, found {t[1]!r}")
        self.i += 1
        return t[1]

    def value(self):
        kind, v = self.peek()
        if kind in ("str", "num", "const"):
            self.i += 1
            return v
        if kind == "op" and v == "{":
            return self.table()
        raise ValueError(f"unexpected {v!r}")

    def table(self):
        self.take("op", "{")
        arr, hashed = [], {}
        while True:
            kind, v = self.peek()
            if kind == "op" and v == "}":
                self.i += 1
                break
            if kind == "op" and v == "[":
                self.i += 1
                key = self.value()
                self.take("op", "]")
                self.take("op", "=")
                hashed[key] = self.value()
            elif kind == "name" and self.peek(1) == ("op", "="):
                self.i += 2
                hashed[v] = self.value()
            else:
                arr.append(self.value())
            if self.peek() in (("op", ","), ("op", ";")):
                self.i += 1
        if not hashed:
            return arr
        for n, v in enumerate(arr, 1):
            hashed.setdefault(n, v)
        # A Lua array written with explicit [1], [2]... keys.
        if all(isinstance(k, int) for k in hashed) and sorted(hashed) == list(range(1, len(hashed) + 1)):
            return [hashed[k] for k in range(1, len(hashed) + 1)]
        return hashed

    def chunk(self):
        out = {}
        while self.i < len(self.toks):
            name = self.take("name")
            self.take("op", "=")
            out[name] = self.value()
        return out


def read_saved_variables(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return _Parser(fh.read()).chunk()


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(k for k in v if isinstance(k, int))]
    return []


# ------------------------------------------------------------------------------------------ rows
def num(v):
    if v is None or v == "":
        return None
    try:
        f = float(v)
    except ValueError:
        return v
    return int(f) if f.is_integer() and "." not in str(v) else f


def parse_rows(rows, columns):
    names = columns.split()
    out = []
    for row in as_list(rows):
        fields = row.split("\t")
        rec = {n: (num(fields[i]) if i < len(fields) else None) for i, n in enumerate(names)}
        for n in ("sig", "label", "name", "how", "src", "code", "cls"):
            if n in rec and rec[n] is not None:
                rec[n] = fields[names.index(n)]
        out.append(rec)
    return out


def load_sessions(paths):
    """Every session in the given SavedVariables files, keyed by session id."""
    sessions = {}
    for path in paths:
        sv = read_saved_variables(path)
        log = sv.get("RXPEnhancedLog")
        if not isinstance(log, dict):
            print(f"{path}: no timing log in it (is logging on? /rxpe log)", file=sys.stderr)
            continue
        if log.get("format") != 1:
            print(f"{path}: log format {log.get('format')} is newer than this reader; reading it anyway", file=sys.stderr)
        cols = log.get("columns") or {}
        for s in as_list(log.get("sessions")):
            if not isinstance(s, dict):
                continue
            meta = {k: v for k, v in s.items() if not isinstance(v, (dict, list))}
            meta["guides"] = as_list(s.get("guides"))
            meta["columns"] = dict(cols)
            meta["raw"] = {k: as_list(s.get(k)) for k in ("steps", "kills", "events")}
            meta["source"] = os.path.abspath(path)
            sessions[s.get("id") or f"{path}#{len(sessions)}"] = meta
    return sessions


def merge_archive(archive_path, sessions):
    """Keeps every session ever read: a session read again replaces its copy when it has more rows."""
    archived = {}
    if archive_path and os.path.exists(archive_path):
        with open(archive_path, encoding="utf-8") as fh:
            archived = json.load(fh).get("sessions", {})

    def size(s):
        return sum(len(v) for v in s["raw"].values())
    for sid, s in sessions.items():
        if sid not in archived or size(s) >= size(archived[sid]):
            archived[sid] = s
    if archive_path:
        os.makedirs(os.path.dirname(os.path.abspath(archive_path)), exist_ok=True)
        with open(archive_path, "w", encoding="utf-8") as fh:
            json.dump({"format": 1, "sessions": archived}, fh)
    return archived


def flatten(sessions, char=None):
    steps, kills, events = [], [], []
    for sid, s in sorted(sessions.items(), key=lambda kv: kv[1].get("started") or 0):
        if char and char.lower() not in str(s.get("char", "")).lower():
            continue
        cols = s["columns"]
        base = {"session": sid, "char": s.get("char"), "race": s.get("race"), "class": s.get("class")}
        guides = s.get("guides") or []
        for kind, out in (("step", steps), ("kill", kills), ("event", events)):
            for r in parse_rows(s["raw"][kind + "s"], cols.get(kind, "")):
                r = {**base, **r}
                if "g" in r:
                    g = r.get("g")
                    r["guide"] = guides[g - 1] if isinstance(g, int) and 0 < g <= len(guides) else ""
                out.append(r)
    kills.sort(key=lambda r: (r["session"], r.get("t") or 0))
    return steps, kills, events


# ------------------------------------------------------------------------------------------ fits
def trimmed_mean(xs, cut=0.1):
    xs = sorted(xs)
    k = int(len(xs) * cut)
    xs = xs[k:len(xs) - k] if len(xs) > 2 * k else xs
    return sum(xs) / len(xs) if xs else None


def med(xs):
    return statistics.median(xs) if xs else None


def rnd(v, d=2):
    return None if v is None else round(v, d)


def good_kill(k):
    return (k.get("tap") == 1 and isinstance(k.get("seq"), (int, float)) and 0 < k["seq"] <= 180
            and k.get("cls") not in ("m", "t") and k.get("xp") != 0)


def fit(steps, kills, events):
    measured, P = {}, {}

    def put(key, value, n, enough, note, engine=None):
        engine = ENGINE_P.get(key) if engine is None else engine
        measured[key] = {"value": rnd(value), "n": n, "engine": engine, "note": note}
        if value is not None and enough:
            P[key] = rnd(value)

    # Fight time, loot and rest per kill, by player level, scaled to an even-level mob like route.py.
    by_level = {}
    for k in kills:
        if not good_kill(k):
            continue
        pl = int(math.floor(k.get("pl") or 0))
        ml = k.get("ml") if isinstance(k.get("ml"), (int, float)) and k.get("ml") > 0 else pl
        rest = min(k.get("still") or 0, 90.0)
        f = level_factor(ml - pl) * (ENGINE_P["elite_time"] if k.get("cls") in ("e", "R") else 1.0)
        by_level.setdefault(pl, []).append({"seq": k["seq"], "rest": rest, "loot": k.get("loot"), "norm": (k["seq"] + rest) / f,
                                            "fight": k.get("fight"), "pull": k.get("pull") or 1, "elite": k.get("cls") in ("e", "R")})
    for key, lo, hi in BANDS:
        rows = [r for lvl, rs in by_level.items() if lo <= lvl <= hi for r in rs if not r["elite"]]
        put(key, trimmed_mean([r["norm"] for r in rows]), len(rows), len(rows) >= MIN_KILLS,
            f"seconds per kill at levels {lo}-{min(hi, 60)}: the fight plus loot and rest standing still after it, "
            "scaled to a mob of your level (trimmed mean)")
    # Elites: their time against normal mobs at the same levels.
    el = [r for rs in by_level.values() for r in rs if r["elite"]]
    if el:
        ratio = []
        for lvl, rs in by_level.items():
            e = [r["seq"] + r["rest"] for r in rs if r["elite"]]
            n = [r["seq"] + r["rest"] for r in rs if not r["elite"]]
            if e and len(n) >= 3:
                ratio += [x / med(n) for x in e]
        put("elite_time", med(ratio), len(ratio), len(ratio) >= 3, "an elite's time as a multiple of a normal mob's")

    # Between mobs: walking from one kill to the next pull, when nothing else happened in between.
    gaps = [k for k in kills if isinstance(k.get("gap"), (int, float)) and 0 <= k["gap"] <= 120 and (k.get("gother") or 0) < 1]
    walk = [k["gmove"] for k in gaps if isinstance(k.get("gmove"), (int, float))]
    measured["between_mobs"] = {
        "n": len(gaps), "walk_s": rnd(med(walk)), "walk_yd": rnd(med([k["gyd"] for k in gaps if isinstance(k.get("gyd"), (int, float))])),
        "gap_s": rnd(med([k["gap"] for k in gaps])),
        "note": "median time and yards walked from one kill to the next pull (route.py prices this from camp spawn spacing, "
                "or open_world_next_s + grind_extra_mid off camp)",
        "engine_open_world_s": ENGINE_P["open_world_next_s"] + ENGINE_P["grind_extra_mid"],
    }

    # Running: yards on foot per second spent moving.
    foot = [s for s in steps if (s.get("mount") or 0) < 0.5 and (s.get("move") or 0) > 5 and (s.get("yd") or 0) > 20]
    yd, mv = sum(s["yd"] for s in foot), sum(s["move"] for s in foot)
    put("run_speed", yd / mv if mv else None, len(foot), len(foot) >= MIN_STEPS,
        "yards a second while moving on foot, out of combat (route.py: 7.0, a level-1 character's run speed)")
    # Path factor: how much further than a straight line you go on steps that are just getting somewhere.
    travel = [s for s in steps if s.get("how") in ("done", "tick") and s.get("part") == 0 and (s.get("kills") or 0) == 0
              and (s.get("combat") or 0) < 5 and isinstance(s.get("direct"), (int, float)) and s["direct"] >= 60
              and (s.get("taxi") or 0) == 0 and (s.get("load") or 0) < 2]
    ratios = [s["yd"] / s["direct"] for s in travel if s.get("yd")]
    put("path_factor", med([min(3.0, max(1.0, r)) for r in ratios]), len(ratios), len(ratios) >= MIN_STEPS,
        "yards run ÷ straight-line yards from where a travel step started to its spot (median)")

    # NPCs.
    visits = [e for e in events if e.get("code") == "W"]
    quest = [e["b"] / e["c"] for e in visits if e.get("a") in ("quest", "gossip") and isinstance(e.get("c"), int) and e["c"] > 0
             and isinstance(e.get("b"), (int, float))]
    put("act_s", med(quest), len(quest), len(quest) >= MIN_VISITS, "seconds at an NPC per quest accepted or turned in (median)")
    train = [float(e["b"]) for e in visits if e.get("a") == "trainer"]
    put("train_s", med(train), len(train), len(train) >= 2, "seconds at a class trainer (median)")
    vend = [float(e["b"]) for e in visits if e.get("a") == "vendor"]
    later = [k for k in kills if good_kill(k) and (k.get("pl") or 0) >= 6]
    put("vendor_per_kill", (sum(vend) / len(later)) if (vend and later) else None, len(vend), len(vend) >= 2 and len(later) >= 50,
        "time at vendors spread over kills from level 6")
    # Hearth: the 10 s cast plus the loading screen after it.
    hs = []
    by_session = {}
    for e in events:
        by_session.setdefault(e["session"], []).append(e)
    for evs in by_session.values():
        for i, e in enumerate(evs):
            if e.get("code") == "H":
                for f in evs[i + 1:i + 6]:
                    if f.get("code") == "LS" and (f["t"] - e["t"]) < 30:
                        hs.append(10.0 + float(f["a"]))
                        break
    put("hearth_s", med(hs), len(hs), len(hs) >= 2, "the 10 s cast plus the loading screen after it (median)")

    # Kill XP against the engine's formula (checks Forever's rule for mobs below you).
    xr = []
    for k in kills:
        if good_kill(k) and isinstance(k.get("xp"), (int, float)) and k["xp"] > 0 and isinstance(k.get("ml"), int) and k["ml"] > 0:
            pl = int(math.floor(k["pl"]))
            want = mob_xp(pl, k["ml"]) * (2 if k.get("cls") in ("e", "R") else 1) / max(1, (k.get("grp") or 1))
            if want > 0:
                xr.append((k["xp"] - (k.get("rested") or 0)) / want)
    measured["kill_xp_vs_engine"] = {"n": len(xr), "ratio": rnd(med(xr), 3),
                                     "note": "logged kill XP (rested taken off) ÷ route.py's mob_xp; 1.0 means the formula is right"}

    levels = {}
    for lvl in sorted(by_level):
        rs = by_level[lvl]
        levels[lvl] = {"kills": len(rs), "fight_s": rnd(med([r["seq"] for r in rs])), "rest_s": rnd(med([r["rest"] for r in rs])),
                       "loot_s": rnd(med([r["loot"] for r in rs if isinstance(r["loot"], (int, float)) and r["loot"] >= 0])),
                       "even_level_s": rnd(trimmed_mean([r["norm"] for r in rs]))}
    return P, measured, levels


def runs(steps, kills, events, sessions):
    """Each session's level-up times, from the session clock and (when known) /played."""
    out = []
    for sid, s in sessions.items():
        evs = [e for e in events if e["session"] == sid]
        lv = {int(e["a"]): e["t"] for e in evs if e.get("code") == "L" and isinstance(e.get("a"), int)}
        st = [x for x in steps if x["session"] == sid]
        out.append({
            "session": sid, "char": s.get("char"), "race": s.get("race"), "class": s.get("class"),
            "started": datetime.fromtimestamp(s["started"], timezone.utc).isoformat() if s.get("started") else None,
            "level_at_start": s.get("level0"), "played_at_start": s.get("played0"), "clock_end": s.get("clockEnd"),
            "level_times": lv, "steps": len(st), "kills": len([k for k in kills if k["session"] == sid]),
            "deaths": len([e for e in evs if e.get("code") == "D"]),
            "afk_s": rnd(sum(x.get("afk") or 0 for x in st), 0), "dead_s": rnd(sum(x.get("dead") or 0 for x in st), 0),
        })
    return out


# ------------------------------------------------------------------------------------------ against a plan
def read_plans(path):
    """Route Splits' Plans.lua: { name: [(signature, predicted seconds, label), ...] }."""
    text = open(path, encoding="utf-8").read()
    plans = {}
    for m in re.finditer(r'RouteSplitsPlans\["([^"]+)"\]\s*=\s*\{(.*?)\n\}', text, re.S):
        steps = re.findall(r'\{"([^"]*)",\s*([\d.]+),\s*"((?:[^"\\]|\\.)*)"\}', m.group(2))
        plans[m.group(1)] = [(sig, float(t), lab) for sig, t, lab in steps]
    return plans


def align(a, b):
    """Longest common subsequence of two signature lists: pairs of (index in a, index in b)."""
    n, m = len(a), len(b)
    L = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            L[i][j] = L[i + 1][j + 1] + 1 if a[i] == b[j] else max(L[i + 1][j], L[i][j + 1])
    i = j = 0
    out = []
    while i < n and j < m:
        if a[i] == b[j]:
            out.append((i, j))
            i, j = i + 1, j + 1
        elif L[i + 1][j] >= L[i][j + 1]:
            i += 1
        else:
            j += 1
    return out


def versus_plan(steps, plans):
    rows = []
    for name, plan in plans.items():
        mine = [s for s in steps if name in str(s.get("guide", "")) and s.get("sig") and s.get("how") in ("done", "tick")]
        if not mine:
            continue
        # The latest run of each step.
        latest = {}
        for s in mine:
            latest[(s["idx"], s["sig"])] = s
        mine = sorted(latest.values(), key=lambda s: s["idx"])
        pairs = align([s["sig"] for s in mine], [p[0] for p in plan])
        for i, j in pairs:
            s = mine[i]
            planned = plan[j][1] - (plan[j - 1][1] if j > 0 else 0)
            actual = s["t1"] - s["t0"] - (s.get("afk") or 0)
            rows.append({"plan": name, "idx": s["idx"], "sig": s["sig"], "label": plan[j][2], "actual_s": rnd(actual, 1),
                         "planned_s": rnd(planned, 1), "diff_s": rnd(actual - planned, 1), "kills": s.get("kills"),
                         "part": s.get("part"), "session": s["session"]})
    return rows


# ------------------------------------------------------------------------------------------ output
def write_csv(path, rows):
    if not rows:
        open(path, "w").close()
        return
    keys = []
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def report(P, measured, levels, run_list, plan_rows, counts):
    lines = ["# Timing log: route engine numbers", "",
             f"{counts['sessions']} sessions, {counts['steps']} steps, {counts['kills']} kills.", "",
             "## Engine parameters", "", "| P key | measured | n | engine now | used | what it is |", "|---|---|---|---|---|---|"]
    for key, m in measured.items():
        if "value" not in m:
            continue
        lines.append(f"| `{key}` | {m['value'] if m['value'] is not None else '—'} | {m['n']} | {m['engine']} | "
                     f"{'yes' if key in P else 'not enough data' if m['value'] is not None else '—'} | {m['note']} |")
    b = measured.get("between_mobs", {})
    x = measured.get("kill_xp_vs_engine", {})
    lines += ["", "## Between mobs", "",
              f"{b.get('n', 0)} pulls after a kill: median {b.get('gap_s')} s from the kill to the next pull, "
              f"{b.get('walk_s')} s of it walking ({b.get('walk_yd')} yd). Off a known camp the engine assumes "
              f"{b.get('engine_open_world_s')} s from level 6.", "",
              "## Kill XP", "", f"{x.get('n', 0)} kills: logged XP is {x.get('ratio')} × the engine's formula (1.0 = right).", "",
              "## Kills by level", "", "| level | kills | fight s | loot s | rest s | per kill, even-level mob |", "|---|---|---|---|---|---|"]
    for lvl, r in levels.items():
        lines.append(f"| {lvl} | {r['kills']} | {r['fight_s']} | {r['loot_s']} | {r['rest_s']} | {r['even_level_s']} |")
    lines += ["", "## Runs", ""]
    for r in run_list:
        lv = ", ".join(f"{k}: {v / 60:.1f} min" for k, v in sorted(r["level_times"].items()))
        lines.append(f"- {r['char']} ({r['race']} {r['class']}), {r['started']}: from level {r['level_at_start']}, "
                     f"{r['steps']} steps, {r['kills']} kills, {r['deaths']} deaths. Level-ups (session clock): {lv or 'none'}")
    if plan_rows:
        tot_a = sum(r["actual_s"] for r in plan_rows)
        tot_p = sum(r["planned_s"] for r in plan_rows)
        lines += ["", "## Against the plan", "",
                  f"{len(plan_rows)} steps matched: {tot_a / 60:.1f} min played against {tot_p / 60:.1f} planned.", "",
                  "Furthest off:", ""]
        for r in sorted(plan_rows, key=lambda r: -abs(r["diff_s"]))[:10]:
            lines.append(f"- step {r['idx']} {r['label']}: {r['actual_s']:.0f} s against {r['planned_s']:.0f} ({r['diff_s']:+.0f})")
    return "\n".join(lines) + "\n"


def find_files(target):
    if os.path.isfile(target):
        return [target]
    found = []
    for root, _, files in os.walk(target):
        if os.path.basename(root) == "SavedVariables" and "RXPEnhanced.lua" in files:
            found.append(os.path.join(root, "RXPEnhanced.lua"))
    return sorted(found)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("source", help="RXPEnhanced.lua from SavedVariables, or a WTF folder")
    ap.add_argument("--out", default="timing_out")
    ap.add_argument("--archive", help="JSON file that keeps every session read (default <out>/timing_archive.json)")
    ap.add_argument("--plans", help="Route Splits' Plans.lua, to compare each step with the plan")
    ap.add_argument("--char", help="only sessions of this character (part of 'Name-Realm')")
    ap.add_argument("--quiet", action="store_true", help="don't print the report")
    a = ap.parse_args(argv)
    files = find_files(a.source)
    if not files:
        sys.exit(f"no RXPEnhanced.lua found at {a.source}")
    os.makedirs(a.out, exist_ok=True)
    sessions = merge_archive(a.archive or os.path.join(a.out, "timing_archive.json"), load_sessions(files))
    steps, kills, events = flatten(sessions, a.char)
    if a.char:
        sessions = {k: v for k, v in sessions.items() if a.char.lower() in str(v.get("char", "")).lower()}
    P, measured, levels = fit(steps, kills, events)
    run_list = runs(steps, kills, events, sessions)
    plan_rows = versus_plan(steps, read_plans(a.plans)) if a.plans else []
    write_csv(os.path.join(a.out, "steps.csv"), steps)
    write_csv(os.path.join(a.out, "kills.csv"), kills)
    write_csv(os.path.join(a.out, "events.csv"), events)
    if a.plans:
        write_csv(os.path.join(a.out, "steps_vs_plan.csv"), plan_rows)
    counts = {"sessions": len(sessions), "steps": len(steps), "kills": len(kills)}
    cal = {"generated": datetime.now(timezone.utc).isoformat(timespec="seconds"), "sources": files, **counts,
           "P": P, "measured": measured, "kills_by_level": levels, "runs": run_list,
           "engine_defaults": ENGINE_P}
    with open(os.path.join(a.out, "calibration.json"), "w", encoding="utf-8") as fh:
        json.dump(cal, fh, indent=1)
    text = report(P, measured, levels, run_list, plan_rows, counts)
    with open(os.path.join(a.out, "report.md"), "w", encoding="utf-8") as fh:
        fh.write(text)
    if not a.quiet:
        print(text)
    return cal


if __name__ == "__main__":
    main()

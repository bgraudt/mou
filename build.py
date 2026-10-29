#!/usr/bin/env python3
"""Mou — конвертер GTFS Metrovalencia (метро+трамвай) в компактный JSON для прототипа.
Запуск:  python3 -I build.py <путь_к_распакованному_GTFS>
Результат кладётся в ./data/
"""
import csv, json, os, sys
from collections import defaultdict
from datetime import date

GTFS = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(OUT, exist_ok=True)

def read(name):
    p = os.path.join(GTFS, name)
    with open(p, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))

def clean(d):  # обрезать пробелы в значениях (в фиде встречаются " 0")
    return {k: (v.strip() if isinstance(v, str) else v) for k, v in d.items()}

stops   = [clean(r) for r in read("stops.txt")]
routes  = [clean(r) for r in read("routes.txt")]
trips   = [clean(r) for r in read("trips.txt")]
cal     = [clean(r) for r in read("calendar.txt")]
caldate = [clean(r) for r in read("calendar_dates.txt")]

# --- какие service_id активны сегодня ---
today = date.today()
ymd = today.strftime("%Y%m%d")
wd = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"][today.weekday()]
active = set()
for c in cal:
    if c["start_date"] <= ymd <= c["end_date"] and c.get(wd) == "1":
        active.add(c["service_id"])
for c in caldate:
    if c["date"] == ymd:
        if c["exception_type"] == "1": active.add(c["service_id"])
        elif c["exception_type"] == "2": active.discard(c["service_id"])

# --- маршруты (линии) ---
route_by_id = {r["route_id"]: r for r in routes}
lines = {}
for r in routes:
    key = r["route_short_name"]          # сводим варианты одной линии (1a,1b…) к номеру
    if key not in lines:
        lines[key] = {
            "line": key,
            "type": "metro" if r["route_type"] == "1" else "tram",
            "color": "#" + (r.get("route_color") or "888888"),
            "text":  "#" + (r.get("route_text_color") or "FFFFFF"),
            "names": set(),
            "route_ids": set(),
        }
    lines[key]["names"].add(r["route_long_name"])
    lines[key]["route_ids"].add(r["route_id"])

# --- trips → shape/route ; какие линии проходят через остановку ---
trip_info = {t["trip_id"]: t for t in trips}
shape_of_route = {}   # route_id -> shape_id (берём первый попавшийся)
for t in trips:
    shape_of_route.setdefault(t["route_id"], t.get("shape_id"))

# --- stop_times: расписание по остановкам + набор линий на остановке ---
dep_by_stop = defaultdict(list)       # stop_id -> [(time, line, headsign, type, color)]
lines_at_stop = defaultdict(set)      # stop_id -> {line}
with open(os.path.join(GTFS, "stop_times.txt"), encoding="utf-8-sig") as fh:
    for row in csv.DictReader(fh):
        tid = row["trip_id"].strip()
        t = trip_info.get(tid)
        if not t: continue
        r = route_by_id.get(t["route_id"])
        if not r: continue
        line = r["route_short_name"]
        sid = row["stop_id"].strip()
        lines_at_stop[sid].add(line)
        if t["service_id"] in active:
            dep = (row.get("departure_time") or row.get("arrival_time") or "").strip()
            if dep:
                dep_by_stop[sid].append({
                    "t": dep[:5],
                    "line": line,
                    "to": t.get("trip_headsign") or "",
                    "type": lines[line]["type"],
                    "color": lines[line]["color"],
                })

# --- остановки ---
out_stops = []
for s in stops:
    sid = s["stop_id"]
    deps = sorted(dep_by_stop.get(sid, []), key=lambda d: d["t"])
    out_stops.append({
        "id": sid,
        "name": s["stop_name"],
        "lat": float(s["stop_lat"]),
        "lon": float(s["stop_lon"]),
        "zone": s.get("zone_id", ""),
        "lines": sorted(lines_at_stop.get(sid, []), key=lambda x: (len(x), x)),
        "dep": deps,
    })

# --- геометрия линий (shapes) ---
shape_pts = defaultdict(list)
with open(os.path.join(GTFS, "shapes.txt"), encoding="utf-8-sig") as fh:
    for row in csv.DictReader(fh):
        shape_pts[row["shape_id"].strip()].append(
            (int(row["shape_pt_sequence"]), float(row["shape_pt_lat"]), float(row["shape_pt_lon"]))
        )
for k in shape_pts:
    shape_pts[k].sort()

out_lines = []
for key, l in sorted(lines.items(), key=lambda kv: (len(kv[0]), kv[0])):
    # собрать все shape'ы всех route_id этой линии
    polylines = []
    seen = set()
    for rid in l["route_ids"]:
        sh = shape_of_route.get(rid)
        if sh and sh not in seen and sh in shape_pts:
            seen.add(sh)
            polylines.append([[lat, lon] for _, lat, lon in shape_pts[sh]])
    out_lines.append({
        "line": key,
        "type": l["type"],
        "color": l["color"],
        "text": l["text"],
        "name": sorted(l["names"])[0] if l["names"] else key,
        "shapes": polylines,
    })

meta = {
    "source": "Metrovalencia / FGV (GTFS)",
    "built": today.isoformat(),
    "service_date": ymd,
    "stops": len(out_stops),
    "lines": len(out_lines),
}

json.dump(out_stops, open(os.path.join(OUT, "stops.json"), "w"), ensure_ascii=False)
json.dump(out_lines, open(os.path.join(OUT, "lines.json"), "w"), ensure_ascii=False)
json.dump(meta,      open(os.path.join(OUT, "meta.json"),  "w"), ensure_ascii=False, indent=2)

print(json.dumps(meta, ensure_ascii=False, indent=2))
print("stops with schedule today:", sum(1 for s in out_stops if s["dep"]))

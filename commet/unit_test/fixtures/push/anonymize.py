import json, os, re, sys
# Usage: python3 anonymize.py <$OUT/push-payloads> <this folder>
SRC, DST = sys.argv[1], sys.argv[2]
ROOM_OF = {"dm": "dm", "group": "group", "mention": "group", "keyword": "group",
           "thread": "group", "group3": "group3", "e2ee-dm": "e2ee", "e2ee-mention": "e2ee"}
ROOM_NAME = {"group": "Group room", "group3": "Group3 room", "dm": "DM room", "e2ee": "E2EE room"}
expected = []
for server in ["synapse", "tuwunel"]:
    os.makedirs(f"{DST}/{server}", exist_ok=True)
    files = sorted(f for f in os.listdir(f"{SRC}/{server}") if f != "matrix.json")
    ids = {}
    for f in files:
        case, fmt = f[:-5].rsplit("-", 1) if not f.endswith("event_id_only.json") else (f[:-len("-event_id_only.json")], "event_id_only")
        n = json.load(open(f"{SRC}/{server}/{f}"))["notification"]
        ids[n["event_id"]] = f"$event-{case}"
        ids[n["room_id"]] = f"!room-{ROOM_OF[case]}:example.org"
    for f in files:
        fmt = "event_id_only" if f.endswith("event_id_only.json") else "full"
        case = f[: -len(f"-{fmt}.json")]
        def walk(v, key=None):
            if isinstance(v, dict):
                return {k: walk(x, k) for k, x in v.items()}
            if isinstance(v, list):
                return [walk(x) for x in v]
            if not isinstance(v, str):
                return 1700000000 if key == "pushkey_ts" else v
            if key == "pushkey": return f"pushkey-{fmt}"
            if key == "local_client_id": return "client-alice"
            if key == "room_name": return ROOM_NAME[ROOM_OF[case]]
            if v in ids: return ids[v]
            if (v.startswith("$") or v.startswith("!")) and key not in ("body",):
                sys.exit(f"unmapped id {v} in {server}/{f}")
            for a, b in [("@alice:localhost", "@alice:example.org"), ("@bob:localhost", "@bob:example.org"), ("@carol:localhost", "@carol:example.org")]:
                v = v.replace(a, b)
            if ":localhost" in v: sys.exit(f"unmapped user in {v}")
            return v
        out = walk(json.load(open(f"{SRC}/{server}/{f}")))
        open(f"{DST}/{server}/{f}", "w").write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    for row in json.load(open(f"{SRC}/{server}/matrix.json")):
        if not row["pushed"]: continue
        o = row["outcome"]
        expected.append({"server": server, "case": row["case"], "format": row["format"],
                         "shown": o.startswith("shown"), "sound": "+sound" in o, "highlight": "+highlight" in o})
open(f"{DST}/expected.json", "w").write(json.dumps(expected, indent=2) + "\n")

"""Convert Rote-format .txt poems (title / author / blank / body) into one rote.poems JSON archive.

Usage: python3 tools/txt2rote.py library/poems library/rote-import.json
Poem ids derive from file names, so re-importing replaces the same poems.
"""
import json, sys, uuid, datetime, pathlib

src = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2])
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
NS = uuid.UUID("7d1a4d3e-5b1c-4b7e-9c1e-rote00000000".replace("rote", "0000"))
poems = []
for f in sorted(src.glob("*.txt")):
    lines = f.read_text(encoding="utf-8").replace("\r\n", "\n").split("\n")
    if len(lines) < 4 or lines[2].strip() != "":
        sys.exit(f"{f.name}: expected title, author, blank line")
    title, author = lines[0].strip(), lines[1].strip()
    body = "\n".join(lines[3:]).rstrip("\n") + "\n"
    poems.append({
        "id": str(uuid.uuid5(NS, f.name)).upper(),
        "title": title, "author": author,
        "sourceNote": f"{f.name}; typed from a standard edition, verify against the link in library/POEMS.md",
        "rawText": body, "locale": "en-US", "status": "draft",
        "createdAt": now, "updatedAt": now,
        "settings": {"contextLines": 2, "sleepGateEnabled": True, "passThreshold": 0.9, "failThreshold": 0.7},
        "rungs": {}, "items": [], "wordStats": [], "runs": [],
    })
out.write_text(json.dumps({"format": "rote.poems", "version": 1, "exportedAt": now, "poems": poems}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"wrote {len(poems)} poems to {out}")

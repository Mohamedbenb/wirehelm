"""Every engine source must declare how it is previewed or tested, including unavailable native paths."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
data=json.loads((root/"coverage/inventory.json").read_text(encoding="utf-8"))
actual={p.relative_to(root).as_posix() for p in (root/"src/main").rglob("*") if p.suffix in {".java",".kt"}}
listed=set()
for feature in data["features"]:
 assert feature.get("preview") and feature.get("tests"),feature["id"]
 listed.update(feature["sources"])
missing=actual-listed;stale=listed-actual
if missing or stale:raise SystemExit(f"Missing coverage mapping: {sorted(missing)}; stale: {sorted(stale)}")
print(f"Coverage inventory verified: {len(actual)} engine sources, {len(data['features'])} capability groups; native/GPU execution remains separately reported")

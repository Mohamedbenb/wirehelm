"""Fail when reusable engine sources acquire SystemUI/hooks/controller dependencies."""
from pathlib import Path
import re, zipfile
root=Path(__file__).resolve().parents[1]
forbidden=[r"io\.github\.libxposed",r"com\.android\.systemui",r"com\.android\.compose\.animation\.scene",r"\bIndicatorSettings\b",r"\bSystemGlassLayers\b",r"\bNetworkSpeedModule\b",r"\bQsTileRegions\b",r"\bNotificationEntry\b",r"io\.flutter"]
errors=[]
for p in (root/"src/main").rglob("*"):
 if p.suffix not in {".java",".kt"}: continue
 text=p.read_text(encoding="utf-8")
 for pattern in forbidden:
  if re.search(pattern,text):errors.append(f"{p.relative_to(root)}: {pattern}")
gradle=(root/"build.gradle.kts").read_text(encoding="utf-8")
if 'project("' in gradle: errors.append("Engine must not depend on a host project")
if errors: raise SystemExit("\n".join(errors))
print("Engine boundary verified: no SystemUI, hook framework, Flutter or host project dependency")

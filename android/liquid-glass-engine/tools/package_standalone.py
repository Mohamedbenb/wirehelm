"""Export only engine/demo sources and their independent Gradle entry point."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import sys,re
module=Path(__file__).resolve().parents[1]
repo=module.parents[1]
version=re.search(r'VERSION="([^"]+)"', (module/"src/main/java/com/nodecockpit/customization/LiquidGlassEngine.java").read_text(encoding="utf-8")).group(1)
out=Path(sys.argv[1]) if len(sys.argv)>1 else repo/f"build/glass-engine-artifacts/Liquid-Glass-Engine-{version}-source.zip"
out.parent.mkdir(parents=True,exist_ok=True)
roots=[module,repo/"android/liquid-glass-demo",repo/"glass-lab"]
files=[]
for root in roots:
 for p in root.rglob("*"):
  rel=p.relative_to(root)
  if p.is_file() and not any(part in {"build",".gradle","__pycache__"} for part in rel.parts) and p.name!="local.properties": files.append(p)
files += [repo/"android/gradlew",repo/"android/gradlew.bat"]
files += list((repo/"android/gradle/wrapper").glob("*"))
with ZipFile(out,"w",ZIP_DEFLATED) as z:
 for p in sorted(files): z.write(p,p.relative_to(repo).as_posix())
print(out)

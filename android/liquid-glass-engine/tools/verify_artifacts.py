"""Check published engine/demo separation and exclusion of compile-only framework stubs."""
from pathlib import Path
from zipfile import ZipFile
from io import BytesIO
import struct,sys

def classes(data):
 def u32(offset):return struct.unpack_from("<I",data,offset)[0]
 count,offset=struct.unpack_from("<II",data,56);strings=[]
 for i in range(count):
  pos=u32(offset+i*4)
  while data[pos]&128:pos+=1
  pos+=1;end=data.index(0,pos);strings.append(data[pos:end].decode("utf-8",errors="replace"))
 count,offset=struct.unpack_from("<II",data,64);types=[strings[u32(offset+i*4)] for i in range(count)]
 count,offset=struct.unpack_from("<II",data,96)
 return {types[u32(offset+i*32)] for i in range(count)}

with ZipFile(sys.argv[1]) as aar:
 assert "assets/licenses/liquid-glass-views.txt" in aar.namelist(),"Missing optical license"
 with ZipFile(BytesIO(aar.read("classes.jar"))) as jar:
  names=jar.namelist()
  assert "com/nodecockpit/customization/LiquidGlassEngine.class" in names
  assert "com/nodecockpit/customization/GlassPreviewView.class" in names
  assert not any(n.startswith(("android/","io/github/libxposed/")) for n in names),"Stub or hook runtime leaked into engine"
  assert not any("NetworkSpeedModule" in n or "SystemGlassLayers" in n for n in names),"Host integration leaked into engine"
with ZipFile(sys.argv[2]) as apk:
 names=apk.namelist();assert "META-INF/xposed/java_init.list" not in names
 defined=set()
 for n in names:
  if n.startswith("classes") and n.endswith(".dex") and "/" not in n:defined.update(classes(apk.read(n)))
 assert "Lcom/nodecockpit/glassdemo/MainActivity;" in defined
 assert "Lcom/nodecockpit/customization/GlassPreviewView;" in defined
 assert not any(n.startswith(("Lio/github/libxposed/","Lcom/android/systemui/")) or "NetworkSpeedModule" in n for n in defined),"Production integration leaked into demo"
print("Verified engine AAR and isolated demo APK; no packaged platform stub or SystemUI/Xposed integration")

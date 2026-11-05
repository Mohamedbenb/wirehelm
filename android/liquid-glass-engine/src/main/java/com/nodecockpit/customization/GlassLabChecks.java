package com.nodecockpit.customization;
import java.util.*;
import org.json.JSONObject;
/** On-device CPU smoke checks. These are not GPU/presentation or privileged transport tests. */
public final class GlassLabChecks {
 private GlassLabChecks(){}
 private static void check(List<String> out,String name,Runnable action){try{action.run();out.add("PASS · "+name);}catch(Throwable error){out.add("FAIL · "+name+": "+error.getClass().getSimpleName()+" "+error.getMessage());}}
 private static void require(boolean condition){if(!condition)throw new IllegalStateException("Contract failed");}
 public static List<String> run(){List<String> out=new ArrayList<>();
  check(out,"All material uniform sizes",()->{byte[] base=CardLiquidParameters.uniforms(400,240,32,new JSONObject(),-.5f,-.8f,0,0,0,new CardRippleTimeline().values);require(base.length==240);require(CardMergeUniforms.extend(base,null).length==272);require(CardNotificationUniforms.cluster(base,new float[0][],0,0).length==848);require(NativeQsUniforms.pack(base,new float[0][],0,0).length==1392);require(NativeLiquidMaterial.pack(400,240,32,3,false,2,4,.03f,.4f,.6f).length==32);});
  check(out,"QS region count and invalid geometry rejection",()->{byte[] b=new byte[240];boolean rejected=false;try{NativeQsUniforms.pack(b,new float[17][16],0,0);}catch(IllegalArgumentException expected){rejected=true;}require(rejected);float[][] shape=new float[1][16];shape[0][0]=Float.NaN;rejected=false;try{NativeQsUniforms.pack(b,shape,0,0);}catch(IllegalArgumentException expected){rejected=true;}require(rejected);});
  check(out,"Notification region/control limits",()->{boolean rejected=false;try{CardNotificationUniforms.cluster(new byte[240],new float[14][8],0,0);}catch(IllegalArgumentException expected){rejected=true;}require(rejected);require(CardNotificationUniforms.cluster(new byte[240],new float[13][8],new float[10][4],48,1,100).length==848);});
  check(out,"Frame receipt rejects stale/replaced submissions",()->{GlassFrameCommit<Object> r=new GlassFrameCommit<>();Object first=new Object(),second=new Object();r.prepare(first);require(!r.ready(first));require(r.submit(first)&&r.ready(first));r.prepare(second);require(!r.ready(first)&&!r.submit(first));require(r.submit(second)&&r.ready(second));r.clear();require(!r.ready(second));});
  check(out,"Shader lease pins, references and underflow",()->{GlassShaderLease lease=new GlassShaderLease();require(lease.canUnregister());lease.acquire();lease.pin(1,true);lease.release();require(!lease.canUnregister());lease.pin(1,false);lease.release();require(lease.canUnregister());});
  check(out,"Readiness timeout, hidden grace and reset",()->{NativeSurfaceReadiness r=new NativeSurfaceReadiness();require(r.pending(0,true));require(!r.pending(3001,true));require(r.pending(10000,false));require(r.pending(20000,true));r.ready();require(r.pending(30000,true));});
  check(out,"Ripple press/release, four-slot expiry",()->{CardRippleTimeline r=new CardRippleTimeline();for(int i=0;i<8;i++)r.emit(.5f,.5f,i*10,i%2==1);require(r.values.length==16);require(r.advance(100,1));require(!r.advance(3000,1));r.clear();require(r.values[2]<0);});
  check(out,"Foreground bounds, manual color and auto contrast",()->{Map<String,Object> values=new HashMap<>();values.put("outlineWidth",99);values.put("shadowRadius",99);ForegroundInkStyle s=new ForegroundInkStyle(values);require(s.outlineWidth==3&&s.shadowRadius==8);require(ForegroundInkStyle.valid(Collections.emptyMap()));require((s.outline(0xffffffff)&0xffffff)==0);require((s.outline(0xff000000)&0xffffff)==0xffffff);});
  check(out,"Contrast changes with known light/dark backdrop",()->require(GlassContrast.foreground(0,0,0)!=GlassContrast.foreground(0,1,0)));
  check(out,"Frame metrics reject duplicate/invalid present fences",()->{GlassFrameStats s=new GlassFrameStats();s.frame(Long.MAX_VALUE,-1,0,0,0);s.frame(100,-1,0,0,0);s.frame(100,-1,0,0,0);require(s.presented==1&&s.gpuCount==0);});
  check(out,"Damped transition remains bounded",()->{DampedShade s=new DampedShade();s.seed(0);for(int i=0;i<120;i++)s.step(255,16,200);require(Float.isFinite(s.value)&&s.value>=0&&s.value<=255);});
  out.add("GPU pixels, presentation timing, cross-window sampling and privileged transport: NOT tested by CPU checks.");return out;
 }
}

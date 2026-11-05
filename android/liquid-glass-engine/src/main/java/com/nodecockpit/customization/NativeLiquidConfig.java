package com.nodecockpit.customization;
import org.json.JSONObject;
/** Missing backend always selects the existing renderer; scoped edge saves own this JSON. */
final class NativeLiquidConfig {
 final int searchWidth,searchHeight;final boolean card;final JSONObject cardOptions;
 final boolean enabled,panel,handle,darkInk,liveHandle,performanceOverlay; final int preset; final float blur,refraction,tint,edge,contrast;
 NativeLiquidConfig(String raw){this(raw,-1);}
 NativeLiquidConfig(String raw,int textTone){darkInk=textTone>=0&&textTone<50;JSONObject v;try{v=new JSONObject(raw);}catch(Exception e){v=new JSONObject();}
  card="card".equals(v.optString("engine"));cardOptions=v.optJSONObject("cardMaterial")==null?new JSONObject():v.optJSONObject("cardMaterial");
  JSONObject search=v.optJSONObject("searchTray");searchWidth=search==null?0:search.optInt("width",0);searchHeight=search==null?0:search.optInt("height",0);
  performanceOverlay=v.optBoolean("performanceOverlay",false);
  liveHandle=v.optBoolean("liveHandle",false);
  enabled="native".equals(v.optString("backend","legacy"));panel=v.optBoolean("panel",true);handle=v.optBoolean("handle",false);
  preset=clamp(v.optInt("preset",3),0,3);
  double[][] defaults={{0,0,0,0,0},{.6,5,.025,.32,.45},{6,2.5,.055,.28,.70},{2.2,4,.035,.42,.60}};
  double[] d=defaults[preset];blur=bound(v.optDouble("blur",d[0]),0,12);refraction=bound(v.optDouble("refraction",d[1]),0,12);tint=bound(v.optDouble("tint",d[2]),0,.6);edge=bound(v.optDouble("edge",d[3]),0,1);contrast=bound(v.optDouble("contrast",d[4]),0,1);
 }
 static float bound(double v,double lo,double hi){return (float)(Double.isFinite(v)?Math.max(lo,Math.min(hi,v)):lo);}
 static boolean valid(String raw){if(raw==null||raw.length()>4096)return false;try{JSONObject v=new JSONObject(raw);
  if(v.has("searchTray")){JSONObject t=v.getJSONObject("searchTray");if(t.has("docked")&&!(t.get("docked") instanceof Boolean))return false;if(t.has("x")!=t.has("y"))return false;for(String k:new String[]{"x","y"})if(t.has(k)&&(!(t.get(k) instanceof Number)||!Double.isFinite(t.getDouble(k))||t.getDouble(k)<0||t.getDouble(k)>1))return false;
   String[] dims={"width","height"};int[] mins={140,180},maxs={600,1200};for(int i=0;i<2;i++)if(t.has(dims[i])){Object n=t.get(dims[i]);double value=t.getDouble(dims[i]);if(!(n instanceof Number)||!Double.isFinite(value)||value!=Math.rint(value)||value!=0&&(value<mins[i]||value>maxs[i]))return false;}}
  if(!GlassTestConfig.valid(v)||!CardLiquidParameters.valid(v))return false;
  if(!java.util.Arrays.asList("legacy","native").contains(v.optString("backend","legacy")))return false;
  for(String k:new String[]{"panel","handle","liveHandle","performanceOverlay"})if(v.has(k)&&!(v.get(k) instanceof Boolean))return false;
  if(v.has("preset")&&(!(v.get("preset") instanceof Number)||v.getDouble("preset")!=v.getInt("preset")||v.getInt("preset")<0||v.getInt("preset")>3))return false;
  String[] names={"blur","refraction","tint","edge","contrast"};double[] max={12,12,.6,1,1};for(int i=0;i<names.length;i++)if(v.has(names[i])){Object n=v.get(names[i]);if(!(n instanceof Number)||!Double.isFinite(((Number)n).doubleValue())||((Number)n).doubleValue()<0||((Number)n).doubleValue()>max[i])return false;}
  return true;}catch(Exception e){return false;}}
 private static int clamp(int v,int lo,int hi){return Math.max(lo,Math.min(hi,v));}
}

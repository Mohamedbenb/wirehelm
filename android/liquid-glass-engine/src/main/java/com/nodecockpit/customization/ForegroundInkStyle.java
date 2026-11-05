package com.nodecockpit.customization;
import org.json.JSONObject;
/** Shared, bounded foreground protection for System Glass; no backdrop sampling. */
public final class ForegroundInkStyle {
 public static final ForegroundInkStyle DEFAULT=new ForegroundInkStyle(java.util.Collections.emptyMap());
 static volatile ForegroundInkStyle current=DEFAULT;
 public final float outlineWidth,outlineOpacity,shadowRadius,shadowOpacity,shadowX,shadowY;
 public final int outlineColor,shadowColor;public final boolean outlineAuto,shadowAuto;
 private final String signature;
 public ForegroundInkStyle(java.util.Map<String,Object> v){outlineWidth=n(v,"outlineWidth",.65f,0,3);outlineOpacity=n(v,"outlineOpacity",100,0,100)/100;shadowRadius=n(v,"shadowRadius",1.5f,0,8);shadowOpacity=n(v,"shadowOpacity",44,0,100)/100;shadowX=n(v,"shadowX",0,-6,6);shadowY=n(v,"shadowY",.5f,-6,6);outlineAuto=bool(v,"outlineAuto",true);shadowAuto=bool(v,"shadowAuto",true);outlineColor=color(str(v,"outlineColor","#000000"));shadowColor=color(str(v,"shadowColor","#000000"));signature=java.util.Arrays.asList(outlineWidth,outlineOpacity,shadowRadius,shadowOpacity,shadowX,shadowY,outlineAuto,shadowAuto,outlineColor,shadowColor).toString();}
 private static boolean bool(java.util.Map<String,Object> v,String k,boolean d){Object x=v.get(k);return x instanceof Boolean?(Boolean)x:d;}
 private static String str(java.util.Map<String,Object> v,String k,String d){Object x=v.get(k);return x instanceof String?(String)x:d;}
 private static float n(java.util.Map<String,Object> v,String k,float d,float lo,float hi){Object value=v.get(k);double x=value instanceof Number?((Number)value).doubleValue():d;return Double.isFinite(x)?(float)Math.max(lo,Math.min(hi,x)):d;}
 private static int color(String s){try{return 0xff000000|Integer.parseInt(s.substring(1),16);}catch(Exception e){return 0xff000000;}}
 public int outline(int ink){return alpha(outlineAuto?opposite(ink):outlineColor,outlineOpacity);}
 public int shadow(int ink){return alpha(shadowAuto?opposite(ink):shadowColor,shadowOpacity);}
 private static int opposite(int ink){double y=.2126*linear(ink>>16&255)+.7152*linear(ink>>8&255)+.0722*linear(ink&255);return y>.179?0xff000000:0xffffffff;}
 private static double linear(int x){double s=x/255.;return s<=.04045?s/12.92:Math.pow((s+.055)/1.055,2.4);}
 private static int alpha(int c,float a){return (Math.round(255*a)<<24)|(c&0xffffff);}
 long offset(float density){return ((long)Float.floatToRawIntBits(shadowX*density)<<32)|(Float.floatToRawIntBits(shadowY*density)&0xffffffffL);}
 static void configure(String raw){try{JSONObject root=new JSONObject(raw).optJSONObject("nativeNotifications"),v=root==null?null:root.optJSONObject("foreground");set(v==null?java.util.Collections.emptyMap():values(v));}catch(Exception e){current=DEFAULT;}}
 static java.util.Map<String,Object> values(JSONObject v){java.util.Map<String,Object> out=new java.util.HashMap<>();java.util.Iterator<String> keys=v.keys();while(keys.hasNext()){String k=keys.next();out.put(k,v.opt(k));}return out;}
 static void set(java.util.Map<String,Object> v){ForegroundInkStyle next=new ForegroundInkStyle(v);if(!current.signature.equals(next.signature))current=next;}
 static boolean valid(JSONObject v){return valid(values(v));}
 static boolean valid(java.util.Map<String,Object> v){for(String k:new String[]{"outlineWidth","outlineOpacity","shadowRadius","shadowOpacity","shadowX","shadowY"})if(v.containsKey(k)){Object value=v.get(k);if(!(value instanceof Number))return false;double x=((Number)value).doubleValue(),lo=k.equals("shadowX")||k.equals("shadowY")?-6:0,hi=k.equals("outlineWidth")?3:k.equals("shadowRadius")?8:k.equals("shadowX")||k.equals("shadowY")?6:100;if(!Double.isFinite(x)||x<lo||x>hi)return false;}for(String k:new String[]{"outlineAuto","shadowAuto"})if(v.containsKey(k)&&!(v.get(k) instanceof Boolean))return false;for(String k:new String[]{"outlineColor","shadowColor"})if(v.containsKey(k)&&(!(v.get(k) instanceof String)||!((String)v.get(k)).matches("#[0-9a-fA-F]{6}")))return false;return true;}
}

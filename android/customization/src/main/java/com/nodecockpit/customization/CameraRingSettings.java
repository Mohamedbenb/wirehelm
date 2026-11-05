package com.nodecockpit.customization;

import java.util.*;
import org.json.*;

/** Strict, bounded notification-ring configuration. No Android or glass dependency. */
final class CameraRingSettings {
    static final String DEFAULT="{\"enabled\":false,\"ambientOnDemand\":false,\"thickness\":3,\"intensity\":100,\"intervalMs\":2500,\"includeOngoing\":false,\"apps\":[]}";
    final boolean enabled,includeOngoing,ambientOnDemand;final float thickness;final int intensity,intervalMs;
    final Map<String,App> apps;
    static final class App {final String pkg,color;final int priority;App(String p,String c,int n){pkg=p;color=c;priority=n;}}
    CameraRingSettings(String raw)throws JSONException{
        if(raw==null||raw.length()>16000)throw new IllegalArgumentException("Ring settings too large");
        JSONObject j=new JSONObject(raw);for(String k:new String[]{"enabled","includeOngoing","ambientOnDemand"})if(j.has(k)&&!(j.get(k) instanceof Boolean))throw new IllegalArgumentException("Invalid "+k);
        enabled=j.optBoolean("enabled",false);includeOngoing=j.optBoolean("includeOngoing",false);ambientOnDemand=j.optBoolean("ambientOnDemand",false);
        thickness=(float)number(j,"thickness",3,1,8,false);intensity=(int)number(j,"intensity",100,10,100,true);intervalMs=(int)number(j,"intervalMs",2500,1000,10000,true);
        JSONArray a=j.has("apps")?j.getJSONArray("apps"):new JSONArray();if(a.length()>64)throw new IllegalArgumentException("Select at most64 apps");
        Map<String,App> map=new LinkedHashMap<>();for(int i=0;i<a.length();i++){
            JSONObject v=a.getJSONObject(i);String pkg=v.getString("package"),color=v.optString("color","#FFFFFF").toUpperCase(Locale.ROOT);
            if(!pkg.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+")||pkg.length()>200||!color.matches("#[0-9A-F]{6}")||map.containsKey(pkg))throw new IllegalArgumentException("Invalid/duplicate ring app");
            map.put(pkg,new App(pkg,color,(int)number(v,"priority",3,1,5,true)));
        }apps=Collections.unmodifiableMap(map);
    }
    private static double number(JSONObject j,String k,double fallback,double lo,double hi,boolean integer)throws JSONException{
        Object v=j.opt(k);if(v==null)return fallback;if(!(v instanceof Number))throw new IllegalArgumentException("Invalid "+k);
        double n=((Number)v).doubleValue();if(!Double.isFinite(n)||n<lo||n>hi||integer&&n!=Math.rint(n))throw new IllegalArgumentException("Invalid "+k);return n;
    }
    static CameraRingSettings safe(String raw){try{return new CameraRingSettings(raw);}catch(Exception e){try{return new CameraRingSettings(DEFAULT);}catch(Exception impossible){throw new AssertionError(impossible);}}}
    static String disabled(String raw){try{return new JSONObject(raw).put("enabled",false).toString();}catch(Exception e){return DEFAULT;}}
    static void mergeOwnership(JSONObject incoming,String current,boolean ownsRing)throws JSONException{
        incoming.put("cameraRing",ownsRing?incoming.optString("cameraRing",DEFAULT):current);
    }
}

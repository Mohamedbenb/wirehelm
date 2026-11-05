package com.nodecockpit.customization;
import org.json.*;
/** Persistent feature choices; native notification and lock-screen privacy remain authoritative. */
final class NotificationUndoSettings {
    static final String DEFAULT="{\"enabled\":false,\"shake\":true,\"button\":true,\"sensitivity\":1}";
    static final String MIGRATED="{\"enabled\":true,\"shake\":true,\"button\":true,\"sensitivity\":1}";
    final boolean enabled,shake,button;
    final int sensitivity;
    NotificationUndoSettings(String raw)throws JSONException{
        if(raw==null||raw.length()>512)throw new IllegalArgumentException("Undo settings too large");
        JSONObject j=new JSONObject(raw);
        for(String key:new String[]{"enabled","shake","button"})if(j.has(key)&&!(j.get(key) instanceof Boolean))throw new IllegalArgumentException("Invalid "+key);
        Object strength=j.opt("sensitivity");
        if(strength!=null&&(!(strength instanceof Number)||!Double.isFinite(((Number)strength).doubleValue())||((Number)strength).doubleValue()!=Math.rint(((Number)strength).doubleValue())||((Number)strength).intValue()<0||((Number)strength).intValue()>2))throw new IllegalArgumentException("Invalid shake strength");
        enabled=j.optBoolean("enabled",false);shake=j.optBoolean("shake",true);button=j.optBoolean("button",true);sensitivity=j.optInt("sensitivity",1);
        if(enabled&&!shake&&!button)throw new IllegalArgumentException("Enable the Undo button or shake");
    }
    static NotificationUndoSettings safe(String raw){try{return new NotificationUndoSettings(raw);}catch(Exception e){try{return new NotificationUndoSettings(DEFAULT);}catch(Exception impossible){throw new AssertionError(impossible);}}}
    static String disabled(String raw){try{return new JSONObject(raw).put("enabled",false).toString();}catch(Exception e){return DEFAULT;}}
    static void mergeOwnership(JSONObject incoming,String current,boolean ownsUndo)throws JSONException{incoming.put("notificationUndo",ownsUndo?incoming.optString("notificationUndo",DEFAULT):current);}
}

package com.nodecockpit.customization;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.drawable.Drawable;

/** Built-in destinations share the existing edge shortcut/folder format. */
public final class EdgeBuiltinShortcuts {
    public static final String CLIPBOARD="com.example.remote_control.clipboard_shelf";
    public static final String APP="com.example.remote_control";
    public static final String LABEL="Clipboard shelf";
    public static final String EXTRA="wirehelm.open";
    public static final String DESTINATION="clipboard";
    public static final String ROUTE="/clipboard-shelf";
    public static final String ACTIONS_DESTINATION="edge-actions", ACTIONS_ROUTE="/edge-actions";
    public static String route(String destination){return DESTINATION.equals(destination)?ROUTE:ACTIONS_DESTINATION.equals(destination)?ACTIONS_ROUTE:null;}
    public static Intent actionSettingsIntent(PackageManager pm){Intent i=pm.getLaunchIntentForPackage(APP);return i==null?null:i.putExtra(EXTRA,ACTIONS_DESTINATION).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);}
    public static boolean isClipboard(String id){return CLIPBOARD.equals(id);}
    public static String owner(String id){return isClipboard(id)?APP:id;}
    public static Intent intent(PackageManager pm,String id){
        Intent launch=pm.getLaunchIntentForPackage(owner(id));
        if(launch!=null&&isClipboard(id))launch.putExtra(EXTRA,DESTINATION).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return launch;
    }
    public static CharSequence label(PackageManager pm,String id)throws PackageManager.NameNotFoundException{
        return isClipboard(id)?LABEL:pm.getApplicationLabel(pm.getApplicationInfo(id,0));
    }
    public static Drawable icon(PackageManager pm,String id)throws PackageManager.NameNotFoundException{return pm.getApplicationIcon(owner(id));}
    public static String addClipboard(String raw){
        if(!FeaturePolicy.validEdgeApps(raw))throw new IllegalArgumentException("Invalid edge shortcuts");
        for(String member:raw.split("[,+]"))if(isClipboard(member))return raw;
        String added=raw.isEmpty()?CLIPBOARD:raw+","+CLIPBOARD;
        if(!FeaturePolicy.validEdgeApps(added))throw new IllegalArgumentException("Edge panel is full. Remove a shortcut before adding Clipboard shelf.");
        return added;
    }
    private EdgeBuiltinShortcuts(){}
}

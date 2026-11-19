package com.nodecockpit.customization;
import org.json.*;
import java.util.*;
/** Independent toolbar content/style settings; no material properties. */
final class EdgeActionSettings {
    static final String DEFAULT="{}";
    static final List<String> IDS=Arrays.asList("edit","windows","capture","clipboard","settings");
    final List<String> order;final Set<String> hidden;final boolean labels;final int iconSize,columns;
    EdgeActionSettings(String raw)throws JSONException {
        JSONObject j=new JSONObject(raw);for(String key:new String[]{"order","hidden"})if(j.has(key)&&!(j.get(key) instanceof JSONArray))throw new IllegalArgumentException("Invalid action list");JSONArray a=j.optJSONArray("order");List<String> o=new ArrayList<>();
        if(a==null)o.addAll(IDS);else for(int i=0;i<a.length();i++)o.add(a.getString(i));
        if(o.size()!=IDS.size()||!new HashSet<>(o).equals(new HashSet<>(IDS)))throw new IllegalArgumentException("Invalid panel action order");
        Set<String> h=new HashSet<>();a=j.optJSONArray("hidden");if(a==null)h.add("clipboard");else for(int i=0;i<a.length();i++){String id=a.getString(i);if(!IDS.contains(id)||!h.add(id))throw new IllegalArgumentException("Invalid hidden action");}
        if(j.has("labels")&&!(j.get("labels") instanceof Boolean))throw new IllegalArgumentException("Invalid action label setting");
        labels=j.optBoolean("labels",true);iconSize=j.optInt("iconSize",24);columns=j.optInt("columns",0);
        if(iconSize<20||iconSize>32||columns<0||columns>4)throw new IllegalArgumentException("Invalid action size or columns");
        if(j.has("iconSize")&&j.getDouble("iconSize")!=iconSize||j.has("columns")&&j.getDouble("columns")!=columns)throw new IllegalArgumentException("Action dimensions must be whole numbers");
        order=Collections.unmodifiableList(o);hidden=Collections.unmodifiableSet(h);
    }
    static int contentWidth(int panelWidthDp,int paddingDp){return Math.max(48,panelWidthDp-2*paddingDp);}
    int columnsFor(int widthDp,boolean wide){return Math.max(1,Math.min(Math.max(1,widthDp/48),columns==0?(wide?4:2):columns));}
    static int toolbarHeightLimit(int heightDp){return Math.max(48,Math.min(heightDp/2,heightDp-144));}
    static EdgeActionSettings safe(String raw){try{return new EdgeActionSettings(raw);}catch(Exception e){try{return new EdgeActionSettings(DEFAULT);}catch(Exception impossible){throw new AssertionError(impossible);}}}
}

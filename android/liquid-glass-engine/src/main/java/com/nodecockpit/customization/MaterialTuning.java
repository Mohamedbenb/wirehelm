package com.nodecockpit.customization;

import java.util.*;

/** Bounded, Android-independent laboratory policy. Disabled preserves shipping behavior. */
final class MaterialTuning {
    static final Map<String,int[]> RANGES;
    static {
        Map<String,int[]> values=new LinkedHashMap<>();
        values.put("saturation",new int[]{0,200,100}); values.put("borderLuminance",new int[]{-100,100,0});
        values.put("darkThreshold",new int[]{5,80,38}); values.put("lightThreshold",new int[]{20,95,62}); values.put("hysteresis",new int[]{0,20,8});
        values.put("backgroundHoldMs",new int[]{0,300,120});values.put("medianWindowMs",new int[]{40,300,160});
        values.put("signalDelta",new int[]{0,150,35}); values.put("lumaResponseMs",new int[]{0,1000,240});
        values.put("appearanceResponseMs",new int[]{16,600,120}); values.put("textResponseMs",new int[]{8,300,90}); values.put("textHoldMs",new int[]{0,600,300});
        values.put("textBias",new int[]{-20,20,0}); values.put("contrastHysteresis",new int[]{0,60,15}); values.put("minimumContrast",new int[]{300,700,450});
        values.put("sampleLeft",new int[]{0,90,0}); values.put("sampleTop",new int[]{0,90,0}); values.put("sampleRight",new int[]{10,100,100}); values.put("sampleBottom",new int[]{10,100,100});
        values.put("samplePaddingDp",new int[]{0,48,0}); values.put("publishIntervalMs",new int[]{0,250,16});
        RANGES=Collections.unmodifiableMap(values);
    }
    static final MaterialTuning DEFAULT=new MaterialTuning(Collections.emptyMap());
    final boolean enabled,showRegions,dynamicText;
    private final Map<String,Integer> values=new LinkedHashMap<>();
    MaterialTuning(Map<String,?> input) {
        dynamicText=Boolean.TRUE.equals(input.get("dynamicText")); enabled=Boolean.TRUE.equals(input.get("enabled")); showRegions=Boolean.TRUE.equals(input.get("showRegions"));
        for(Map.Entry<String,int[]> e:RANGES.entrySet()) { Object raw=input.get(e.getKey()); int[] r=e.getValue(); int n=raw instanceof Number?((Number)raw).intValue():r[2]; values.put(e.getKey(),Math.max(r[0],Math.min(r[1],n))); }
    }
    int get(String key) { return values.get(key); }
    static boolean valid(Map<String,?> input) {
        for(Map.Entry<String,?> e:input.entrySet()) {
            if(e.getKey().equals("enabled")||e.getKey().equals("showRegions")||e.getKey().equals("dynamicText")) { if(!(e.getValue() instanceof Boolean)) return false; continue; }
            int[] range=RANGES.get(e.getKey()); if(range==null||!(e.getValue() instanceof Number)) return false;
            double n=((Number)e.getValue()).doubleValue(); if(!Double.isFinite(n)||n!=Math.rint(n)||n<range[0]||n>range[1]) return false;
        }
        MaterialTuning t=new MaterialTuning(input);
        return t.get("darkThreshold")<t.get("lightThreshold")&&t.get("sampleLeft")<t.get("sampleRight")&&t.get("sampleTop")<t.get("sampleBottom");
    }
    int[] crop(int left,int top,int right,int bottom,float density,int displayLeft,int displayTop,int displayRight,int displayBottom) {
        int width=Math.max(1,right-left),height=Math.max(1,bottom-top),padding=enabled?Math.round(get("samplePaddingDp")*density):0;
        int l=left+(enabled?Math.round(width*get("sampleLeft")/100f):0)-padding,t=top+(enabled?Math.round(height*get("sampleTop")/100f):0)-padding;
        int r=enabled?left+Math.round(width*get("sampleRight")/100f)+padding:right,b=enabled?top+Math.round(height*get("sampleBottom")/100f)+padding:bottom;
        l=Math.max(displayLeft,Math.min(displayRight-1,l));t=Math.max(displayTop,Math.min(displayBottom-1,t));
        return new int[]{l,t,Math.max(l+1,Math.min(displayRight,r)),Math.max(t+1,Math.min(displayBottom,b))};
    }
    boolean samplingChanged(MaterialTuning previous) {
        if(enabled!=previous.enabled) return true; if(!enabled) return false;
        if(showRegions!=previous.showRegions) return true;
        for(String key:new String[]{"sampleLeft","sampleTop","sampleRight","sampleBottom","samplePaddingDp"}) if(get(key)!=previous.get(key)) return true;
        return false;
    }
    int luminanceResponse(String role) { return role.equals("edgeLegacy")&&!enabled?0:enabled?get("lumaResponseMs"):240; }
    float delta() { return enabled?get("signalDelta")/1000f:.035f; }
    float tone(float luma) {
        if(!enabled) return GlassTransitionMath.tone(luma);
        float low=Math.max(0,.18f+(get("darkThreshold")-38)/100f-(get("hysteresis")-8)/100f),high=Math.min(1,.82f+(get("lightThreshold")-62)/100f+(get("hysteresis")-8)/100f);
        float t=Math.max(0,Math.min(1,(luma-low)/Math.max(.01f,high-low))); return t*t*(3-2*t);
    }
    int tint(int color) {
        if(!enabled||get("saturation")==100) return color;
        float gray=.2126f*((color>>16)&255)+.7152f*((color>>8)&255)+.0722f*(color&255),sat=get("saturation")/100f; int out=color&0xff000000;
        for(int shift:new int[]{16,8,0}) out|=Math.round(Math.max(0,Math.min(255,gray+(((color>>shift)&255)-gray)*sat)))<<shift;
        return out;
    }
    int border(int color) { if(!enabled) return color; float n=get("borderLuminance")/100f; return (color&0xff000000)|(GlassTransitionMath.mix(color,n<0?0xff000000:0xffffffff,Math.abs(n))&0xffffff); }
    @Override public boolean equals(Object value) { if(!(value instanceof MaterialTuning)) return false; MaterialTuning t=(MaterialTuning)value; return enabled==t.enabled&&showRegions==t.showRegions&&dynamicText==t.dynamicText&&values.equals(t.values); }
    @Override public int hashCode() { return values.hashCode()+(enabled?1:0)+(showRegions?2:0); }
}

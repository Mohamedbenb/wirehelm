package com.nodecockpit.customization;

import android.content.Context;
import android.graphics.Rect;
import android.os.Handler;
import android.view.View;
import android.view.WindowManager;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.Executor;

/** Optional SystemUI region-sampling adapter kept isolated from the glass resolver. */
final class EdgeBackdropSampler {
    static ClassLoader systemUiLoader;
    interface Listener { void onBackdropLightChanged(boolean light); }
    private static final String[] HELPERS={
        "com.android.wm.shell.shared.handles.RegionSamplingHelper",
        "com.android.systemui.shared.navigationbar.RegionSamplingHelper",
        "com.android.systemui.navigationbar.gestural.RegionSamplingHelper",
        "com.android.systemui.statusbar.phone.RegionSamplingHelper"
    };
    private final Context context; private final Handler main; private final Executor background;
    private final View view; private final Listener listener;
    private final float topFraction,bottomFraction;
    private Object helper; private Method stop; private String source="unavailable",error=""; private boolean stopped; private int callbacks;
    private float luminance=Float.NaN; private Boolean lastLight;
    private MaterialTuning tuning=MaterialTuning.DEFAULT;
    private String role="edgeLegacy";
    private final long regionId=MaterialEnvironment.SHARED.register();
    private boolean deliveryQueued; private long lastDelivery;
    private RegionOverlay overlay;private java.util.function.Supplier<Rect> regionOverride;
    EdgeBackdropSampler region(java.util.function.Supplier<Rect> bounds){regionOverride=bounds;return this;}
    float rawLuminance(){return MaterialEnvironment.SHARED.rawLuminance(regionId);}
    private final Runnable deliver=this::deliverMeasurement;
    private void deliverMeasurement() {
        deliveryQueued=false; if(stopped) return; lastDelivery=android.os.SystemClock.uptimeMillis();
        MaterialEnvironment.Sample sample=MaterialEnvironment.SHARED.advance(regionId,lastDelivery,tuning);
        if(sample!=null&&!role.equals("edgeLegacy")) { luminance=sample.luminance; if(sample.mode!=0) lastLight=sample.mode>0; }
        listener.onBackdropLightChanged(Boolean.TRUE.equals(lastLight));
        if(!stopped&&sample!=null&&MaterialEnvironment.SHARED.needsAdvance(regionId)&&lastDelivery-sample.at<8000) { deliveryQueued=true;main.postDelayed(deliver,Math.max(16,tuning.get("publishIntervalMs"))); }
    }
    EdgeBackdropSampler laboratory(String role,MaterialTuning tuning) {
        boolean changed=!this.tuning.equals(tuning); this.role=role;this.tuning=tuning;
        if(changed&&helper!=null&&!stopped&&!deliveryQueued) { deliveryQueued=true;main.post(deliver); }
        return this;
    }
    float luminance() { return luminance; }

    EdgeBackdropSampler(Context context,Handler main,Executor background,View view,Listener listener) {
        this(context,main,background,view,0f,1f,listener);
    }
    EdgeBackdropSampler(Context context,Handler main,Executor background,View view,float topFraction,float bottomFraction,Listener listener) {
        this.context=context; this.main=main; this.background=background; this.view=view; this.listener=listener;
        this.topFraction=Math.max(0f,Math.min(1f,topFraction)); this.bottomFraction=Math.max(this.topFraction,Math.min(1f,bottomFraction));
    }
    boolean samples(View candidate) { return view==candidate; }
    void start() {
        if (stopped) return;
        if (!view.isAttachedToWindow()) return;
        for (String name:HELPERS) {
            try { if (create(name)) { source=name;
                if(tuning.enabled&&tuning.showRegions) { overlay=new RegionOverlay(); overlay.setBounds(0,0,view.getWidth(),view.getHeight()); view.getOverlay().add(overlay); }
                return; } }
            catch (Throwable failure) { if (error.isEmpty()) error=name+": "+failure; android.util.Log.w("NodeCockpit","Local sampling failed: "+name,failure); }
        }
    }
    private boolean create(String name) throws Exception {
        ClassLoader loader=systemUiLoader==null?context.getClassLoader():systemUiLoader;
        Class<?> type=Class.forName(name,false,loader);
        // Optimized SystemUI removes InnerClasses metadata while retaining the
        // callback type. Resolve its binary name instead of enumerating metadata.
        Class<?> callbackType=Class.forName(name+"$SamplingCallback",false,loader);
        if (callbackType==null || !callbackType.isInterface()) { error="SamplingCallback interface unavailable: "+name; return false; }
        Object callback=Proxy.newProxyInstance(loader,new Class<?>[]{callbackType},(proxy,method,args) -> {
            switch (method.getName()) {
                case "onRegionDarknessChanged":
                    if(stopped) return null;
                    callbacks++;
                    boolean light=!((Boolean)args[args.length-1]);
                    luminance=Float.NaN; // A failed median read must not reuse a prior filtered estimate as a new native measurement.
                    try { java.lang.reflect.Field field=type.getDeclaredField("mCurrentMedianLuma"); field.setAccessible(true); luminance=field.getFloat(helper);
                        if (view.getWidth()<=dp(20)) { float threshold=Boolean.TRUE.equals(lastLight)?.30f:.36f; light=luminance>=threshold; }
                    } catch (Throwable ignored) {}
                    try {
                    float measured=Float.isFinite(luminance)?luminance:(light?.82f:.18f);
                    Rect region=sampledRegion();
                    MaterialEnvironment.Sample material=MaterialEnvironment.SHARED.observe(regionId,role,measured,Float.isFinite(luminance)?"nativeMedianLuma":"nativeDarknessEstimate",Float.isFinite(luminance)?.94f:.65f,android.os.SystemClock.uptimeMillis(),region.left,region.top,region.right,region.bottom,tuning);
                    if(material!=null&&(tuning.enabled||!role.equals("edgeLegacy"))) { luminance=material.luminance; light=material.mode==0?(lastLight==null?light:lastLight):material.mode>0; }
                    } catch(Throwable unavailable) { error="Regional model unavailable: "+unavailable.getClass().getSimpleName(); }
                    lastLight=light;
                    if(!deliveryQueued) { deliveryQueued=true; long delay=tuning.enabled?Math.max(0,tuning.get("publishIntervalMs")-(android.os.SystemClock.uptimeMillis()-lastDelivery)):0; main.postDelayed(deliver,delay); }
                    if(overlay!=null) overlay.invalidateSelf(); return null;
                case "getSampledRegion": return sampledRegion();
                case "isSamplingEnabled": return true;
                case "toString": return "NodeCockpitEdgeSamplingCallback";
                case "hashCode": return System.identityHashCode(proxy);
                case "equals": return proxy==args[0];
                default: return null;
            }
        });
        Constructor<?> selected=null;
        for (Constructor<?> candidate:type.getDeclaredConstructors()) {
            Class<?>[] p=candidate.getParameterTypes();
            if (p.length>=2&&View.class.isAssignableFrom(p[0])&&p[1].isAssignableFrom(callbackType)&&p.length<=5
                && (selected==null||p.length<selected.getParameterCount())) selected=candidate;
        }
        if (selected==null) { error="Unsupported helper constructor: "+name; return false; }
        Class<?>[] p=selected.getParameterTypes(); Object[] args=new Object[p.length]; args[0]=view; args[1]=callback;
        for (int i=2;i<p.length;i++) {
            if (Executor.class.isAssignableFrom(p[i])) args[i]=p.length==3?background:(i==2?context.getMainExecutor():background);
            else {
                Constructor<?> factory=p[i].getDeclaredConstructor(); factory.setAccessible(true); args[i]=factory.newInstance();
            }
        }
        selected.setAccessible(true); helper=selected.newInstance(args);
        invokeOptional(type,"setWindowVisible",new Class<?>[]{boolean.class},new Object[]{true});
        invokeOptional(type,"setWindowHasBlurs",new Class<?>[]{boolean.class},new Object[]{false});
        // Pixel Android 17 exposes these directly; older helpers use setters.
        setOptionalFlag(type,"mWindowVisible",true);
        setOptionalFlag(type,"mWindowHasBlurs",false);
        Method start=type.getDeclaredMethod("start",Rect.class); start.setAccessible(true); start.invoke(helper,sampledRegion());
        try { stop=type.getDeclaredMethod("stopAndDestroy"); }
        catch (NoSuchMethodException ignored) { stop=type.getDeclaredMethod("stop"); }
        stop.setAccessible(true); return true;
    }
    private void invokeOptional(Class<?> type,String name,Class<?>[] types,Object[] args) {
        try { Method method=type.getDeclaredMethod(name,types); method.setAccessible(true); method.invoke(helper,args); } catch (Throwable ignored) {}
    }
    private void setOptionalFlag(Class<?> type,String name,boolean value) {
        try { java.lang.reflect.Field field=type.getDeclaredField(name); field.setAccessible(true); field.setBoolean(helper,value); } catch (Throwable ignored) {}
    }
    private Rect sampledRegion() {
        int[] location=new int[2]; view.getLocationOnScreen(location);
        Rect display=((WindowManager)context.getSystemService(Context.WINDOW_SERVICE)).getCurrentWindowMetrics().getBounds();
        int expansion=view.getWidth()<dp(64)?dp(24):0;
        int top=location[1]+Math.round(view.getHeight()*topFraction), bottom=location[1]+Math.round(view.getHeight()*bottomFraction);
        Rect region=new Rect(Math.max(display.left,location[0]-expansion),Math.max(display.top,top),Math.min(display.right,location[0]+view.getWidth()),Math.min(display.bottom,Math.max(top+1,bottom)));
        if(regionOverride!=null) { Rect supplied=regionOverride.get();if(supplied!=null&&!supplied.isEmpty())region.set(supplied); }
        if(tuning.enabled) { int[] bounds=tuning.crop(region.left,region.top,region.right,region.bottom,context.getResources().getDisplayMetrics().density,display.left,display.top,display.right,display.bottom);region.set(bounds[0],bounds[1],bounds[2],bounds[3]); }
        region.left=Math.max(display.left,Math.min(display.right-1,region.left));region.top=Math.max(display.top,Math.min(display.bottom-1,region.top));
        region.right=Math.max(region.left+1,Math.min(display.right,region.right));region.bottom=Math.max(region.top+1,Math.min(display.bottom,region.bottom));return region;
    }
    void stop() {
        stopped=true; main.removeCallbacks(deliver); deliveryQueued=false; MaterialEnvironment.SHARED.remove(regionId);
        if(overlay!=null) { view.getOverlay().remove(overlay); overlay=null; }
        Object target=helper; helper=null;
        if (target!=null&&stop!=null) try { stop.invoke(target); } catch (Throwable ignored) {}
        stop=null;
    }
    void refreshBounds() {
        if (helper==null||stopped) return;
        if(overlay!=null) { overlay.setBounds(0,0,view.getWidth(),view.getHeight()); overlay.invalidateSelf(); }
        try {
            java.lang.reflect.Field field=helper.getClass().getDeclaredField("mSamplingRequestBounds"); field.setAccessible(true);
            Rect bounds=(Rect)field.get(helper),next=sampledRegion();
            if (!next.equals(bounds)) { bounds.set(next); Method update=helper.getClass().getDeclaredMethod("updateSamplingListener"); update.setAccessible(true); update.invoke(helper); }
        } catch (Throwable ignored) {}
    }
    String diagnostics() {
        String state=""; if (helper!=null) for (String key:new String[]{"mSamplingEnabled","mSamplingListenerRegistered","mWindowVisible","mWindowHasBlurs","mSamplingRequestBounds","mRegisteredSamplingBounds"}) {
            try { java.lang.reflect.Field field=helper.getClass().getDeclaredField(key); field.setAccessible(true); state+=","+key+"="+field.get(helper); } catch (Throwable ignored) {}
        }
        return "source="+source+",callbacks="+callbacks+state+(error.isEmpty()?"":",error="+error);
    }
    private final class RegionOverlay extends android.graphics.drawable.Drawable {
        private final android.graphics.Paint paint=new android.graphics.Paint(3);
        @Override public void draw(android.graphics.Canvas canvas) {
            try {
            Rect region=sampledRegion(); int[] location=new int[2];view.getLocationOnScreen(location); region.offset(-location[0],-location[1]);
            paint.setStyle(android.graphics.Paint.Style.STROKE);paint.setStrokeWidth(dp(1));paint.setColor(0xc000bcd4);canvas.drawRect(region,paint);
            paint.setStyle(android.graphics.Paint.Style.FILL);paint.setTextSize(dp(10));canvas.drawText(role,Math.max(0,region.left)+dp(3),Math.max(dp(11),region.top+dp(12)),paint);
            } catch(Throwable ignored) { /* Diagnostics must never break native rendering. */ }
        }
        @Override public void setAlpha(int a) {} @Override public void setColorFilter(android.graphics.ColorFilter filter) {} @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }
    private int dp(int value) { return Math.round(value*context.getResources().getDisplayMetrics().density); }
}

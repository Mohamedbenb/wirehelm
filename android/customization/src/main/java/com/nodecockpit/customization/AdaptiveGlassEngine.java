package com.nodecockpit.customization;

import android.app.WallpaperColors;
import android.app.WallpaperManager;
import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.LinearGradient;
import android.graphics.Outline;
import android.graphics.Shader;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.WindowInsetsController;
import java.lang.reflect.Method;
import java.util.WeakHashMap;

/** Resolves glass appearance independently from SystemUI view/class names. */
final class AdaptiveGlassEngine {
    enum Mode { LIGHT, NEUTRAL, DARK }
    static final class Style {
        final Mode mode; final String source; final float confidence, luminance;
        final int tint, foreground, border, separator, blurRadius, transitionMs;
        final boolean automaticForeground;
        Style(Mode mode,String source,float confidence,float luminance,int tint,int foreground,
              int border,int separator,int blurRadius,int transitionMs) {
            this(mode,source,confidence,luminance,tint,foreground,border,separator,blurRadius,transitionMs,true);
        }
        Style(Mode mode,String source,float confidence,float luminance,int tint,int foreground,
              int border,int separator,int blurRadius,int transitionMs,boolean automaticForeground) {
            this.automaticForeground=automaticForeground;
            this.mode=mode; this.source=source; this.confidence=confidence; this.luminance=luminance;
            this.tint=tint; this.foreground=foreground; this.border=border;
            this.separator=separator; this.blurRadius=blurRadius; this.transitionMs=transitionMs;
        }
    }
    interface Listener { void onGlassAppearanceChanged(); }
    private static final long DEBOUNCE_MS=180;
    private final Context context; private final Handler main; private final Listener listener;
    private final WeakHashMap<View,BlurBinding> bindings=new WeakHashMap<>();
    private float wallpaperLuminance=Float.NaN; private Mode stableMode=Mode.NEUTRAL;
    private Boolean foregroundLight,localBackdropLight; private int foregroundSignalRevision,localSignalRevision;
    private int blurCreations,appearanceUpdates; private String lastSource="fallback";
    private final Runnable notifyAppearance;
    AdaptiveGlassEngine(Context context,Handler main,Listener listener) {
        this.context=context; this.main=main; this.listener=listener;
        notifyAppearance=() -> { appearanceUpdates++; this.listener.onGlassAppearanceChanged(); };
        refreshWallpaperSignal();
        try {
            WallpaperManager.getInstance(context).addOnColorsChangedListener((colors,which) -> {
                updateWallpaper(colors); main.removeCallbacks(notifyAppearance); main.postDelayed(notifyAppearance,DEBOUNCE_MS);
            },main);
        } catch (Throwable ignored) {}
    }
    private void refreshWallpaperSignal() {
        try { updateWallpaper(WallpaperManager.getInstance(context).getWallpaperColors(WallpaperManager.FLAG_SYSTEM)); }
        catch (Throwable ignored) {}
    }
    private void updateWallpaper(WallpaperColors colors) {
        if (colors==null || colors.getPrimaryColor()==null) return;
        int c=colors.getPrimaryColor().toArgb();
        wallpaperLuminance=(float)(0.2126*linear(Color.red(c)/255f)+0.7152*linear(Color.green(c)/255f)+0.0722*linear(Color.blue(c)/255f));
    }
    private static double linear(float c) { return c<=0.04045?c/12.92:Math.pow((c+0.055)/1.055,2.4); }
    Style resolve(int baselineOpacity,int baselineBlur,String preference,View signalView) {
        int appearance=systemBarAppearance(signalView);
        boolean hasLocalSignal=localBackdropLight!=null;
        boolean hasForegroundSignal=foregroundLight!=null;
        boolean hasContrastSignal=hasLocalSignal||hasForegroundSignal||appearance>=0;
        boolean lightBars=hasLocalSignal?localBackdropLight:hasForegroundSignal?foregroundLight:(appearance&WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS)!=0;
        float luminance=hasContrastSignal?(lightBars?0.82f:0.22f):wallpaperLuminance;
        String source=hasLocalSignal?"edgeRegion":hasForegroundSignal?"foregroundAppearance":hasContrastSignal?"systemUiContrast":"wallpaper";
        float confidence=hasLocalSignal?0.96f:hasForegroundSignal?0.9f:hasContrastSignal?0.68f:0.62f;
        if (Float.isNaN(luminance)) {
            boolean night=(context.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;
            luminance=night?0.18f:0.72f; source="uiModeFallback"; confidence=0.35f;
        }
        Mode environment=luminance<0.38f?Mode.DARK:luminance>0.62f?Mode.LIGHT:Mode.NEUTRAL;
        if (stableMode==Mode.DARK&&luminance<0.46f) environment=Mode.DARK;
        if (stableMode==Mode.LIGHT&&luminance>0.54f) environment=Mode.LIGHT;
        stableMode=environment; lastSource=source;
        // Auto blend follows the sampled background like the navigation handle;
        // Auto contrast preserves the original inverse treatment.
        boolean lightGlass="light".equals(preference)
            || ("auto".equals(preference)&&environment!=Mode.DARK)
            || ("contrast".equals(preference)&&environment!=Mode.LIGHT);
        int adjustment=lightGlass?-4:7;
        int resolvedOpacity=baselineOpacity==0?0:Math.max(0,Math.min(95,baselineOpacity+adjustment));
        int alpha=Math.round(255*resolvedOpacity/100f);
        int rgb=lightGlass?Color.rgb(242,247,251):Color.rgb(24,29,36);
        // With nearly transparent glass, content must contrast the real backdrop rather than the tint.
        int foreground=resolvedOpacity<32
            ?(environment==Mode.LIGHT?0xFF10161D:0xFFF8FAFD)
            :(lightGlass?0xFF10161D:0xFFF8FAFD);
        int border=environment==Mode.LIGHT?0x4818202A:environment==Mode.DARK?0x58FFFFFF:0x48FFFFFF;
        int separator=lightGlass?0x68101820:0x72FFFFFF;
        return new Style(environment,source,confidence,luminance,Color.argb(alpha,Color.red(rgb),Color.green(rgb),Color.blue(rgb)),
            foreground,border,separator,baselineBlur,160);
    }
    int signalToken(View signalView) {
        if (localBackdropLight!=null) return 0x10000000|localSignalRevision&0x0fffffff;
        if (foregroundLight!=null) return 0x20000000|foregroundSignalRevision&0x0fffffff;
        int appearance=systemBarAppearance(signalView);
        return appearance<0?0x40000000:appearance;
    }
    boolean setForegroundLight(Boolean light) {
        if (light==foregroundLight || light!=null&&light.equals(foregroundLight)) return false;
        foregroundLight=light; foregroundSignalRevision++; return true;
    }
    boolean setLocalBackdropLight(Boolean light) {
        if (light==localBackdropLight || light!=null&&light.equals(localBackdropLight)) return false;
        localBackdropLight=light; localSignalRevision++; return true;
    }
    private int systemBarAppearance(View signalView) {
        if (Build.VERSION.SDK_INT<30 || signalView==null || !signalView.isAttachedToWindow()) return -1;
        try {
            WindowInsetsController controller=signalView.getWindowInsetsController();
            return controller==null?-1:controller.getSystemBarsAppearance();
        } catch (Throwable ignored) { return -1; }
    }
    /** Adapter API: native surfaces retain ownership of bounds, clipping and input. */
    Drawable surfaceDrawable(View view,Style style,float radius) {
        BlurBinding binding=bindings.get(view);
        if (binding==null) { binding=createBinding(view); if (binding!=null) bindings.put(view,binding); }
        if (binding==null) return fallback(style,radius);
        binding.update(style.blurRadius,radius,style.tint,style.transitionMs);
        return binding.drawable;
    }
    void releaseSurface(View view) {
        if(view!=null&&view.getForeground() instanceof EdgeOutlineDrawable)((EdgeOutlineDrawable)view.getForeground()).cancel();
        BlurBinding binding=bindings.remove(view);
        if(binding!=null){
            if(binding.tintAnimator!=null)binding.tintAnimator.cancel();
            // Removing the Java reference does not deactivate compositor blur.
            try{binding.radius.invoke(binding.drawable,0);binding.color.invoke(binding.drawable,0);}catch(Throwable ignored){}
            binding.drawable.setAlpha(0);binding.drawable.setBounds(0,0,0,0);binding.drawable.setVisible(false,false);view.invalidate();
        }
    }
    void apply(View view,Style style,float radius,boolean border) {
        BlurBinding binding=bindings.get(view);
        if (binding==null) { binding=createBinding(view); if (binding!=null) bindings.put(view,binding); }
        if (binding!=null) {
            binding.update(style.blurRadius,radius,style.tint,style.transitionMs);
            view.setBackground(binding.drawable);
        } else view.setBackground(fallback(style,radius));
        configureClip(view,radius);
        GradientDrawable outline=new GradientDrawable(); outline.setColor(Color.TRANSPARENT); outline.setCornerRadius(radius);
        if (border) outline.setStroke(Math.max(2,dp(1)),style.border); view.setForeground(outline);
    }
    void applyEdge(View view,Style style,float radius,boolean screenEdgeRight) {
        applyEdge(view,style,radius,screenEdgeRight,style.border,style.border);
    }
    void applyEdge(View view,Style style,float radius,boolean screenEdgeRight,int startBorder,int endBorder) {
        BlurBinding binding=bindings.get(view);
        if(binding==null){binding=createBinding(view);if(binding!=null)bindings.put(view,binding);}
        if(binding!=null){binding.update(style.blurRadius,radius,style.tint,style.transitionMs);if(view.getBackground()!=binding.drawable)view.setBackground(binding.drawable);}
        else setFlatBackground(view,style,radius);
        edgeOutline(view,radius,screenEdgeRight,startBorder,endBorder,true,binding);
    }
    void applyFlatEdge(View view,Style style,float radius,boolean screenEdgeRight){
        if(bindings.containsKey(view))releaseSurface(view);
        setFlatBackground(view,style,radius);
        edgeOutline(view,radius,screenEdgeRight,style.border,style.border,false,null);
    }
    private void setFlatBackground(View view,Style style,float radius){
        Drawable old=view.getBackground();FlatEdgeDrawable d=old instanceof FlatEdgeDrawable?(FlatEdgeDrawable)old:new FlatEdgeDrawable();d.update(style.tint,radius);if(old!=d)view.setBackground(d);
    }
    private void edgeOutline(View view,float radius,boolean edgeRight,int start,int end,boolean animate,BlurBinding binding){
        Drawable previous=view.getForeground();boolean narrow=view.getWidth()<=dp(20);
        EdgeOutlineDrawable outline=previous instanceof EdgeOutlineDrawable?(EdgeOutlineDrawable)previous:null;
        boolean shape=outline!=null&&outline.radius==radius&&outline.screenEdgeRight==edgeRight&&outline.narrow==narrow;
        if(!shape){if(outline!=null)outline.cancel();outline=new EdgeOutlineDrawable(start,end,radius,Math.max(2,dp(1)),edgeRight);outline.narrow=narrow;view.setForeground(outline);
            if(narrow){view.setOutlineProvider(new ViewOutlineProvider(){public void getOutline(View target,Outline o){o.setRoundRect(edgeRight?0:-(int)radius,0,target.getWidth()+(edgeRight?(int)radius:0),target.getHeight(),radius);}});view.setClipToOutline(true);
                if(binding!=null)try{Method corners=binding.drawable.getClass().getMethod("setCornerRadius",float.class,float.class,float.class,float.class);corners.invoke(binding.drawable,edgeRight?radius:0f,edgeRight?0f:radius,edgeRight?radius:0f,edgeRight?0f:radius);}catch(Throwable ignored){}
            }else configureClip(view,radius);
        }
        outline.colors(start,end,animate);
    }
    private static final class FlatEdgeDrawable extends GradientDrawable {
        private int tint=Integer.MIN_VALUE;private float radius=-1;
        void update(int c,float r){if(c!=tint){tint=c;int a=Color.alpha(c);setColors(new int[]{Color.argb(Math.min(255,a+18),Color.red(c),Color.green(c),Color.blue(c)),c});}if(radius!=r){radius=r;setCornerRadius(r);}}
    }
    void applyHandle(View view,Style style,float radius) { applyEdge(view,style,radius,true); }
    private void configureClip(View view,float radius) {
        view.setOutlineProvider(new ViewOutlineProvider() { @Override public void getOutline(View target,Outline outline) {
            outline.setRoundRect(0,0,target.getWidth(),target.getHeight(),radius);
        }});
        view.setClipToOutline(true);
    }
    private BlurBinding createBinding(View view) {
        if (Build.VERSION.SDK_INT<31 || !view.isAttachedToWindow()) return null;
        try {
            Method rootMethod=View.class.getDeclaredMethod("getViewRootImpl"); rootMethod.setAccessible(true);
            Object root=rootMethod.invoke(view); if (root==null) return null;
            Object drawable=root.getClass().getMethod("createBackgroundBlurDrawable").invoke(root);
            blurCreations++;
            return new BlurBinding((Drawable)drawable,drawable.getClass().getMethod("setBlurRadius",int.class),
                drawable.getClass().getMethod("setCornerRadius",float.class),drawable.getClass().getMethod("setColor",int.class));
        } catch (Throwable e) { return null; }
    }
    private GradientDrawable fallback(Style style,float radius) {
        int base=style.tint, a=Color.alpha(base);
        GradientDrawable d=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{
            Color.argb(Math.min(255,a+18),Color.red(base),Color.green(base),Color.blue(base)),base});
        d.setCornerRadius(radius); return d;
    }
    int blurCreations() { return blurCreations; }
    int appearanceUpdates() { return appearanceUpdates; }
    String lastSource() { return lastSource; }
    private int dp(int value) { return Math.round(value*context.getResources().getDisplayMetrics().density); }
    /** Rounded outline with the screen-edge side intentionally omitted. */
    private static final class EdgeOutlineDrawable extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG); private final Path path=new Path(); private final float radius;
        private int startColor,endColor,targetStart,targetEnd;private boolean narrow;private ValueAnimator animator;private final boolean screenEdgeRight;
        EdgeOutlineDrawable(int startColor,int endColor,float radius,float width,boolean screenEdgeRight) {
            this.radius=radius; this.startColor=this.targetStart=startColor; this.endColor=this.targetEnd=endColor; this.screenEdgeRight=screenEdgeRight; paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(width);
        }
        void cancel(){if(animator!=null){animator.cancel();animator=null;}}
        void colors(int start,int end,boolean animate){if(!animate){cancel();targetStart=start;targetEnd=end;if(startColor!=start||endColor!=end){startColor=start;endColor=end;invalidateSelf();}return;}if(targetStart==start&&targetEnd==end)return;targetStart=start;targetEnd=end;cancel();
            if(!animate||!ValueAnimator.areAnimatorsEnabled()||startColor==start&&endColor==end){startColor=start;endColor=end;invalidateSelf();return;}
            final int fromStart=startColor,fromEnd=endColor;final android.animation.ArgbEvaluator evaluator=new android.animation.ArgbEvaluator();ValueAnimator next=ValueAnimator.ofFloat(0,1);animator=next;next.setDuration(280);next.addUpdateListener(a->{float t=(Float)a.getAnimatedValue();startColor=(Integer)evaluator.evaluate(t,fromStart,start);endColor=(Integer)evaluator.evaluate(t,fromEnd,end);invalidateSelf();});next.addListener(new android.animation.AnimatorListenerAdapter(){public void onAnimationEnd(android.animation.Animator a){if(animator==a)animator=null;}});next.start();
        }
        @Override public void draw(Canvas canvas) {
            android.graphics.Rect b=getBounds(); float inset=paint.getStrokeWidth()/2f;
            float left=b.left+inset,top=b.top+inset,bottom=b.bottom-inset,right=b.right;
            paint.setShader(new LinearGradient(left,top,left,bottom,new int[]{startColor,endColor},null,Shader.TileMode.CLAMP));
            float r=Math.max(0f,Math.min(radius-inset,Math.min((bottom-top)/2f,(right-left)/2f))); path.reset();
            if (screenEdgeRight) {
                path.moveTo(right,top); path.lineTo(left+r,top); path.arcTo(left,top,left+2*r,top+2*r,270,-90,false);
                path.lineTo(left,bottom-r); path.arcTo(left,bottom-2*r,left+2*r,bottom,180,-90,false); path.lineTo(right,bottom);
            } else {
                path.moveTo(left,top); path.lineTo(right-r,top); path.arcTo(right-2*r,top,right,top+2*r,270,90,false);
                path.lineTo(right,bottom-r); path.arcTo(right-2*r,bottom-2*r,right,bottom,0,90,false); path.lineTo(left,bottom);
            }
            // Broad translucent inner strokes fade toward the glass. The outer
            // hairline retains local contrast without a diagonal alpha ramp.
            float width=paint.getStrokeWidth();
            for (int layer=4;layer>=1;layer--) { paint.setStrokeWidth(width*(layer+1)); paint.setAlpha(Math.max(1,32/layer)); canvas.drawPath(path,paint); }
            paint.setStrokeWidth(width); paint.setAlpha(255); canvas.drawPath(path,paint);
        }
        @Override public void setAlpha(int alpha) { paint.setAlpha(alpha); invalidateSelf(); }
        @Override public void setColorFilter(android.graphics.ColorFilter filter) { paint.setColorFilter(filter); invalidateSelf(); }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }
    private final class BlurBinding {
        final Drawable drawable; final Method radius,corners,color; int lastTint=Integer.MIN_VALUE,displayedTint,lastBlur=Integer.MIN_VALUE;float lastCorner=Float.NaN; ValueAnimator tintAnimator;
        BlurBinding(Drawable drawable,Method radius,Method corners,Method color) { this.drawable=drawable; this.radius=radius; this.corners=corners; this.color=color; }
        void update(int blur,float corner,int tint,int duration) {
            try {
                if(lastBlur!=blur){radius.invoke(drawable,dp(blur));lastBlur=blur;}if(lastCorner!=corner){corners.invoke(drawable,corner);lastCorner=corner;}
                if (lastTint==Integer.MIN_VALUE || duration<=0) { if(tintAnimator!=null){tintAnimator.cancel();tintAnimator=null;}color.invoke(drawable,tint); lastTint=tint; displayedTint=tint; return; }
                if (lastTint==tint) return;
                if (tintAnimator!=null) tintAnimator.cancel();
                tintAnimator=ValueAnimator.ofArgb(displayedTint,tint); tintAnimator.setDuration(duration);
                tintAnimator.addUpdateListener(a -> { try { displayedTint=(Integer)a.getAnimatedValue(); color.invoke(drawable,displayedTint); } catch (Throwable ignored) {} });
                tintAnimator.start(); lastTint=tint;
            }
            catch (Throwable ignored) {}
        }
    }
}

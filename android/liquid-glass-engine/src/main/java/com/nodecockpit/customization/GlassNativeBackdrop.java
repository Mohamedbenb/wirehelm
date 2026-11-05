package com.nodecockpit.customization;

import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import android.view.View;
import android.view.WindowManager;
import java.lang.reflect.Method;

/**
 * Experimental component-local framework blur. The framework drawable's RenderNode tracks motion.
 * This is native backdrop blur/tint, not a refraction shader or an owned-content RenderEffect.
 * Non-SDK API restrictions are respected: unsupported hosts receive an explicit unavailable result.
 */
@androidx.annotation.RequiresApi(31)
public final class GlassNativeBackdrop implements AutoCloseable {
    public static final class Attempt {
        public final GlassNativeBackdrop session;
        public final String unavailable;
        private Attempt(GlassNativeBackdrop session,String unavailable){this.session=session;this.unavailable=unavailable;}
    }
    private final View owner;
    private final Drawable drawable;
    private final GlassNativeBlurLease lease;
    private final WindowManager windowManager;
    private final java.util.function.Consumer<Boolean> blurChanges;
    private boolean allowed=true,requestedVisible=true,availabilityRegistered;
    private final View.OnAttachStateChangeListener attachment=new View.OnAttachStateChangeListener(){
        public void onViewAttachedToWindow(View v){}
        public void onViewDetachedFromWindow(View v){close();}
    };

    public static Attempt tryCreate(View owner) {
        if(Looper.myLooper()!=Looper.getMainLooper())return new Attempt(null,"UI thread required");
        if(owner==null || !owner.isAttachedToWindow())return new Attempt(null,"Attach the native owner first");
        try {
            WindowManager wm=owner.getContext().getSystemService(WindowManager.class);
            if(wm==null || !wm.isCrossWindowBlurEnabled())return new Attempt(null,"System cross-window blur is disabled");
            Method getter=View.class.getDeclaredMethod("getViewRootImpl");getter.setAccessible(true);
            Object root=getter.invoke(owner);
            if(root==null)return new Attempt(null,"Native window root unavailable");
            Object value=root.getClass().getMethod("createBackgroundBlurDrawable").invoke(root);
            if(!(value instanceof Drawable))return new Attempt(null,"Framework blur drawable unavailable");
            Drawable drawable=(Drawable)value;
            // Resolve all operations before publishing the session. No silent shader substitution.
            try{return new Attempt(new GlassNativeBackdrop(owner,drawable,wm),"");}
            catch(Exception unavailable){drawable.setVisible(false,false);throw unavailable;}
        } catch(Exception unavailable){return new Attempt(null,unavailable.getClass().getSimpleName()+": native drawable access unavailable");}
    }

    private GlassNativeBackdrop(View owner,Drawable drawable,WindowManager wm)throws Exception {
        this.owner=owner;this.drawable=drawable;
        windowManager=wm;
        Class<?> type=drawable.getClass();
        Method blur=type.getMethod("setBlurRadius",int.class),corners=type.getMethod("setCornerRadius",float.class,float.class,float.class,float.class),color=type.getMethod("setColor",int.class);
        lease=new GlassNativeBlurLease(new GlassNativeBlurLease.Backend(){
            public void configure(GlassNativeBlurRegion r)throws Exception{
                drawable.setBounds(0,0,r.width,r.height);
                // Framework overload orders the bottom corners BL, BR.
                corners.invoke(drawable,r.tl,r.tr,r.bl,r.br);
                color.invoke(drawable,r.tint);blur.invoke(drawable,r.blur);
            }
            public void visible(boolean visible){drawable.setVisible(visible,false);}
            public void release()throws Exception{blur.invoke(drawable,0);drawable.setCallback(null);}
        });
        blurChanges=enabled->{
            if(lease.closed())return;
            allowed=Boolean.TRUE.equals(enabled);lease.visible(allowed&&requestedVisible);owner.invalidate();
        };
        drawable.setVisible(false,false);
        windowManager.addCrossWindowBlurEnabledListener(owner.getContext().getMainExecutor(),blurChanges);
        availabilityRegistered=true;
        owner.addOnAttachStateChangeListener(attachment);
    }

    /** Call inside the component's own hardware draw, before its native foreground. */
    public boolean draw(Canvas canvas,GlassNativeBlurRegion region){
        return draw(canvas,region,1);
    }
    /** Native primitive opacity; callers still own transforms and clipping. */
    public boolean draw(Canvas canvas,GlassNativeBlurRegion region,float opacity){
        if(Looper.myLooper()!=Looper.getMainLooper())return false;
        if(!allowed||!Float.isFinite(opacity)||opacity<0||opacity>1)return false;
        drawable.setAlpha(Math.round(opacity*255));
        boolean recorded=lease.draw(region,owner.isAttachedToWindow(),canvas.isHardwareAccelerated(),()->drawable.draw(canvas));
        if(lease.closed())close();
        return recorded;
    }
    /** Apply local layout/style changes before the window's pre-draw where possible. */
    public boolean prepare(GlassNativeBlurRegion region){
        if(Looper.myLooper()!=Looper.getMainLooper() || !owner.isAttachedToWindow())return false;
        boolean prepared=lease.prepare(region);if(lease.closed())close();return prepared;
    }
    public void setVisible(boolean visible){if(Looper.myLooper()!=Looper.getMainLooper())throw new IllegalStateException("UI thread required");requestedVisible=visible;lease.visible(visible&&allowed);owner.invalidate();}
    public String diagnostics(){return lease.closed()?"Unavailable: "+lease.failure():!allowed?"System cross-window blur disabled":"Native RenderNode blur; presentation unverified";}
    public void close(){
        if(Looper.myLooper()!=Looper.getMainLooper())throw new IllegalStateException("UI thread required");
        if(availabilityRegistered){availabilityRegistered=false;windowManager.removeCrossWindowBlurEnabledListener(blurChanges);}
        lease.close();owner.removeOnAttachStateChangeListener(attachment);owner.invalidate();
    }
}

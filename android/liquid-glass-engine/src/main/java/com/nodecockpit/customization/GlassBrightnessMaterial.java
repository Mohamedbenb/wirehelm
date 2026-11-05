package com.nodecockpit.customization;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;

/**
 * Reusable component-local native brightness material. Host owns input, layout,
 * draw order, transforms and lifecycle. UI-thread only; false means retain stock.
 * No sampled screen bounds, separate surface, shader or implicit blur fallback.
 */
@androidx.annotation.RequiresApi(31)
public final class GlassBrightnessMaterial implements AutoCloseable {
    public enum Role { CONTAINER, TRACK, INDICATOR }
    public static final int MAX_SLOTS=4;
    interface Backend extends AutoCloseable {
        boolean draw(Canvas canvas,GlassBrightnessGeometry.Shape shape,GlassNativeBlurRegion region,float opacity,Role role);
        void visible(boolean value);
        String diagnostics();
        void close();
    }
    interface Factory { Backend create() throws Exception; }
    private final Factory factory;
    private final View nativeOwner;
    private final Backend[] slots=new Backend[MAX_SLOTS];
    private final boolean[] attempted=new boolean[MAX_SLOTS];
    private final float progressBlur,indicatorBlur;
    private boolean closed,visible=true;
    private int created,draws,fallbacks;
    private String failure="";

    /** New owner/configuration starts a new bounded session; no retry in a failed draw loop. */
    public GlassBrightnessMaterial(View owner,float progressBlur,float indicatorBlur){
        this(owner,()->{
            GlassNativeBackdrop.Attempt attempt=GlassNativeBackdrop.tryCreate(owner);
            if(attempt.session==null)throw new IllegalStateException(attempt.unavailable);
            return new NativeBackend(attempt.session);
        },progressBlur,indicatorBlur);
    }
    GlassBrightnessMaterial(Factory factory,float progressBlur,float indicatorBlur){this(null,factory,progressBlur,indicatorBlur);}
    private GlassBrightnessMaterial(View owner,Factory factory,float progressBlur,float indicatorBlur){
        if(factory==null||!Float.isFinite(progressBlur)||!Float.isFinite(indicatorBlur))throw new IllegalArgumentException("Finite native blur radii required");
        this.nativeOwner=owner;this.factory=factory;
        this.progressBlur=Math.max(0,Math.min(150,progressBlur));this.indicatorBlur=Math.max(0,Math.min(150,indicatorBlur));
    }
    static GlassNativeBlurRegion region(Role role,GlassBrightnessGeometry.Shape shape,float progressBlur,float indicatorBlur){
        float blur=role==Role.CONTAINER?18:role==Role.INDICATOR?indicatorBlur:shape.x<=1?progressBlur:0;
        int tint=role==Role.INDICATOR?0x38ffffff:role==Role.CONTAINER?0x10ffffff:0x18ffffff;
        return new GlassNativeBlurRegion((int)Math.ceil(shape.w),(int)Math.ceil(shape.h),blur,shape.tl,shape.tr,shape.br,shape.bl,tint);
    }
    /** Slot is the native draw ordinal for this owner (0..3), not a global renderer index. */
    public boolean draw(Canvas canvas,int slot,Role role,GlassBrightnessGeometry.Shape shape,float opacity){
        if(closed||!visible||slot<0||slot>=MAX_SLOTS||role==null||shape==null||!Float.isFinite(opacity)||opacity<0||opacity>1){fallbacks++;return false;}
        if(nativeOwner!=null&&(canvas==null||!canvas.isHardwareAccelerated())){fallbacks++;return false;}
        if(!attempted[slot]){
            attempted[slot]=true;
            try{slots[slot]=factory.create();if(slots[slot]!=null)created++;else failure="Native backend unavailable";}
            catch(Exception unavailable){failure=unavailable.getClass().getSimpleName()+": "+unavailable.getMessage();}
        }
        Backend backend=slots[slot];
        if(backend==null){fallbacks++;return false;}
        if(!backend.draw(canvas,shape,region(role,shape,progressBlur,indicatorBlur),opacity,role)){
            failure=backend.diagnostics();fallbacks++;return false;
        }
        draws++;return true;
    }
    public void setVisible(boolean value){
        if(closed||visible==value)return;visible=value;
        for(Backend backend:slots)if(backend!=null)backend.visible(value);
    }
    public int createdSessions(){return created;}
    public String diagnostics(){return "native brightness: draws="+draws+",sessions="+created+",fallback="+fallbacks+",closed="+closed+",reason="+failure;}
    public void close(){if(closed)return;closed=true;for(int i=0;i<slots.length;i++){if(slots[i]!=null)slots[i].close();slots[i]=null;}}

    private static final class NativeBackend implements Backend {
        private final GlassNativeBackdrop session;
        private final Paint edge=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path border=new Path();
        private final RectF bounds=new RectF();
        private final float[] radii=new float[8];
        NativeBackend(GlassNativeBackdrop session){this.session=session;}
        public boolean draw(Canvas canvas,GlassBrightnessGeometry.Shape shape,GlassNativeBlurRegion region,float opacity,Role role){
            int save=canvas.save();
            try{
                canvas.translate(shape.x,shape.y);canvas.scale(shape.w/region.width,shape.h/region.height);
                if(!session.draw(canvas,region,opacity))return false;
                bounds.set(.6f,.6f,region.width-.6f,region.height-.6f);
                radii[0]=radii[1]=shape.tl;radii[2]=radii[3]=shape.tr;radii[4]=radii[5]=shape.br;radii[6]=radii[7]=shape.bl;
                border.reset();border.addRoundRect(bounds,radii,Path.Direction.CW);
                edge.setStyle(Paint.Style.STROKE);edge.setStrokeWidth(1.2f);
                edge.setColor(role==Role.INDICATOR?0xeeffffff:0x99ffffff);
                edge.setAlpha(Math.round(edge.getAlpha()*opacity));canvas.drawPath(border,edge);return true;
            }finally{canvas.restoreToCount(save);}
        }
        public void visible(boolean value){session.setVisible(value);}
        public String diagnostics(){return session.diagnostics();}
        public void close(){session.close();}
    }
}

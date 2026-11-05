package com.nodecockpit.customization;

/** Host-independent local primitive geometry. No native component or screen coordinates. */
public final class GlassBrightnessGeometry {
    private GlassBrightnessGeometry() {}
    public static final class Shape {
        public final float x,y,w,h,tl,tr,br,bl;
        private Shape(float x,float y,float w,float h,float tl,float tr,float br,float bl){
            this.x=x;this.y=y;this.w=w;this.h=h;this.tl=tl;this.tr=tr;this.br=br;this.bl=bl;
        }
    }
    /** Outer/start corners followed by inner/end corners; coordinates remain component-local. */
    public static Shape track(float x,float y,float w,float h,float outer,float inner,boolean vertical){
        if(!Float.isFinite(x)||!Float.isFinite(y)||!Float.isFinite(w)||!Float.isFinite(h)
            ||Math.abs(x)>8192||Math.abs(y)>8192||w<.5f||h<.5f||w>4096||h>4096
            ||!Float.isFinite(outer)||!Float.isFinite(inner)||outer<0||inner<0)return null;
        float limit=Math.min(w,h)/2;
        outer=Math.min(limit,outer);inner=Math.min(limit,inner);
        return vertical?new Shape(x,y,w,h,outer,outer,inner,inner):new Shape(x,y,w,h,outer,inner,inner,outer);
    }
}

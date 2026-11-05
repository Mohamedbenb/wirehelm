package com.nodecockpit.customization;

/** Component-local native blur bounds. Corner order is TL, TR, BR, BL. */
public final class GlassNativeBlurRegion {
    public final int width, height, blur;
    public final float tl, tr, br, bl;
    public final int tint;

    public GlassNativeBlurRegion(int width,int height,float blur,float tl,float tr,float br,float bl,int tint) {
        if(width<1 || height<1 || width>4096 || height>4096 || !Float.isFinite(blur)
            || !Float.isFinite(tl) || !Float.isFinite(tr) || !Float.isFinite(br) || !Float.isFinite(bl))
            throw new IllegalArgumentException("Finite, bounded local blur geometry required");
        this.width=width;this.height=height;this.blur=Math.round(Math.max(0,Math.min(150,blur)));
        float limit=Math.min(width,height)/2f;
        this.tl=Math.max(0,Math.min(limit,tl));this.tr=Math.max(0,Math.min(limit,tr));
        this.br=Math.max(0,Math.min(limit,br));this.bl=Math.max(0,Math.min(limit,bl));this.tint=tint;
    }
    boolean same(GlassNativeBlurRegion other){return other!=null && width==other.width && height==other.height
        && blur==other.blur && tint==other.tint && tl==other.tl && tr==other.tr && br==other.br && bl==other.bl;}
}

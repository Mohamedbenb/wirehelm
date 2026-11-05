package com.nodecockpit.customization;

/** Pure slider geometry shared by preview and native hosts. No value or input ownership. */
public final class GlassSliderGeometry {
    private GlassSliderGeometry() {}

    public static float fraction(float value) {
        return Float.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
    }

    /** Filled rectangle: square cutoff, with outer corners supplied by the parent material. */
    public static float[] fill(float left, float top, float width, float height,
                               float progress, boolean vertical, boolean rtl) {
        float p = fraction(progress);
        return vertical ? new float[]{left, top + height * (1-p), width, height*p}
            : new float[]{rtl ? left + width*(1-p) : left, top, width*p, height};
    }

    /** The existing 12-float mask ABI. Clip is in the same coordinates as the shape. */
    public static float[] mask(float left, float top, float width, float height,
                               float progress, float radius, float blur, float mode,
                               float clipLeft, float clipTop, float clipRight, float clipBottom) {
        float[] result = {left+width/2, top+height/2, width/2, height/2, fraction(progress),
            Math.max(0, Math.min(radius, Math.min(width,height)/2)), Math.max(0,blur), mode,
            clipLeft, clipTop, clipRight, clipBottom};
        for (float v : result) if (!Float.isFinite(v)) throw new IllegalArgumentException("Finite slider geometry required");
        if (width <= 0 || height <= 0 || clipRight <= clipLeft || clipBottom <= clipTop)
            throw new IllegalArgumentException("Visible slider geometry required");
        return result;
    }
}

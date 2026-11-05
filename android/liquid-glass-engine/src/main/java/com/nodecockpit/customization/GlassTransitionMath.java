package com.nodecockpit.customization;

/** Deterministic transition math, independent of Android and frame rate. */
final class GlassTransitionMath {
    static float amount(float elapsedMs,float timeConstantMs) { return 1f-(float)Math.exp(-Math.max(0f,elapsedMs)/timeConstantMs); }
    static float approach(float current,float target,float amount) { return current+(target-current)*amount; }
    static float tone(float luminance) { float t=Math.max(0f,Math.min(1f,(luminance-.18f)/.64f)); return t*t*(3f-2f*t); }
    static int mix(int from,int to,float amount) {
        float t=Math.max(0f,Math.min(1f,amount)); int out=0;
        for(int shift=0;shift<=24;shift+=8) out|=Math.round(((from>>>shift)&255)*(1f-t)+((to>>>shift)&255)*t)<<shift;
        return out;
    }
    static boolean close(int a,int b) { for(int s=0;s<=24;s+=8) if(Math.abs(((a>>>s)&255)-((b>>>s)&255))>2) return false; return true; }
}

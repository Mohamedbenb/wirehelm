package com.nodecockpit.customization;

/** Smooth rise/fall in component uptime. No frame loop or Android dependencies. */
final class CameraRingPulse {
    static float level(long elapsedMs,int durationMs){
        if(durationMs<=0||elapsedMs<0)return 0;
        long phase=elapsedMs%(2L*durationMs);
        float t=phase<=durationMs?phase/(float)durationMs:(2L*durationMs-phase)/(float)durationMs;
        return t*t*(3-2*t);
    }
    static int alpha(long elapsedMs,int durationMs,int intensity){
        int maximum=Math.round(255*Math.max(0,Math.min(100,intensity))/100f);
        return Math.round(maximum*level(elapsedMs,durationMs));
    }
    static long delay(long elapsedMs,int durationMs){
        if(durationMs<=0)return 100;
        long cadence=Math.max(100,(durationMs+31L)/32L);
        long boundary=durationMs-Math.max(0,elapsedMs)%durationMs;
        return Math.max(1,Math.min(cadence,boundary));
    }
}

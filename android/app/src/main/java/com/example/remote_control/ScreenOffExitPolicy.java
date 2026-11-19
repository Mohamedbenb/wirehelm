package com.example.remote_control;
/** Elapsed-time policy only; no package/UID kill or SystemUI dependency. */
public final class ScreenOffExitPolicy {
    public static final long DELAY_MS=30000;
    private long offAt=-1;
    public void screenOff(long now){if(offAt<0)offAt=now;}
    public void screenOn(){offAt=-1;}
    public long remaining(long now){return offAt<0?-1:Math.max(0,DELAY_MS-Math.max(0,now-offAt));}
    public boolean shouldExit(long now,boolean interactive,boolean requiredWork){return !interactive&&offAt>=0&&remaining(now)==0&&!requiredWork;}
}

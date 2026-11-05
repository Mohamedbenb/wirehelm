package com.nodecockpit.customization;

/** Two distinct acceleration peaks during a bounded Undo lease. No Android dependencies. */
final class NotificationUndoShake {
    private static final long WARMUP=250_000_000L,MIN_GAP=120_000_000L,MAX_GAP=900_000_000L;
    private final long start,deadline;
    private final double threshold;
    private long last=Long.MIN_VALUE,first=Long.MIN_VALUE;
    private boolean released=true,triggered;
    NotificationUndoShake(long start,long deadline,int sensitivity){
        this.start=start;this.deadline=deadline;
        threshold=sensitivity==0?.65:sensitivity==2?1.3:.95;
    }
    boolean sample(long now,float x,float y,float z){
        if(triggered||now<=last||now<start||now>=deadline)return false;
        last=now;
        if(now-start<WARMUP)return false;
        double force=Math.abs(Math.sqrt((double)x*x+(double)y*y+(double)z*z)/9.80665-1);
        if(!Double.isFinite(force))return false;
        if(force<threshold*.4){released=true;return false;}
        if(force<threshold||!released)return false;
        released=false;
        if(first==Long.MIN_VALUE||now-first>MAX_GAP){first=now;return false;}
        if(now-first<MIN_GAP)return false;
        triggered=true;return true;
    }
}

package com.nodecockpit.customization;

/** Seven native observations plus a short persistence window; interpolation is not an observation. */
final class BackdropStability {
    private final float[] values=new float[7],sorted=new float[7];
    private final long[] times=new long[7];
    private int size,cursor; private float accepted=Float.NaN,candidate=Float.NaN; private long since,lastAdvance;private int window=160;
    static boolean applies(String role){return role.equals("fingerprint")||role.equals("sectionInk")||role.equals("notifications")||role.equals("lockNotifications")||role.equals("shadeSummary")||role.equals("lockSummary")||role.equals("cardContext")||role.equals("qsTile")||role.equals("qsContext")||role.equals("quickSettings")||role.equals("drawerHeader");}
    private static int hold(MaterialTuning tuning){return tuning.enabled?Math.round(tuning.get("backgroundHoldMs")*(tuning.dynamicText?.5f:1f)):120;}
    float observe(float value,long now,MaterialTuning tuning){
        values[cursor]=value;times[cursor]=now;cursor=(cursor+1)%values.length;size=Math.min(size+1,values.length);
        return advance(now,tuning);
    }
    float advance(long now,MaterialTuning tuning){
        lastAdvance=now;window=tuning.enabled?tuning.get("medianWindowMs"):160;
        int n=0;for(int i=0;i<size;i++)if(now-times[i]<=window)sorted[n++]=values[i];
        java.util.Arrays.sort(sorted,0,n);
        float median=n==0?values[(cursor+values.length-1)%values.length]:n%2==0?(sorted[n/2-1]+sorted[n/2])*.5f:sorted[n/2];
        if(!Float.isFinite(accepted)){accepted=median;return accepted;}
        float band=tuning.enabled?.012f+tuning.get("contrastHysteresis")/1000f:.027f;
        if(Math.abs(median-accepted)<band){candidate=Float.NaN;return accepted;}
        if(!Float.isFinite(candidate)||(median-accepted)*(candidate-accepted)<=0)since=now;
        candidate=median;
        if(now-since>=hold(tuning)){accepted=candidate;candidate=Float.NaN;}
        return accepted;
    }
    boolean pending(){int last=(cursor+values.length-1)%values.length;return Float.isFinite(candidate)||size>0&&lastAdvance-times[last]<=window&&Math.abs(accepted-values[last])>.012f;}
}

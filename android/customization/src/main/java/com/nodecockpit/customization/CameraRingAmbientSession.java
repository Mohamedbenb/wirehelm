package com.nodecockpit.customization;

/** Identity-scoped ownership for native ambient sessions. No Android API. */
final class CameraRingAmbientSession {
    static final long DURATION_MS=30000;
    private long generation,deadline;
    private Object machine;
    private boolean attempted,owned,automatic;
    long arm(long now){clear();deadline=now+DURATION_MS;return generation;}
    void armAutomatic(){clear();automatic=true;deadline=Long.MAX_VALUE;}
    void clear(){generation++;deadline=0;machine=null;attempted=false;owned=false;automatic=false;}
    boolean automatic(){return automatic;}
    boolean expiredTest(long now){return deadline!=0&&!automatic&&!live(now);}
    boolean live(long now){return deadline>now;}
    long deadline(){return deadline;}
    long generation(){return generation;}
    boolean begin(Object value,long now){if(value==null||!live(now)||attempted)return false;machine=value;attempted=true;return true;}
    boolean claim(long token,Object value,long now){if(token!=generation||value!=machine||!attempted||!live(now))return false;owned=true;return true;}
    void nativeRequest(Object value,String state){nativeRequest(value,state,"");}
    void nativeRequest(Object value,String state,String previous){
        // Native proximity pausing remains part of this acquired session. Other native
        // requests (including another AOD request) transfer ownership away from us.
        boolean proximityResume=state.equals("DOZE_AOD")&&(previous.equals("DOZE_AOD_PAUSING")||previous.equals("DOZE_AOD_PAUSED"));
        boolean automaticRefresh=automatic&&state.equals("DOZE_AOD")&&previous.equals("DOZE_AOD");
        if(value==machine&&owned&&!state.equals("DOZE_AOD_PAUSING")&&!state.equals("DOZE_AOD_PAUSED")&&!proximityResume&&!automaticRefresh)owned=false;
    }
    boolean mayRelease(Object value,String state){return owned&&value==machine&&(state.equals("DOZE_AOD")||state.equals("DOZE_AOD_PAUSING")||state.equals("DOZE_AOD_PAUSED"));}
    boolean owned(){return owned;}
}

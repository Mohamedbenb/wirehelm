package com.nodecockpit.customization;

/** One attempt per notification change or native lifecycle opportunity, never per repaint. */
final class CameraRingAmbientAutomatic {
    private String demand="";
    private boolean opportunity;
    void demand(String value){
        String next=value==null?"":value;
        if(!next.equals(demand)){demand=next;opportunity=!next.isEmpty();}
    }
    boolean wanted(){return !demand.isEmpty();}
    void nativeOpportunity(){if(wanted())opportunity=true;}
    void suspend(){opportunity=false;}
    boolean ready(){return wanted()&&opportunity;}
    boolean take(){if(!ready())return false;opportunity=false;return true;}
}

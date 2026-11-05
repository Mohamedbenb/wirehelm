package com.nodecockpit.customization;
/** Native AOD visibility; no Android dependencies. */
final class CameraRingAodPolicy {
    static boolean canDraw(boolean interactive,int state,int rotation){return !interactive&&rotation==0&&(state==3||state==4);}
}

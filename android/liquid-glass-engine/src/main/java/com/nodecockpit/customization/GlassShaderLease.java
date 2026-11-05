package com.nodecockpit.customization;
/** Shader code lifetime is selected-backend lifetime; visible layers are separately reference-counted. */
final class GlassShaderLease {
 private int users,pins;
 void pin(int owner,boolean enabled){pins=enabled?pins|owner:pins&~owner;}
 void acquire(){users++;}
 void release(){users=Math.max(0,users-1);}
 boolean canUnregister(){return users==0&&pins==0;}
}

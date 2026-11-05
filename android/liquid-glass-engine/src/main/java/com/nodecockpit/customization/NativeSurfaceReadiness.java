package com.nodecockpit.customization;
/** Bounded startup grace; hidden windows do not consume the readiness budget. */
final class NativeSurfaceReadiness {
 private long started=-1;
 boolean pending(long now,boolean visible){if(!visible){started=-1;return true;}if(started<0)started=now;return now-started<3000;}
 void ready(){started=-1;}
}

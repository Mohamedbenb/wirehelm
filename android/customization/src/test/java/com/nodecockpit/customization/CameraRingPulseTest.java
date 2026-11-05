package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class CameraRingPulseTest {
    @Test public void startsDarkAndReachesConfiguredPeakAtDuration(){assertEquals(0,CameraRingPulse.alpha(0,1000,70));assertEquals(Math.round(255*.7f),CameraRingPulse.alpha(1000,1000,70));}
    @Test public void rampsMonotonicallyBothDirections(){int before=0;for(int t=0;t<=1000;t+=10){int now=CameraRingPulse.alpha(t,1000,100);assertTrue(now>=before);before=now;}for(int t=1000;t<=2000;t+=10){int now=CameraRingPulse.alpha(t,1000,100);assertTrue(now<=before);before=now;}assertEquals(0,before);}
    @Test public void configuredDurationControlsBothFadeDirections(){assertEquals(.5f,CameraRingPulse.level(1250,2500),.00001f);assertEquals(1,CameraRingPulse.level(2500,2500),0);assertEquals(.5f,CameraRingPulse.level(3750,2500),.00001f);assertEquals(0,CameraRingPulse.level(5000,2500),0);}
    @Test public void repeatsWithoutOvershootingIntensity(){for(int t=0;t<20000;t+=17){int alpha=CameraRingPulse.alpha(t,1000,35);assertTrue(alpha>=0&&alpha<=Math.round(255*.35f));assertEquals(alpha,CameraRingPulse.alpha(t+2000,1000,35));}}
    @Test public void smoothEndpointsHaveSmallInitialAndFinalSteps(){assertTrue(CameraRingPulse.level(10,1000)<.001f);assertTrue(1-CameraRingPulse.level(990,1000)<.001f);}
    @Test public void invalidClockOrDurationIsDark(){assertEquals(0,CameraRingPulse.alpha(-1,1000,100));assertEquals(0,CameraRingPulse.alpha(100,0,100));assertEquals(0,CameraRingPulse.alpha(100,-1,100));}
    @Test public void delayedFrameSamplesCurrentPhaseWithoutCatchup(){assertEquals(CameraRingPulse.alpha(500,1000,80),CameraRingPulse.alpha(100500,1000,80));}
    @Test public void cadenceIsBoundedAndHitsPhaseBoundary(){assertEquals(100,CameraRingPulse.delay(0,1000));assertEquals(313,CameraRingPulse.delay(0,10000));assertEquals(20,CameraRingPulse.delay(980,1000));assertEquals(100,CameraRingPulse.delay(1000,1000));}
}

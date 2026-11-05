package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassTransitionMathTest {
    @Test public void subpixelStepsSettleAt120Hz() {
        float value=251f; for(int i=0;i<90;i++) value=GlassTransitionMath.approach(value,255f,GlassTransitionMath.amount(1000f/120f,72f));
        assertEquals(255f,value,.01f);
    }
    @Test public void highRefreshAnd60HzReachSameColorAfterSameTime() {
        float fast=0f,slow=0f; for(int i=0;i<60;i++) fast=GlassTransitionMath.approach(fast,255f,GlassTransitionMath.amount(1000f/120f,72f));
        for(int i=0;i<30;i++) slow=GlassTransitionMath.approach(slow,255f,GlassTransitionMath.amount(1000f/60f,72f));
        assertEquals(slow,fast,.001f);
    }
    @Test public void tonesAreContinuousAcrossOldBinaryThreshold() { assertTrue(Math.abs(GlassTransitionMath.tone(.559f)-GlassTransitionMath.tone(.561f))<.01f); }
    @Test public void toneClampsEndpoints() { assertEquals(0f,GlassTransitionMath.tone(-1f),0f); assertEquals(1f,GlassTransitionMath.tone(2f),0f); }
    @Test public void toneIsMonotonic() { float previous=0; for(int i=0;i<=100;i++) { float next=GlassTransitionMath.tone(i/100f); assertTrue(next>=previous); previous=next; } }
    @Test public void sameOpacitySurvivesColorTransitions() { for(int i=0;i<=100;i++) assertEquals(71,GlassTransitionMath.mix(0x47181d24,0x47f2f7fb,i/100f)>>>24); }
    @Test public void elapsedTimeIsFrameRateIndependent() { float half=GlassTransitionMath.amount(8f,72f); float twice=1f-(1f-half)*(1f-half); assertEquals(GlassTransitionMath.amount(16f,72f),twice,.00001f); }
    @Test public void retargetStartsAtDisplayedColorWithoutOvershoot() { int middle=GlassTransitionMath.mix(0xff000000,0xffffffff,.4f); assertEquals(middle,GlassTransitionMath.mix(middle,0xff000000,0)); int reversed=GlassTransitionMath.mix(middle,0xff000000,.2f); assertTrue((reversed&255)<(middle&255)); assertTrue((reversed&255)>0); }
}

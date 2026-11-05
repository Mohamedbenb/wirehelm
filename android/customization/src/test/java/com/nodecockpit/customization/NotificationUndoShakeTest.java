package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class NotificationUndoShakeTest {
    private NotificationUndoShake detector(){return new NotificationUndoShake(0,5_000_000_000L,1);}
    private boolean high(NotificationUndoShake s,long ms){return s.sample(ms*1_000_000L,30,0,9.80665f);}
    private void rest(NotificationUndoShake s,long ms){assertFalse(s.sample(ms*1_000_000L,0,0,9.80665f));}
    @Test public void twoSeparatedPeaksTrigger(){NotificationUndoShake s=detector();assertFalse(high(s,300));rest(s,350);assertTrue(high(s,500));}
    @Test public void sustainedAccelerationIsNotTwoShakes(){NotificationUndoShake s=detector();assertFalse(high(s,300));assertFalse(high(s,500));assertFalse(high(s,700));}
    @Test public void ordinaryMovementDoesNotTrigger(){NotificationUndoShake s=detector();for(int t=300;t<5000;t+=20)assertFalse(s.sample(t*1_000_000L,2,1,9.80665f));}
    @Test public void swipingWarmupDoesNotCount(){NotificationUndoShake s=detector();assertFalse(high(s,100));rest(s,280);assertFalse(high(s,400));}
    @Test public void separatedGesturesDoNotCombine(){NotificationUndoShake s=detector();assertFalse(high(s,300));rest(s,350);assertFalse(high(s,1300));rest(s,1350);assertTrue(high(s,1500));}
    @Test public void fastSensorNoiseDoesNotTrigger(){NotificationUndoShake s=detector();assertFalse(high(s,300));rest(s,310);assertFalse(high(s,330));}
    @Test public void expiryCannotUndo(){NotificationUndoShake s=detector();assertFalse(high(s,4800));rest(s,4900);assertFalse(high(s,5000));}
    @Test public void triggerIsOneShot(){NotificationUndoShake s=detector();high(s,300);rest(s,350);assertTrue(high(s,500));rest(s,550);assertFalse(high(s,700));}
    @Test public void staleSamplesCannotRearm(){NotificationUndoShake s=detector();high(s,300);rest(s,290);assertFalse(high(s,500));}
    @Test public void nonfiniteInputIsIgnored(){NotificationUndoShake s=detector();assertFalse(s.sample(300_000_000L,Float.NaN,0,0));assertFalse(s.sample(350_000_000L,Float.POSITIVE_INFINITY,0,0));assertFalse(high(s,400));rest(s,450);assertTrue(high(s,600));}
    @Test public void sensitivityChangesRequiredStrength(){NotificationUndoShake gentle=new NotificationUndoShake(0,5_000_000_000L,0),firm=new NotificationUndoShake(0,5_000_000_000L,2);assertFalse(gentle.sample(300_000_000L,15,0,9.80665f));rest(gentle,350);assertTrue(gentle.sample(500_000_000L,15,0,9.80665f));assertFalse(firm.sample(300_000_000L,15,0,9.80665f));rest(firm,350);assertFalse(firm.sample(500_000_000L,15,0,9.80665f));}
}

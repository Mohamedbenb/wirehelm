package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class CameraRingAmbientSessionTest {
    @Test public void idleNeverClaimsOrReleases(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();assertFalse(s.live(0));assertFalse(s.begin(m,0));assertFalse(s.claim(0,m,0));assertFalse(s.mayRelease(m,"DOZE_AOD"));}
    @Test public void oneAttemptAndBoundedClaim(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();long g=s.arm(100);assertTrue(s.begin(m,200));assertFalse(s.begin(m,201));assertTrue(s.claim(g,m,300));assertTrue(s.mayRelease(m,"DOZE_AOD"));assertFalse(s.live(30100));}
    @Test public void delayedProximityResultCannotEnterAfterExpiry(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();long g=s.arm(0);s.begin(m,1);assertFalse(s.claim(g,m,30000));}
    @Test public void cancelAndRearmRejectStaleCallbacksEvenSameMachine(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();long old=s.arm(0);s.begin(m,1);s.clear();s.arm(2);s.begin(m,3);assertFalse(s.claim(old,m,4));}
    @Test public void replacementIdentityCannotClaimOrRelease(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object a=new Object(),b=new Object();long g=s.arm(0);s.begin(a,1);assertFalse(s.claim(g,b,2));assertTrue(s.claim(g,a,2));assertFalse(s.mayRelease(b,"DOZE_AOD"));}
    @Test public void nativeAodRequestTakesOwnershipEvenSameState(){CameraRingAmbientSession s=owned();Object m=machine;s.nativeRequest(m,"DOZE_AOD");assertFalse(s.mayRelease(m,"DOZE_AOD"));}
    @Test public void proximityPauseDoesNotLoseExpiryOwnership(){CameraRingAmbientSession s=owned();Object m=machine;s.nativeRequest(m,"DOZE_AOD_PAUSING");s.nativeRequest(m,"DOZE_AOD_PAUSED");assertTrue(s.mayRelease(m,"DOZE_AOD_PAUSED"));assertTrue(s.mayRelease(m,"DOZE_AOD"));}
    @Test public void proximityResumeRemainsBoundedByOriginalLease(){CameraRingAmbientSession s=owned();Object m=machine;s.nativeRequest(m,"DOZE_AOD_PAUSED","DOZE_AOD");s.nativeRequest(m,"DOZE_AOD","DOZE_AOD_PAUSED");assertTrue(s.mayRelease(m,"DOZE_AOD"));assertFalse(s.live(30000));}
    @Test public void pulseWakeStopAndDockTransferOwnership(){for(String state:new String[]{"DOZE_REQUEST_PULSE","FINISH","DOZE","DOZE_AOD_DOCKED"}){CameraRingAmbientSession s=owned();Object m=machine;s.nativeRequest(m,state);assertFalse(state,s.mayRelease(m,"DOZE_AOD"));}}
    @Test public void unknownAndNativePulseStatesAreNeverForcedBack(){CameraRingAmbientSession s=owned();Object m=machine;for(String state:new String[]{"FINISH","DOZE_PULSING","INITIALIZED","DOZE_AOD_DOCKED"})assertFalse(state,s.mayRelease(m,state));}
    @Test public void unrelatedMachineCannotStealOwnership(){CameraRingAmbientSession s=owned();Object m=machine;s.nativeRequest(new Object(),"FINISH");assertTrue(s.mayRelease(m,"DOZE_AOD"));}
    private Object machine;
    private CameraRingAmbientSession owned(){CameraRingAmbientSession s=new CameraRingAmbientSession();machine=new Object();long g=s.arm(0);assertTrue(s.begin(machine,1));assertTrue(s.claim(g,machine,2));return s;}
}

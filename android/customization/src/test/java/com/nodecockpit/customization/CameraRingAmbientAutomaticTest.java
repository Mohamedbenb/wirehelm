package com.nodecockpit.customization;
import org.junit.Test;
import org.json.*;
import static org.junit.Assert.*;
public class CameraRingAmbientAutomaticTest {
    @Test public void legacySettingsAndDefaultsDoNotEnableAmbient()throws Exception{assertFalse(new CameraRingSettings("{\"enabled\":true}").ambientOnDemand);assertFalse(new CameraRingSettings(CameraRingSettings.DEFAULT).ambientOnDemand);}
    @Test public void optInStrictlyBooleanAndSafetyDisablePreservesIntent()throws Exception{
        CameraRingSettings s=new CameraRingSettings("{\"enabled\":true,\"ambientOnDemand\":true}");assertTrue(s.ambientOnDemand);
        CameraRingSettings disabled=new CameraRingSettings(CameraRingSettings.disabled("{\"enabled\":true,\"ambientOnDemand\":true}"));assertFalse(disabled.enabled);assertTrue(disabled.ambientOnDemand);
        for(String invalid:new String[]{"1","\"true\"","null"}){try{new CameraRingSettings("{\"ambientOnDemand\":"+invalid+"}");fail(invalid);}catch(IllegalArgumentException expected){}}
    }
    @Test public void duplicateRenderingCannotRetryAnAttempt(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.demand("notice:1");assertTrue(a.take());for(int i=0;i<1000;i++){a.demand("notice:1");assertFalse(a.take());}}
    @Test public void realNotificationUpdateAllowsOneNewAttempt(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.demand("notice:1");a.take();a.demand("notice:2");assertTrue(a.take());assertFalse(a.take());}
    @Test public void clearingStopsDemandAndRepostHasNewOpportunity(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.demand("notice:1");a.take();a.demand("");assertFalse(a.wanted());assertFalse(a.ready());a.demand("notice:1");assertTrue(a.take());}
    @Test public void nativeEventsWithoutNoticesCannotTurnDisplayOn(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.nativeOpportunity();assertFalse(a.take());a.demand(null);assertFalse(a.wanted());}
    @Test public void wakeSuppressesUntilNextNativeSessionEvent(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.demand("notice:1");a.suspend();a.demand("notice:1");assertFalse(a.take());a.nativeOpportunity();assertTrue(a.take());assertFalse(a.take());}
    @Test public void nativePulseCompletionPermitsOneReentry(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();a.demand("notice:1");a.take();a.suspend();a.nativeOpportunity();assertTrue(a.take());assertFalse(a.take());}
    @Test public void automaticSessionDoesNotInheritTestTimeoutAndClearInvalidatesCallbacks(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();s.armAutomatic();long g=s.generation();assertTrue(s.automatic());assertTrue(s.live(24*60*60*1000L));assertTrue(s.begin(m,1));assertTrue(s.claim(g,m,2));s.clear();assertFalse(s.automatic());assertFalse(s.claim(g,m,3));assertFalse(s.mayRelease(m,"DOZE_AOD"));}
    @Test public void winnerHandoffKeepsOwnedSessionUntilLastNotificationClears(){CameraRingAmbientAutomatic a=new CameraRingAmbientAutomatic();CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();a.demand("high:1");assertTrue(a.take());s.armAutomatic();s.begin(m,1);s.claim(s.generation(),m,2);a.demand("low:1");assertTrue(a.wanted());assertTrue(s.owned());a.demand("");assertFalse(a.wanted());assertTrue(s.mayRelease(m,"DOZE_AOD"));s.clear();assertFalse(s.owned());}
    @Test public void boundedTestStillExpiresAfterAutomaticSession(){CameraRingAmbientSession s=new CameraRingAmbientSession();s.armAutomatic();s.arm(100);assertFalse(s.automatic());assertFalse(s.live(30100));}
    @Test public void lateTestAlarmCannotStopAutomaticOrNewerTestSession(){CameraRingAmbientSession s=new CameraRingAmbientSession();s.arm(0);s.clear();s.armAutomatic();assertFalse(s.expiredTest(30000));s.arm(29000);assertFalse(s.expiredTest(30000));assertTrue(s.expiredTest(59000));s.clear();assertFalse(s.expiredTest(90000));}
    @Test public void unrelatedPageCannotRemoveSavedAmbientOptIn()throws Exception{String raw="{\"enabled\":true,\"ambientOnDemand\":true}";JSONObject stale=new JSONObject().put("cameraRing",CameraRingSettings.DEFAULT);CameraRingSettings.mergeOwnership(stale,raw,false);assertTrue(new CameraRingSettings(stale.getString("cameraRing")).ambientOnDemand);}
    @Test public void automaticNativeRefreshStillReleasesOnLastNotice(){CameraRingAmbientSession s=new CameraRingAmbientSession();Object m=new Object();s.armAutomatic();s.begin(m,1);s.claim(s.generation(),m,2);s.nativeRequest(m,"DOZE_AOD","DOZE_AOD");assertTrue(s.mayRelease(m,"DOZE_AOD"));s.clear();assertFalse(s.mayRelease(m,"DOZE_AOD"));}
}

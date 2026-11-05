package com.nodecockpit.customization;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class CameraRingEligibilityTest {
    private CameraRingSelection.Notice n(String key,String pkg,long posted){return new CameraRingSelection.Notice(key,pkg,posted,false,false);}
    @Test public void startsEmptyUntilAuthoritativeList(){CameraRingEligibility e=new CameraRingEligibility();assertFalse(e.ready());assertTrue(e.snapshot().isEmpty());e.reconcile(List.of(n("a","a.app",1)));assertTrue(e.snapshot().isEmpty());}
    @Test public void dismissalRemovesOnlyItsOwnKey(){CameraRingEligibility e=new CameraRingEligibility();var a=n("a","a.app",1);var b=n("b","a.app",2);e.rendered(List.of(a,b));e.reconcile(List.of(b));assertEquals(List.of(b),e.snapshot());}
    @Test public void retainedUnreadRecordCannotResurrectOnRelock(){CameraRingEligibility e=new CameraRingEligibility();var a=n("a","a.app",1);e.rendered(List.of(a));e.reconcile(List.of());for(int i=0;i<5;i++)e.reconcile(List.of(a));assertTrue(e.ready());assertTrue(e.snapshot().isEmpty());}
    @Test public void genuinelyRenderedNewNoticeCanReturn(){CameraRingEligibility e=new CameraRingEligibility();e.rendered(List.of(n("a","a.app",1)));e.reconcile(List.of());var fresh=n("a","a.app",2);e.rendered(List.of(fresh));assertEquals(List.of(fresh),e.snapshot());}
    @Test public void emptyFilteredListClearsRetainedRecords(){CameraRingEligibility e=new CameraRingEligibility();var a=n("hidden","a.app",1);e.rendered(List.of(a));e.rendered(List.of());e.reconcile(List.of(a));assertTrue(e.snapshot().isEmpty());}
    @Test public void cancelOrLifetimeExtensionCannotKeepOldWinner(){CameraRingEligibility e=new CameraRingEligibility();var a=n("cancelled","a.app",1);var b=n("live","b.app",2);e.rendered(List.of(a,b));e.reconcile(List.of(b));e.reconcile(List.of(a,b));assertEquals(List.of(b),e.snapshot());}
    @Test public void clearAllGroupedChildrenStayGone(){CameraRingEligibility e=new CameraRingEligibility();var a=n("child1","a.app",1);var b=n("child2","a.app",2);e.rendered(List.of(a,b));e.reconcile(List.of());e.reconcile(List.of(a,b));assertTrue(e.snapshot().isEmpty());}
    @Test public void clearingHighPriorityRevealsRemainingApp()throws Exception{CameraRingSettings settings=new CameraRingSettings("{\"enabled\":true,\"apps\":[{\"package\":\"a.high\",\"priority\":5},{\"package\":\"a.low\",\"priority\":1}]}");CameraRingEligibility e=new CameraRingEligibility();var a=n("high","a.high",1);var b=n("low","a.low",2);e.rendered(List.of(a,b));assertEquals(a,CameraRingSelection.winner(settings,e.snapshot()));e.reconcile(List.of(b));assertEquals(b,CameraRingSelection.winner(settings,e.snapshot()));}
    @Test public void reconcileCannotAddNewOrPreviouslyFilteredKeys(){CameraRingEligibility e=new CameraRingEligibility();var a=n("a","a.app",1);var b=n("b","b.app",2);e.rendered(List.of(a));e.reconcile(List.of(a,b));assertEquals(List.of(a),e.snapshot());e.rendered(List.of(a,b));assertEquals(2,e.snapshot().size());}
    @Test public void failureOrDisableDropsAllCachedState(){CameraRingEligibility e=new CameraRingEligibility();e.rendered(List.of(n("a","a.app",1)));e.clear();assertFalse(e.ready());assertTrue(e.snapshot().isEmpty());}
    @Test public void copiedSnapshotsDoNotTrackMutableProducer(){CameraRingEligibility e=new CameraRingEligibility();List<CameraRingSelection.Notice> input=new ArrayList<>(List.of(n("a","a.app",1)));e.rendered(input);input.clear();assertEquals(1,e.snapshot().size());try{e.snapshot().clear();fail();}catch(UnsupportedOperationException expected){}}
    @Test public void budgetsApplyToRenderAndReconcile(){List<CameraRingSelection.Notice> input=new ArrayList<>();for(int i=0;i<2049;i++)input.add(n(""+i,"a.app",i));CameraRingEligibility e=new CameraRingEligibility();try{e.rendered(input);fail();}catch(IllegalArgumentException expected){}try{e.reconcile(input);fail();}catch(IllegalArgumentException expected){}}
}

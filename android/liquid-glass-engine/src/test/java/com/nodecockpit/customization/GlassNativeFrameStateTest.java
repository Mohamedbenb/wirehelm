package com.nodecockpit.customization;

import org.junit.Test;
import static org.junit.Assert.*;

/** Frame-order/ownership tests, not GPU or presentation claims. */
public class GlassNativeFrameStateTest {
    private GlassNativeFrameState.Pose pose(long f){return new GlassNativeFrameState.Pose(f,10,20,310,100,0,0,300,80,300,80,false,false,false);}
    private GlassNativeFrameState.Appearance ink(long seq,boolean replace){return new GlassNativeFrameState.Appearance(seq,300,80,40,1,replace,new byte[]{1,2});}
    private void join(GlassNativeFrameState s,long f){long g=s.generation();s.position(g,pose(f));s.appearance(g,f,ink(f,true));}
    @Test public void eitherCallbackOrderJoinsOnlyAvailableFrameInputs(){
        GlassNativeFrameState s=new GlassNativeFrameState();long g=s.generation();
        s.position(g,pose(10));assertNull(s.join(10));s.appearance(g,11,ink(1,true));assertNull(s.join(10));assertTrue(s.join(11).shown());
        s.appearance(g,12,ink(2,true));s.position(g,pose(12));assertTrue(s.join(12).shown());
    }
    @Test public void staleFrameCannotReplaceSubmittedFrame(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,12);assertTrue(s.submitted(s.join(12)));join(s,11);assertNull(s.join(11));assertEquals(12,s.join(12).pose.frame);}
    @Test public void newerAppearanceOnSameFrameCanCorrectTransaction(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,12);s.submitted(s.join(12));s.appearance(s.generation(),12,ink(13,false));assertTrue(s.submitted(s.join(12)));assertFalse(s.join(12).shown());}
    @Test public void closeRejectsQueuedCallbacks(){GlassNativeFrameState s=new GlassNativeFrameState();long g=s.generation();join(s,1);s.close();s.position(g,pose(2));s.appearance(g,2,ink(2,true));assertNull(s.join(2));assertFalse(s.commit(g,2,true));assertEquals(0,s.retained());}
    @Test public void windowGenerationCannotReuseOldPosition(){GlassNativeFrameState s=new GlassNativeFrameState();long g=s.generation();join(s,1);s.window(false);s.window(true);s.position(g,pose(2));s.appearance(s.generation(),2,ink(2,true));assertNull(s.join(2));assertFalse(s.warm());}
    @Test public void hiddenWindowCannotSubmitRetainedGeometry(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);GlassNativeFrameState.Submission old=s.join(1);s.window(false);assertNull(s.join(1));assertFalse(s.submitted(old));}
    @Test public void warmupRequiresMatchingDimensionsAndProducedCommit(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);s.submitted(s.join(1));assertFalse(s.commit(s.generation(),1,false));assertFalse(s.warm());assertTrue(s.commit(s.generation(),1,true));assertTrue(s.warm());}
    @Test public void transparentBackgroundPaintIsNotComponentOpacity(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);assertTrue(s.join(1).shown());s.appearance(s.generation(),2,new GlassNativeFrameState.Appearance(2,300,80,40,0,true,new byte[]{1}));assertFalse(s.join(2).shown());}
    @Test public void clippedAndSwappedPositionsCannotShow(){GlassNativeFrameState s=new GlassNativeFrameState();long g=s.generation();s.appearance(g,1,ink(1,true));s.position(g,new GlassNativeFrameState.Pose(1,10,20,310,100,0,80,300,80,300,80,false,false,false));assertFalse(s.join(1).shown());s.position(g,new GlassNativeFrameState.Pose(2,10,20,310,100,0,0,300,80,300,80,true,true,false));assertFalse(s.join(2).shown());}
    @Test public void lostPositionHidesWithoutDisarmingPreparedResources(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);s.submitted(s.join(1));s.commit(s.generation(),1,true);s.position(s.generation(),new GlassNativeFrameState.Pose(2,0,0,0,0,0,0,0,0,0,0,false,false,true));s.submitted(s.join(2));assertFalse(s.join(2).shown());assertFalse(s.commit(s.generation(),2,true));assertTrue(s.warm());}
    @Test public void mismatchedNativeSizeDoesNotShowOrWarm(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);s.appearance(s.generation(),1,new GlassNativeFrameState.Appearance(2,301,80,40,1,true,new byte[]{1}));assertFalse(s.join(1).shown());s.submitted(s.join(1));assertFalse(s.commit(s.generation(),1,true));assertFalse(s.warm());}
    @Test public void historyIsBoundedAndUniformInputsAreCopied(){GlassNativeFrameState s=new GlassNativeFrameState();for(int i=0;i<100;i++)join(s,i);assertEquals(8,s.retained());byte[] b={1};GlassNativeFrameState.Appearance a=new GlassNativeFrameState.Appearance(1,300,80,40,1,true,b);b[0]=9;assertEquals(1,a.uniforms[0]);}
    @Test public void unchangedAppearanceAndPoseDoNotRequireResubmission(){GlassNativeFrameState s=new GlassNativeFrameState();join(s,1);GlassNativeFrameState.Submission first=s.join(1);join(s,2);assertTrue(s.join(2).sameVisual(first));s.appearance(s.generation(),3,new GlassNativeFrameState.Appearance(3,300,80,40,.5f,true,new byte[]{1,2}));assertFalse(s.join(3).sameVisual(first));}
}

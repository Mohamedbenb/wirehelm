package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassNativeBlurLeaseTest {
 private static class Backend implements GlassNativeBlurLease.Backend {
  int configurations,releases,records;boolean visible,failConfigure,failHide;
  public void configure(GlassNativeBlurRegion r){if(failConfigure)throw new IllegalStateException("unsupported");configurations++;}
  public void visible(boolean v){visible=v;if(!v&&failHide)throw new IllegalStateException("lost root");}
  public void release(){releases++;}
 }
 private GlassNativeBlurRegion region(){return new GlassNativeBlurRegion(300,80,40,30,30,30,30,0);}
 @Test public void sameLocalShapeRecordsWithoutGeometryResampling(){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);assertTrue(lease.prepare(region()));for(int i=0;i<3;i++)assertTrue(lease.draw(region(),true,true,()->b.records++));assertEquals(1,b.configurations);assertEquals(3,b.records);}
 @Test public void failedPreparationDoesNotSuppressStock(){Backend b=new Backend();b.failConfigure=true;GlassNativeBlurLease lease=new GlassNativeBlurLease(b);assertFalse(lease.draw(region(),true,true,()->b.records++));assertEquals(0,b.records);assertEquals(1,b.releases);assertFalse(b.visible);}
 @Test public void drawFailureClosesBackendAndRejectsFurtherDraws(){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);assertFalse(lease.draw(region(),true,true,()->{throw new IllegalStateException("recording failed");}));assertFalse(lease.draw(region(),true,true,()->b.records++));assertEquals(1,b.releases);}
 @Test public void detachAndSoftwareCanvasFailClosed(){for(boolean attached:new boolean[]{false,true}){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);assertFalse(lease.draw(region(),attached,false,()->b.records++));assertEquals(0,b.records);assertEquals(1,b.releases);}}
 @Test public void hiddenMaterialCannotRecordAndCanResume(){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);lease.prepare(region());lease.visible(false);assertFalse(lease.draw(region(),true,true,()->b.records++));lease.visible(true);assertTrue(lease.draw(region(),true,true,()->b.records++));assertEquals(1,b.configurations);}
 @Test public void teardownStillReleasesIfVisibilityFails(){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);b.failHide=true;lease.close();lease.close();assertEquals(1,b.releases);assertTrue(lease.closed());}
 @Test public void styleChangeUpdatesOnlyOneNativeOwner(){Backend b=new Backend();GlassNativeBlurLease lease=new GlassNativeBlurLease(b);lease.prepare(region());lease.prepare(new GlassNativeBlurRegion(300,80,70,30,30,30,30,0));assertEquals(2,b.configurations);}
}

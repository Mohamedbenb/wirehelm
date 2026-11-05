package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class GlassFrameStatsTest {
 @Test public void duplicateAndPendingFencesAreNotFrames(){GlassFrameStats s=new GlassFrameStats();s.frame(0,-1,0,0,0);s.frame(Long.MAX_VALUE,-1,0,0,0);s.frame(100,2000000,20,10,2);s.frame(100,-1,0,0,0);s.frame(90,-1,0,0,0);assertEquals(1,s.presented);assertEquals(1,s.gpuCount);assertEquals(1,s.missed);assertEquals(2,s.dropped);String text=s.snapshot(.5);assertTrue(text.contains("FPS: 2"));assertTrue(text.contains("2.00ms"));assertEquals(0,s.presented);s.frame(100,-1,0,0,0);assertEquals(0,s.presented);}
 @Test public void idleDoesNotReportRefreshRate(){GlassFrameStats s=new GlassFrameStats();assertTrue(s.snapshot(.5).contains("FPS: 0"));assertTrue(s.snapshot(.5).contains("pending"));}
 @Test public void windowReportsDoNotPretendToBePresentationFps(){GlassFrameStats s=new GlassFrameStats();s.frame(0,1000000,20,10,2);String text=s.windowSnapshot();assertTrue(text.contains("Host frame reports: 1"));assertTrue(text.contains("not presentation FPS"));assertTrue(text.contains("1.00ms"));assertEquals(0,s.presented);assertEquals(0,s.reports);}
}

package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassFrameCommitTest {
 @Test public void preparationDoesNotClaimSubmission(){GlassFrameCommit<Object> g=new GlassFrameCommit<>();Object f=new Object();g.prepare(f);assertFalse(g.ready(f));assertTrue(g.submit(f));assertTrue(g.ready(f));}
 @Test public void replacementRejectsOldFrameEvenIfPixelsAreEqual(){GlassFrameCommit<String> g=new GlassFrameCommit<>();String a=new String("same"),b=new String("same");g.prepare(a);g.submit(a);g.prepare(b);assertFalse(g.ready(a));assertFalse(g.ready(b));assertFalse(g.submit(a));assertTrue(g.submit(b));assertTrue(g.ready(b));}
 @Test public void clearRejectsLateSubmission(){GlassFrameCommit<Object> g=new GlassFrameCommit<>();Object f=new Object();g.prepare(f);g.submit(f);g.clear();assertFalse(g.ready(f));assertFalse(g.submit(f));assertFalse(g.ready(null));}
 @Test public void unchangedPacketCanBeAcknowledgedOnAnotherDraw(){GlassFrameCommit<Object> g=new GlassFrameCommit<>();Object f=new Object();g.prepare(f);assertTrue(g.submit(f));assertTrue(g.submit(f));assertTrue(g.ready(f));}
}

package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class NativeSurfaceReadinessTest {
 @Test public void givesOneBoundedStartupGrace(){NativeSurfaceReadiness r=new NativeSurfaceReadiness();assertTrue(r.pending(0,true));assertTrue(r.pending(2999,true));assertFalse(r.pending(3000,true));assertFalse(r.pending(4000,true));}
 @Test public void hiddenWindowDoesNotExhaustBudget(){NativeSurfaceReadiness r=new NativeSurfaceReadiness();assertTrue(r.pending(0,true));assertTrue(r.pending(100000,false));assertTrue(r.pending(100001,true));assertFalse(r.pending(103001,true));}
 @Test public void successfulBindingResetsBudget(){NativeSurfaceReadiness r=new NativeSurfaceReadiness();r.pending(0,true);r.ready();assertTrue(r.pending(6000,true));assertFalse(r.pending(9000,true));}
}

package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class GlassShaderLeaseTest {
 @Test public void screenOffOrThermalLayerTeardownDoesNotDropSelectedShader(){GlassShaderLease l=new GlassShaderLease();l.pin(2,true);l.acquire();l.release();assertFalse(l.canUnregister());l.acquire();assertFalse(l.canUnregister());l.release();l.pin(2,false);assertTrue(l.canUnregister());}
 @Test public void oneFeatureCannotUnregisterAnotherFeaturesShader(){GlassShaderLease l=new GlassShaderLease();l.pin(1,true);l.pin(2,true);l.pin(2,false);assertFalse(l.canUnregister());l.pin(1,false);assertTrue(l.canUnregister());}
 @Test public void disableWaitsForLiveLayerClients(){GlassShaderLease l=new GlassShaderLease();l.pin(2,true);l.acquire();l.acquire();l.pin(2,false);l.release();assertFalse(l.canUnregister());l.release();assertTrue(l.canUnregister());}
}

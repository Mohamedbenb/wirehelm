package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassNativeBlurRegionTest {
 @Test public void boundsAndCornersAreLocalAndBounded(){GlassNativeBlurRegion r=new GlassNativeBlurRegion(200,40,200,100,-1,12,8,0x12345678);assertEquals(150,r.blur);assertEquals(20,r.tl,0);assertEquals(0,r.tr,0);assertEquals(12,r.br,0);assertEquals(8,r.bl,0);assertEquals(0x12345678,r.tint);}
 @Test(expected=IllegalArgumentException.class) public void invalidGeometryCannotCreateNativeRegion(){new GlassNativeBlurRegion(0,100,40,4,4,4,4,0);}
 @Test(expected=IllegalArgumentException.class) public void invalidBlurCannotReachFramework(){new GlassNativeBlurRegion(100,100,Float.NaN,4,4,4,4,0);}
 @Test public void equivalentPacketsDoNotRequireReconfiguration(){assertTrue(new GlassNativeBlurRegion(100,40,40,20,20,20,20,0).same(new GlassNativeBlurRegion(100,40,40,200,200,200,200,0)));}
}

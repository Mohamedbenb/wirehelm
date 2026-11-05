package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassKawaseBlurTest {
 @Test public void invalidAndZeroAreIdentity(){ for(float r:new float[]{0,-1,Float.NaN,Float.POSITIVE_INFINITY}) assertEquals(0,GlassKawaseBlur.offsets(r).length); }
 @Test public void workAndRadiusAreBounded(){ assertArrayEquals(GlassKawaseBlur.offsets(150),GlassKawaseBlur.offsets(10000),0); assertEquals(4,GlassKawaseBlur.offsets(48).length); }
 @Test public void passSchedule(){ assertArrayEquals(new float[]{6,6,12,18},GlassKawaseBlur.offsets(48),0); assertArrayEquals(new float[]{.5f},GlassKawaseBlur.offsets(1),0); }
}

package com.example.remote_control.glasscard
import org.junit.Assert.*
import org.junit.Test
class TouchRippleStateTest {
 @Test fun downAndReleaseHaveIndependentOriginsAndOppositePolarity(){val s=TouchRippleState();s.emit(.2f,.3f,1000,false);s.emit(.8f,.7f,1200,true);val f=s.frame(1300,2f);assertEquals(.2f,f[0],0f);assertEquals(.3f,f[2],.001f);assertEquals(1f,f[3],0f);assertEquals(.8f,f[4],0f);assertEquals(.1f,f[6],.001f);assertEquals(-1f,f[7],0f)}
 @Test fun expiresAndClearsWithoutResidualWaves(){val s=TouchRippleState();s.emit(.5f,.5f,0,false);assertTrue(s.active());val f=s.frame(2000,1.4f);assertFalse(s.active());assertArrayEquals(TouchRippleState.emptyFrame(),f,0f);s.emit(.1f,.2f,2000,true);s.clear();assertFalse(s.active());assertArrayEquals(TouchRippleState.emptyFrame(),s.frame(2000,1f),0f)}
 @Test fun fixedCapacityAndInputBounds(){val s=TouchRippleState();for(i in 0..20)s.emit(-1f,2f,i.toLong(),false);val f=s.frame(30,2f);assertEquals(16,f.size);for(i in 0..3){assertEquals(0f,f[4*i],0f);assertEquals(1f,f[4*i+1],0f);assertTrue(f[4*i+2]>=0);assertEquals(1f,f[4*i+3],0f)}}
 @Test fun lifetimeIsBoundedAndFasterDampingSettlesEarlier(){for(s in listOf(.25f,1f,2.5f,Float.NaN))for(d in listOf(.3f,1.4f,3f,Float.NaN)){val life=TouchRippleState.lifetime(s,d);assertTrue(life.isFinite()&&life>0&&life<=4.5f)};assertTrue(TouchRippleState.lifetime(.25f,3f)<TouchRippleState.lifetime(.25f,.3f));assertTrue(TouchRippleState.lifetime(2.5f,1f)<TouchRippleState.lifetime(.25f,1f))}
}

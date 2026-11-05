package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class DampedShadeTest {
 @Test public void sustainedRetargetKeepsPositionAndVelocity(){DampedShade p=new DampedShade();p.seed(20);p.step(200,80,150);float x=p.value,v=p.velocity;assertTrue(v>0);p.step(0,0,150);assertEquals(x,p.value,.0001f);assertEquals(v,p.velocity,.0001f);p.step(0,1,150);assertTrue(p.value>x);for(int i=0;i<150;i++)p.step(0,16,150);assertTrue(p.close(0,.6f));}
 @Test public void frameRateIndependentAndBounded(){DampedShade a=new DampedShade(),b=new DampedShade();a.seed(0);b.seed(0);for(int i=0;i<30;i++)a.step(220,16,150);for(int i=0;i<60;i++)b.step(220,8,150);assertEquals(a.value,b.value,.002f);assertEquals(a.velocity,b.velocity,.0001f);assertTrue(a.value<=220);}
 @Test public void reversedTargetsConvergeWithoutResettingToOldStart(){DampedShade p=new DampedShade();p.seed(40);p.step(200,100,150);float from=p.value;p.step(100,16,150);assertTrue(p.value>from);for(int i=0;i<100;i++)p.step(100,16,150);assertTrue(p.close(100,.6f));}
}

package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class CardRippleTimelineTest {
 @Test public void currentAgeDoesNotDependOnNumberOfFrames(){CardRippleTimeline a=new CardRippleTimeline(),b=new CardRippleTimeline();a.emit(.2f,.8f,1000,false);b.emit(.2f,.8f,1000,false);for(int i=1000;i<1500;i+=8)a.advance(i,2);a.advance(1500,2);b.advance(1500,2);assertArrayEquals(a.values,b.values,0);assertEquals(.5f,a.values[2],0);}
 @Test public void releaseIsSeparateAndAllWavesExpire(){CardRippleTimeline t=new CardRippleTimeline();t.emit(.2f,.3f,1000,false);t.emit(.7f,.8f,1100,true);assertEquals(1,t.values[3],0);assertEquals(-1,t.values[7],0);assertTrue(t.advance(1200,2));assertFalse(t.advance(4000,2));t.clear();for(int i=0;i<4;i++){assertEquals(-1,t.values[i*4+2],0);assertEquals(0,t.values[i*4+3],0);}}
 @Test public void rapidTouchesStayBoundedAndInvalidCoordinatesAreSafe(){CardRippleTimeline t=new CardRippleTimeline();for(int i=0;i<100;i++)t.emit(Float.NaN,5,i,false);assertEquals(16,t.values.length);for(int i=0;i<4;i++){assertEquals(.5f,t.values[i*4],0);assertEquals(1,t.values[i*4+1],0);}for(float s:new float[]{.25f,1,2.5f,Float.NaN})for(float d:new float[]{.3f,1.4f,3,Float.NaN}){float l=CardRippleTimeline.lifetime(s,d);assertTrue(Float.isFinite(l)&&l>0&&l<=4.5f);}}
}

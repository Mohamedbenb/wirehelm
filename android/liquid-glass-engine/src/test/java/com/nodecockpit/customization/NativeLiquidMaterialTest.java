package com.nodecockpit.customization;
import org.junit.Test;
import java.nio.*;
import static org.junit.Assert.*;
public class NativeLiquidMaterialTest {
 @Test public void compactContrastCannotChangePresetOrInkAndRetainsUniformLayout(){
  for(int p=0;p<4;p++)for(boolean dark:new boolean[]{false,true})for(float support:new float[]{0,.01f,.45f,.6f,1}){
   byte[] bytes=NativeLiquidMaterial.pack(370,1890,79,p,dark,2.2f,4,.035f,.42f,support);assertEquals(32,bytes.length);
   FloatBuffer f=ByteBuffer.wrap(bytes).order(ByteOrder.nativeOrder()).asFloatBuffer();assertEquals(370,f.get(0),0);assertEquals(1890,f.get(1),0);assertEquals(79,f.get(2),0);
   float mode=f.get(3);assertEquals(p+(dark?4:0),(int)Math.floor(mode+.001f));assertEquals(support,(mode-(float)Math.floor(mode))*4,.00001f);
   assertEquals(2.2f,f.get(4),0);assertEquals(4,f.get(5),0);assertEquals(.035f,f.get(6),0);assertEquals(.42f,f.get(7),0);
  }
 }
 @Test public void gentleShoulderPreservesOrderingInsteadOfFlatteningBrightDetail(){
  double previous=-1;for(int i=0;i<=1000;i++){double l=i/1000.;double mapped=l/(1+.6*.12*l);assertTrue(mapped>=0&&mapped<=1);assertTrue(mapped>previous);previous=mapped;}
  assertTrue(1/(1+.6*.12)>.9);
 }
}

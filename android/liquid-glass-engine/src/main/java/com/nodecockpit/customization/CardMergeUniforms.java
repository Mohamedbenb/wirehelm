package com.nodecockpit.customization;
import java.nio.*;
final class CardMergeUniforms {
 static final int BYTES=272;
 static byte[] extend(byte[] base,float[] shapes){
  if(base.length!=240||shapes!=null&&shapes.length!=13)throw new IllegalArgumentException("Invalid card shape contract");
  ByteBuffer b=ByteBuffer.allocate(BYTES).order(ByteOrder.nativeOrder());b.put(base);
  if(shapes!=null){for(float f:shapes)if(!Float.isFinite(f))throw new IllegalArgumentException("Non-finite shape");for(int i=0;i<4;i++)b.putFloat((4+i)*4,shapes[i]);for(int i=0;i<4;i++)b.putFloat((8+i)*4,shapes[4]);for(int i=0;i<8;i++)b.putFloat(240+i*4,shapes[5+i]);}
  return b.array();
 }
 static float union(float a,float b,float k){if(k<=.5f)return Math.min(a,b);float h=Math.max(0,Math.min(1,.5f+.5f*(b-a)/k));return b+(a-b)*h-k*h*(1-h);}
}

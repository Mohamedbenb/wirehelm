package com.nodecockpit.customization;

import android.graphics.RenderEffect;
import android.graphics.RuntimeShader;

/** Full-resolution Kawase approximation. No claim of SurfaceFlinger pixel equivalence.
 * Host supplies an owned backdrop; Android 13+ hardware rendering is required.
 * Unlike SurfaceFlinger this version does not downsample intermediate images.
 */
public final class GlassKawaseBlur {
 private GlassKawaseBlur() {}
 public static float[] offsets(float radius) {
  if (!Float.isFinite(radius) || radius <= 0) return new float[0];
  float half = Math.min(radius, 150f) * .5f;
  int count = Math.min(4, (int)Math.ceil(half));
  float step = half / count;
  float[] result = new float[count];
  for (int i=0;i<count;i++) result[i]=Math.max(1,i)*step;
  return result;
 }
 /** Null means identity. Caller owns caching and fallback if shader creation fails. */
 @androidx.annotation.RequiresApi(33) public static RenderEffect create(float radius) {
  RenderEffect result=null;
  for(float offset:offsets(radius)) {
   RuntimeShader shader=new RuntimeShader("uniform shader backdrop; uniform float distance; half4 main(float2 p) { half4 sum=backdrop.eval(p); for(int y=-1;y<=1;y+=2) { for(int x=-1;x<=1;x+=2) { sum+=backdrop.eval(p+float2(x,y)*distance); } } return sum/5.0; }");
   shader.setFloatUniform("distance",offset);
   RenderEffect pass=RenderEffect.createRuntimeShaderEffect(shader,"backdrop");
   result=result==null?pass:RenderEffect.createChainEffect(pass,result);
  }
  return result;
 }
}

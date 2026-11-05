package com.nodecockpit.customization;

import android.graphics.*;
/** Android's native blur filter on a reduced-resolution owned backdrop, before glass shading.
 * Android 13+, hardware Canvas only. The caller records background content, never foreground.
 * Radius is in full-resolution pixels. This is not a replica of a device-specific SF filter.
 */
@androidx.annotation.RequiresApi(31)
public final class GlassBackdropBlur implements AutoCloseable {
 public interface Recorder { void draw(Canvas canvas); }
 private final RenderNode reduced=new RenderNode("GlassBackdropBlurReduced");
 private float previousRadius=-1;
 @androidx.annotation.RequiresApi(26) public static int reducedSize(int size) { return Math.max(1,(int)Math.ceil(Math.max(0,size)/4.0)); }
 public void draw(Canvas output,int width,int height,float radius,float mix,Recorder recorder) {
  if(!output.isHardwareAccelerated())throw new IllegalArgumentException("Hardware canvas required");
  if(width<=0||height<=0)return;
  radius=Float.isFinite(radius)?Math.max(0,Math.min(150,radius)):0;
  mix=Float.isFinite(mix)?Math.max(0,Math.min(1,mix)):0;
  if(radius==0||mix==0){recorder.draw(output);return;}
  int w=reducedSize(width),h=reducedSize(height);
  reduced.setPosition(0,0,w,h);
  if(previousRadius!=radius){reduced.setRenderEffect(RenderEffect.createBlurEffect(radius/4f,radius/4f,Shader.TileMode.CLAMP));previousRadius=radius;}
  Canvas c=reduced.beginRecording(w,h);
  try {c.scale(.25f,.25f);recorder.draw(c);}finally{reduced.endRecording();}
  if(mix<1)recorder.draw(output);
  int save=output.save();
  try {output.clipRect(0,0,width,height);output.scale(4f,4f);reduced.setAlpha(mix);output.drawRenderNode(reduced);}finally{output.restoreToCount(save);}
 }
 @Override public void close(){reduced.discardDisplayList();reduced.setRenderEffect(null);previousRadius=-1;}
}

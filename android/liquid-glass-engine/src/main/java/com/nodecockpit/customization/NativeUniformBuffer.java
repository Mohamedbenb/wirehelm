package com.nodecockpit.customization;

import android.graphics.*;
import android.hardware.*;
import android.media.*;
import android.os.Handler;
import android.view.*;
/** A single GPU-cleared transparent buffer, retained and reposted without writes.
 * New submissions change the effect layer frame number, which the composition cache observes.
 * No application/background pixels are acquired. No producer loop or buffer copies.
 */
@androidx.annotation.RequiresApi(33)
final class NativeUniformBuffer implements AutoCloseable {
 private final Handler handler;private final Runnable timeout;private boolean delivered;
 private ImageReader reader;private Image image;private HardwareBuffer buffer;private SyncFence fence;private Throwable error;private boolean closed;int frames;
 NativeUniformBuffer(int w,int h,Handler handler,Runnable ready){
  this.handler=handler;timeout=()->{if(!closed&&!delivered){error=new IllegalStateException("Owned clear-buffer readiness timeout");delivered=true;if(reader!=null)reader.setOnImageAvailableListener(null,null);ready.run();}};handler.postDelayed(timeout,1500);
  try{reader=ImageReader.newInstance(w,h,PixelFormat.RGBA_8888,2,HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE|HardwareBuffer.USAGE_GPU_COLOR_OUTPUT);
   reader.setOnImageAvailableListener(r->{if(closed)return;try{image=r.acquireLatestImage();if(image==null)return;buffer=image.getHardwareBuffer();fence=image.getFence();if(buffer==null||(buffer.getUsage()&HardwareBuffer.USAGE_PROTECTED_CONTENT)!=0)throw new IllegalStateException("Invalid owned transparent buffer");}catch(Throwable e){error=e;}finally{r.setOnImageAvailableListener(null,null);handler.removeCallbacks(timeout);if(!delivered){delivered=true;ready.run();}}},handler);
   Surface producer=reader.getSurface();Canvas c=producer.lockHardwareCanvas();try{c.drawColor(Color.TRANSPARENT,PorterDuff.Mode.CLEAR);}finally{producer.unlockCanvasAndPost(c);}
  }catch(Throwable e){error=e;handler.removeCallbacks(timeout);if(!delivered){delivered=true;ready.run();}}
 }
 boolean ready(){return buffer!=null||error!=null;}
 void append(SurfaceControl.Transaction t,SurfaceControl layer,Rect damage){if(closed||error!=null||buffer==null)throw new IllegalStateException("Owned buffer unavailable",error);t.setBuffer(layer,buffer,fence);t.setDamageRegion(layer,new Region(damage));frames++;}
 public void close(){if(closed)return;closed=true;handler.removeCallbacks(timeout);if(reader!=null)reader.setOnImageAvailableListener(null,null);if(fence!=null){fence.close();fence=null;}if(buffer!=null){buffer.close();buffer=null;}if(image!=null){image.close();image=null;}if(reader!=null){reader.close();reader=null;}}
}

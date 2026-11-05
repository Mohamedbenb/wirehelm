package com.nodecockpit.customization;
import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Build;
import android.os.Handler;
import android.view.FrameMetrics;
import android.view.View;
import android.view.Window;
/** Public host-window frame metrics. No hidden API or display-presentation FPS claim. */
final class GlassFrameObserver implements AutoCloseable {
 final GlassFrameStats stats=new GlassFrameStats();
 private Window window; private Window.OnFrameMetricsAvailableListener listener;
 private boolean closed; private String unavailable="waiting";
 GlassFrameObserver(View root,Handler handler){try{
  Context context=root.getContext();Activity activity=null;
  for(int i=0;i<16;i++){
   if(context instanceof Activity){activity=(Activity)context;break;}
   if(!(context instanceof ContextWrapper))break;
   Context next=((ContextWrapper)context).getBaseContext();if(next==context)break;context=next;
  }
  if(activity==null)throw new IllegalStateException("Host Activity unavailable");
  window=activity.getWindow();
  listener=(host,metrics,drops)->{
   if(closed)return;
   long gpu=Build.VERSION.SDK_INT>=31?metrics.getMetric(FrameMetrics.GPU_DURATION):-1;
   long deadline=Build.VERSION.SDK_INT>=31?metrics.getMetric(FrameMetrics.DEADLINE):-1;
   stats.frame(0,gpu,metrics.getMetric(FrameMetrics.TOTAL_DURATION),deadline,drops);
  };
  window.addOnFrameMetricsAvailableListener(listener,handler);unavailable=null;
 }catch(RuntimeException failure){unavailable="unavailable";close();}}
 String snapshot(double seconds){return unavailable==null?stats.windowSnapshot():"Host-window frame metrics: "+unavailable;}
 public void close(){if(closed)return;closed=true;if(window!=null&&listener!=null)window.removeOnFrameMetricsAvailableListener(listener);listener=null;window=null;}
}
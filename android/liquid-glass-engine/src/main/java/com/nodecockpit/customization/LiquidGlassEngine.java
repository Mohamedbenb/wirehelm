package com.nodecockpit.customization;
import android.view.View;
/** Public host API. Calls and disposal belong to the host View's UI thread. */
public final class LiquidGlassEngine {
 public static final int API_VERSION=1;
 public static final String VERSION="1.5.2-dev";
 private LiquidGlassEngine(){}
 private static void requireRadius(float radius){if(!Float.isFinite(radius)||radius<0)throw new IllegalArgumentException("Radius must be finite and nonnegative");}
 private static void requireUiThread(){if(android.os.Looper.myLooper()!=android.os.Looper.getMainLooper())throw new IllegalStateException("Glass sessions require the UI thread");}
 /** Attach compositor optics to a caller-owned view. Unsupported backends retain host drawing. */
 @androidx.annotation.RequiresApi(33)
 public static Session attach(View host,String configuration,float radius,Runnable changed){
  requireUiThread();requireRadius(radius);
  if(android.os.Build.VERSION.SDK_INT<33)throw new UnsupportedOperationException("Compositor backend requires Android 13+");
  if(host==null||changed==null)throw new IllegalArgumentException("Host and invalidation callback required");
  if(!NativeLiquidConfig.valid(configuration))throw new IllegalArgumentException("Invalid material configuration");
  return new Session(host,configuration,radius,changed);
 }
 @androidx.annotation.RequiresApi(33)
 public static final class Session implements AutoCloseable {
  private final EdgeMaterialSurface surface;private final boolean card;private boolean closed;
  private Session(View host,String raw,float radius,Runnable changed){NativeLiquidConfig c=new NativeLiquidConfig(raw);if(!c.enabled)throw new IllegalArgumentException("Compositor session requires native backend configuration");card=c.card;surface=c.card?new CardLiquidSurface(host,"glass-engine",radius,c,changed):new NativeLiquidSurface(host,"glass-engine",radius,c,changed);}
  public boolean active(){return !closed&&surface.active();}
  public String diagnostics(){return closed?"closed":surface.diagnostics();}
  public void configure(String raw,float radius){requireUiThread();requireRadius(radius);if(closed)throw new IllegalStateException("Session closed");if(!NativeLiquidConfig.valid(raw))throw new IllegalArgumentException("Invalid material configuration");NativeLiquidConfig next=new NativeLiquidConfig(raw);if(!next.enabled)throw new IllegalArgumentException("Close the session to disable its native backend");if(next.card!=card)throw new IllegalArgumentException("Create a new session to switch renderer families");surface.configure(next,radius);}
  @Override public void close(){requireUiThread();if(closed)return;closed=true;surface.close();}
 }
}

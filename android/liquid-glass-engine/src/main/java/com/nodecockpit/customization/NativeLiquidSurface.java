package com.nodecockpit.customization;

import android.content.Context;
import android.graphics.*;
import android.os.*;
import android.view.*;
import java.lang.reflect.*;
import java.util.Arrays;

/** Owned buffer-backed compositor material. No capture, sampling, worker or frame polling.
 * Geometry is queued on the same root draw transaction as native foreground rendering.
 * Hidden APIs are used only after capability and permission checks; failures retain legacy.
 */
@androidx.annotation.RequiresApi(33)
final class NativeLiquidSurface implements ViewTreeObserver.OnPreDrawListener, View.OnAttachStateChangeListener, EdgeMaterialSurface {
 private static android.os.IBinder shader;
 private static int users,registrations,failures;private static boolean backendEnabled; private static Method post,unregister;
 private final View view; private final String name; private final Runnable changed;
 private NativeLiquidConfig config; private SurfaceControl layer;private Surface surface;private Object queue;
 private volatile SurfaceControl.Transaction firstBuffer;private volatile int generation;private boolean waitingBuffer;
 private int width,height;private float radius;private volatile boolean closed;private boolean active,failed;private byte[] lastUniforms;private String lastGeometry="";
 private int transactions;private String error="";
 private android.os.PowerManager power;private android.os.PowerManager.OnThermalStatusChangedListener thermalListener;
 NativeLiquidSurface(View view,String name,float radius,NativeLiquidConfig config,Runnable changed){this.view=view;this.name=name;this.radius=radius;this.config=config;this.changed=changed;if(failures>=3){failed=true;error="Circuit open after three attachment failures; select Legacy then Native to retry";return;}power=view.getContext().getSystemService(android.os.PowerManager.class);
 if(power==null||power.getCurrentThermalStatus()>=2){failed=true;error="Native material deferred at thermal status 2+";return;}
 thermalListener=status -> {if(status>=2){close();changed.run();}};
 try{power.addThermalStatusListener(view.getContext().getMainExecutor(),thermalListener);}catch(RuntimeException e){thermalListener=null;failed=true;error="Thermal observer unavailable: "+e;return;}
 view.addOnAttachStateChangeListener(this);view.getViewTreeObserver().addOnPreDrawListener(this);view.invalidate();}
 public void configure(NativeLiquidConfig c,float r){config=c;radius=r;lastGeometry="";view.invalidate();}
 static void resetCircuit(){failures=0;}
 static void setBackendEnabled(boolean enabled){backendEnabled=enabled;releaseShader();}
 public boolean active(){return active&&!closed&&!failed;}
 public String diagnostics(){return name+":"+(active()?"active":failed?"fallback":"pending")+",geometry="+lastGeometry+",tx="+transactions+",registrations="+registrations+",error="+error;}
 static Object call(Object o,String n,Class<?>[] types,Object... args)throws Exception{return o.getClass().getMethod(n,types).invoke(o,args);}
 private void acquire()throws Exception {
  if(view.getContext().checkSelfPermission("android.permission.READ_FRAME_BUFFER")!=android.content.pm.PackageManager.PERMISSION_GRANTED)throw new SecurityException("READ_FRAME_BUFFER required");
  if(shader==null){post=SurfaceControl.Transaction.class.getMethod("setPostProcess",SurfaceControl.class,android.os.IBinder.class,byte[].class,int.class);unregister=SurfaceControl.class.getMethod("unregisterShader",android.os.IBinder.class);
   if(SurfaceControl.Transaction.class.getField("SAMPLE_BEHIND").getInt(null)!=1)throw new IllegalStateException("Unsupported backdrop contract");
   shader=(android.os.IBinder)SurfaceControl.class.getMethod("registerShader",String.class,String.class).invoke(null,"Vector.NativeLiquid.v1",NativeLiquidMaterial.SHADER);if(shader==null)throw new IllegalStateException("Shader rejected");registrations++;
  }users++;
 }
 private void create(int w,int h)throws Exception {
  if(Build.VERSION.SDK_INT<31)throw new UnsupportedOperationException("AttachedSurfaceControl unavailable");
  AttachedSurfaceControl root=view.getRootSurfaceControl();if(root==null)return;
  acquire();boolean owned=false;
  try{
   Object b=Class.forName("android.view.SurfaceControl$Builder").getConstructor().newInstance();
   call(b,"setName",new Class[]{String.class},"VectorLiquid-"+name);call(b,"setOpaque",new Class[]{boolean.class},false);call(b,"setBufferSize",new Class[]{int.class,int.class},w,h);layer=(SurfaceControl)call(b,"build",new Class[]{});owned=true;
   queue=Class.forName("android.graphics.BLASTBufferQueue").getConstructor(String.class,boolean.class).newInstance("VectorLiquid-"+name,true);
   call(queue,"update",new Class[]{SurfaceControl.class,int.class,int.class,int.class},layer,w,h,PixelFormat.RGBA_8888);surface=(Surface)call(queue,"createSurface",new Class[]{});
   final int request=++generation;waitingBuffer=true;
   java.util.function.Consumer<SurfaceControl.Transaction> consumer=t -> {if(closed||request!=generation){t.close();return;}firstBuffer=t;view.postInvalidateOnAnimation();};
   Method sync=null;for(Method m:queue.getClass().getMethods())if(m.getName().equals("syncNextTransaction")&&Arrays.asList(m.getParameterTypes()).contains(java.util.function.Consumer.class)&&(sync==null||m.getParameterCount()<sync.getParameterCount()))sync=m;
   if(sync==null)throw new NoSuchMethodException("BLAST first-buffer synchronization unavailable");
   Class<?>[] types=sync.getParameterTypes();Object[] args=new Object[types.length];for(int i=0;i<types.length;i++){if(types[i]==java.util.function.Consumer.class)args[i]=consumer;else if(types[i]==boolean.class)args[i]=true;else throw new NoSuchMethodException("Unsupported BLAST synchronization parameter");}
   if(!((Boolean)sync.invoke(queue,args)))throw new IllegalStateException("BLAST synchronization rejected");
   Canvas canvas=surface.lockCanvas(null);try{canvas.drawColor(Color.TRANSPARENT,PorterDuff.Mode.CLEAR);}finally{surface.unlockCanvasAndPost(canvas);}
   width=w;height=h;view.postInvalidateOnAnimation();
  }catch(Throwable e){if(!owned){users--;releaseShader();}throw e;}
 }
 @Override public boolean onPreDraw(){if(closed||failed)return true;
  try{
   if(!view.isAttachedToWindow()||view.getWidth()<1||view.getHeight()<1)return true;
   int w=view.getWidth(),h=view.getHeight();if(w>2400||h>4000)throw new IllegalArgumentException("Region exceeds safety bounds");
   if(layer!=null&&(w!=width||h!=height)){destroy();lastUniforms=null;lastGeometry="";}
   if(layer==null)create(w,h);if(layer==null||(waitingBuffer&&firstBuffer==null))return true;
   AttachedSurfaceControl root=view.getRootSurfaceControl();if(root==null)throw new IllegalStateException("Root surface lost");
   int[] pos=new int[2];view.getLocationInWindow(pos);Rect clip=new Rect();boolean shown=view.getLocalVisibleRect(clip)&&view.isShown();float alpha=1;View ancestor=view;while(true){alpha*=ancestor.getAlpha();if(!(ancestor.getParent() instanceof View))break;ancestor=(View)ancestor.getParent();}
   if(!shown)clip.setEmpty();
   byte[] uniforms=NativeLiquidMaterial.uniforms(w,h,radius,config);String geometry=pos[0]+":"+pos[1]+":"+clip+":"+alpha+":"+shown+":"+radius;
   if(geometry.equals(lastGeometry)&&Arrays.equals(uniforms,lastUniforms))return true;
   boolean first=waitingBuffer;SurfaceControl.Transaction t=first?firstBuffer:new SurfaceControl.Transaction();
   if(first){firstBuffer=null;waitingBuffer=false;Method rootMethod=View.class.getDeclaredMethod("getViewRootImpl");rootMethod.setAccessible(true);Object vri=rootMethod.invoke(view);
    SurfaceControl parent=(SurfaceControl)vri.getClass().getMethod("getSurfaceControl").invoke(vri);
    if(parent==null||!parent.isValid()){t.close();throw new IllegalStateException("Owned root buffer unavailable");}
    // buildReparentTransaction uses a positive-z Bounds layer, above native foreground.
    // A direct negative child of our own buffer composes BEFORE that foreground instead.
    t.reparent(layer,parent).setLayer(layer,-1);}
   SurfaceControl.Transaction.class.getMethod("setDestinationFrame",SurfaceControl.class,Rect.class).invoke(t,layer,new Rect());
   t.setPosition(layer,pos[0],pos[1]).setCrop(layer,clip).setAlpha(layer,alpha).setVisibility(layer,shown&&alpha>.001f);SurfaceControl.Transaction.class.getMethod("setCornerRadius",SurfaceControl.class,float.class).invoke(t,layer,radius);
   if(!Arrays.equals(uniforms,lastUniforms))post.invoke(t,layer,shader,uniforms,1);
   if(!root.applyTransactionOnDraw(t)){t.close();throw new IllegalStateException("Geometry synchronization rejected");}t.close();transactions++;lastGeometry=geometry;lastUniforms=uniforms;if(first){active=true;changed.run();}view.postInvalidateOnAnimation();
  }catch(Throwable e){Throwable x=e instanceof InvocationTargetException&&e.getCause()!=null?e.getCause():e;error=x.toString();failed=true;failures++;android.util.Log.w("VectorLiquid",name+" using legacy",x);destroy();changed.run();}
  return true;
 }
 private static void releaseShader(){if(users==0&&!backendEnabled&&shader!=null){try{unregister.invoke(null,shader);}catch(Throwable e){android.util.Log.w("VectorLiquid","Unregister failed",e);}shader=null;}}
 private void destroy(){generation++;waitingBuffer=false;SurfaceControl.Transaction pending=firstBuffer;firstBuffer=null;if(pending!=null)pending.close();active=false;if(layer!=null){try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){if(post!=null)post.invoke(t,layer,null,null,0);t.setVisibility(layer,false).reparent(layer,null).apply();}catch(Throwable e){android.util.Log.w("VectorLiquid","Teardown",e);}layer.release();layer=null;users=Math.max(0,users-1);releaseShader();}if(surface!=null){surface.release();surface=null;}if(queue!=null){try{call(queue,"destroy",new Class[]{});}catch(Exception ignored){}queue=null;}}
 @Override public void close(){if(closed)return;closed=true;if(power!=null&&thermalListener!=null){power.removeThermalStatusListener(thermalListener);thermalListener=null;}if(view.getViewTreeObserver().isAlive())view.getViewTreeObserver().removeOnPreDrawListener(this);view.removeOnAttachStateChangeListener(this);destroy();}
 @Override public void onViewAttachedToWindow(View v){}
 @Override public void onViewDetachedFromWindow(View v){close();}
}


package com.nodecockpit.customization;
import android.content.*;
import android.graphics.*;
import android.hardware.*;
import android.os.*;
import android.view.*;
import java.lang.reflect.*;
import java.util.*;
/** Card optics behind existing native edge foreground. Geometry uses its root draw transaction. */
@androidx.annotation.RequiresApi(33)
final class CardLiquidSurface implements EdgeMaterialSurface,ViewTreeObserver.OnPreDrawListener,View.OnAttachStateChangeListener,Choreographer.FrameCallback {
 interface Region {default void prepareFrame(){}default void frameSubmitted(){}default void frameUnavailable(){}default float[][] systemBlurRegions(){return new float[0][];}default int systemBlurCapacity(){return 0;}default void frame(Rect bounds){}float alpha();void clip(Rect bounds);int order();default boolean cluster(){return false;}default boolean quickSettings(){return false;}default byte[] uniforms(byte[] base){return null;}default int maxPixels(){return 2000000;}}
 static final class SystemBlurRegion { final float left,top,right,bottom;final int radius;SystemBlurRegion(float l,float t,float r,float b,int px){left=l;top=t;right=r;bottom=b;radius=px;} }
 private GlassPerformanceHud.Lease hud;
 private final Region region;private final boolean clustered;private IBinder materialShader;
 private static IBinder shader,clusterShader,qsShader;private static final GlassShaderLease qsLease=new GlassShaderLease();private static final GlassShaderLease baseLease=new GlassShaderLease(),unionLease=new GlassShaderLease();private static int failures,notificationFailures,qsFailures;private static boolean qsSelected;private static Method post;
 static synchronized void setQuickSettingsBackendEnabled(boolean enabled){if(enabled&&!qsSelected)qsFailures=0;qsSelected=enabled;qsLease.pin(1,enabled);releaseShader();}
 static void resetCircuit(){failures=0;}
 static synchronized void setNotificationBackendEnabled(boolean value){baseLease.pin(2,value);unionLease.pin(2,value);releaseShader();}
 static void resetNotificationCircuit(){notificationFailures=0;}
 static synchronized void setBackendEnabled(boolean enabled){baseLease.pin(1,enabled);releaseShader();}
 private final View view;private final String name;private final Runnable changed;private final Handler main=new Handler(Looper.getMainLooper());
 private NativeLiquidConfig config;private float radius;private SurfaceControl lens,blur;private SurfaceControl[] regionBlur=new SurfaceControl[0];private final boolean[] regionBlurKnown=new boolean[16],regionBlurShown=new boolean[16];private final float[][] regionBlurBounds=new float[16][];private final float[] regionBlurAlpha=new float[16];private NativeUniformBuffer buffer;
 private boolean closed,failed,active,thermalPaused,framePosted,screenOff,acquired,thermalRegistered,receiverRegistered;private int width,height,generation;private String error="",lastGeometry="",lastBlurGeometry="";private byte[] last;
 private final NativeSurfaceReadiness rootReadiness=new NativeSurfaceReadiness();
 private boolean touching;private float press,target,tx,ty;private long lastFrame;private final CardRippleTimeline timeline=new CardRippleTimeline();private final float[] waves=timeline.values;private int transactions;
 private final PowerManager power;private final PowerManager.OnThermalStatusChangedListener thermal;
 private final BroadcastReceiver receiver=new BroadcastReceiver(){public void onReceive(Context c,Intent i){screenOff=Intent.ACTION_SCREEN_OFF.equals(i.getAction())||!power.isInteractive();if(screenOff)rootReadiness.ready();if(screenOff||power.isPowerSaveMode()){stopMotion();Light.remove(CardLiquidSurface.this);}view.invalidate();}};
 CardLiquidSurface(View v,String n,float r,NativeLiquidConfig c,Runnable change){this(v,n,r,c,change,null);}
 CardLiquidSurface(View v,String n,float r,NativeLiquidConfig c,Runnable change,Region region){this.region=region;this.clustered=region!=null&&region.cluster();view=v;name=n;radius=r;config=c;changed=change;power=v.getContext().getSystemService(PowerManager.class);clearWaves();
  thermal=status->{if(closed)return;thermalPaused=status>=2;if(thermalPaused){stopMotion();Light.remove(this);destroy();}changed.run();view.invalidate();};
  if((region==null?failures:region.quickSettings()?qsFailures:notificationFailures)>=3||power==null){failed=true;error="Card optics unavailable/circuit/thermal";return;}
  try{thermalPaused=power.getCurrentThermalStatus()>=2;screenOff=!power.isInteractive();power.addThermalStatusListener(v.getContext().getMainExecutor(),thermal);thermalRegistered=true;
  IntentFilter f=new IntentFilter();f.addAction(Intent.ACTION_SCREEN_OFF);f.addAction(Intent.ACTION_SCREEN_ON);f.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);v.getContext().registerReceiver(receiver,f);receiverRegistered=true;
  v.addOnAttachStateChangeListener(this);v.getViewTreeObserver().addOnPreDrawListener(this);v.invalidate();}catch(Throwable e){failed=true;error=e.toString();if(region==null)failures++;else if(region.quickSettings())qsFailures++;else notificationFailures++;detachObservers();android.util.Log.w("VectorCard","Observer initialization; material unavailable",e);}
 }
 public void configure(NativeLiquidConfig c,float r){config=c;radius=r;if(!c.cardOptions.optBoolean("touchRipples"))clearWaves();if(!c.cardOptions.optBoolean("pressEffects",true))press=target=0;lastGeometry="";lastBlurGeometry="";view.invalidate();}
 public boolean active(){return active&&!failed&&!closed&&!thermalPaused;}
 public String diagnostics(){return name+":card="+(active()?"active":failed?"unavailable":"pending")+",tx="+transactions+",error="+error;}
 private boolean motion(){return !closed&&!failed&&!screenOff&&power!=null&&power.isInteractive()&&!power.isPowerSaveMode()&&android.animation.ValueAnimator.areAnimatorsEnabled();}
 public void touch(MotionEvent e){if(!motion())return;int[] pos=new int[2];view.getLocationOnScreen(pos);float x=e.getRawX()-pos[0],y=e.getRawY()-pos[1];int action=e.getActionMasked();
  if(action==MotionEvent.ACTION_DOWN&&view instanceof GlassMergeGeometry&&!((GlassMergeGeometry)view).hit(e.getRawX(),e.getRawY()))return;
  if(action==MotionEvent.ACTION_DOWN&&(x<0||y<0||x>view.getWidth()||y>view.getHeight()))return;
  if(action==MotionEvent.ACTION_DOWN)touching=true;else if(action==MotionEvent.ACTION_UP&&!touching)return;
  if(action==MotionEvent.ACTION_UP)touching=false;
  tx=Math.max(0,Math.min(view.getWidth(),x));ty=Math.max(0,Math.min(view.getHeight(),y));
  if(action==MotionEvent.ACTION_CANCEL){stopMotion();view.invalidate();return;}
  if(action==MotionEvent.ACTION_DOWN||action==MotionEvent.ACTION_UP){
   if(config.cardOptions.optBoolean("pressEffects",true))target=action==MotionEvent.ACTION_DOWN?1:0;
   if(config.cardOptions.optBoolean("touchRipples")&&CardLiquidParameters.n(config.cardOptions,"rippleStrength",.5,0,1)>0){timeline.emit(tx/Math.max(1,view.getWidth()),ty/Math.max(1,view.getHeight()),SystemClock.uptimeMillis(),action==MotionEvent.ACTION_UP);}
   requestFrame();
  }else if(target>0)view.invalidate();
 }
 private void requestFrame(){if(!framePosted){framePosted=true;Choreographer.getInstance().postFrameCallback(this);}}
 public void doFrame(long ns){framePosted=false;if(!motion()){stopMotion();view.invalidate();return;}long now=ns/1000000;float dt=lastFrame==0?1f/60:Math.min(.1f,Math.max(0,(now-lastFrame)/1000f));lastFrame=now;
  press+=(target-press)*(1-(float)Math.exp(-dt/(target>0?.06f:.107f)));if(Math.abs(target-press)<.002f)press=target;
  boolean moving=press!=target;float life=CardLiquidParameters.lifetime(config.cardOptions);
  moving|=timeline.advance(now,life);
  view.invalidate();if(moving)requestFrame();else lastFrame=0;
 }
 private void clearWaves(){timeline.clear();}
 private void stopMotion(){touching=false;if(framePosted)Choreographer.getInstance().removeFrameCallback(this);framePosted=false;lastFrame=0;press=target=0;clearWaves();}
 private static Object call(Object o,String n,Class<?>[] types,Object... a)throws Exception{return o.getClass().getMethod(n,types).invoke(o,a);}
 static synchronized IBinder acquire(boolean cluster,boolean qs)throws Exception{
  if(post==null)post=SurfaceControl.Transaction.class.getMethod("setPostProcess",SurfaceControl.class,IBinder.class,byte[].class,int.class);
  if(qs){if(qsShader==null)qsShader=(IBinder)SurfaceControl.class.getMethod("registerShader",String.class,String.class).invoke(null,"Vector.QsUnion.v4",NativeQsShader.SOURCE);if(qsShader==null)throw new IllegalStateException("QS shader rejected");qsLease.acquire();return qsShader;}
  if(cluster){if(clusterShader==null)clusterShader=(IBinder)SurfaceControl.class.getMethod("registerShader",String.class,String.class).invoke(null,"Vector.NotificationUnion.v7",CardNotificationShader.SOURCE);if(clusterShader==null)throw new IllegalStateException("Notification union shader rejected");unionLease.acquire();return clusterShader;}
  if(shader==null)shader=(IBinder)SurfaceControl.class.getMethod("registerShader",String.class,String.class).invoke(null,"Vector.CardLens.Merge.v4",CardLiquidMergeShader.SOURCE);if(shader==null)throw new IllegalStateException("Card shader rejected");baseLease.acquire();return shader;
 }
 static synchronized void release(boolean cluster,boolean qs){if(qs)qsLease.release();else if(cluster)unionLease.release();else baseLease.release();releaseShader();}
 private static void unregister(IBinder token){try{SurfaceControl.class.getMethod("unregisterShader",IBinder.class).invoke(null,token);}catch(Throwable e){android.util.Log.w("VectorCard","Shader cleanup",e);}}
 private static void releaseShader(){if(qsLease.canUnregister()&&qsShader!=null){unregister(qsShader);qsShader=null;}if(baseLease.canUnregister()&&shader!=null){unregister(shader);shader=null;}if(unionLease.canUnregister()&&clusterShader!=null){unregister(clusterShader);clusterShader=null;}}
 private SurfaceControl layer(String suffix)throws Exception{Object b=Class.forName("android.view.SurfaceControl$Builder").getConstructor().newInstance();call(b,"setName",new Class[]{String.class},"VectorCard-"+name+suffix);call(b,"setOpaque",new Class[]{boolean.class},false);call(b,"setBufferSize",new Class[]{int.class,int.class},width,height);return (SurfaceControl)call(b,"build",new Class[]{});}
 public boolean onPreDraw(){if(closed||failed||thermalPaused)return true;long prepareAt=System.nanoTime();try{
  if(!view.isAttachedToWindow()||view.getWidth()<2||view.getHeight()<2){if(region!=null)region.frameUnavailable();if(active)destroy();return true;}boolean qsFrame=region!=null&&region.quickSettings();if(qsFrame){region.prepareFrame();if(last==null&&region.alpha()<=.001f)return true;}
  boolean merged=view instanceof GlassMergeGeometry&&((GlassMergeGeometry)view).merging();boolean shaped=merged||region!=null&&region.cluster();
  int w=view.getWidth(),h=view.getHeight();if(w>2400||h>4000||(long)w*h>(merged?4000000:region==null?2000000:region.maxPixels()))throw new IllegalStateException("Owned material bounds exceeded");
  if(buffer!=null&&(w!=width||h!=height)){destroy();stopMotion();}
  if(buffer==null){if(view.getContext().checkSelfPermission("android.permission.READ_FRAME_BUFFER")!=android.content.pm.PackageManager.PERMISSION_GRANTED)throw new SecurityException("READ_FRAME_BUFFER required");materialShader=acquire(clustered,region!=null&&region.quickSettings());acquired=true;width=w;height=h;if(!clustered)blur=layer("-preblur");lens=layer("-lens");if(region!=null&&region.systemBlurCapacity()>0){int count=Math.max(0,Math.min(16,region.systemBlurCapacity()));regionBlur=new SurfaceControl[count];for(int i=0;i<count;i++)regionBlur[i]=layer("-region-blur-"+i);}final int g=++generation;buffer=new NativeUniformBuffer(w,h,main,()->{if(!closed&&g==generation)view.postInvalidateOnAnimation();});return true;}
  if(!buffer.ready())return true;AttachedSurfaceControl root=view.getRootSurfaceControl();if(root==null){if(region!=null)region.frameUnavailable();if(active)destroy();return true;}
  if(region!=null&&!qsFrame)region.prepareFrame();Rect frame=new Rect(0,0,w,h);if(region!=null)region.frame(frame);int[] pos=new int[2];view.getLocationInWindow(pos);Rect clip=new Rect();boolean shown=!screenOff&&view.getLocalVisibleRect(clip)&&view.isShown();float alpha=1;View a=view;while(true){alpha*=a.getAlpha();if(!(a.getParent() instanceof View))break;a=(View)a.getParent();}
  if(region!=null){alpha*=Math.max(0,Math.min(1,region.alpha()));region.clip(clip);if(alpha<=.001f||clip.isEmpty())shown=false;}
  if(merged)((GlassMergeGeometry)view).crop(clip);
  if(frame.isEmpty()||!clip.intersect(frame)){shown=false;clip.setEmpty();}else clip.offset(-frame.left,-frame.top);pos[0]+=frame.left;pos[1]+=frame.top;int materialWidth=Math.max(1,frame.width()),materialHeight=Math.max(1,frame.height());
  if(config.performanceOverlay&&GlassPerformanceHud.enabled&&shown&&alpha>.001f){if(hud==null||!hud.active())hud=GlassPerformanceHud.acquire(view.getRootView(),clustered?1:2);}else if(hud!=null){hud.close();hud=null;}
  if(!shown){clip.setEmpty();stopMotion();}if(hud!=null)hud.allocation((long)width*height*4,(long)clip.width()*clip.height()*(clustered?1:2));if(shown&&motion()&&config.cardOptions.optBoolean("sensorLighting",true))Light.add(this);else Light.remove(this);
  float r=Math.min(radius,Math.min(materialWidth,materialHeight)/2f);float lx=config.cardOptions.optBoolean("sensorLighting",true)?Light.x:-.577f,ly=config.cardOptions.optBoolean("sensorLighting",true)?Light.y:-.817f;
  byte[] base=CardLiquidParameters.uniforms(materialWidth,materialHeight,r,config.cardOptions,lx,ly,press,tx,ty,waves);
  byte[] u=region!=null&&region.cluster()?region.uniforms(base):CardMergeUniforms.extend(base,merged?((GlassMergeGeometry)view).shapes(CardLiquidParameters.blur(config.cardOptions),CardLiquidParameters.mix(config.cardOptions)):null);String geometry=pos[0]+":"+pos[1]+":"+clip+":"+alpha+":"+shown+":"+r;
  float[][] systemBlur=region==null?new float[0][]:region.systemBlurRegions();if(systemBlur.length>regionBlur.length)throw new IllegalArgumentException("System blur region capacity exceeded");for(float[] b:systemBlur)if(b.length!=5||!Float.isFinite(b[0])||!Float.isFinite(b[1])||!Float.isFinite(b[2])||!Float.isFinite(b[3])||!Float.isFinite(b[4])||b[2]<=0||b[3]<=0||b[4]<0)throw new IllegalArgumentException("Invalid system blur region");String blurGeometry=Arrays.deepToString(systemBlur);boolean update=!Arrays.equals(last,u);if(!update&&geometry.equals(lastGeometry)&&blurGeometry.equals(lastBlurGeometry)){if(region!=null){if(shown)region.frameSubmitted();else region.frameUnavailable();}return true;}
  SurfaceControl.Transaction t=new SurfaceControl.Transaction();try{
   if(last==null){Method m=View.class.getDeclaredMethod("getViewRootImpl");m.setAccessible(true);Object vri=m.invoke(view);SurfaceControl parent=vri==null?null:(SurfaceControl)vri.getClass().getMethod("getSurfaceControl").invoke(vri);if(parent==null||!parent.isValid()){if(waitForOwnedRoot())return true;throw new IllegalStateException("Owned root unavailable");}rootReadiness.ready();int order=region==null?-1:region.order();if(blur!=null)t.reparent(blur,parent).setLayer(blur,order-1);for(int i=0;i<regionBlur.length;i++)if(regionBlur[i]!=null)t.reparent(regionBlur[i],parent).setLayer(regionBlur[i],order-100-i);t.reparent(lens,parent).setLayer(lens,order);}
   for(SurfaceControl sc:(blur==null?new SurfaceControl[]{lens}:new SurfaceControl[]{blur,lens})){call(t,"setDestinationFrame",new Class[]{SurfaceControl.class,Rect.class},sc,new Rect());t.setPosition(sc,pos[0],pos[1]).setCrop(sc,clip).setAlpha(sc,alpha).setVisibility(sc,shown&&alpha>.001f);call(t,"setCornerRadius",new Class[]{SurfaceControl.class,float.class},sc,shaped?0:r);if(update)buffer.append(t,sc,new Rect(0,0,w,h));}
   int nativeRadius=shaped?0:Math.round(CardLiquidParameters.blur(config.cardOptions));float nativeMix=shaped?0:CardLiquidParameters.mix(config.cardOptions);
   if(blur!=null){t.setAlpha(blur,alpha*nativeMix);call(t,"setBackgroundBlurRadius",new Class[]{SurfaceControl.class,int.class},blur,nativeRadius);}
   for(int i=0;i<regionBlur.length;i++){SurfaceControl sc=regionBlur[i];float[] b=i<systemBlur.length?systemBlur[i]:null;boolean visible=b!=null&&shown&&alpha>.001f;boolean same=regionBlurKnown[i]&&visible==regionBlurShown[i]&&(!visible||(Arrays.equals(b,regionBlurBounds[i])&&Float.compare(alpha,regionBlurAlpha[i])==0));if(sc!=null&&!same){if(visible){float l=b[0],top=b[1],rw=b[2]-b[0],rh=b[3]-b[1];t.setPosition(sc,pos[0]+l,pos[1]+top).setCrop(sc,new Rect(0,0,Math.max(1,(int)Math.ceil(rw)),Math.max(1,(int)Math.ceil(rh)))).setAlpha(sc,alpha).setVisibility(sc,true);call(t,"setCornerRadius",new Class[]{SurfaceControl.class,float.class},sc,Math.min(rw,rh)/2);call(t,"setBackgroundBlurRadius",new Class[]{SurfaceControl.class,int.class},sc,Math.round(b[4]));regionBlurBounds[i]=b.clone();}else{t.setAlpha(sc,0).setVisibility(sc,false);call(t,"setBackgroundBlurRadius",new Class[]{SurfaceControl.class,int.class},sc,0);regionBlurBounds[i]=null;}regionBlurKnown[i]=true;regionBlurShown[i]=visible;regionBlurAlpha[i]=alpha;}}
   // Snapshot/cross-fade guard is needed for an active native pre-blur, not Blur=0.
   call(t,"setBackgroundBlurRadius",new Class[]{SurfaceControl.class,int.class},lens,nativeRadius>0&&nativeMix>.001f?1:0);
   if(update)post.invoke(t,lens,materialShader,u,1);
   if(!root.applyTransactionOnDraw(t))throw new IllegalStateException("Draw-synchronized material transaction rejected");transactions++;if(hud!=null)hud.submission(System.nanoTime()-prepareAt);last=u;lastGeometry=geometry;lastBlurGeometry=blurGeometry;if(region!=null){if(shown)region.frameSubmitted();else region.frameUnavailable();}if(!active){active=true;changed.run();}view.postInvalidateOnAnimation();
  }finally{t.close();}
 }catch(Throwable e){fail(e);}return true;}
 private boolean waitForOwnedRoot(){if(region==null||!region.quickSettings())return false;boolean visible=!screenOff&&view.getWindowVisibility()==View.VISIBLE&&view.isShown();if(!rootReadiness.pending(SystemClock.uptimeMillis(),visible))return false;if(visible)view.postInvalidateOnAnimation();return true;}
 private void detachObservers(){if(receiverRegistered){try{view.getContext().unregisterReceiver(receiver);}catch(RuntimeException ignored){}receiverRegistered=false;}if(thermalRegistered){try{power.removeThermalStatusListener(thermal);}catch(RuntimeException ignored){}thermalRegistered=false;}}
 private void fail(Throwable e){if(closed||failed)return;failed=true;if(region==null)failures++;else if(region.quickSettings())qsFailures++;else notificationFailures++;error=(e instanceof InvocationTargetException&&e.getCause()!=null?e.getCause():e).toString();stopMotion();Light.remove(this);destroy();android.util.Log.w("VectorCard",name+" material unavailable",e);changed.run();}
 private SurfaceControl[] allLayers(){ArrayList<SurfaceControl> all=new ArrayList<>();all.add(lens);all.add(blur);all.addAll(Arrays.asList(regionBlur));return all.toArray(new SurfaceControl[0]);}
 private void destroy(){if(region!=null)region.frameUnavailable();rootReadiness.ready();if(hud!=null){hud.close();hud=null;}generation++;active=false;for(SurfaceControl s:allLayers())if(s!=null){try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){t.setVisibility(s,false).reparent(s,null).apply();}catch(Throwable e){android.util.Log.w("VectorCard","Layer teardown",e);}s.release();}lens=blur=null;regionBlur=new SurfaceControl[0];Arrays.fill(regionBlurKnown,false);Arrays.fill(regionBlurShown,false);Arrays.fill(regionBlurBounds,null);Arrays.fill(regionBlurAlpha,0);if(buffer!=null){buffer.close();buffer=null;}if(acquired){release(clustered,region!=null&&region.quickSettings());acquired=false;materialShader=null;}last=null;lastGeometry="";lastBlurGeometry="";}
 public void close(){if(closed)return;closed=true;stopMotion();Light.remove(this);view.removeOnAttachStateChangeListener(this);if(view.getViewTreeObserver().isAlive())view.getViewTreeObserver().removeOnPreDrawListener(this);detachObservers();destroy();}
 public void onViewAttachedToWindow(View v){}public void onViewDetachedFromWindow(View v){close();}
 /** Shared, event-driven gravity light; no sensor subscription when no material is visible. */
 private static final class Light implements SensorEventListener {
  static final Set<CardLiquidSurface> views=new HashSet<>();static SensorManager manager;static final Light LISTENER=new Light();static float x=-.577f,y=-.817f;
  static void add(CardLiquidSurface v){if(!views.add(v)||manager!=null)return;SensorManager m=v.view.getContext().getSystemService(SensorManager.class);if(m==null)return;Sensor s=m.getDefaultSensor(Sensor.TYPE_GRAVITY);if(s==null)s=m.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);if(s!=null&&m.registerListener(LISTENER,s,SensorManager.SENSOR_DELAY_GAME))manager=m;}
  static void remove(CardLiquidSurface v){views.remove(v);if(views.isEmpty()&&manager!=null){manager.unregisterListener(LISTENER);manager=null;}}
  public void onAccuracyChanged(Sensor s,int a){}
  public void onSensorChanged(SensorEvent e){float gx=e.values[0],gy=e.values[1];CardLiquidSurface first=views.stream().findFirst().orElse(null);if(first==null)return;int rotation=first.view.getDisplay()==null?0:first.view.getDisplay().getRotation();float ux=rotation==1?-gy:rotation==2?-gx:rotation==3?gy:gx,uy=rotation==1?gx:rotation==2?-gy:rotation==3?-gx:gy;float p=(float)Math.hypot(ux,uy),t=Math.min(1,p/SensorManager.GRAVITY_EARTH),nx=-.577f,ny=-.817f;if(p>.5f){nx=(-ux/p)*t+nx*(1-t);ny=(uy/p)*t+ny*(1-t);}float length=(float)Math.hypot(nx,ny);nx/=Math.max(.001f,length);ny/=Math.max(.001f,length);float ax=x+.14f*(nx-x),ay=y+.14f*(ny-y);if(Math.abs(ax-x)+Math.abs(ay-y)>.004f){x=ax;y=ay;for(CardLiquidSurface v:views)v.view.postInvalidateOnAnimation();}}
 }
}

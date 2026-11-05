package com.example.remote_control.glasscard
import android.graphics.*
import android.os.*
import android.view.*
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.*

/** Narrow root-owned compositor session. One registration; changes are event driven.
 * Both drawable layers are negative children of the existing foreground surface root:
 * WMS/SurfaceView motion therefore moves material and foreground in the same hierarchy. */
@androidx.annotation.RequiresApi(33)
class CardCompositorBroker(private val parent:SurfaceControl,private val host:IBinder,private val failure:(Throwable)->Unit):AutoCloseable {
 private val thread=HandlerThread("CardCompositor").apply{start()};private val handler=Handler(thread.looper)
 private val pending=AtomicReference<Bundle?>();private var closed=false;private var generation=0
 private var blur:SurfaceControl?=null;private var lens:SurfaceControl?=null;private var buffer:CardCompositorBuffer?=null
 private var token:IBinder?=null;private var width=0;private var height=0;private var last:ByteArray?=null;private var lastBlur=-1;private var lastMix=-1f
 private var allowed=false;private var sampler:CardCompositorSampler?=null;private var sampled=Rect();private var sampleTime=0L
 private fun call(o:Any,n:String,vararg v:Pair<Class<*>,Any?>):Any?=o.javaClass.getMethod(n,*v.map{it.first}.toTypedArray()).invoke(o,*v.map{it.second}.toTypedArray())
 private fun layer(name:String):SurfaceControl {
  val b=Class.forName("android.view.SurfaceControl\$Builder").getConstructor().newInstance()
  call(b,"setName",String::class.java to name);call(b,"setOpaque",Boolean::class.javaPrimitiveType!! to false)
  call(b,"setParent",SurfaceControl::class.java to parent);call(b,"setBufferSize",Int::class.javaPrimitiveType!! to width,Int::class.javaPrimitiveType!! to height)
  return call(b,"build") as SurfaceControl
 }
 fun update(state:Bundle){if(closed)return;pending.set(Bundle(state));handler.removeCallbacks(apply);handler.post(apply)}
 fun visibility(value:Boolean){handler.post{if(closed)return@post;allowed=value;try{if(!value){pending.get()?.let{val cleared=Bundle(it);cleared.putFloatArray("ripples",TouchRippleState.emptyFrame());cleared.putFloat("press",0f);pending.set(cleared)};sampler?.destroy();sampler=null;sampled.setEmpty()};applyState()}catch(e:Throwable){failure(e)}}}
 private val apply=Runnable{try{applyState()}catch(e:Throwable){failure(e)}}
 private fun applyState(){if(closed)return;val s=pending.get() ?: return
  val w=s.getInt("w");val h=s.getInt("h");check(w in 64..2400&&h in 64..4000&&w.toLong()*h<=2000000&&parent.isValid){"Invalid owned card region"}
  if(token==null){android.graphics.RuntimeShader(CardCompositorMaterial.SHADER);token=SurfaceControl::class.java.getMethod("registerShader",String::class.java,String::class.java).invoke(null,"NodeCockpit.Card.Lens.${android.os.Process.myPid()}",CardCompositorMaterial.SHADER) as? IBinder ?: error("Shader registration rejected")}
  if(buffer==null||w!=width||h!=height){destroyLayers();width=w;height=h;val request=++generation
   blur=layer("NodeCockpit-Card-NativePreblur");lens=layer("NodeCockpit-Card-CompositorLens")
   buffer=CardCompositorBuffer(w,h,handler){if(!closed&&request==generation)handler.post(apply)};return
  }
  val owned=buffer ?: return;if(!owned.ready())return
  val c=JSONObject(s.getString("config","{}"));val u=CardCompositorMaterial.pack(s)
  val radius=min(c.optDouble("radius",32.0).toFloat()*s.getFloat("density",1f),min(w,h)/2f)
  val strength=c.optDouble("blurStrength",0.0).toFloat()
  val blurRadius=GlassBlur.radius(strength).roundToInt().coerceIn(0,48)
  val mix=GlassBlur.contribution(strength)
  val changed=last?.contentEquals(u)!=true||lastBlur!=blurRadius||lastMix!=mix
  SurfaceControl.Transaction().use { t ->
   for((sc,z) in listOf(blur!! to -2,lens!! to -1)){
    t.setLayer(sc,z).setPosition(sc,0f,0f).setCrop(sc,Rect(0,0,w,h)).setVisibility(sc,allowed)
    call(t,"setDestinationFrame",SurfaceControl::class.java to sc,Rect::class.java to Rect())
    call(t,"setCornerRadius",SurfaceControl::class.java to sc,Float::class.javaPrimitiveType!! to radius)
    if(changed)owned.append(t,sc,Rect(0,0,w,h))
   }
   t.setAlpha(blur!!,if(blurRadius>0)mix else 0f)
   call(t,"setBackgroundBlurRadius",SurfaceControl::class.java to blur!!,Int::class.javaPrimitiveType!! to blurRadius)
   // For a later BEHIND effect, inspected SkiaRenderEngine uses a copying snapshot when
   // native blur cross-fades. Keep that guard only while native pre-blur is active; its
   // 1px draw is overwritten by kSrc post-process, while
   // the lens samples the independently preserved preblur result (not itself).
   call(t,"setBackgroundBlurRadius",SurfaceControl::class.java to lens!!,Int::class.javaPrimitiveType!! to if(blurRadius>0&&mix>.001f)1 else 0)
   if(changed)call(t,"setPostProcess",SurfaceControl::class.java to lens!!,IBinder::class.java to token,ByteArray::class.java to u,Int::class.javaPrimitiveType!! to 1)
   t.apply()
  }
  last=u;lastBlur=blurRadius;lastMix=mix
  if(allowed&&c.optBoolean("adaptiveText",true)){
   val bounds=Rect(s.getInt("x"),s.getInt("y"),s.getInt("x")+w,s.getInt("y")+h)
   if(bounds!=sampled&&SystemClock.uptimeMillis()-sampleTime>=64){
    if(sampler==null)sampler=CardCompositorSampler({handler.post(it)}){l->try{val p=Parcel.obtain();val r=Parcel.obtain();try{p.writeFloat(l);host.transact(5,p,r,0)}finally{p.recycle();r.recycle()}}catch(_:Exception){}}
    try{sampler!!.region(blur!!,bounds);sampled.set(bounds);sampleTime=SystemClock.uptimeMillis()}catch(e:Throwable){sampler?.destroy();sampler=null;android.util.Log.w("LiquidGlassCard","Optional text sampler unavailable",e)}
   }else if(bounds!=sampled){handler.removeCallbacks(apply);handler.postDelayed(apply,64)}
  }else {sampler?.destroy();sampler=null;sampled.setEmpty()}
 }
 private fun destroyLayers(){generation++;sampler?.destroy();sampler=null;sampled.setEmpty();for(sc in listOf(lens,blur)){if(sc!=null){try{SurfaceControl.Transaction().use{it.setVisibility(sc,false).reparent(sc,null).apply()}}catch(_:Throwable){};sc.release()}};lens=null;blur=null;buffer?.close();buffer=null;last=null;lastBlur=-1;lastMix=-1f}
 override fun close(){if(closed)return;handler.post{closed=true;destroyLayers();token?.let{try{SurfaceControl::class.java.getMethod("unregisterShader",IBinder::class.java).invoke(null,it)}catch(_:Throwable){}};token=null;parent.release();thread.quitSafely()}}
}

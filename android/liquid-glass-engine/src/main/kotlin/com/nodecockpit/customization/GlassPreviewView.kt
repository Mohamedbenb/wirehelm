package com.nodecockpit.customization

import android.content.Context
import android.graphics.*
import android.os.PowerManager
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import com.example.remote_control.glasscard.GlassBlur
import com.example.remote_control.glasscard.GlassLensRenderer
import com.example.remote_control.glasscard.LightSourceController
import com.example.remote_control.glasscard.TouchRippleState
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*

/** All sampling is from the caller-owned backdrop. No device settings or other windows are read. */
@androidx.annotation.RequiresApi(33)
class GlassPreviewView(context:Context):FrameLayout(context) {
 private var config=GlassLabState()
 private var ink=ForegroundInkStyle.DEFAULT
 private var material=JSONObject()
 private var alive=false
 private var resumed=true
 private var queued=false
 private var lightRegistered=false
 private var origin=SystemClock.uptimeMillis()
 private var phase=0f
 private var serial=0L
 private var press=0f
 private var target=0f
 private var touchX=0f
 private var touchY=0f
 private var lastFrame=0L
 private var clockPausedAt=0L
 private var inkValues:Map<String,Any> = emptyMap()
 private var tuning=MaterialTuning.DEFAULT
 private var policyValid=true
 private val pulses=TouchRippleState()
 private val emptyRipples=TouchRippleState.emptyFrame()
 private val density=resources.displayMetrics.density
 private val backdrop=Backdrop(context)
 private var stage=Stage(context)
 private var hud:GlassPerformanceHud.Lease?=null
 private val power=context.getSystemService(PowerManager::class.java)
 private var statusAt=0L
 private val observed=linkedMapOf<String,String>()
 var onStatus:((String)->Unit)?=null
 var onAction:((String)->Unit)?=null
 var onProgress:((Float)->Unit)?=null
 /** Display-only animated value, committed before the native geometry callback. */
 var onRenderedProgress:((Float)->Unit)?=null
 /** Called while the material frame is being drawn, before native child views render. */
 var onNativeGeometry:((List<RectF>,Float,Float,Float,Float)->Unit)?=null
 private var nativeForegroundMode=false
 private var regionActivity=FloatArray(0)
 private var regionPageOffset=0f
 /** App-owned tile state. Geometry, optics and native placement consume it in the same draw. */
 fun setRegionActivity(values:FloatArray){require(values.size<=16&&values.all{it.isFinite()});regionActivity=values.map{it.coerceIn(0f,1f)}.toFloatArray();stage.invalidate()}
 fun setRegionPageOffset(value:Float){require(value.isFinite());regionPageOffset=value.coerceIn(-1f,1f);stage.invalidate()}
 private val next=Runnable{queued=false;if(active())redrawScene()}
 init{clipChildren=true;addView(backdrop);addView(stage);applyState(config)}
 fun applyState(state:GlassLabState){val changedScene=state.scene!=config.scene||state.profile!=config.profile;if(changedScene)stage.resetInteraction();config=state.copy().also{it.validateSelections()};material=JSONObject().apply{GlassLabCatalog.controls.forEach{put(it.key,config.number(it.key))};put("material",if(config.flag("regular"))"regular"else"clear");put("glassTintColor",hex(config.color("glassTintColor")));for(k in listOf("outward","touchRipples","reactionEnabled"))put(k,config.flag(k))}
  val nextInk=mapOf("outlineWidth" to config.number("outlineWidth"),"outlineOpacity" to config.number("outlineOpacity"),"shadowRadius" to config.number("shadowRadius"),"shadowOpacity" to config.number("shadowOpacity"),"shadowX" to config.number("shadowX"),"shadowY" to config.number("shadowY"),"outlineAuto" to config.flag("outlineAuto"),"shadowAuto" to config.flag("shadowAuto"),"outlineColor" to hex(config.color("outlineColor")),"shadowColor" to hex(config.color("shadowColor")))
  if(nextInk!=inkValues){inkValues=nextInk;ink=ForegroundInkStyle(nextInk)}
  val policy=mutableMapOf<String,Any>("enabled" to true);MaterialTuning.RANGES.keys.forEach{policy[it]=config.number("policy.$it").roundToInt()};policyValid=MaterialTuning.valid(policy);if(policyValid)tuning=MaterialTuning(policy)
  if(!config.flag("touchRipples"))pulses.clear();if(!config.flag("pressEffects"))press=0f
  syncObservers();redrawScene();statusAt=0
 }
 fun setActive(value:Boolean){resumed=value;if(!value)stopMotion();syncObservers();redrawScene()}
 /** Leaves material rendering to the engine and lets real Android child views provide ink/actions. */
 fun useNativeForeground(value:Boolean){nativeForegroundMode=value;stage.invalidate()}
 /** For interactive native child samples, forward pointer input into the engine geometry/ripple host. */
 fun forwardNativeTouch(source:View,event:MotionEvent):Boolean{
  val from=IntArray(2);val to=IntArray(2);source.getLocationOnScreen(from);getLocationOnScreen(to)
  val copy=MotionEvent.obtain(event);copy.offsetLocation((from[0]-to[0]).toFloat(),(from[1]-to[1]).toFloat())
  return try{stage.dispatchTouchEvent(copy)}finally{copy.recycle()}
 }
 fun recreateRenderer(){val positions=stage.savePositions();stopMotion();LightSourceController.unregister(stage);lightRegistered=false;hud?.close();hud=null;stage.release();val stageIndex=indexOfChild(stage);removeView(stage);stage=Stage(context);stage.restorePositions(positions);addView(stage,stageIndex);requestLayout();origin=SystemClock.uptimeMillis();clockPausedAt=if(active())0 else origin;observed.clear();syncObservers();redrawScene()}
 fun resetInteraction(){stage.resetInteraction();redrawScene()}
 fun saveRegionPositions():FloatArray=stage.savePositions()
 fun restoreRegionPositions(values:FloatArray){stage.restorePositions(values);redrawScene()}
 fun injectFailure(){stage.injectFailure();stage.invalidate()}
 fun resetMotion(){stopMotion();phase=0f;origin=SystemClock.uptimeMillis();clockPausedAt=if(active())0 else origin;redrawScene()}
 fun report():String="Glass engine ${LiquidGlassEngine.VERSION}/api${LiquidGlassEngine.API_VERSION}\n${stage.diagnostics()}\nObserved shader submissions: ${observed.entries.joinToString{it.key+"="+it.value}}\n${nativeCapabilities()}\nGPU/pixel correctness and cross-window synchronization are not automatically validated."
 fun runContractChecks():String=GlassLabChecks.run().joinToString("\n")
 fun nativeCapabilities():String {
  val permission=context.checkSelfPermission("android.permission.READ_FRAME_BUFFER")==android.content.pm.PackageManager.PERMISSION_GRANTED
  val shader=android.view.SurfaceControl::class.java.methods.any{it.name=="registerShader"}
  val post=android.view.SurfaceControl.Transaction::class.java.methods.any{it.name=="setPostProcess"}
  return "Native compositor: ${if(permission&&shader&&post)"capability checks pass; privileged host run still required"else"unavailable to this app"} (permission=$permission, shader=$shader, transaction=$post). Transport not executed."
 }
 // Compatibility with the first library API.
 var progress:Float get()=config.number("progress");set(v){config.setNumber("progress",v);applyState(config)}
 var blur:Float get()=config.number("progressBlur");set(v){config.setNumber("progressBlur",v);config.setNumber("indicatorBlur",v);applyState(config)}
 var refraction:Float get()=config.number("refraction");set(v){config.setNumber("refraction",v);applyState(config)}
 var outline:Float get()=config.number("outlineWidth");set(v){config.setNumber("outlineWidth",v);applyState(config)}
 var shadow:Float get()=config.number("shadowRadius");set(v){config.setNumber("shadowRadius",v);applyState(config)}
 var offset:Float get()=config.number("offset");set(v){config.setNumber("offset",v);applyState(config)}
 var alternate:Boolean get()=config.background==1;set(v){config.background=if(v)1 else 0;applyState(config)}
 private fun redrawScene(){if(motionAllowed()){val snapshot=GlassLabGeometry.phase(SystemClock.uptimeMillis()-origin,config.number("speed"),true);serial=snapshot.first;phase=snapshot.second};backdrop.invalidate();stage.invalidate()}
 private fun renderable()=alive&&resumed&&isShown&&windowVisibility==VISIBLE
 private fun active()=renderable()&&!config.flag("paused")
 private fun motionAllowed()=active()&&!config.flag("reduceMotion")&&android.animation.ValueAnimator.areAnimatorsEnabled()&&power?.isPowerSaveMode!=true&&(power?.currentThermalStatus?:0)<2&&!config.flag("simulatePowerSave")&&!config.flag("simulateThermal")
 private fun schedule(){if(!queued&&motionAllowed()){queued=true;postOnAnimation(next)}}
 private fun stopMotion(){stage.cancelInteraction();removeCallbacks(next);queued=false;target=0f;press=0f;lastFrame=0;pulses.clear()}
 private fun syncObservers(){
  val now=SystemClock.uptimeMillis();if(!active()){if(clockPausedAt==0L)clockPausedAt=now;stopMotion()}else if(clockPausedAt!=0L){origin+=now-clockPausedAt;clockPausedAt=0;lastFrame=0}
  if(!motionAllowed()){removeCallbacks(next);queued=false;target=0f;press=0f;pulses.clear()}
  val sensor=motionAllowed()&&config.profile!=5&&config.flag("sensorLighting")&&!config.flag("forceFallback")&&!config.flag("simulatePowerSave")&&!config.flag("simulateThermal")&&(power?.currentThermalStatus?:0)<2
  if(sensor&&!lightRegistered){LightSourceController.register(stage);lightRegistered=true}else if(!sensor&&lightRegistered){LightSourceController.unregister(stage);lightRegistered=false}
  val show=active()&&config.flag("performanceHud");GlassPerformanceHud.configure(show)
  if(show&&hud==null)hud=GlassPerformanceHud.acquire(this,1) else if(!show){hud?.close();hud=null}
 }
 override fun onAttachedToWindow(){super.onAttachedToWindow();alive=true;origin=SystemClock.uptimeMillis();syncObservers();redrawScene()}
 override fun onDetachedFromWindow(){alive=false;stopMotion();LightSourceController.unregister(stage);lightRegistered=false;hud?.close();hud=null;GlassPerformanceHud.configure(false);stage.release();super.onDetachedFromWindow()}
 override fun onVisibilityChanged(changedView:View,visibility:Int){super.onVisibilityChanged(changedView,visibility);if(!alive)return;if(!isShown){stopMotion();stage.release()};syncObservers();redrawScene()}
 override fun onWindowVisibilityChanged(v:Int){super.onWindowVisibilityChanged(v);if(!alive)return;if(v!=VISIBLE)stopMotion();syncObservers();redrawScene()}
 override fun onMeasure(w:Int,h:Int){setMeasuredDimension(MeasureSpec.getSize(w),MeasureSpec.getSize(h));for(i in 0 until childCount)getChildAt(i).measure(MeasureSpec.makeMeasureSpec(measuredWidth,MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(measuredHeight,MeasureSpec.EXACTLY))}
 override fun onLayout(changed:Boolean,l:Int,t:Int,r:Int,b:Int){for(i in 0 until childCount)getChildAt(i).layout(0,0,width,height);syncObservers()}
 private fun hex(color:Int)="#%06X".format(color and 0xffffff)
 private inner class Backdrop(c:Context):View(c){val paint=Paint(Paint.ANTI_ALIAS_FLAG)
  override fun onDraw(canvas:Canvas){
   val moving=config.motion in listOf(6,8);val shift=if(moving)phase*80*density else 0f
   canvas.drawColor(if(config.background==1)0xffefe9df.toInt()else 0xff142039.toInt())
   when(config.background){
    2->{val step=20*density;for(y in 0..ceil(height/step).toInt())for(x in -4..ceil(width/step).toInt()){paint.color=if((x+y)%2==0)Color.WHITE else Color.BLACK;canvas.drawRect(x*step+shift,y*step,(x+1)*step+shift,(y+1)*step,paint)}}
    3->{paint.textSize=19*density;for(row in 0..height/(28*density).toInt()){paint.color=if(row%2==0)Color.WHITE else 0xff759fc0.toInt();canvas.drawText("Aa 012345 مرحبا Glass • contrast",-shift,row*28*density,paint)}}
    4->{paint.shader=LinearGradient(shift,0f,width.toFloat()+shift,height.toFloat(),intArrayOf(Color.RED,Color.BLUE,Color.GREEN,Color.WHITE),null,Shader.TileMode.MIRROR);canvas.drawRect(0f,0f,width.toFloat(),height.toFloat(),paint);paint.shader=null}
    else->{val step=52*density;for(row in 0..ceil(height/step).toInt())for(col in -2..ceil(width/step).toInt()){paint.color=if((row+col)%2==0)0xff6b90be.toInt()else 0xffb56a8b.toInt();canvas.drawCircle(col*step+step/2+shift,row*step+step/2,step*.32f,paint)}}
   }
  }
 }
 private inner class Stage(c:Context):View(c){
  private val exact=GlassLabRenderer();private val levelRenderer=GlassLabRenderer();private val local=GlassLensRenderer();private val paint=Paint(Paint.ANTI_ALIAS_FLAG);private val path=Path()
  private val tone=SmoothInkTone().apply{seed(Color.WHITE)};private var elapsedMs=16f;private var filteredLuma=.5f;private var policyResult="off"
  private var frames=0L;private var cpu=0L;private var bytes=0;private var currentProfile=0;private var result="not drawn";private var rects=emptyList<GlassLabRect>()
  private val interaction=GlassLabInteraction();private val hitMatrix=Matrix();private val inverseHit=Matrix();private val hitPoint=FloatArray(2);private var lastAlpha=1f;private var lastClip=1f;private var displayScene=0;private var disabled=-1;private var lastRegionClip=1f;private var lastBaseRects=emptyList<GlassLabRect>()
  private var lastRects=emptyList<GlassLabRect>();private var lastProgress=.55f
  fun diagnostics()="${GlassLabCatalog.profiles[currentProfile]} · $result · uniform $bytes B\nUI draws=$frames; last record CPU=${"%.2f".format(cpu/1e6)}ms (not GPU) · pulses=${pulses.active()} · sensor=$lightRegistered\nHost: pointers=${interaction.pointerCount}, selected=${interaction.selected}, clicks=${interaction.clickCount}\nPolicy: $policyResult\n${exact.diagnostics()}"
  fun resetInteraction(){interaction.reset();target=0f;parent?.requestDisallowInterceptTouchEvent(false)}
  fun cancelInteraction(){interaction.cancel();parent?.requestDisallowInterceptTouchEvent(false)}
  fun savePositions()=interaction.savePositions()
  fun restorePositions(values:FloatArray){interaction.restorePositions(values)}
  fun injectFailure(){exact.injectFailure()}
  fun release(){exact.close();levelRenderer.close();local.release()}
  private fun logical(x:Float,y:Float):Pair<Float,Float>{hitPoint[0]=x;hitPoint[1]=y;if(hitMatrix.invert(inverseHit))inverseHit.mapPoints(hitPoint);return hitPoint[0] to hitPoint[1]}
  override fun onTouchEvent(e:MotionEvent):Boolean{
   if(!active()||lastAlpha<=.001f){cancelInteraction();target=0f;return false}
   val index=e.actionIndex;val id=e.getPointerId(index);val point=logical(e.getX(index),e.getY(index));val now=SystemClock.uptimeMillis()
   when(e.actionMasked){
    MotionEvent.ACTION_DOWN,MotionEvent.ACTION_POINTER_DOWN->{
     val accepted=point.first>=0&&point.first<=width*lastClip&&lastRegionClip>0&&interaction.down(id,point.first,point.second,lastRects.map{it.copy(width=it.width*lastRegionClip)},disabled)
     if(!accepted)return interaction.pointerCount>0
     parent.requestDisallowInterceptTouchEvent(true);touchX=point.first;touchY=point.second
     if(config.profile!=5&&config.flag("touchRipples"))pulses.emit(touchX/max(1,width),touchY/max(1,height),now,false)
    }
    MotionEvent.ACTION_MOVE->{for(i in 0 until e.pointerCount){val pointer=e.getPointerId(i);if(!interaction.hasPointer(pointer))continue;val p=logical(e.getX(i),e.getY(i));touchX=p.first;touchY=p.second;interaction.move(pointer,p.first,p.second,lastRects,width.toFloat(),height.toFloat(),displayScene==6&&config.flag("dragCards"),config.number("dragSlop")*density)}}
    MotionEvent.ACTION_UP,MotionEvent.ACTION_POINTER_UP->{
     val captured=interaction.hasPointer(id);touchX=point.first;touchY=point.second
     val clicked=interaction.up(id,point.first,point.second,interaction.layout(lastBaseRects,width.toFloat(),height.toFloat()).map{it.copy(width=it.width*lastRegionClip)},displayScene==7&&!nativeForegroundMode)
     if(captured&&config.profile!=5&&config.flag("touchRipples"))pulses.emit(touchX/max(1,width),touchY/max(1,height),now,true)
     if(clicked!=null){performClick();onAction?.invoke(if(displayScene==7&&!nativeForegroundMode)"Button ${clicked+1}: ${if(interaction.toggled(clicked))"ON"else"OFF"} · ${interaction.clicks(clicked)} clicks"else"Card ${clicked+1} tapped")}
     if(interaction.pointerCount==0)parent.requestDisallowInterceptTouchEvent(false)
    }
    MotionEvent.ACTION_CANCEL->{interaction.cancel();pulses.clear();parent.requestDisallowInterceptTouchEvent(false)}
   }
   target=if(interaction.pointerCount>0)1f else 0f
   if(displayScene==0&&lastRects.isNotEmpty()&&e.actionMasked in listOf(MotionEvent.ACTION_DOWN,MotionEvent.ACTION_MOVE)&&interaction.pointerCount>0){val r=lastRects[0];val value=GlassLabGeometry.sliderProgress(r,touchX,touchY,config.flag("verticalSlider"),config.flag("rtl"));config.setNumber("progress",value);onProgress?.invoke(value)}
   invalidate();return true
  }
  override fun performClick():Boolean{super.performClick();return true}
  override fun onDraw(canvas:Canvas){
   if(!renderable()||width<2||height<2)return
   val begin=System.nanoTime();val now=SystemClock.uptimeMillis()
   val s=config.copy();if(s.motion==7&&motionAllowed()){s.profile=(serial%GlassLabCatalog.profiles.size).toInt();if(s.scene !in GlassLabCatalog.supportedScenes(s.profile))s.scene=1};currentProfile=s.profile
   lastBaseRects=GlassLabGeometry.regions(s,width.toFloat(),height.toFloat(),density,phase);rects=if(s.scene==6)interaction.layout(lastBaseRects,width.toFloat(),height.toFloat())else lastBaseRects;if(s.profile==4&&s.scene==5&&regionPageOffset!=0f)rects=rects.map{it.copy(left=it.left+regionPageOffset*width)};lastRects=rects;displayScene=s.scene;disabled=if(s.scene==7&&s.flag("disableLastButton"))rects.lastIndex else -1;if(rects.isEmpty())return
   if(interaction.pointerCount==0)target=0f
   val dt=if(lastFrame==0L)1/60f else ((now-lastFrame)/1000f).coerceIn(0f,.1f);lastFrame=now;elapsedMs=dt*1000
   val desired=if(config.profile!=5&&config.flag("pressEffects")&&motionAllowed())target else 0f;press+=(desired-press)*(1-exp(-dt/(if(desired>press).06f else .107f)));if(abs(desired-press)<.002f)press=desired
   val pulseFrame=if(config.flag("touchRipples")&&motionAllowed()&&pulses.active())pulses.frame(now,TouchRippleState.lifetime(config.number("rippleSpeed"),config.number("rippleDamping")))else emptyRipples
   val alpha=GlassLabGeometry.alpha(s,phase);val progress=GlassLabGeometry.progress(s,phase);lastProgress=progress;lastAlpha=alpha;lastClip=s.number("clip");lastRegionClip=if(s.profile==4)s.number("regionClip")else 1f
   val save=canvas.save();val centerX=width/2f;val centerY=height/2f
   val scale=s.number("scale")*(if(s.motion in listOf(4,8)) .6f+.4f*phase else 1f);val rotation=s.number("rotation")+(if(s.motion==4)30*(phase-.5f)else 0f);hitMatrix.setScale(scale,scale,centerX,centerY);hitMatrix.preRotate(rotation,centerX,centerY);canvas.scale(scale,scale,centerX,centerY);canvas.rotate(rotation,centerX,centerY);canvas.clipRect(0f,0f,width*s.number("clip"),height.toFloat())
   if(s.scene==0)onRenderedProgress?.invoke(progress)
   onNativeGeometry?.invoke(rects.map{RectF(it.left,it.top,it.left+it.width,it.top+it.height)},scale,rotation,alpha,s.number("clip"))
   val layer=canvas.saveLayerAlpha(0f,0f,width.toFloat(),height.toFloat(),(alpha*255).roundToInt())
   val fallback=s.flag("forceFallback")||s.flag("simulatePowerSave")||s.flag("simulateThermal")||power?.isPowerSaveMode==true||(power?.currentThermalStatus?:0)>=2
   val r=rects[0];val radius=if(s.scene==2)min(r.width,r.height)/2 else min(s.number("radius")*density,min(r.width,r.height)/2)
   if(fallback){result="explicit fallback";fallback(canvas,r,radius)}else if(s.profile==0){
    result=if(local.draw(canvas,this,localParams(s,r,radius,pulseFrame),ceil(max(12f,s.number("refraction")+s.number("blurStrength"))).toInt(),backdrop,0f,0f))"draw submitted"else"renderer unavailable";if(result!="draw submitted")fallback(canvas,r,radius);bytes=0
   }else{
    if(s.profile==5){path.reset();path.addRoundRect(RectF(r.left,r.top,r.left+r.width,r.top+r.height),radius,radius,Path.Direction.CW);canvas.clipPath(path)}
    val packet=uniforms(s,r,radius,progress,pulseFrame,alpha);bytes=packet.size
    val frame=if(s.profile==5)Rect(r.left.toInt(),r.top.toInt(),ceil(r.left+r.width).toInt(),ceil(r.top+r.height).toInt())else Rect(0,0,width,height)
    val maskedAndroidProgress=s.flag("androidBlur")&&s.profile==4&&s.scene==0
    val preBlur=if(s.flag("androidBlur")&&s.profile in 1..4&&!maskedAndroidProgress)GlassBlur.radius(s.number("blurStrength"))else if(s.profile==1||(s.profile==2&&rects.size<2))GlassBlur.radius(s.number("blurStrength"))else 0f
    var androidProgressMask:RectF?=null
    var androidProgressShape:Path?=null
    if(maskedAndroidProgress){
     val fill=GlassLabGeometry.sliderFill(r,progress,s.flag("verticalSlider"),s.flag("rtl"))
     androidProgressMask=RectF(fill.left,fill.top,fill.left+fill.width,fill.top+fill.height)
     val cardCorners=corners(s,r,radius)
     androidProgressShape=Path().apply{addRoundRect(RectF(r.left,r.top,r.left+r.width,r.top+r.height),floatArrayOf(cardCorners[0],cardCorners[0],cardCorners[1],cardCorners[1],cardCorners[2],cardCorners[2],cardCorners[3],cardCorners[3]),Path.Direction.CW)}
    }
    val good=exact.draw(canvas,backdrop,s.profile,packet,frame,preBlur,if(preBlur>0)GlassBlur.contribution(s.number("blurStrength"))else 0f,s.flag("kawasePreblur"),androidProgressMask,GlassBlur.radius(s.number("progressBlur")),GlassBlur.contribution(s.number("progressBlur")),androidProgressShape)
    result=if(good)"draw submitted"else"renderer unavailable"
    if(!good)fallback(canvas,r,radius)
    else if(maskedAndroidProgress){
     result="draw submitted · Android blur clipped to progress"
    }
   }
   if(!fallback)observed[GlassLabCatalog.profiles[s.profile]]=result
   if(!fallback&&nativeForegroundMode&&s.profile==4&&s.scene==0){
    val marker=indicator(s,r,progress)
    val shape=GlassLabRect(marker.left,marker.top,marker.width(),marker.height())
    val level=s.copy().apply{scene=1;setNumber("blurStrength",s.number("indicatorBlur"))}
    val packet=uniforms(level,shape,marker.width()/2,progress,pulseFrame,alpha,listOf(shape))
    val blur=if(level.flag("androidBlur"))GlassBlur.radius(level.number("blurStrength"))else 0f
    val markerSave=canvas.save()
    path.reset();path.addRoundRect(marker,marker.width()/2,marker.width()/2,Path.Direction.CW)
    canvas.clipPath(path)
    try{levelRenderer.draw(canvas,backdrop,4,packet,Rect(0,0,width,height),blur,if(blur>0)GlassBlur.contribution(level.number("blurStrength"))else 0f,false)}finally{canvas.restoreToCount(markerSave)}
    paint.shader=null;paint.style=Paint.Style.STROKE;paint.strokeWidth=density;paint.color=Color.WHITE
    canvas.drawRoundRect(marker,marker.width()/2,marker.width()/2,paint)
    paint.style=Paint.Style.FILL
   }
   if(!nativeForegroundMode){drawForeground(canvas,s,r,radius,progress);if(s.flag("policyProbe"))drawPolicy(canvas,s)}
   canvas.restoreToCount(layer);canvas.restoreToCount(save);frames++;cpu=System.nanoTime()-begin;hud?.allocation(0,width.toLong()*height);hud?.submission(cpu)
   if(now-statusAt>500&&(config.flag("metrics")||result!="draw submitted")){statusAt=now;val status=diagnostics();post{onStatus?.invoke(status)}}
   if(motionAllowed()&&(config.motion!=0||(config.flag("pressEffects")&&abs(desired-press)>.002f)||pulses.active()||(config.flag("policyProbe")&&!tone.settled())))schedule()
  }
  private fun drawPolicy(canvas:Canvas,s:GlassLabState){
   val raw=if(s.motion==6)phase else s.number("policyLuma");val response=tuning.luminanceResponse("lab").toFloat();filteredLuma=if(response<=0)raw else GlassTransitionMath.approach(filteredLuma,raw,GlassTransitionMath.amount(elapsedMs,response))
   tone.duration(s.number("toneDuration").roundToInt());val color=tone.step(0,filteredLuma,s.number("policySurround"),raw,0x44ffffff,s.flag("policyConstrainOther"),elapsedMs,tuning)
   val gray=(if(raw<=.0031308f)12.92f*raw else 1.055f*raw.pow(1/2.4f)-.055f).coerceIn(0f,1f);val channel=(gray*255).roundToInt();val y=max(0f,height-56*density)
   paint.style=Paint.Style.FILL;paint.color=Color.rgb(channel,channel,channel);canvas.drawRect(0f,y,width.toFloat(),height.toFloat(),paint)
   paint.color=tuning.tint(0xff5bc3a0.toInt());canvas.drawRect(0f,y,28*density,height.toFloat(),paint)
   paint.color=color;paint.textSize=13*density;canvas.drawText("Known luma ${"%.2f".format(raw)} · smooth ink",34*density,y+21*density,paint)
   val crop=tuning.crop(0,y.toInt(),width,height,density,0,0,width,height);paint.style=Paint.Style.STROKE;paint.strokeWidth=2*density;paint.color=tuning.border(0xff8899dd.toInt());canvas.drawRect(crop[0].toFloat(),crop[1].toFloat(),crop[2].toFloat(),crop[3].toFloat(),paint)
   policyResult="valid=$policyValid, tone=${color and 255}, limited=${tone.limited()}, repairs=${tone.repairs()}, threshold=${tuning.delta()}, target=${"%.2f".format(tuning.tone(raw))}, crop=${crop.joinToString()}"
  }
  private fun fallback(canvas:Canvas,r:GlassLabRect,radius:Float){paint.shader=null;paint.style=Paint.Style.FILL;paint.color=0xdd45536b.toInt();for(rect in rects)canvas.drawRoundRect(RectF(rect.left,rect.top,rect.left+rect.width,rect.top+rect.height),radius,radius,paint)}
  private fun localParams(s:GlassLabState,r:GlassLabRect,radius:Float,waves:FloatArray):GlassLensRenderer.LensParams{
   val second=rects.getOrNull(1);val angle=Math.toRadians(s.number("lightAngle").toDouble());val lx=if(lightRegistered)LightSourceController.lightDirX else cos(angle).toFloat();val ly=if(lightRegistered)LightSourceController.lightDirY else sin(angle).toFloat();val corners=corners(s,r,radius)
   val tint=if(s.flag("regular"))((s.number("regularToneStrength")*2.55f).roundToInt() shl 24)or 0xffffff else ((s.number("baseVeil")*2.55f).roundToInt() shl 24)or 0xffffff
   return GlassLensRenderer.LensParams(GlassBlur.radius(s.number("blurStrength")),r.cx,r.cy,r.width/2,r.height/2,corners[0],corners[1],corners[2],corners[3],r.cx,r.cy,r.width/2,r.height/2,s.number("softness"),second?.cx?:0f,second?.cy?:0f,(second?.width?:0f)/2,(second?.height?:0f)/2,if(second==null)radius else min(radius,min(second.width,second.height)/2),s.number("merge")*density,s.number("bevel"),s.number("refraction"),s.number("falloff"),s.flag("outward"),6f,s.number("dispersion"),lx,ly,s.number("specular"),tint,s.flag("regular"),(s.number("glassTintStrength")*255).roundToInt().shl(24)or(s.color("glassTintColor")and 0xffffff),s.number("dimming")/100,s.number("saturation"),press,touchX,touchY,press,GlassBlur.contribution(s.number("blurStrength")),if(s.flag("reactionEnabled"))s.number("reactionIntensity")else 0f,if(s.flag("touchRipples"))s.number("rippleStrength")else 0f,s.number("rippleSpeed"),s.number("rippleDamping"),TouchRippleState.lifetime(s.number("rippleSpeed"),s.number("rippleDamping")),waves)
  }
  private fun corners(s:GlassLabState,r:GlassLabRect,radius:Float)=if(s.profile==4&&(s.scene==5||(s.scene==7&&nativeForegroundMode))){val active=regionActivity.getOrElse(rects.indexOf(r)){0f};FloatArray(4){radius+(min(20*density,min(r.width,r.height)/2)-radius)*active}}else if(s.scene==7&&s.profile==4&&interaction.toggled(rects.indexOf(r)))FloatArray(4){min(10*density,min(r.width,r.height)/2)}else if(s.scene==3||s.flag("asymmetric"))floatArrayOf(s.number("cornerTL"),s.number("cornerTR"),s.number("cornerBR"),s.number("cornerBL")).map{min(it*density,min(r.width,r.height)/2)}.toFloatArray()else FloatArray(4){radius}
  private fun uniforms(s:GlassLabState,r:GlassLabRect,radius:Float,progress:Float,waves:FloatArray,alpha:Float,shapeOverride:List<GlassLabRect>?=null):ByteArray{
   if(s.profile==5)return NativeLiquidMaterial.pack((ceil(r.left+r.width).toInt()-r.left.toInt()).coerceAtLeast(1),(ceil(r.top+r.height).toInt()-r.top.toInt()).coerceAtLeast(1),radius,s.number("classicPreset").toInt(),s.flag("darkInk"),s.number("classicBlur"),s.number("classicRefraction"),s.number("classicTint"),s.number("classicEdge"),s.number("classicContrast"))
   val angle=Math.toRadians(s.number("lightAngle").toDouble());val lx=if(lightRegistered)LightSourceController.lightDirX else cos(angle).toFloat();val ly=if(lightRegistered)LightSourceController.lightDirY else sin(angle).toFloat()
   val base=CardLiquidParameters.uniforms(width.toFloat(),height.toFloat(),radius,material,lx,ly,press,touchX,touchY,waves)
   val b=ByteBuffer.wrap(base).order(ByteOrder.nativeOrder());floatArrayOf(r.cx,r.cy,r.width/2,r.height/2).forEachIndexed{i,v->b.putFloat(16+i*4,v)};corners(s,r,radius).forEachIndexed{i,v->b.putFloat(32+i*4,v)}
   val blur=if(s.flag("androidBlur"))0f else GlassBlur.radius(s.number("blurStrength"));val mix=if(s.flag("androidBlur"))0f else GlassBlur.contribution(s.number("blurStrength"))
   return when(s.profile){
    1->base
    2->{val second=rects.getOrNull(1);GlassLabGeometry.mergePacket(base,r,second,radius,s.number("merge")*density,blur,mix)}
    3->{val shapes=rects.take(13).mapIndexed{index,it->floatArrayOf(it.cx,it.cy,it.width/2,it.height/2,min(radius,min(it.width,it.height)/2),s.number("merge")*density,regionAlpha(s,index),0f)}.toTypedArray();val pills=if(nativeForegroundMode&&!s.flag("controlMaskPreview"))emptyArray<FloatArray>()else rects.take(10).map{floatArrayOf(it.left+it.width-20*density,it.top+18*density,13*density,9*density)}.toTypedArray();CardNotificationUniforms.cluster(base,shapes,pills,blur,mix,if(s.flag("androidBlur"))0f else s.number("pillBlur"))}
    else->{val shapes=(shapeOverride?:rects).take(16).mapIndexed{index,it->val c=corners(s,it,radius);floatArrayOf(it.cx,it.cy,it.width/2,it.height/2,c[0],c[1],c[2],c[3],0f,0f,regionAlpha(s,index),0f,it.left,it.top,it.left+it.width*s.number("regionClip"),it.top+it.height)}.toTypedArray();val indicator=indicator(s,r,progress);val mask=if(s.scene==0)GlassSliderGeometry.mask(r.left,r.top,r.width,r.height,progress,radius,if(s.flag("androidBlur"))0f else GlassBlur.radius(s.number("progressBlur")),if(s.flag("verticalSlider"))2f else if(s.flag("rtl"))1f else 0f,r.left,r.top,r.left+r.width,r.top+r.height)else null;val thumb=if(s.scene==0)GlassSliderGeometry.mask(indicator.left,indicator.top,indicator.width(),indicator.height(),1f,indicator.width()/2,if(s.flag("androidBlur"))0f else GlassBlur.radius(s.number("indicatorBlur")),1f,r.left,r.top,r.left+r.width,r.top+r.height)else null;NativeQsUniforms.pack(base,shapes,blur,mix,mask,thumb)}
   }
  }
  private fun regionAlpha(s:GlassLabState,index:Int)=if(s.scene==7&&index==disabled).3f else if(index%2==1)s.number("regionAlpha")else 1f
  private fun indicator(s:GlassLabState,r:GlassLabRect,p:Float):RectF{val marker=GlassLabGeometry.sliderIndicator(r,p,s.flag("verticalSlider"),s.flag("rtl"),8*density,10*density);return RectF(marker.left,marker.top,marker.left+marker.width,marker.top+marker.height)}
  private fun drawProtectedLabel(canvas:Canvas,label:String,r:GlassLabRect,color:Int,alpha:Float,font:Float,clip:Float){
   val save=canvas.save();canvas.clipRect(r.left,r.top,r.left+r.width*clip,r.top+r.height)
   paint.shader=null;paint.textSize=min(font*resources.displayMetrics.scaledDensity,16*density);paint.typeface=Typeface.DEFAULT_BOLD
   val x=r.cx-paint.measureText(label)/2;val y=r.cy+paint.textSize*.35f
   paint.style=Paint.Style.STROKE;paint.color=ink.outline(color);paint.alpha=(paint.alpha*alpha).roundToInt();paint.strokeWidth=2*ink.outlineWidth*density;paint.setShadowLayer(ink.shadowRadius*density,ink.shadowX*density,ink.shadowY*density,ink.shadow(color))
   if(ink.outlineOpacity>0&&ink.outlineWidth>0)canvas.drawText(label,x,y,paint)
   paint.style=Paint.Style.FILL;paint.color=color;paint.alpha=(255*alpha).roundToInt();canvas.drawText(label,x,y,paint);paint.clearShadowLayer();paint.alpha=255;canvas.restoreToCount(save)
  }
  private fun drawForeground(canvas:Canvas,s:GlassLabState,r:GlassLabRect,radius:Float,progress:Float){
   val inferred=if(s.background==1).85f else if(s.background==2).5f else .12f
   val color=if(s.flag("autoInk"))GlassContrast.foreground(0,inferred,0)else s.color("inkColor")
   paint.shader=null;paint.style=Paint.Style.STROKE;paint.strokeWidth=density;paint.color=0xbfffffff.toInt()
   if(s.flag("border"))for((index,rect)in rects.withIndex()){val saved=canvas.save();if(s.profile==4)canvas.clipRect(rect.left,rect.top,rect.left+rect.width*s.number("regionClip"),rect.top+rect.height);paint.alpha=(191*(if(s.profile in listOf(3,4))regionAlpha(s,index)else 1f)).roundToInt();val c=corners(s,rect,min(radius,min(rect.width,rect.height)/2));path.reset();path.addRoundRect(RectF(rect.left,rect.top,rect.left+rect.width,rect.top+rect.height),floatArrayOf(c[0],c[0],c[1],c[1],c[2],c[2],c[3],c[3]),Path.Direction.CW);canvas.drawPath(path,paint);canvas.restoreToCount(saved)};paint.alpha=255
   if(s.scene==0){val marker=indicator(s,r,progress);paint.color=color;canvas.drawRoundRect(marker,marker.width()/2,marker.width()/2,paint)}
   if(s.scene in listOf(6,7)){
    val order=rects.indices.filter{it!=interaction.selected}+listOf(interaction.selected).filter{it in rects.indices}
    for(index in order){val rect=rects[index];val label=if(s.scene==6)"Drag ${index+1}" else if(index==disabled)"Disabled" else "${index+1} ${if(interaction.toggled(index))"ON ✓"else"OFF"}";drawProtectedLabel(canvas,label,rect,color,if(index==disabled).35f else 1f,s.number("font"),if(s.profile==4)s.number("regionClip")else 1f)}
    return
   }
   val sample=if(s.scene==0)"${(progress*100).roundToInt()}%"else s.text
   paint.textSize=s.number("font")*resources.displayMetrics.scaledDensity;paint.typeface=Typeface.DEFAULT_BOLD
   val x=r.left+44*density;val y=r.cy+paint.textSize*.35f
   paint.setShadowLayer(ink.shadowRadius*density,ink.shadowX*density,ink.shadowY*density,ink.shadow(color))
   paint.style=Paint.Style.STROKE;paint.strokeWidth=2*ink.outlineWidth*density;paint.color=ink.outline(color)
   if(ink.outlineOpacity>0&&ink.outlineWidth>0)canvas.drawText(sample,x,y,paint)
   if(ink.outlineOpacity==0f||ink.outlineWidth==0f){paint.style=Paint.Style.FILL;paint.color=color;canvas.drawText(sample,x,y,paint)}
   paint.clearShadowLayer();paint.style=Paint.Style.FILL;paint.color=color;canvas.drawText(sample,x,y,paint)
   path.reset();val cx=r.left+23*density;val cy=r.cy;path.addCircle(cx,cy,5*density,Path.Direction.CW);for(i in 0..7){val a=i*PI/4;path.moveTo(cx+cos(a).toFloat()*8*density,cy+sin(a).toFloat()*8*density);path.lineTo(cx+cos(a).toFloat()*11*density,cy+sin(a).toFloat()*11*density)}
   paint.style=Paint.Style.STROKE;paint.setShadowLayer(ink.shadowRadius*density,ink.shadowX*density,ink.shadowY*density,ink.shadow(color));paint.color=ink.outline(color);paint.strokeWidth=(1.5f+2*ink.outlineWidth)*density;if(ink.outlineOpacity>0&&ink.outlineWidth>0)canvas.drawPath(path,paint);paint.color=color;paint.strokeWidth=1.5f*density;canvas.drawPath(path,paint);paint.clearShadowLayer()
   if(s.profile==3){paint.style=Paint.Style.FILL;paint.textSize=12*density;for((i,rect)in rects.withIndex())canvas.drawText("${i+1}⌄",rect.left+rect.width-30*density,rect.top+22*density,paint)}
  }
 }
}

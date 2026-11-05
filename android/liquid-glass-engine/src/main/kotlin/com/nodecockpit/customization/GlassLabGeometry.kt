package com.nodecockpit.customization
import kotlin.math.*
data class GlassLabRect(val left:Float,val top:Float,val width:Float,val height:Float){val cx get()=left+width/2;val cy get()=top+height/2}
object GlassLabGeometry {
 private fun sliderFraction(value:Float)=GlassSliderGeometry.fraction(value)
 fun sliderProgress(r:GlassLabRect,x:Float,y:Float,vertical:Boolean,rtl:Boolean):Float {
  val value=if(vertical)1f-(y-r.top)/max(1f,r.height)else (x-r.left)/max(1f,r.width)
  return sliderFraction(if(!vertical&&rtl)1f-value else value)
 }
 fun sliderFill(r:GlassLabRect,progress:Float,vertical:Boolean,rtl:Boolean):GlassLabRect {
  val fill=GlassSliderGeometry.fill(r.left,r.top,r.width,r.height,progress,vertical,rtl)
  return GlassLabRect(fill[0],fill[1],fill[2],fill[3])
 }
 fun sliderIndicator(r:GlassLabRect,progress:Float,vertical:Boolean,rtl:Boolean,inset:Float,thickness:Float):GlassLabRect {
  val p=sliderFraction(progress);val span=if(vertical)r.height else r.width
  val thick=thickness.coerceIn(0f,max(0f,span));val pad=min(max(inset,thick/2),span/2)
  val position=((if(vertical||rtl)1-p else p)*span).coerceIn(pad,span-pad)
  return if(vertical)GlassLabRect(r.left+r.width*.2f,r.top+position-thick/2,r.width*.6f,thick)
   else GlassLabRect(r.left+position-thick/2,r.top+r.height*.2f,thick,r.height*.6f)
 }
 fun phase(elapsed:Long,duration:Float,enabled:Boolean):Pair<Long,Float>{val span=(if(duration.isFinite())duration else 1600f).toLong().coerceAtLeast(1);val now=elapsed.coerceAtLeast(0);val cycle=now/span;val raw=(now%span).toFloat()/span;return cycle to if(!enabled).5f else if(cycle%2L==0L)raw else 1-raw}

 fun regions(s:GlassLabState,w:Float,h:Float,density:Float,phase:Float):List<GlassLabRect>{
  if(!w.isFinite()||!h.isFinite()||w<=1||h<=1)return emptyList()
  val p=if(phase.isFinite())phase.coerceIn(0f,1f)else 0f
  val margin=min(16*density,min(w,h)/8);val availableW=max(1f,w-2*margin);val availableH=max(1f,h-2*margin)
  val resizing=s.motion in listOf(2,8);val fraction=if(resizing).5f+.5f*p else 1f
  var rw=(availableW*s.number("width")*fraction).coerceIn(1f,availableW);var rh=(availableH*s.number("height")*fraction).coerceIn(1f,availableH)
  if(s.scene==2){val side=min(rw,rh);rw=side;rh=side}
  val offset=if(s.motion in listOf(1,8))p else s.number("offset")
  val x=(w-rw)/2;val y=margin+(availableH-rh)*offset
  val first=GlassLabRect(x,y,rw,rh)
  if(s.scene==6){val limit=if(s.profile in listOf(0,2))2 else if(s.profile==3)13 else 16;val n=s.number("count").roundToInt().coerceIn(1,limit);val cardW=min(availableW*.68f,220*density);val cardH=min(availableH*.48f,100*density);return (0 until n).map{val t=if(n==1).5f else it.toFloat()/(n-1);GlassLabRect(margin+t*(availableW-cardW),margin+t*(availableH-cardH),cardW,cardH)}}
  if(s.scene==7){val limit=if(s.profile in listOf(0,2))2 else 6;val n=s.number("count").roundToInt().coerceIn(1,limit);val cols=min(3,n);val rows=ceil(n/cols.toFloat()).toInt();val gap=min(10*density,min(availableW/max(1,cols*2),availableH/max(1,rows*2)));val bw=max(1f,(availableW-(cols-1)*gap)/cols);val bh=min(74*density,max(1f,(availableH-(rows-1)*gap)/rows));return (0 until n).map{GlassLabRect(margin+(it%cols)*(bw+gap),margin+(it/cols)*(bh+gap),bw,bh)}}
  if(s.scene==5){val maxCount=if(s.profile==3)13 else if(s.profile==4)16 else 2;val n=s.number("count").roundToInt().coerceIn(1,maxCount);val cols=if(n>4)4 else 2;val rows=ceil(n/cols.toFloat()).toInt();val gap=min(8*density,min(availableW/max(1,cols*2),availableH/max(1,rows*2)));val cw=max(1f,(availableW-(cols-1)*gap)/cols);val ch=max(1f,(availableH-(rows-1)*gap)/rows);return (0 until n).map{GlassLabRect(margin+(it%cols)*(cw+gap),margin+(it/cols)*(ch+gap),cw,ch)}}
  if(s.scene==4){val side=min(availableH*.6f,availableW*.43f);val separation=(.45f+s.number("separation")*.7f)*side;return listOf(GlassLabRect(w/2-separation-side/2,h/2-side/2,side,side),GlassLabRect(w/2+separation-side*s.number("secondaryWidth")/2,h/2-side*s.number("secondaryHeight")/2,side*s.number("secondaryWidth"),side*s.number("secondaryHeight")))}
  return listOf(first)
 }
 fun mergePacket(base:ByteArray,first:GlassLabRect,second:GlassLabRect?,radius:Float,blend:Float,blur:Float,mix:Float):ByteArray=CardMergeUniforms.extend(base,floatArrayOf(first.cx,first.cy,first.width/2,first.height/2,radius,second?.cx?:0f,second?.cy?:0f,(second?.width?:0f)/2,(second?.height?:0f)/2,if(second==null)radius else min(radius,min(second.width,second.height)/2),if(second==null)0f else blend,blur,mix))
 fun progress(s:GlassLabState,phase:Float)=if(s.motion in listOf(5,8))phase.coerceIn(0f,1f)else s.number("progress")
 fun alpha(s:GlassLabState,phase:Float)=s.number("alpha")*(if(s.motion in listOf(3,8))phase.coerceIn(0f,1f)else 1f)
}

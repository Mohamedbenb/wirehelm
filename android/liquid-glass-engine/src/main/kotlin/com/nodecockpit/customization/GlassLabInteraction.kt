package com.nodecockpit.customization

import kotlin.math.*
/** Lab host gestures/actions. Material/merge/ripple rendering remains in the engine. */
class GlassLabInteraction {
 private data class Capture(val index:Int,val downX:Float,val downY:Float,val left:Float,val top:Float,var moved:Boolean=false)
 private val captures=mutableMapOf<Int,Capture>()
 private val locations=mutableMapOf<Int,Pair<Float,Float>>()
 private val toggles=mutableSetOf<Int>()
 private val clicks=mutableMapOf<Int,Int>()
 var selected=-1;private set
 val pointerCount get()=captures.size
 val clickCount get()=clicks.values.sum()
 fun hasPointer(pointer:Int)=captures.containsKey(pointer)
 fun toggled(index:Int)=index in toggles
 fun clicks(index:Int)=clicks[index]?:0
 fun cancel(){captures.clear()}
 fun reset(){captures.clear();locations.clear();toggles.clear();clicks.clear();selected=-1}
 fun savePositions():FloatArray=locations.entries.sortedBy{it.key}.flatMap{listOf(it.key.toFloat(),it.value.first,it.value.second)}.toFloatArray()
 fun restorePositions(values:FloatArray){
  require(values.size%3==0&&values.size<=48)
  val restored=mutableMapOf<Int,Pair<Float,Float>>()
  for(i in values.indices step 3){val index=values[i];val x=values[i+1];val y=values[i+2]
   require(index.isFinite()&&index==index.toInt().toFloat()&&index in 0f..15f&&x.isFinite()&&y.isFinite()&&x in 0f..1f&&y in 0f..1f)
   restored[index.toInt()]=x to y
  }
  cancel();locations.clear();locations.putAll(restored)
 }
 fun layout(base:List<GlassLabRect>,width:Float,height:Float):List<GlassLabRect>{
  captures.entries.removeAll{it.value.index !in base.indices};if(selected !in base.indices)selected=-1
  locations.keys.retainAll(base.indices.toSet());toggles.retainAll(base.indices.toSet());clicks.keys.retainAll(base.indices.toSet())
  return base.mapIndexed{i,r->locations[i]?.let{r.copy(left=it.first*max(0f,width-r.width),top=it.second*max(0f,height-r.height))}?:r}
 }
 fun down(pointer:Int,x:Float,y:Float,regions:List<GlassLabRect>,disabled:Int=-1):Boolean{
  if(captures.containsKey(pointer)||!x.isFinite()||!y.isFinite())return false
  val order=(regions.indices.filter{it!=selected}+listOf(selected).filter{it in regions.indices}).asReversed()
  val index=order.firstOrNull{it!=disabled&&captures.values.none{c->c.index==it}&&contains(regions[it],x,y)}?:return false
  val r=regions[index];captures[pointer]=Capture(index,x,y,r.left,r.top);selected=index;return true
 }
 fun move(pointer:Int,x:Float,y:Float,regions:List<GlassLabRect>,width:Float,height:Float,drag:Boolean,slop:Float){
  val c=captures[pointer]?:return;if(!x.isFinite()||!y.isFinite()||c.index !in regions.indices)return
  if(hypot(x-c.downX,y-c.downY)>slop)c.moved=true
  if(drag&&c.moved){val r=regions[c.index];val w=max(0f,width-r.width);val h=max(0f,height-r.height);locations[c.index]=Pair(if(w==0f)0f else ((c.left+x-c.downX)/w).coerceIn(0f,1f),if(h==0f)0f else ((c.top+y-c.downY)/h).coerceIn(0f,1f))}
 }
 fun up(pointer:Int,x:Float,y:Float,regions:List<GlassLabRect>,toggle:Boolean):Int?{
  val c=captures.remove(pointer)?:return null
  if(c.moved||c.index !in regions.indices||!contains(regions[c.index],x,y))return null
  clicks[c.index]=(clicks[c.index]?:0)+1;if(toggle&&!toggles.add(c.index))toggles.remove(c.index)
  return c.index
 }
 private fun contains(r:GlassLabRect,x:Float,y:Float)=x>=r.left&&y>=r.top&&x<=r.left+r.width&&y<=r.top+r.height
}

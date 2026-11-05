package com.example.remote_control.glasscard
import kotlin.math.*
/** Fixed four-pulse history, driven by known touches rather than background capture. */
class TouchRippleState {
 companion object {
  const val COUNT=4
  fun lifetime(speed:Float,damping:Float):Float {
   val s=if(speed.isFinite())speed.coerceIn(.25f,2.5f) else 1f
   val d=if(damping.isFinite())damping.coerceIn(.3f,3f) else 1.4f
   return min(4.5f,min(1f/s+.4f,ln(100f)/d))
  }
  fun emptyFrame()=FloatArray(16).also{for(i in 0 until COUNT)it[i*4+2]=-1f}
 }
 private class Pulse {var x=0f;var y=0f;var began=0L;var sign=0f}
 private val pulses=Array(COUNT){Pulse()};private var next=0
 fun emit(x:Float,y:Float,nowMs:Long,release:Boolean){val e=pulses[next];e.x=if(x.isFinite())x.coerceIn(0f,1f) else .5f;e.y=if(y.isFinite())y.coerceIn(0f,1f) else .5f;e.began=nowMs;e.sign=if(release)-1f else 1f;next=(next+1)%COUNT}
 fun frame(nowMs:Long,lifetime:Float):FloatArray {val out=emptyFrame();for(i in pulses.indices){val e=pulses[i];if(e.sign==0f)continue;val age=max(0L,nowMs-e.began)/1000f;if(age>=lifetime){e.sign=0f;continue};val k=i*4;out[k]=e.x;out[k+1]=e.y;out[k+2]=age;out[k+3]=e.sign};return out}
 fun active()=pulses.any{it.sign!=0f}
 fun clear(){pulses.forEach{it.sign=0f};next=0}
}

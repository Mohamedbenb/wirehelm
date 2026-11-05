package com.example.remote_control.glasscard
import kotlin.math.sqrt
/** One material-independent public blur strength; old settings migrate by blur variance. */
object GlassBlur {
 private fun finite(v:Float)=if(v.isFinite())v else 0f
 fun radius(strength:Float)=48f*finite(strength).coerceIn(0f,100f)/100f
 fun contribution(strength:Float):Float {val t=(finite(strength)/10f).coerceIn(0f,1f);return t*t*(3f-2f*t)}
 fun fromLegacy(radius:Float,mix:Float,clear:Boolean):Float {
  val target=finite(radius).coerceIn(0f,48f)*(if(clear).35f else 1f)*sqrt(finite(mix).coerceIn(0f,1f))
  if(target<=0)return 0f
  var lo=0f;var hi=100f
  repeat(24){val mid=(lo+hi)*.5f;val effective=GlassBlur.radius(mid)*sqrt(contribution(mid));if(effective<target)lo=mid else hi=mid}
  return (lo+hi)*.5f
 }
}

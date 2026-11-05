package com.example.remote_control.glasscard
import kotlin.math.pow
/** Chooses the higher contrast outline against the actual native glyph colour. */
object ForegroundInkPolicy {
 fun luminance(color:Int):Double {fun channel(v:Int):Double{val s=v/255.0;return if(s<=.04045)s/12.92 else ((s+.055)/1.055).pow(2.4)};return .2126*channel(color shr 16 and 255)+.7152*channel(color shr 8 and 255)+.0722*channel(color and 255)}
 fun outline(color:Int):Int=if((luminance(color)+.05)/.05 >= 1.05/(luminance(color)+.05))0xff000000.toInt() else 0xffffffff.toInt()
 fun contrast(a:Int,b:Int):Double{val x=luminance(a);val y=luminance(b);return (maxOf(x,y)+.05)/(minOf(x,y)+.05)}
}

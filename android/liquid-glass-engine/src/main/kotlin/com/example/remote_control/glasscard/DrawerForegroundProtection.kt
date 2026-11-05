package com.example.remote_control.glasscard
import android.graphics.*
import android.graphics.drawable.Drawable
import android.text.TextPaint
import android.view.View
import android.widget.*
/** Native Layout glyphs and icon drawables stay native. No backdrop sampling or foreground bitmap. */
object DrawerForegroundProtection {
 fun text(v:TextView){if(v.background !is GlyphOutline){val left=v.paddingLeft;val top=v.paddingTop;val right=v.paddingRight;val bottom=v.paddingBottom;val d=GlyphOutline(v,v.background);v.background=d;d.bind();val pad=kotlin.math.ceil(1.5*v.resources.displayMetrics.density).toInt();v.setPadding(left+pad,top+pad,right+pad,bottom+pad)};val outline=ForegroundInkPolicy.outline(v.currentTextColor);v.setShadowLayer(2f*v.resources.displayMetrics.density,0f,.6f*v.resources.displayMetrics.density,outline)}
 fun icon(v:ImageView,ink:Int){val d=v.drawable ?: return;if(d !is IconOutline){val wrapped=IconOutline(d,v.resources.displayMetrics.density,ink);v.setImageDrawable(wrapped);wrapped.bind()}}
 fun tree(v:View,ink:Int){when(v){is TextView->text(v);is ImageView->icon(v,ink)};if(v is android.view.ViewGroup)for(i in 0 until v.childCount)tree(v.getChildAt(i),ink)}
 private class GlyphOutline(val label:TextView,val base:Drawable?):Drawable(),Drawable.Callback{
  fun bind(){base?.callback=this}
  override fun invalidateDrawable(who:Drawable){invalidateSelf()}
  override fun scheduleDrawable(who:Drawable,what:Runnable,whenMs:Long){scheduleSelf(what,whenMs)}
  override fun unscheduleDrawable(who:Drawable,what:Runnable){unscheduleSelf(what)}
  override fun setHotspot(x:Float,y:Float){base?.setHotspot(x,y)}
  override fun jumpToCurrentState(){base?.jumpToCurrentState()}
  private val saved=TextPaint();private val density=label.resources.displayMetrics.density
  override fun draw(c:Canvas){base?.let{it.bounds=bounds;it.draw(c)};val layout=label.layout ?: return;val paint=layout.paint;saved.set(paint);val save=c.save()
   try{c.translate((label.totalPaddingLeft-label.scrollX).toFloat(),(label.totalPaddingTop-label.scrollY).toFloat());val outline=ForegroundInkPolicy.outline(label.currentTextColor)
    paint.clearShadowLayer();paint.style=Paint.Style.STROKE;paint.strokeJoin=Paint.Join.ROUND;paint.strokeCap=Paint.Cap.ROUND
    paint.strokeWidth=2.4f*density;paint.color=if(outline==Color.BLACK)0x70ffffff else 0x70000000;layout.draw(c)
    paint.strokeWidth=1.15f*density;paint.color=outline;layout.draw(c)
   }finally{paint.set(saved);c.restoreToCount(save)}
  }
  override fun isStateful()=base?.isStateful ?: false
  override fun onStateChange(state:IntArray):Boolean=base?.setState(state) ?: false
  override fun onLevelChange(level:Int)=base?.setLevel(level) ?: false
  override fun getPadding(padding:Rect)=base?.getPadding(padding) ?: false
  override fun setAlpha(alpha:Int){base?.alpha=alpha}
  override fun setColorFilter(filter:ColorFilter?){base?.colorFilter=filter}
  @Deprecated("Deprecated in Java")override fun getOpacity()=PixelFormat.TRANSLUCENT
 }
 private class IconOutline(val inner:Drawable,val density:Float,val ink:Int):Drawable(),Drawable.Callback{
  private var drawing=false
  fun bind(){inner.callback=this}
  override fun invalidateDrawable(who:Drawable){if(!drawing)invalidateSelf()}
  override fun scheduleDrawable(who:Drawable,what:Runnable,whenMs:Long){scheduleSelf(what,whenMs)}
  override fun unscheduleDrawable(who:Drawable,what:Runnable){unscheduleSelf(what)}
  override fun jumpToCurrentState(){inner.jumpToCurrentState()}
  private val offsets=floatArrayOf(-1f,0f,1f,0f,0f,-1f,0f,1f,-.707f,-.707f,.707f,-.707f,-.707f,.707f,.707f,.707f)
  private val shadow=PorterDuffColorFilter(0x80000000.toInt(),PorterDuff.Mode.SRC_IN)
  private val border=PorterDuffColorFilter(ForegroundInkPolicy.outline(ink),PorterDuff.Mode.SRC_IN)
  private val outer=PorterDuffColorFilter(if(ForegroundInkPolicy.outline(ink)==Color.BLACK)0x60ffffff else 0x60000000,PorterDuff.Mode.SRC_IN)
  private var filter:ColorFilter?=inner.colorFilter
  override fun draw(c:Canvas){drawing=true;inner.bounds=bounds;val original=inner.colorFilter
   try{inner.colorFilter=shadow;val shadowSave=c.save();c.translate(0f,1.2f*density);inner.draw(c);c.restoreToCount(shadowSave);for(ring in 0..1){inner.colorFilter=if(ring==0)outer else border;val r=density*(if(ring==0)1.5f else .75f);for(i in offsets.indices step 2){val save=c.save();c.translate(offsets[i]*r,offsets[i+1]*r);inner.draw(c);c.restoreToCount(save)}};inner.colorFilter=filter;inner.draw(c)}finally{inner.colorFilter=original;drawing=false}
  }
  override fun onBoundsChange(b:Rect){inner.bounds=b}
  override fun getIntrinsicWidth()=inner.intrinsicWidth
  override fun getIntrinsicHeight()=inner.intrinsicHeight
  override fun isStateful()=inner.isStateful
  override fun onStateChange(state:IntArray)=inner.setState(state)
  override fun setAlpha(alpha:Int){inner.alpha=alpha}
  override fun setColorFilter(f:ColorFilter?){filter=f;invalidateSelf()}
  @Deprecated("Deprecated in Java")override fun getOpacity()=PixelFormat.TRANSLUCENT
 }
}

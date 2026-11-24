package com.nodecockpit.customization;
import android.graphics.*;
import android.graphics.drawable.*;
import android.text.*;
import android.view.View;
import android.widget.*;
import java.lang.ref.WeakReference;
/** Draws the existing label outline and a quiet shadow behind native adaptive icons. */
final class EdgeInkBacking extends GradientDrawable implements Drawable.Callback {
 private final WeakReference<View> owner;
 private final Drawable base;
 private final TextPaint saved=new TextPaint();
 private Paint appIconShadow;
 private Layout hintOwnerLayout, hintLayout;
 private CharSequence cachedHint;
 EdgeInkBacking(View v,Drawable original){owner=new WeakReference<>(v);base=original;if(base!=null)base.setCallback(this);}
 void bind(){if(base!=null)base.setCallback(this);}
 @Override public void invalidateDrawable(Drawable who){invalidateSelf();}
 @Override public void scheduleDrawable(Drawable who,Runnable what,long when){scheduleSelf(what,when);}
 @Override public void unscheduleDrawable(Drawable who,Runnable what){unscheduleSelf(what);}
 @Override public boolean isStateful(){return base!=null&&base.isStateful()||super.isStateful();}
 @Override protected boolean onStateChange(int[] state){boolean changed=super.onStateChange(state);return base!=null&&base.setState(state)||changed;}
 @Override public void setHotspot(float x,float y){if(base!=null)base.setHotspot(x,y);}
 @Override public void jumpToCurrentState(){super.jumpToCurrentState();if(base!=null)base.jumpToCurrentState();}
 @Override public boolean getPadding(Rect p){return base!=null&&base.getPadding(p);}
 @Override public void draw(Canvas c){
  View v=owner.get();if(v==null)return;
  if(base!=null){base.setBounds(getBounds());base.draw(c);}super.draw(c);
  float d=v.getResources().getDisplayMetrics().density;
  if(v instanceof TextView){TextView label=(TextView)v;Layout layout=labelLayout(label);if(layout==null)return;
   int ink=label.getText().length()==0?label.getCurrentHintTextColor():label.getCurrentTextColor();
   int outline=outline(ink);TextPaint paint=layout.getPaint();saved.set(paint);int save=c.save();
   try{c.clipRect(label.getCompoundPaddingLeft(),label.getExtendedPaddingTop(),v.getWidth()-label.getCompoundPaddingRight(),v.getHeight()-label.getExtendedPaddingBottom());c.translate(label.getCompoundPaddingLeft()-label.getScrollX(),label.getTotalPaddingTop()-label.getScrollY());
    paint.clearShadowLayer();paint.setStyle(Paint.Style.STROKE);paint.setStrokeJoin(Paint.Join.ROUND);paint.setStrokeCap(Paint.Cap.ROUND);
    paint.setStrokeWidth(2.4f*d);paint.setColor(outline==Color.BLACK?0x70ffffff:0x70000000);layout.draw(c);
    paint.setStrokeWidth(1.15f*d);paint.setColor(outline);layout.draw(c);
   }finally{paint.set(saved);c.restoreToCount(save);}
  }else if(v instanceof ImageView image&&image.getDrawable() instanceof AdaptiveIconDrawable icon){
   if(icon.getBounds().isEmpty())return;
   if(appIconShadow==null){
    appIconShadow=new Paint(Paint.ANTI_ALIAS_FLAG);
    appIconShadow.setColor(0x1210161d);
   }
   float unit=d/Math.max(.01f,image.getImageMatrix().mapRadius(1f));
   appIconShadow.setShadowLayer(unit,0,.5f*unit,0x3010161d);
   int save=c.save();
   c.translate(image.getPaddingLeft(),image.getPaddingTop());
   c.concat(image.getImageMatrix());
   c.drawPath(icon.getIconMask(),appIconShadow);
   c.restoreToCount(save);
  }
 }
 private Layout labelLayout(TextView label){
  Layout layout=label.getLayout();
  CharSequence hint=label.getHint();
  if(layout==null||label.length()!=0||TextUtils.isEmpty(hint)||layout.getWidth()<=0)return layout;
  if(hintOwnerLayout!=layout||!TextUtils.equals(hint,cachedHint)){
   hintOwnerLayout=layout;cachedHint=hint;
   hintLayout=StaticLayout.Builder.obtain(hint,0,hint.length(),new TextPaint(layout.getPaint()),layout.getWidth())
    .setAlignment(layout.getAlignment()).setIncludePad(label.getIncludeFontPadding())
    .setMaxLines(Math.max(1,label.getMaxLines())).setEllipsize(TextUtils.TruncateAt.END).build();
  }
  return hintLayout;
 }
 private static int outline(int ink){double r=channel(Color.red(ink)),g=channel(Color.green(ink)),b=channel(Color.blue(ink));return .2126*r+.7152*g+.0722*b>.179?Color.BLACK:Color.WHITE;}
 private static double channel(int c){double s=c/255.;return s<=.04045?s/12.92:Math.pow((s+.055)/1.055,2.4);}
}

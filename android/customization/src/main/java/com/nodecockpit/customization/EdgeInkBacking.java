package com.nodecockpit.customization;
import android.graphics.*;
import android.graphics.drawable.*;
import android.text.*;
import android.view.View;
import android.widget.*;
import java.lang.ref.WeakReference;
/** Reuses Drawer Studio's native Layout outline technique. No masks, sampling, timers or glyph replacement. */
final class EdgeInkBacking extends GradientDrawable implements Drawable.Callback {
 private final WeakReference<View> owner;
 private final Drawable base;
 private final TextPaint saved=new TextPaint();
 private Drawable iconBorder,iconHalo,sourceIcon;
 private ForegroundInkStyle lastProtection;private int lastInk=Color.WHITE;private final boolean compactIcons;
 EdgeInkBacking(View v,Drawable original){this(v,original,false);}
 EdgeInkBacking(View v,Drawable original,boolean compact){compactIcons=compact;owner=new WeakReference<>(v);base=original;if(base!=null)base.setCallback(this);}
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
  if(v instanceof TextView){TextView label=(TextView)v;Layout layout=label.getLayout();if(layout==null)return;
   int ink=label.getText().length()==0?label.getCurrentHintTextColor():label.getCurrentTextColor();
   ForegroundInkStyle protection=compactIcons?ForegroundInkStyle.current:ForegroundInkStyle.DEFAULT;int outline=compactIcons?protection.outline(ink):outline(ink);TextPaint paint=layout.getPaint();saved.set(paint);int save=c.save();
   try{c.clipRect(label.getCompoundPaddingLeft(),label.getExtendedPaddingTop(),v.getWidth()-label.getCompoundPaddingRight(),v.getHeight()-label.getExtendedPaddingBottom());c.translate(label.getCompoundPaddingLeft()-label.getScrollX(),label.getTotalPaddingTop()-label.getScrollY());
    paint.clearShadowLayer();paint.setStyle(Paint.Style.STROKE);paint.setStrokeJoin(Paint.Join.ROUND);paint.setStrokeCap(Paint.Cap.ROUND);
    if(!compactIcons){paint.setStrokeWidth(2.4f*d);paint.setColor(outline==Color.BLACK?0x70ffffff:0x70000000);layout.draw(c);}
    if(!compactIcons||protection.outlineWidth>0&&protection.outlineOpacity>0){paint.setStrokeWidth((compactIcons?2*protection.outlineWidth:1.15f)*d);paint.setColor(outline);layout.draw(c);}
   }finally{paint.set(saved);c.restoreToCount(save);}
  }else if(v instanceof ImageView){ImageView image=(ImageView)v;Drawable icon=image.getDrawable();if(icon==null||icon.getConstantState()==null)return;
   int ink=lastInk;
   if(iconBorder==null||sourceIcon!=icon){sourceIcon=icon;iconBorder=icon.getConstantState().newDrawable().mutate();iconHalo=icon.getConstantState().newDrawable().mutate();}
   ForegroundInkStyle protection=compactIcons?ForegroundInkStyle.current:ForegroundInkStyle.DEFAULT;iconBorder.setColorFilter(compactIcons?protection.outline(ink):outline(ink),PorterDuff.Mode.SRC_IN);iconHalo.setColorFilter(compactIcons?protection.shadow(ink):outline(ink)==Color.BLACK?0x70ffffff:0x70000000,PorterDuff.Mode.SRC_IN);
   int save=c.save();c.translate(image.getPaddingLeft(),image.getPaddingTop());c.concat(image.getImageMatrix());iconBorder.setBounds(icon.getBounds());iconHalo.setBounds(icon.getBounds());
   // Outline copies are separate drawables, so drawing never invalidates the native icon.
   if(compactIcons){for(int ring=0;ring<2;ring++){if(ring==0?protection.shadowOpacity<=0:protection.outlineOpacity<=0||protection.outlineWidth<=0)continue;for(int i=0;i<4;i++){int z=c.save();double a=i*Math.PI/2;float radius=ring==0?protection.shadowRadius:protection.outlineWidth;c.translate(((float)Math.cos(a)*radius+(ring==0?protection.shadowX:0))*d,((float)Math.sin(a)*radius+(ring==0?protection.shadowY:0))*d);(ring==0?iconHalo:iconBorder).draw(c);c.restoreToCount(z);}}}else for(int ring=0;ring<2;ring++){float radius=(ring==0?1.5f:.75f)*d;Drawable layer=ring==0?iconHalo:iconBorder;
    for(int i=0;i<8;i++){double a=i*Math.PI/4;int s=c.save();c.translate((float)Math.cos(a)*radius,(float)Math.sin(a)*radius);layer.draw(c);c.restoreToCount(s);}}
   c.restoreToCount(save);
  }
 }
 void ink(int color){lastInk=color;if(compactIcons&&lastProtection!=ForegroundInkStyle.current){lastProtection=ForegroundInkStyle.current;invalidateSelf();}}
 private static int outline(int ink){double r=channel(Color.red(ink)),g=channel(Color.green(ink)),b=channel(Color.blue(ink));return .2126*r+.7152*g+.0722*b>.179?Color.BLACK:Color.WHITE;}
 private static double channel(int c){double s=c/255.;return s<=.04045?s/12.92:Math.pow((s+.055)/1.055,2.4);}
}

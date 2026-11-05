package com.nodecockpit.customization;

import android.graphics.*;
import android.graphics.drawable.Drawable;

/** Native bitmap/vector glyph decoration. Alpha masks are cached; no backdrop is sampled. */
public final class GlassInkDrawable extends Drawable implements Drawable.Callback {
 private final Drawable source;
 private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
 private ForegroundInkStyle style=ForegroundInkStyle.DEFAULT;
 private int ink=Color.WHITE,opacity=255,padding;
 private float density=1f;
 private Bitmap fill,outline,shadow;
 private final int[] shadowOffset=new int[2];
 private boolean dirty=true,building;

 public GlassInkDrawable(Drawable source){if(source==null)throw new IllegalArgumentException("Glyph required");this.source=source.mutate();this.source.setCallback(this);}
 public void configure(ForegroundInkStyle next,int color,float scale){
  if(next==null||!Float.isFinite(scale)||scale<=0)throw new IllegalArgumentException("Valid style/density required");
  if(style.outlineWidth!=next.outlineWidth||style.shadowRadius!=next.shadowRadius||density!=scale)dirty=true;
  style=next;ink=color;density=scale;invalidateSelf();
 }
 // Published masks may still be held by a RenderThread display list; drop ownership
 // and let Android retire them rather than recycling their pixels prematurely.
 public void release(){fill=outline=shadow=null;dirty=true;}
 private void rebuild(int width,int height){
  release();building=true;
  try{
   Bitmap original=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);
   try{source.setBounds(0,0,width,height);source.draw(new Canvas(original));fill=original.extractAlpha();}finally{original.recycle();}
   float radius=style.outlineWidth*density;
   padding=(int)Math.ceil(radius);
   if(padding>0){
    Bitmap expanded=Bitmap.createBitmap(width+padding*2,height+padding*2,Bitmap.Config.ARGB_8888);
    try{Canvas c=new Canvas(expanded);Paint mask=new Paint(Paint.ANTI_ALIAS_FLAG);mask.setColor(Color.WHITE);
     for(int y=-padding;y<=padding;y++)for(int x=-padding;x<=padding;x++)if(x*x+y*y<=radius*radius+.5f)c.drawBitmap(fill,padding+x,padding+y,mask);
     outline=expanded.extractAlpha();
    }finally{expanded.recycle();}
   }
   if(style.shadowRadius>0){Paint blur=new Paint(Paint.ANTI_ALIAS_FLAG);blur.setMaskFilter(new BlurMaskFilter(style.shadowRadius*density,BlurMaskFilter.Blur.NORMAL));shadow=fill.extractAlpha(blur,shadowOffset);}
   dirty=false;
  }finally{building=false;}
 }
 private void layer(Canvas canvas,Bitmap bitmap,float x,float y,int color){
  if(bitmap==null)return;
  paint.setColor(color);paint.setAlpha(Math.round(Color.alpha(color)*opacity/255f));canvas.drawBitmap(bitmap,x,y,paint);
 }
 @Override public void draw(Canvas canvas){
  Rect b=getBounds();if(b.isEmpty())return;
  // Bound glyph-mask allocation. Normal native control icons are far smaller than this.
  if(b.width()>512||b.height()>512){source.setBounds(b);source.draw(canvas);return;}
  if(dirty||fill==null||fill.getWidth()!=b.width()||fill.getHeight()!=b.height())rebuild(b.width(),b.height());
  layer(canvas,shadow,b.left+shadowOffset[0]+style.shadowX*density,b.top+shadowOffset[1]+style.shadowY*density,style.shadow(ink));
  layer(canvas,outline,b.left-padding,b.top-padding,style.outline(ink));
  layer(canvas,fill,b.left,b.top,ink);
 }
 @Override protected void onBoundsChange(Rect bounds){dirty=true;}
 @Override public boolean isStateful(){return source.isStateful();}
 @Override protected boolean onStateChange(int[] state){boolean changed=source.setState(state);if(changed){dirty=true;invalidateSelf();}return changed;}
 @Override protected boolean onLevelChange(int level){boolean changed=source.setLevel(level);if(changed){dirty=true;invalidateSelf();}return changed;}
 @Override public boolean onLayoutDirectionChanged(int direction){boolean changed=source.setLayoutDirection(direction);if(changed){dirty=true;invalidateSelf();}return changed;}
 @Override public int getIntrinsicWidth(){return source.getIntrinsicWidth();}
 @Override public int getIntrinsicHeight(){return source.getIntrinsicHeight();}
 @Override public void setAlpha(int alpha){opacity=Math.max(0,Math.min(255,alpha));invalidateSelf();}
 @Override public void setColorFilter(ColorFilter filter){source.setColorFilter(filter);dirty=true;invalidateSelf();}
 @SuppressWarnings("deprecation") @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
 @Override public void invalidateDrawable(Drawable who){if(!building){dirty=true;invalidateSelf();}}
 @Override public void scheduleDrawable(Drawable who,Runnable what,long when){scheduleSelf(what,when);}
 @Override public void unscheduleDrawable(Drawable who,Runnable what){unscheduleSelf(what);}
}

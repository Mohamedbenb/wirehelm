package com.nodecockpit.customization;
import android.graphics.*;
import android.graphics.drawable.Drawable;
/** Font-independent close mark: no encoding or system-theme glyph dependency. */
final class EdgeCloseDrawable extends Drawable {
 private final Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
 EdgeCloseDrawable(){p.setColor(Color.WHITE);p.setStyle(Paint.Style.STROKE);p.setStrokeCap(Paint.Cap.ROUND);}
 @Override public void draw(Canvas c){Rect b=getBounds();float inset=Math.min(b.width(),b.height())*.17f;p.setStrokeWidth(Math.max(1,Math.min(b.width(),b.height())*.12f));c.drawLine(b.left+inset,b.top+inset,b.right-inset,b.bottom-inset,p);c.drawLine(b.right-inset,b.top+inset,b.left+inset,b.bottom-inset,p);}
 @Override public void setAlpha(int a){p.setAlpha(a);invalidateSelf();}
 @Override public void setColorFilter(ColorFilter f){p.setColorFilter(f);invalidateSelf();}
 @Override public ConstantState getConstantState(){return new ConstantState(){public Drawable newDrawable(){return new EdgeCloseDrawable();}public int getChangingConfigurations(){return 0;}};}
 @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
}

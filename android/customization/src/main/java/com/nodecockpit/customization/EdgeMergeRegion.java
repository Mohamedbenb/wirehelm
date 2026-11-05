package com.nodecockpit.customization;
import android.content.Context;
import android.graphics.Rect;
import android.view.View;
/** Fixed editor-sized transparent host; only the moving two-shape union is composed. */
final class EdgeMergeRegion extends View implements GlassMergeGeometry {
 public boolean merging(){return merging;}
 final View primary,secondary;boolean merging;
 private final int[] own=new int[2],a=new int[2],b=new int[2];
 EdgeMergeRegion(Context c,View p,View s){super(c);primary=p;secondary=s;}
 public float[] shapes(float blur,float mix){
  getLocationInWindow(own);primary.getLocationInWindow(a);secondary.getLocationInWindow(b);float d=getResources().getDisplayMetrics().density;
  return new float[]{a[0]-own[0]+primary.getWidth()/2f,a[1]-own[1]+primary.getHeight()/2f,primary.getWidth()/2f,primary.getHeight()/2f,Math.min(30*d,Math.min(primary.getWidth(),primary.getHeight())/2f),b[0]-own[0]+secondary.getWidth()/2f,b[1]-own[1]+secondary.getHeight()/2f,secondary.getWidth()/2f,secondary.getHeight()/2f,Math.min(18*d,Math.min(secondary.getWidth(),secondary.getHeight())/2f),40*d,blur,mix};
 }
 public void crop(Rect clip){getLocationInWindow(own);primary.getLocationInWindow(a);secondary.getLocationInWindow(b);int pad=(int)Math.ceil(10*getResources().getDisplayMetrics().density)+2;clip.intersect(Math.min(a[0],b[0])-own[0]-pad,Math.min(a[1],b[1])-own[1]-pad,Math.max(a[0]+primary.getWidth(),b[0]+secondary.getWidth())-own[0]+pad,Math.max(a[1]+primary.getHeight(),b[1]+secondary.getHeight())-own[1]+pad);}
 public boolean hit(float rawX,float rawY){Rect r=new Rect();return primary.getGlobalVisibleRect(r)&&r.contains((int)rawX,(int)rawY)||secondary.getGlobalVisibleRect(r)&&r.contains((int)rawX,(int)rawY);}
}

package com.nodecockpit.customization;
/** Geometry shared by drag, keyboard relayout and persistence. All inputs are root-local pixels. */
final class EdgeSearchPlacement {
 static int size(int requested,int fallback,int extent,int inset){return Math.max(1,Math.min(requested>0?requested:fallback,Math.max(1,extent-2*inset)));}
 static float clamp(float value,float extent,float size,float inset){return Math.max(inset,Math.min(Math.max(inset,extent-size-inset),value));}
 static float fraction(float value,float extent,float size,float inset){float travel=Math.max(0,extent-size-2*inset);return travel<=0?0:Math.max(0,Math.min(1,(value-inset)/travel));}
 static float position(float fraction,float extent,float size,float inset){return inset+Math.max(0,Math.min(1,fraction))*Math.max(0,extent-size-2*inset);}
}

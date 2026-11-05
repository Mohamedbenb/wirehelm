package com.nodecockpit.customization;
import android.graphics.Rect;
/** Host-supplied geometry for a two-shape union. No component discovery in the engine. */
interface GlassMergeGeometry {
 boolean merging(); boolean hit(float rawX,float rawY);
 void crop(Rect clip); float[] shapes(float blur,float mix);
}

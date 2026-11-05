package com.nodecockpit.customization;
import android.view.MotionEvent;
interface EdgeMaterialSurface extends AutoCloseable {
 void configure(NativeLiquidConfig c,float radius); boolean active(); String diagnostics(); void close();
 default void touch(MotionEvent e){}
}

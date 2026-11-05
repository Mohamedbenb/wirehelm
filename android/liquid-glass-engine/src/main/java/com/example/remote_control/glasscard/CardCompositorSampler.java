package com.example.remote_control.glasscard;
import android.view.*;import android.graphics.Rect;import java.util.concurrent.Executor;import java.util.function.Consumer;
/** Existing Glass Lab CompositionSamplingListener mechanism; foreground option only. */
final class CardCompositorSampler extends CompositionSamplingListener {
 private final Consumer<Float> sink;
 CardCompositorSampler(Executor executor,Consumer<Float> sink){super(executor);this.sink=sink;}
 @Override public void onSampleCollected(float l){if(Float.isFinite(l)&&l>=0&&l<=1)sink.accept(l);}
 void region(SurfaceControl stop,Rect bounds){CompositionSamplingListener.register(this,0,stop,bounds);}
}

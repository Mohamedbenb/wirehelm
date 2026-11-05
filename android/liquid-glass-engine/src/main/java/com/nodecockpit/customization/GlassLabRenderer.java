package com.nodecockpit.customization;
import android.graphics.*;
import android.view.View;
import java.nio.*;
import java.util.*;
/** Original optics/packets on an owned backdrop; compositor passthrough becomes transparent View output. */
@androidx.annotation.RequiresApi(33)
final class GlassLabRenderer implements AutoCloseable {
 @androidx.annotation.RequiresApi(26) static String viewSource(int selected){
  String code=switch(selected){case 1->CardLiquidShader.SOURCE;case 2->CardLiquidMergeShader.SOURCE;case 3->CardNotificationShader.SOURCE;case 4->NativeQsShader.SOURCE;case 5->NativeLiquidMaterial.SHADER;default->throw new IllegalArgumentException("Unknown profile");};
  if(selected>=2&&selected<=4)code=code.replace("return content.eval(coord);","return half4(0.0);")
   .replace("half4 untouched=content.eval(coord); return mix(untouched,half4(half3(col)*untouched.a,untouched.a),half(cov));","return half4(half3(col * cov), half(cov));");
  return code;
 }
 private final GlassBackdropBlur backdropBlur=new GlassBackdropBlur();
 private final RenderNode node=new RenderNode("GlassEngineLab");
 private final RenderNode maskedBlurNode=new RenderNode("GlassEngineLabMaskedAndroidBlur");
 private final RectF blurShapeBounds=new RectF(); private float previousMaskedBlur=-1f; private long maskedBlurDraws; private int maskedBlurFailures;
 private boolean previousKawase; private boolean failNext;void injectFailure(){failNext=true;failures.clear();}
 private RuntimeShader shader;private int profile=-1;private byte[] previous;private int builds;private float previousBlur=-1,previousMix=-1;private final Map<Integer,String> failures=new HashMap<>();private String error="";
 boolean draw(Canvas canvas,View source,int selected,byte[] bytes,Rect frame,float blur,float mix,boolean kawase){
  return draw(canvas,source,selected,bytes,frame,blur,mix,kawase,null,0f,0f,null);
 }
 boolean draw(Canvas canvas,View source,int selected,byte[] bytes,Rect frame,float blur,float mix,boolean kawase,RectF blurMask,float maskBlur,float maskMix,Path blurShape){
  if(failures.containsKey(selected)){error=failures.get(selected);return false;}
  if(!canvas.isHardwareAccelerated()){error="Hardware canvas required";return false;}
  try{
   if(failNext){failNext=false;throw new IllegalStateException("Injected lab shader failure");}
   if(shader==null||selected!=profile){shader=new RuntimeShader(viewSource(selected));profile=selected;previous=null;builds++;}
   if(!Arrays.equals(previous,bytes)||blur!=previousBlur||mix!=previousMix||kawase!=previousKawase){
    FloatBuffer data=ByteBuffer.wrap(bytes).order(ByteOrder.nativeOrder()).asFloatBuffer();float[] values=new float[data.remaining()];data.get(values);
    if(selected==5){shader.setFloatUniform("geometry",Arrays.copyOfRange(values,0,4));shader.setFloatUniform("material",Arrays.copyOfRange(values,4,8));}else shader.setFloatUniform("u",values);
    RenderEffect effect=RenderEffect.createRuntimeShaderEffect(shader,selected==5?"inLayer":"content");
    if(!kawase&&blur>.01f&&mix>.001f){RenderEffect blurred=kawase?GlassKawaseBlur.create(blur):RenderEffect.createBlurEffect(blur,blur,Shader.TileMode.CLAMP);if(mix<1){ColorMatrix weight=new ColorMatrix(new float[]{1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,mix,0});blurred=RenderEffect.createBlendModeEffect(RenderEffect.createOffsetEffect(0,0),RenderEffect.createColorFilterEffect(new ColorMatrixColorFilter(weight),blurred),BlendMode.SRC_OVER);}effect=RenderEffect.createChainEffect(effect,blurred);}
    node.setRenderEffect(effect);previous=bytes.clone();previousBlur=blur;previousMix=mix;previousKawase=kawase;
   }
   node.setPosition(frame.left,frame.top,frame.right,frame.bottom);Canvas recording=node.beginRecording(frame.width(),frame.height());try{GlassBackdropBlur.Recorder backdrop=c->{int saved=c.save();try{c.translate(-frame.left,-frame.top);source.draw(c);}finally{c.restoreToCount(saved);}};if(kawase)backdropBlur.draw(recording,frame.width(),frame.height(),blur,mix,backdrop);else backdrop.draw(recording);
    // Composite the masked blur into the shader INPUT, before the glass optics run.
    if(blurMask!=null){int saved=recording.save();try{recording.translate(-frame.left,-frame.top);if(blurShape!=null){recording.clipPath(blurShape);blurShape.computeBounds(blurShapeBounds,true);}else blurShapeBounds.set(blurMask);if(!drawMaskedBackdropBlur(recording,source,frame,blurMask,maskBlur,maskMix,blurShapeBounds))throw new IllegalStateException(error);}finally{recording.restoreToCount(saved);}}
   }finally{node.endRecording();}canvas.drawRenderNode(node);error="";return true;
  }catch(RuntimeException e){error=e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage());shader=null;previous=null;failures.put(selected,error);node.discardDisplayList();node.setRenderEffect(null);return false;}
 }
 /** Android RenderEffect backdrop pass clipped to one component-owned glass region. */
 boolean drawMaskedBackdropBlur(Canvas canvas,View source,Rect frame,RectF mask,float radius,float mix,RectF sourceBounds){
  if(mask.isEmpty()||radius<=.01f||mix<=.001f)return true;
  if(!canvas.isHardwareAccelerated()){error="Masked Android blur needs a hardware canvas";maskedBlurFailures++;return false;}
  try{
   int padding=(int)Math.ceil(radius*3f);
   // Keep the backdrop region fixed to the whole control while its fill changes.
   Rect blurFrame=new Rect(Math.max(frame.left,(int)Math.floor(sourceBounds.left-padding)),Math.max(frame.top,(int)Math.floor(sourceBounds.top-padding)),Math.min(frame.right,(int)Math.ceil(sourceBounds.right+padding)),Math.min(frame.bottom,(int)Math.ceil(sourceBounds.bottom+padding)));
   if(blurFrame.isEmpty())return true;
   if(Float.compare(previousMaskedBlur,radius)!=0){maskedBlurNode.setRenderEffect(RenderEffect.createBlurEffect(radius,radius,Shader.TileMode.CLAMP));previousMaskedBlur=radius;}
   maskedBlurNode.setPosition(blurFrame.left,blurFrame.top,blurFrame.right,blurFrame.bottom);
   Canvas recording=maskedBlurNode.beginRecording(blurFrame.width(),blurFrame.height());
   try{int saved=recording.save();try{recording.translate(-blurFrame.left,-blurFrame.top);source.draw(recording);}finally{recording.restoreToCount(saved);}}
   finally{maskedBlurNode.endRecording();}
   int save=canvas.save();
   // The glass shader supplies the outer card corners; the fill cutoff stays straight.
   try{canvas.clipRect(mask);int layer=canvas.saveLayerAlpha(mask,(int)(mix*255f),Canvas.ALL_SAVE_FLAG);try{canvas.drawRenderNode(maskedBlurNode);}finally{canvas.restoreToCount(layer);}}
   finally{canvas.restoreToCount(save);}
   maskedBlurDraws++;error="";return true;
  }catch(RuntimeException e){error="Masked Android blur "+e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage());maskedBlurFailures++;maskedBlurNode.discardDisplayList();maskedBlurNode.setRenderEffect(null);previousMaskedBlur=-1f;return false;}
 }
 String diagnostics(){return "shader builds="+builds+", masked Android blur draws="+maskedBlurDraws+", failures="+maskedBlurFailures+", error="+(error.isEmpty()?"none":error);}
 public void close(){backdropBlur.close();node.discardDisplayList();node.setRenderEffect(null);maskedBlurNode.discardDisplayList();maskedBlurNode.setRenderEffect(null);previousMaskedBlur=-1f;shader=null;previous=null;}
}

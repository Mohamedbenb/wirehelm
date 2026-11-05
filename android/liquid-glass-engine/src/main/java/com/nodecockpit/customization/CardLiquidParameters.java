package com.nodecockpit.customization;
import org.json.JSONObject;
import java.nio.*;
/** Same 240-byte contract as CardCompositorMaterial; all optical source comes from that shader. */
final class CardLiquidParameters {
 static float n(JSONObject c,String k,double d,double lo,double hi){double v=c.optDouble(k,d);return (float)(Double.isFinite(v)?Math.max(lo,Math.min(hi,v)):d);}
 static float blur(JSONObject c){return .48f*n(c,"blurStrength",12,0,100);}
 static float mix(JSONObject c){float t=n(c,"blurStrength",12,0,100)/10f;t=Math.min(1,t);return t*t*(3-2*t);}
 static float lifetime(JSONObject c){return CardRippleTimeline.lifetime(n(c,"rippleSpeed",1,.25,2.5),n(c,"rippleDamping",1.4,.3,3));}
 static byte[] uniforms(float w,float h,float r,JSONObject c,float lx,float ly,float press,float tx,float ty,float[] pulses){
  boolean clear="clear".equals(c.optString("material","clear"));int tint=android.graphics.Color.parseColor(c.optString("glassTintColor","#FFFFFF"));
  float strength=c.optBoolean("touchRipples")?n(c,"rippleStrength",.5,0,1):0;
  float[] a={w,h,r,n(c,"softness",0,0,24),w/2,h/2,w/2,h/2,r,r,r,r,n(c,"bevel",48,4,160),n(c,"refraction",160,0,240),n(c,"falloff",2,0,6),c.optBoolean("outward")?1:-1,
   1,1,w-1,h-1,n(c,"dispersion",.1,0,.9),lx,ly,n(c,"specular",1,0,2)*(clear?1.2f:1),1,1,1,clear?n(c,"baseVeil",100*20f/255,0,100)/100:n(c,"regularToneStrength",100,0,100)/100,
   (tint>>16&255)/255f,(tint>>8&255)/255f,(tint&255)/255f,n(c,"glassTintStrength",0,0,1),clear?0:1,n(c,"dimming",0,0,100)/100,n(c,"saturation",140,0,200)/100,press,tx,ty,press,c.optBoolean("reactionEnabled")?n(c,"reactionIntensity",.25,0,1):0,
   strength,n(c,"rippleSpeed",1,.25,2.5),n(c,"rippleDamping",1.4,.3,3),lifetime(c)};
  ByteBuffer b=ByteBuffer.allocate(240).order(ByteOrder.nativeOrder());for(float f:a)b.putFloat(f);for(float f:pulses)b.putFloat(f);return b.array();
 }
 static boolean valid(JSONObject root){try{
  if(root.has("engine")&&!java.util.Arrays.asList("classic","card").contains(root.getString("engine")))return false;
  if(!root.has("cardMaterial"))return true;if(!(root.get("cardMaterial") instanceof JSONObject))return false;JSONObject c=root.getJSONObject("cardMaterial");
  for(String k:new String[]{"sensorLighting","pressEffects","touchRipples","reactionEnabled","outward"})if(c.has(k)&&!(c.get(k) instanceof Boolean))return false;
  if(c.has("material")&&!java.util.Arrays.asList("regular","clear").contains(c.getString("material")))return false;
  if(c.has("glassTintColor")&&!c.getString("glassTintColor").matches("#[0-9a-fA-F]{6}"))return false;
  String[] keys={"regularToneStrength","baseVeil","blurStrength","dimming","glassTintStrength","bevel","refraction","falloff","dispersion","specular","saturation","softness","reactionIntensity","rippleStrength","rippleSpeed","rippleDamping"};
  double[] lo={0,0,0,0,0,4,0,0,0,0,0,0,0,0,.25,.3},hi={100,100,100,100,1,160,240,6,.9,2,200,24,1,1,2.5,3};
  for(int i=0;i<keys.length;i++)if(c.has(keys[i])){Object v=c.get(keys[i]);if(!(v instanceof Number)||!Double.isFinite(((Number)v).doubleValue())||((Number)v).doubleValue()<lo[i]||((Number)v).doubleValue()>hi[i])return false;}return true;
 }catch(Exception e){return false;}}
}

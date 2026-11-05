package com.nodecockpit.customization;
import java.nio.*;
/** Current-composition local statistics; one child, at most nine samples, no temporal state. */
final class NativeLiquidMaterial {
 static final String SHADER="""
 uniform shader inLayer;
 uniform float4 geometry;
 uniform float4 material;
 float luminance(half4 c) {
   return dot(float3(c.rgb),float3(0.2126,0.7152,0.0722))/max(float(c.a),0.001);
 }
 half4 main(float2 p) {
   float mode=floor(geometry.w+0.001);
   if (mod(mode,4.0)<0.5) return inLayer.eval(p);
   bool darkInk=mode>=4.0;
   float support=clamp(fract(geometry.w)*4.0,0.0,1.0);
   float2 size=geometry.xy, center=size*0.5;
   float radius=min(geometry.z,min(center.x,center.y));
   float2 v=abs(p-center)-(center-radius), outside=max(v,float2(0.0));
   float olen=length(outside);
   float distance=olen+min(max(v.x,v.y),0.0)-radius;
   float2 normal=(olen>0.001 ? outside/olen : (v.x>v.y ? float2(1.0,0.0):float2(0.0,1.0)))*sign(p-center);
   // Fixed lens character: maximum bend just inside the curved rim, negligible in the body.
   float thickness=clamp(radius*0.28,3.0,16.0);
   float depth=max(-distance,0.0), t=depth/thickness;
   float lens=t*exp(1.0-t);
   float2 q=clamp(p-normal*material.y*0.85*lens,float2(0.5),size-float2(0.5));
   // A sparse one-pass kernel must not become nine separated copies at high strength.
   // Strength controls contribution while radius approaches a bounded bilinear footprint.
   float spread=1.0+1.8*(1.0-exp(-material.x*0.22));
   half4 a=inLayer.eval(q);
   half4 b=inLayer.eval(q+float2(spread,0.0));
   half4 c=inLayer.eval(q-float2(spread,0.0));
   half4 d=inLayer.eval(q+float2(0.0,spread));
   half4 e=inLayer.eval(q-float2(0.0,spread));
   half4 f=inLayer.eval(q+float2(spread,spread));
   half4 g=inLayer.eval(q+float2(spread,-spread));
   half4 h=inLayer.eval(q+float2(-spread,spread));
   half4 i=inLayer.eval(q-float2(spread,spread));
   half4 average=a*0.25+(b+c+d+e)*0.125+(f+g+h+i)*0.0625;
   float la=luminance(a),lb=luminance(b),lc=luminance(c),ld=luminance(d),le=luminance(e);
   float lf=luminance(f),lg=luminance(g),lh=luminance(h),li=luminance(i);
   float mean=la*0.25+(lb+lc+ld+le)*0.125+(lf+lg+lh+li)*0.0625;
   float second=la*la*0.25+(lb*lb+lc*lc+ld*ld+le*le)*0.125+(lf*lf+lg*lg+lh*lh+li*li)*0.0625;
   float deviation=sqrt(max(second-mean*mean,0.0));
   float chromaDetail=length(float3(a.rgb-average.rgb))/max(float(average.a),0.001);
   float busy=smoothstep(0.035,0.40,deviation/(mean+0.14)+chromaDetail*0.15);
   // The same current-frame samples drive diffusion and local contrast, not delayed callbacks.
   float diffusion=(1.0-exp(-material.x*0.55))*(0.80+0.20*busy);
   half4 sampled=mix(a,average,diffusion);
   float alpha=float(sampled.a);
   float3 rgb=float3(sampled.rgb)/max(alpha,0.001);
   float3 pivot=float3(average.rgb)/max(float(average.a),0.001);
   rgb=mix(pivot,rgb,1.0/(1.0+support*0.80*busy));
   // Gentle continuous shoulder/toe; no brightness ceiling or foreground polarity switch.
   if(darkInk) rgb=mix(rgb,float3(1.0),support*0.035*(1.0-clamp(mean,0.0,1.0)));
   else rgb/=1.0+support*0.12*max(mean,0.0);
   float tintAmount=clamp(material.z*(0.75+0.35*busy+0.15*clamp(mean,0.0,1.0)),0.0,0.65);
   float3 neutral=darkInk?float3(0.82,0.84,0.86):float3(0.42,0.46,0.50);
   rgb=mix(rgb,mix(neutral,pivot,0.35),tintAmount);
   // Directional optical thickness and inner glint share a smooth rounded-rectangle normal.
   float light=max(dot(normal,float2(-0.54499,-0.83844)),0.0);
   float opposite=max(dot(normal,float2(0.54499,0.83844)),0.0);
   float hair=exp(-depth/max(0.8,thickness*0.20));
   float inner=exp(-pow((depth-thickness*0.65)/max(1.0,thickness*0.35),2.0));
   rgb*=1.0-material.w*opposite*0.07*exp(-t);
   float glint=material.w*(hair*(0.025+0.17*light*light)+inner*0.035*light);
   rgb=mix(rgb,float3(1.0),glint);
   return half4(clamp(rgb,float3(0.0),float3(1.0))*alpha,alpha);
 }
 """;
 static byte[] uniforms(int w,int h,float r,NativeLiquidConfig c) {
  return pack(w,h,r,c.preset,c.darkInk,c.blur,c.refraction,c.tint,c.edge,c.contrast);
 }
 /** Fractional mode stores contrast0..1 in a quarter-unit; floor keeps preset/ink bits distinct. */
 static byte[] pack(int w,int h,float r,int preset,boolean dark,float blur,float ref,float tint,float edge,float contrast) {
  return ByteBuffer.allocate(32).order(ByteOrder.nativeOrder()).putFloat(w).putFloat(h).putFloat(r)
   .putFloat(preset+(dark?4:0)+contrast*0.25f).putFloat(blur).putFloat(ref).putFloat(tint).putFloat(edge).array();
 }
}

package com.nodecockpit.customization;
/** Restores upstream GlassLensRenderer's shape2/radius2/blendK smooth union.
 * App's independent 240-byte shader remains unchanged; edge uniforms add two float4 slots.
 * MIT source attribution remains in liquid-glass-views.txt. */
final class CardLiquidMergeShader {
 static final String SOURCE=CardLiquidShader.SOURCE
  .replace("0.14 + 0.08 * e);", "(0.14 + 0.08 * e)*u[6].a);")
  // SAMPLE_BEHIND is drawn with kSrc: coverage must blend into the original backdrop,
  // never erase the unoccupied part of this rectangular composition region.
  .replace("return half4(0.0);", "return content.eval(coord);")
  .replace("return half4(half3(col * cov), half(cov));", "half4 untouched=content.eval(coord); return mix(untouched,half4(half3(col)*untouched.a,untouched.a),half(cov));")
  .replace("uniform float4 u[15];","uniform float4 u[17];")
  .replace("(float4(0.0))","(u[15])")
  .replace("sdRoundedBox(p - (u[15]).xy, (u[15]).zw, (0.0))", "sdRoundedBox(p - (u[15]).xy, (u[15]).zw, u[16].x)")
  .replace("if ((0.0) > 0.5)","if (u[16].y > 0.5)")
  .replace("sminPoly(d, d2, (0.0))","sminPoly(d, d2, u[16].y)")
  .replace("half4 main(float2 coord)",
   "float3 mergedBlur(float2 p) { float r=u[16].z; float2 lo=u[4].xy,hi=u[4].zw; float3 c=content.eval(clamp(p,lo,hi)).rgb*.2; " +
   "c+=content.eval(clamp(p+float2(r,0),lo,hi)).rgb*.1; c+=content.eval(clamp(p-float2(r,0),lo,hi)).rgb*.1; " +
   "c+=content.eval(clamp(p+float2(0,r),lo,hi)).rgb*.1; c+=content.eval(clamp(p-float2(0,r),lo,hi)).rgb*.1; " +
   "c+=content.eval(clamp(p+float2(r,r)*.7071,lo,hi)).rgb*.1; c+=content.eval(clamp(p-float2(r,r)*.7071,lo,hi)).rgb*.1; " +
   "c+=content.eval(clamp(p+float2(r,-r)*.7071,lo,hi)).rgb*.1; c+=content.eval(clamp(p-float2(r,-r)*.7071,lo,hi)).rgb*.1; return c; } half4 main(float2 coord)")
  .replace("float lum = dot(col,", "if(u[15].z>0.5 && u[16].z>0.01 && u[16].w>0.001) col=mix(col,mergedBlur(cG),u[16].w); float lum = dot(col,");
}

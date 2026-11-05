package com.example.remote_control.glasscard
/** Shared stateless current-frame reaction. No motion estimation, clock or history.
 * Four background reads when enabled; displacement is bounded below three physical px.
 * The smooth SDF-depth envelope pins the disturbance to zero at the glass border. */
object GlassReaction {
 const val SHADER="""
 float2 restrainedReaction(float2 q,float2 lo,float2 hi,float depth,float2 size,float strength) {
  if (strength <= 0.0) return float2(0.0);
  float fade = smoothstep(0.0, max(2.0,min(12.0,min(size.x,size.y)*0.1)),max(depth,0.0));
  if (fade <= 0.0) return float2(0.0);
  float3 weights=float3(0.2126,0.7152,0.0722);
  float xp=dot(float3(content.eval(clamp(q+float2(3.0,0.0),lo,hi)).rgb),weights);
  float xm=dot(float3(content.eval(clamp(q-float2(3.0,0.0),lo,hi)).rgb),weights);
  float yp=dot(float3(content.eval(clamp(q+float2(0.0,3.0),lo,hi)).rgb),weights);
  float ym=dot(float3(content.eval(clamp(q-float2(0.0,3.0),lo,hi)).rgb),weights);
  float2 gradient=float2(xp-xm,yp-ym);
  float2 flow=float2(gradient.y,-gradient.x)+gradient*0.25;
  return flow*(3.0*clamp(strength,0.0,1.0)*fade/(0.18+length(flow)));
 }
 """
}

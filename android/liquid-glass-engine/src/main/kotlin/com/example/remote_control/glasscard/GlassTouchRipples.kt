package com.example.remote_control.glasscard
/** Analytic outward wave packets; rounded borders absorb waves. No backdrop reads. */
object GlassTouchRipples {
 const val SHADER="""
 float3 rippleWave(float2 p,float2 size,float4 settings,float4 event) {
  float age=event.z;
  if(event.w==0.0||age<0.0||age>=settings.w)return float3(0.0);
  float2 delta=p-event.xy*size;float distance=length(delta);
  float front=age*settings.y*length(size);
  float width=max(8.0,min(size.x,size.y)*0.075);
  float q=(distance-front)/width;
  float envelope=exp(-0.5*q*q-settings.z*age)*smoothstep(0.0,0.06,age)*(1.0-smoothstep(max(settings.w-0.2,0.0),settings.w,age));
  float phase=q*3.0;float amplitude=event.w*settings.x*envelope;
  return float3((delta/max(distance,1.0))*(5.0*sin(phase)*amplitude),0.035*cos(phase)*amplitude);
 }
 float3 touchRipples(float2 p,float2 size,float depth,float4 settings,float4 a,float4 b,float4 c,float4 d) {
  if(settings.x<=0.0)return float3(0.0);
  float3 wave=rippleWave(p,size,settings,a)+rippleWave(p,size,settings,b)+rippleWave(p,size,settings,c)+rippleWave(p,size,settings,d);
  float limit=8.0*settings.x;wave.xy*=limit/sqrt(limit*limit+dot(wave.xy,wave.xy));
  float boundary=smoothstep(0.0,8.0,max(depth,0.0));
  return float3(wave.xy*boundary,clamp(wave.z,-0.06*settings.x,0.06*settings.x)*boundary);
 }
 """
}

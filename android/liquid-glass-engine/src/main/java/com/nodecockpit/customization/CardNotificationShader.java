package com.nodecockpit.customization;
/** Same rounded-box/smooth union as edge/search, with analytic gradients in one bounded traversal. */
final class CardNotificationShader {
 private static final String SAMPLE=
 "float4 unionSample(float2 p){float4 result=float4(100000.0,0.0,-1.0,0.0);for(int i=0;i<13;i++){float4 s=u[17+i*2];float4 a=u[18+i*2];if(s.z<=0.5||a.z<=0.001)continue;float2 local=p-s.xy;float2 box=abs(local)-s.zw;float k=max(a.y,0.001);if(result.x<99999.0 && max(box.x,box.y)>=result.x+k)continue;float radius=clamp(a.x,0.0,min(s.z,s.w));float2 q=box+radius;float2 outside=max(q,float2(0.0));float len=length(outside);float d=len+min(max(q.x,q.y),0.0)-radius;float2 normal=len>0.0001?outside/len*sign(local):(q.x>q.y?float2(sign(local.x),0.0):float2(0.0,sign(local.y)));if(result.x>99999.0){result=float4(d,normal,a.z);}else{float h=clamp(0.5+0.5*(d-result.x)/k,0.0,1.0);result=float4(mix(d,result.x,h)-k*h*(1.0-h),mix(normal,result.yz,h),mix(a.z,result.w,h));}}return result;} ";
 static final String SOURCE=CardLiquidMergeShader.SOURCE.replace("uniform float4 u[17];","uniform float4 u[53];")
 .replace("half4 main(float2 coord)",SAMPLE+"float expandMask(float2 p){float mask=0.0;for(int i=0;i<10;i++){if(float(i)>=u[16].x)break;float4 s=u[43+i];float2 q=abs(p-s.xy)-s.zw;if(max(q.x,q.y)>2.0)continue;float d=sdRoundedBox(p-s.xy,s.zw,min(s.z,s.w));mask=max(mask,1.0-smoothstep(-1.0,2.0,d));}return mask;} half4 main(float2 coord)")
 .replace("float3 mergedBlur(float2 p) { float r=u[16].z;", "float3 mergedBlur(float2 p,float r) {")
 .replace("if(u[15].z>0.5 && u[16].z>0.01 && u[16].w>0.001) col=mix(col,mergedBlur(cG),u[16].w);", "if(diffusion>0.01 && contribution>0.001 && contribution<1.0)col=mix(col,mergedBlur(cG,diffusion),contribution);")
 .replace("float3 col;", "float control=u[16].x>0.5?expandMask(p):0.0;control*=u[15].w;float diffusion=mix(u[16].z,u[16].y,control);float contribution=max(u[16].w,control);float3 col;")
 .replace("if ((u[0].w) > 0.01 && slope > 0.001)", "if(diffusion>0.01 && contribution>=1.0)col=mergedBlur(cG,diffusion);else if ((u[0].w) > 0.01 && slope > 0.001)")
 .replace("float d = lensSDF(p);","float4 region=unionSample(p); float d=region.x;")
 .replace("float cov = clamp(0.5 - d / 1.5, 0.0, 1.0);","float cov = clamp(0.5 - d / 1.5, 0.0, 1.0)*region.w;")
 .replace("float2 n = float2(\n                    lensSDF(p + float2(1.0, 0.0)) - lensSDF(p - float2(1.0, 0.0)),\n                    lensSDF(p + float2(0.0, 1.0)) - lensSDF(p - float2(0.0, 1.0))\n                );","float2 n=region.yz;");
}

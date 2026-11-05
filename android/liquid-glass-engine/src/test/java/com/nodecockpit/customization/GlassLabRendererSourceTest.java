package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;

public class GlassLabRendererSourceTest {
 @Test public void viewOutputsTransparencyWithoutChangingCompositorSources(){
  String[] original={CardLiquidMergeShader.SOURCE,CardNotificationShader.SOURCE,NativeQsShader.SOURCE};
  String[] abi={"uniform float4 u[17];","uniform float4 u[53];","uniform float4 u[87];"};
  for(int i=0;i<original.length;i++){
   assertTrue(original[i].contains("return content.eval(coord);"));
   String view=GlassLabRenderer.viewSource(i+2);
   assertFalse(view.contains("return content.eval(coord);"));
   assertTrue(view.contains("return half4(0.0);"));
   assertTrue(view.contains("return half4(half3(col * cov), half(cov));"));
   assertTrue(view.contains(abi[i]));
  }
 }
 @Test public void alreadyLocalProfilesKeepTheirSource(){
  assertEquals(CardLiquidShader.SOURCE,GlassLabRenderer.viewSource(1));
  assertEquals(NativeLiquidMaterial.SHADER,GlassLabRenderer.viewSource(5));
 }
}

package com.nodecockpit.customization;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;
public class NativeLiquidSettingsTest {
 @Test public void materialChangesOnlyEdgeAppearance(){
  Map<String,Object> m=new HashMap<>();IndicatorSettings old=new IndicatorSettings(m);
  m.put("edgePanelNativeGlass","{\"backend\":\"native\",\"handle\":false}");
  IndicatorSettings next=new IndicatorSettings(m);
  assertNotEquals(old.edgeVisualSignature(),next.edgeVisualSignature());assertEquals(old.edgeContentSignature(),next.edgeContentSignature());assertEquals(old.edgeGeometrySignature(),next.edgeGeometrySignature());assertEquals(old.functionalSignature(),next.functionalSignature());
 }
 @Test public void partialSavesDoNotCrossFeatureOrSafetyBoundaries(){
  assertTrue(SavedSetupScope.owns("edge","edgePanelNativeGlass"));assertTrue(SavedSetupScope.owns("all","edgePanelNativeGlass"));assertFalse(SavedSetupScope.owns("glass","edgePanelNativeGlass"));assertFalse(SavedSetupScope.owns("network","edgePanelNativeGlass"));assertFalse(SavedSetupScope.owns("edge","safetyBoot"));
 }
}

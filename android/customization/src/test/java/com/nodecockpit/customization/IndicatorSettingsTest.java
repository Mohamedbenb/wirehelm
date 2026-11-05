package com.nodecockpit.customization;

import static org.junit.Assert.*;
import java.util.HashMap;
import java.util.Map;
import org.junit.Test;

public final class IndicatorSettingsTest {
    @Test public void retiredGlassFlagsDoNotAffectActiveSettings() {
        Map<String,Object> values=new HashMap<>();
        IndicatorSettings before=new IndicatorSettings(values);
        values.put("shadeGlassEnabled",true); values.put("lockGlassEnabled",true);
        IndicatorSettings after=new IndicatorSettings(values);
        assertEquals(before.functionalSignature(),after.functionalSignature());
        assertEquals(before.edgeGeometrySignature(),after.edgeGeometrySignature());
        assertEquals(before.edgeVisualSignature(),after.edgeVisualSignature());
    }
    private static IndicatorSettings settings(long safetyAt,int height) {
        Map<String,Object> values=new HashMap<>();
        values.put("schema",1); values.put("edgePanelEnabled",true); values.put("edgePanelHeight",height);
        values.put("revision",7L); values.put("safetyBoot",3); values.put("safetyAt",safetyAt);
        return new IndicatorSettings(values);
    }
    @Test public void safetyRefreshDoesNotChangeVisualOrGeometrySignatures() {
        IndicatorSettings first=settings(1000,520),second=settings(2000,520);
        assertEquals(first.functionalSignature(),second.functionalSignature());
        assertEquals(first.edgeGeometrySignature(),second.edgeGeometrySignature());
        assertEquals(first.edgeVisualSignature(),second.edgeVisualSignature());
        assertNotEquals(first.safetySignature(),second.safetySignature());
    }
    @Test public void panelHeightIsClampedAndValidated() {
        assertEquals(240,settings(1000,100).edgePanelHeight);
        assertEquals(720,settings(1000,900).edgePanelHeight);
        assertTrue(FeaturePolicy.validEdgePanel(50,260,520,68,48,72));
        assertFalse(FeaturePolicy.validEdgePanel(50,260,800,68,48,72));
        assertTrue(FeaturePolicy.validEdgeTintMode("auto"));
        assertFalse(FeaturePolicy.validEdgeTintMode("system"));
        assertTrue(FeaturePolicy.validEdgeApps("com.android.chrome,org.telegram.messenger"));
        assertFalse(FeaturePolicy.validEdgeApps("invalid package"));
    }
    @Test public void unitModesPreservePrefixesAndBitCase() {
        Map<String,Object> values=new HashMap<>();
        assertEquals("MB/s",new IndicatorSettings(values).formatUnit("MB/s"));
        values.put("unitLabel","unit");
        assertEquals("MB",new IndicatorSettings(values).formatUnit("MB/s"));
        assertEquals("Mb",new IndicatorSettings(values).formatUnit("Mb/s"));
        values.put("unitLabel","prefix");
        assertEquals("G",new IndicatorSettings(values).formatUnit("GB/s"));
        values.put("unitLabel","none");
        assertEquals("",new IndicatorSettings(values).formatUnit("KB/s"));
        values.put("unitLabel","custom"); values.put("unitSuffix","Bps");
        assertEquals("MBps",new IndicatorSettings(values).formatUnit("MB/s"));
    }
    @Test public void networkFormattingIsBoundedAndDoesNotChangeEdgeSettings() {
        Map<String,Object> values=new HashMap<>();
        IndicatorSettings before=new IndicatorSettings(values);
        values.put("unitGap",100); values.put("unitScale",1); values.put("horizontalPosition",2000);
        values.put("boldValue",true); values.put("boldText",true); values.put("indicatorDesign","glass");
        IndicatorSettings after=new IndicatorSettings(values);
        assertEquals(8,after.unitGap); assertEquals(50,after.unitScale); assertEquals(1000,after.horizontalPosition);
        assertTrue(after.boldValue); assertTrue(after.boldText);
        values.put("unitGap",-100); assertEquals(-4,new IndicatorSettings(values).unitGap);
        assertEquals(before.edgeGeometrySignature(),after.edgeGeometrySignature());
        assertEquals(before.edgeVisualSignature(),after.edgeVisualSignature());
        assertEquals(before.edgeContentSignature(),after.edgeContentSignature());
    }
 @Test public void panelTextToneChangesAppearanceOnly() {
  java.util.Map<String,Object> v=new java.util.HashMap<>();IndicatorSettings off=new IndicatorSettings(v);
  v.put("edgePanelTextTone",80);IndicatorSettings on=new IndicatorSettings(v);
  assertEquals(80,on.edgePanelTextTone);assertNotEquals(off.edgeVisualSignature(),on.edgeVisualSignature());assertEquals(off.edgeContentSignature(),on.edgeContentSignature());
  assertEquals(off.edgeGeometrySignature(),on.edgeGeometrySignature());assertEquals(off.functionalSignature(),on.functionalSignature());
  assertTrue(SavedSetupScope.owns("edge","edgePanelTextTone"));
 }
}

package com.nodecockpit.customization;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;
public class RetiredGlassSettingsTest {
    @Test public void retiredSelectionMigratesWithoutChangingActiveFeatures()throws Exception{
        JSONObject c=new JSONObject().put("enabled",true).put("edgePanelEnabled",false).put("shadeGlassEnabled",true).put("lockGlassEnabled",true)
            .put("systemGlassStyle","{\"nativeNotifications\":{\"enabled\":true,\"brightnessProgressBlur\":83}}")
            .put("edgePanelNativeGlass","{\"backend\":\"legacy\",\"testOverlay\":{\"enabled\":true},\"cardMaterial\":{\"blurStrength\":42},\"searchTray\":{\"width\":320}}");
        RetiredGlassSettings.normalize(c);
        assertTrue(c.getBoolean("enabled"));assertFalse(c.getBoolean("edgePanelEnabled"));
        assertFalse(c.getBoolean("shadeGlassEnabled"));assertFalse(c.getBoolean("lockGlassEnabled"));assertEquals("{}",c.getString("systemGlassStyle"));
        JSONObject edge=new JSONObject(c.getString("edgePanelNativeGlass"));
        assertEquals(320,edge.getJSONObject("searchTray").getInt("width"));
        assertEquals("native",edge.getString("backend"));assertEquals("card",edge.getString("engine"));
        assertFalse(edge.has("testOverlay"));
        assertEquals(42,edge.getJSONObject("cardMaterial").getInt("blurStrength"));
    }
    @Test public void recoversMissingOpticsAndPreservesExplicitHandleChoices()throws Exception{
        JSONObject defaults=new JSONObject(RetiredGlassSettings.edge("malformed"));
        assertEquals("card",defaults.getString("engine"));
        assertTrue(defaults.getBoolean("handle"));assertTrue(defaults.getBoolean("liveHandle"));
        JSONObject explicit=new JSONObject(RetiredGlassSettings.edge("{\"backend\":\"native\",\"engine\":\"classic\",\"handle\":false,\"liveHandle\":false}"));
        assertEquals("classic",explicit.getString("engine"));
        assertFalse(explicit.getBoolean("handle"));assertFalse(explicit.getBoolean("liveHandle"));
    }
    @Test public void emptySavedConfigMigratesAndNormalizationIsIdempotent()throws Exception{
        String once=RetiredGlassSettings.edge("{\"searchTray\":{\"x\":0.4,\"y\":0.5}}");
        assertEquals(once,RetiredGlassSettings.edge(once));
        JSONObject optics=new JSONObject(once).getJSONObject("cardMaterial");
        assertEquals(0,optics.getInt("baseVeil"));
        assertEquals(0,optics.getInt("regularToneStrength"));
        JSONObject explicit=new JSONObject(RetiredGlassSettings.edge("{\"cardMaterial\":{\"baseVeil\":12}}"));
        assertEquals(12,explicit.getJSONObject("cardMaterial").getInt("baseVeil"));
    }
}

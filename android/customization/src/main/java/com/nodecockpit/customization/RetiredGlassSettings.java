package com.nodecockpit.customization;

import org.json.JSONObject;

/** Keeps edge material settings compatible while retiring stock SystemUI glass. */
final class RetiredGlassSettings {
    static String edge(String raw){
        JSONObject settings = new JSONObject();
        try {
            if (raw != null && raw.length() <= 4096) {
                try {
                    JSONObject saved = new JSONObject(raw);
                    saved.remove("testOverlay");
                    if (NativeLiquidConfig.valid(saved.toString())) settings = saved;
                } catch (org.json.JSONException malformed) {
                    // Use the edge defaults if the saved material cannot be parsed.
                }
            }
            settings.put("backend", "native");
            if (!settings.has("engine")) settings.put("engine", "card");
            if (!settings.has("handle")) settings.put("handle", true);
            if (!settings.has("liveHandle")) settings.put("liveHandle", true);
            if ("card".equals(settings.optString("engine"))) {
                JSONObject optics = settings.optJSONObject("cardMaterial");
                if (optics == null) optics = new JSONObject();
                if (!optics.has("baseVeil")) optics.put("baseVeil", 0);
                if (!optics.has("regularToneStrength")) optics.put("regularToneStrength", 0);
                settings.put("cardMaterial", optics);
            }
        } catch (org.json.JSONException invalid) {
            throw new IllegalStateException("Invalid edge material defaults", invalid);
        }
        return settings.toString();
    }
    static void normalize(JSONObject config)throws Exception{
        config.put("shadeGlassEnabled",false).put("lockGlassEnabled",false);
        config.put("systemGlassStyle", "{}");
        config.put("edgePanelNativeGlass",edge(config.optString("edgePanelNativeGlass","{}")));
    }
}

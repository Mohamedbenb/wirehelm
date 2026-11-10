package com.nodecockpit.customization;

import org.junit.Test;
import static org.junit.Assert.*;

public class EdgeAppRulesTest {
    @Test public void resolvesOnlyTheForegroundAppAndPreservesShortcutOrder() throws Exception {
        var rules = EdgeAppRules.parse("""
            {"com.example.browser":"com.example.notes,com.example.reader",
             "com.example.camera":"com.example.editor,com.example.gallery"}
            """);
        assertEquals("com.example.notes,com.example.reader",
            EdgeAppRules.shortcuts(rules, "com.example.browser", app -> true));
        assertEquals("com.example.gallery",
            EdgeAppRules.shortcuts(rules, "com.example.camera", app -> app.endsWith(".gallery")));
        assertEquals("", EdgeAppRules.shortcuts(rules, "com.example.browser", app -> false));
        assertNull(EdgeAppRules.shortcuts(rules, "com.example.launcher", app -> true));
    }

    @Test public void defaultsApplyForOlderAndInvalidSettings() {
        assertTrue(new IndicatorSettings(java.util.Map.of()).edgePanelAppRules.isEmpty());
        assertTrue(EdgeAppRules.safe("{\"com.example.browser\":true}").isEmpty());
        assertTrue(EdgeAppRules.safe("{\"com.example.browser\":\"com.example.notes,com.example.notes\"}").isEmpty());
    }

    @Test public void panelEditsUpdateOnlyTheOpenAppRule() throws Exception {
        String original = """
            {"com.example.browser":"com.example.notes",
             "com.example.camera":"com.example.gallery"}
            """;
        String updated = EdgeAppRules.update(original, "com.example.browser",
            "com.example.reader,com.example.notes");
        assertEquals("com.example.reader,com.example.notes",
            EdgeAppRules.parse(updated).get("com.example.browser"));
        var cleared = EdgeAppRules.parse(EdgeAppRules.update(updated, "com.example.browser", ""));
        assertFalse(cleared.containsKey("com.example.browser"));
        assertEquals("com.example.gallery", cleared.get("com.example.camera"));
    }

    @Test public void foregroundIsHiddenWithoutChangingSavedShortcuts() throws Exception {
        var rules = EdgeAppRules.parse("""
            {"com.example.browser":"com.example.browser,com.example.notes",
             "com.example.camera":"com.example.camera"}
            """);
        assertEquals("com.example.notes",
            EdgeAppRules.shortcuts(rules, "com.example.browser", app -> true));
        assertEquals("", EdgeAppRules.shortcuts(rules, "com.example.camera", app -> true));
        assertEquals("com.example.browser,com.example.notes", rules.get("com.example.browser"));
        assertEquals("", EdgeAppRules.visibleFavorite("com.example.browser", "com.example.browser"));
        assertEquals("com.example.notes+com.example.reader",
            EdgeAppRules.visibleFavorite("com.example.browser+com.example.notes+com.example.reader",
                "com.example.browser"));
    }
}

package com.nodecockpit.customization;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.StringJoiner;
import java.util.function.Predicate;
import org.json.JSONException;
import org.json.JSONObject;

final class EdgeAppRules {
    static final int MAX_RULES = 16;
    static final String EMPTY = "{}";

    static Map<String, String> parse(String raw) throws JSONException {
        if (raw.length() > MAX_RULES * 1100) throw new IllegalArgumentException("Edge app rules are too large");
        JSONObject rules = new JSONObject(raw);
        if (rules.length() > MAX_RULES) throw new IllegalArgumentException("Use up to 16 app-specific shortcut lists");
        Map<String, String> result = new HashMap<>();
        Iterator<String> packages = rules.keys();
        while (packages.hasNext()) {
            String pkg = packages.next();
            Object value = rules.get(pkg);
            if (!validPackage(pkg)
                    || !(value instanceof String apps) || apps.isEmpty() || apps.contains("+")
                    || !FeaturePolicy.validEdgeApps(apps)) {
                throw new IllegalArgumentException("Invalid app-specific shortcut list");
            }
            HashSet<String> unique = new HashSet<>();
            for (String app : apps.split(",")) {
                if (!unique.add(app)) throw new IllegalArgumentException("Duplicate app shortcut");
            }
            result.put(pkg, apps);
        }
        return Collections.unmodifiableMap(result);
    }

    static String update(String raw, String pkg, String apps) throws JSONException {
        if (!validPackage(pkg)) throw new IllegalArgumentException("Invalid foreground app");
        JSONObject rules = new JSONObject(raw);
        if (apps.isEmpty()) rules.remove(pkg);
        else rules.put(pkg, apps);
        String updated = rules.toString();
        parse(updated);
        return updated;
    }

    private static boolean validPackage(String pkg) {
        return pkg.length() <= 255 && pkg.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+");
    }

    static Map<String, String> safe(String raw) {
        try {
            return parse(raw);
        } catch (JSONException | IllegalArgumentException invalid) {
            return Collections.emptyMap();
        }
    }

    static String shortcuts(Map<String, String> rules, String pkg, Predicate<String> canLaunch) {
        String apps = rules.get(pkg);
        if (apps == null) return null;
        StringJoiner usable = new StringJoiner(",");
        for (String app : apps.split(",")) {
            if (!app.equals(pkg) && canLaunch.test(app)) usable.add(app);
        }
        return usable.toString();
    }

    static String visibleFavorite(String item, String foreground) {
        if (foreground == null || foreground.isEmpty()) return item;
        StringJoiner members = new StringJoiner("+");
        for (String member : item.split("\\+")) {
            if (!member.equals(foreground)) members.add(member);
        }
        return members.toString();
    }

    private EdgeAppRules() {}
}

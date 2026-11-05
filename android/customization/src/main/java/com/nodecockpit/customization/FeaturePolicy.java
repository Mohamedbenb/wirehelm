package com.nodecockpit.customization;

/** No Android dependencies: policy is shared by probes, UI and hook guards. */
public final class FeaturePolicy {
    public static final int SCHEMA = 1;
    public static final int PROTOCOL = 1;
    public static final int HOOK_VERSION = 182;
    public static final long SAFETY_LEASE_MS = 90000;
    public static final String GROUP = "node_cockpit_local_v1";
    public static final String ACTION_DISABLE = "com.nodecockpit.customization.DISABLE";
    public static final String TESTED_FINGERPRINT = "google/frankel/frankel:17/CP3A.261005.005/16271449:user/release-keys";
    /** Automatic suspension retains user intent; only explicit disable clears it. */
    public static boolean clearDesiredOnEmergency(String reason) { return "Disabled by user".equals(reason); }
    public static boolean supported(int sdk, String fingerprint) {
        return sdk == 37 && TESTED_FINGERPRINT.equals(fingerprint);
    }
    public static boolean valid(int interval, int threshold, int textSize) {
        return interval >= 500 && interval <= 5000 && threshold >= 0 && threshold <= 1024 && textSize >= 8 && textSize <= 18;
    }
    public static boolean validLayout(int height, int width, int stackedTextSize, int arrowScale, int arrowGap, int directionGap, int iconGap, int verticalOffset) {
        return height >= 13 && height <= 20 && width >= 26 && width <= 64
            && stackedTextSize >= 4 && stackedTextSize <= 12 && arrowScale >= 60 && arrowScale <= 200
            && arrowGap >= -3 && arrowGap <= 6 && directionGap >= 0 && directionGap <= 12
            && iconGap >= 0 && iconGap <= 12 && verticalOffset >= -3 && verticalOffset <= 3;
    }
    public static boolean validEdgePanel(int position, int width, int height, int opacity, int blur, int handleHeight) {
        return position >= 5 && position <= 95 && width >= 120 && width <= 360 && height >= 240 && height <= 720
            && opacity >= 0 && opacity <= 95 && blur >= 0 && blur <= 100
            && handleHeight >= 40 && handleHeight <= 120;
    }
    public static boolean validEdgeTintMode(String mode) { return "auto".equals(mode)||"contrast".equals(mode)||"light".equals(mode)||"dark".equals(mode); }
    public static boolean validEdgeSide(String side) { return "left".equals(side)||"right".equals(side); }
    public static boolean validEdgeApps(String apps) {
        if (apps==null||apps.length()>800) return false;
        if (apps.isEmpty()) return true;
        String[] values=apps.split("[,+]",-1); if (values.length>12) return false;
        for (String value:values) if (!value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+")) return false;
        return true;
    }
    public static String formatRate(long bytes, long elapsedMs) {
        if (bytes < 0 || elapsedMs <= 0) return "—";
        double rate = bytes * 1000.0 / elapsedMs;
        return rate >= 1048576 ? String.format(java.util.Locale.ROOT, "%.1fM", rate / 1048576)
            : String.format(java.util.Locale.ROOT, "%.0fK", rate / 1024);
    }
    public static boolean safetyLeaseValid(int boot, int checkedBoot, long now, long checkedAt) {
        return boot >= 0 && boot == checkedBoot && checkedAt > 0 && now >= checkedAt && now-checkedAt < SAFETY_LEASE_MS;
    }
    public static String[] rateParts(double bytesPerSecond, boolean bits, int decimals) {
        double value = Math.max(0, bytesPerSecond) * (bits ? 8 : 1);
        String[] units = bits ? new String[]{"Kb/s", "Mb/s", "Gb/s"} : new String[]{"KB/s", "MB/s", "GB/s"};
        value /= 1024;
        int unit=0;
        while (value >= 1024 && unit < units.length-1) { value/=1024; unit++; }
        double scale=Math.pow(10,Math.max(0,Math.min(2,decimals)));
        if (Math.round(value*scale)/scale>=1024 && unit<units.length-1) { value/=1024; unit++; }
        return new String[]{String.format(java.util.Locale.ROOT, "%."+Math.max(0,Math.min(2,decimals))+"f", value).trim(), units[unit]};
    }
    private FeaturePolicy() {}
}

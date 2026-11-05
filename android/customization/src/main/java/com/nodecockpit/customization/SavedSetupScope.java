package com.nodecockpit.customization;

/** Explicit ownership keeps partial saves from changing another feature or runtime safety state. */
public final class SavedSetupScope {
    public static boolean valid(String scope) { return "all".equals(scope)||"network".equals(scope)||"edge".equals(scope)||"glass".equals(scope); }
    public static boolean owns(String scope,String key) {
        if (!valid(scope)) throw new IllegalArgumentException("Unknown setup feature");
        if (key==null||java.util.Arrays.asList("revision","emergencyDisabled","recoveryReason","safetyAt","safetyBoot").contains(key)) return false;
        if ("all".equals(scope)) return true;
        if ("edge".equals(scope)) return key.startsWith("edgePanel")||key.startsWith("edgeHandle");
        if ("glass".equals(scope)) return "shadeGlassEnabled".equals(key)||"lockGlassEnabled".equals(key)||"systemGlassStyle".equals(key);
        return java.util.Arrays.asList("enabled","intervalMs","thresholdKB","textSize","indicatorHeight","rateWidth","stackedTextSize","arrowScale","arrowGap","directionGap","iconGap","boldValue","boldText","unitGap","unitScale","unitLabel","unitSuffix","horizontalPosition","indicatorDesign","verticalOffset","hideIdle","showUpload","showArrows","position","layout","units","decimals").contains(key);
    }
}

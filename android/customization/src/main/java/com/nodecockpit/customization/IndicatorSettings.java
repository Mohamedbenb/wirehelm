package com.nodecockpit.customization;

import java.util.Map;

/** One immutable preference snapshot; heartbeat-only updates never reset the rate baseline. */
final class IndicatorSettings {
    final boolean enabled, showUpload, showArrows, hideIdle, bits, stacked, right, edgePanelEnabled;
    final String edgePanelApps, edgePanelSide, edgePanelFolderNames;
    final int edgePanelTextTone;
    final int interval, textSize, threshold, decimals, boot, horizontalPosition;
    final String indicatorDesign, unitLabel, unitSuffix;
    final boolean boldValue, boldText;
    final int unitGap, unitScale;
    final int indicatorHeight, rateWidth, stackedTextSize, arrowScale, arrowGap, directionGap, iconGap, verticalOffset;
    final int edgePanelPosition, edgePanelWidth, edgePanelHeight, edgeHandleHeight;
    final long revision, safetyAt;
    final String edgePanelNativeGlass, edgePanelTintMode, edgeHandleTintMode;
    final boolean edgePanelTextAdaptation;
    final int edgePanelTextDurationMs, edgePanelOpacity, edgePanelBlur, edgeHandleOpacity, edgeHandleBlur;
    final String cameraRing,notificationUndo;
    IndicatorSettings(Map<String, ?> values) {
        cameraRing=text(values,"cameraRing",CameraRingSettings.DEFAULT);
        notificationUndo=text(values,"notificationUndo",NotificationUndoSettings.DEFAULT);
        enabled=number(values,"schema",0)==1 && flag(values,"enabled",false);
        showUpload=flag(values,"showUpload",true); showArrows=flag(values,"showArrows",true);
        hideIdle=flag(values,"hideIdle",true); bits="bits".equals(values.get("units"));
        stacked=!"inline".equals(values.get("layout"));
        right="right".equals(values.get("position"));
        horizontalPosition=clamp(number(values,"horizontalPosition",-1),-1,1000);
        indicatorDesign=text(values,"indicatorDesign","plain");
        unitLabel=text(values,"unitLabel","full"); unitSuffix=text(values,"unitSuffix","B/s");
        boldValue=flag(values,"boldValue",false); boldText=flag(values,"boldText",false);
        unitGap=clamp(number(values,"unitGap",1),-4,8); unitScale=clamp(number(values,"unitScale",100),50,120);
        edgePanelEnabled=flag(values,"edgePanelEnabled",false);
        edgePanelTextTone=clamp(number(values,"edgePanelTextTone",-1),-1,100);
        edgePanelNativeGlass=RetiredGlassSettings.edge(text(values,"edgePanelNativeGlass","{}"));
        edgePanelTintMode=text(values,"edgePanelTintMode","auto");
        edgeHandleTintMode=text(values,"edgeHandleTintMode","auto");
        edgePanelTextAdaptation=flag(values,"edgePanelTextAdaptation",false);
        edgePanelTextDurationMs=clamp(number(values,"edgePanelTextDurationMs",-1),-1,10000);
        edgePanelOpacity=clamp(number(values,"edgePanelOpacity",68),0,95);
        edgePanelBlur=clamp(number(values,"edgePanelBlur",48),0,100);
        edgeHandleOpacity=clamp(number(values,"edgeHandleOpacity",68),0,95);
        edgeHandleBlur=clamp(number(values,"edgeHandleBlur",48),0,100);
        edgePanelSide=text(values,"edgePanelSide","right");
        edgePanelApps=text(values,"edgePanelApps","");
        edgePanelFolderNames=text(values,"edgePanelFolderNames","{}");
        edgePanelPosition=clamp(number(values,"edgePanelPosition",50),5,95);
        edgePanelWidth=clamp(number(values,"edgePanelWidth",260),120,360);
        edgePanelHeight=clamp(number(values,"edgePanelHeight",520),240,720);
        edgeHandleHeight=clamp(number(values,"edgeHandleHeight",72),40,120);
        interval=clamp(number(values,"interval",1000),500,5000);
        textSize=clamp(number(values,"textSize",10),8,18);
        indicatorHeight=clamp(number(values,"indicatorHeight",16),13,20);
        rateWidth=clamp(number(values,"rateWidth",38),26,64);
        stackedTextSize=clamp(number(values,"stackedTextSize",8),4,12);
        arrowScale=clamp(number(values,"arrowScale",140),60,200);
        arrowGap=clamp(number(values,"arrowGap",0),-3,6);
        directionGap=clamp(number(values,"directionGap",6),0,12);
        iconGap=clamp(number(values,"iconGap",6),0,12);
        verticalOffset=clamp(number(values,"verticalOffset",0),-3,3);
        threshold=clamp(number(values,"threshold",1),0,1024);
        decimals=clamp(number(values,"decimals",1),0,2);
        boot=number(values,"safetyBoot",-1);
        revision=longNumber(values,"revision",0); safetyAt=longNumber(values,"safetyAt",0);
    }
    String formatUnit(String original) {
        if ("none".equals(unitLabel)) return "";
        String prefix=original.substring(0,1);
        if ("prefix".equals(unitLabel)) return prefix;
        if ("unit".equals(unitLabel)) return original.replace("/s","");
        if ("custom".equals(unitLabel)) return prefix+unitSuffix;
        return original;
    }
    boolean safetyValid(int currentBoot, long now) { return FeaturePolicy.safetyLeaseValid(currentBoot,boot,now,safetyAt); }
    String functionalSignature() { return enabled+":"+edgePanelEnabled; }
    String edgeGeometrySignature() { return edgePanelPosition+":"+edgePanelWidth+":"+edgePanelHeight+":"+edgeHandleHeight+":"+edgePanelSide; }
    String edgeVisualSignature() { return edgePanelNativeGlass+":"+edgePanelTextTone+":"+edgePanelTintMode+":"+edgeHandleTintMode+":"+edgePanelTextAdaptation+":"+edgePanelTextDurationMs+":"+edgePanelOpacity+":"+edgePanelBlur+":"+edgeHandleOpacity+":"+edgeHandleBlur; }
    String edgeContentSignature() { return edgePanelApps+":"+edgePanelFolderNames; }
    String safetySignature() { return boot+":"+safetyAt; }
    static int clamp(int n,int min,int max) { return Math.max(min,Math.min(max,n)); }
    private static int number(Map<String,?> m,String k,int d) { Object v=m.get(k); return v instanceof Number ? ((Number)v).intValue():d; }
    private static long longNumber(Map<String,?> m,String k,long d) { Object v=m.get(k); return v instanceof Number ? ((Number)v).longValue():d; }
    private static boolean flag(Map<String,?> m,String k,boolean d) { Object v=m.get(k); return v instanceof Boolean ? (Boolean)v:d; }
    private static String text(Map<String,?> m,String k,String d) { Object v=m.get(k); return v instanceof String?(String)v:d; }
}

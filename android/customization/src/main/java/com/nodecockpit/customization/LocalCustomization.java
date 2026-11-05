package com.nodecockpit.customization;

import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyManager;
import org.json.JSONObject;
import io.github.libxposed.service.XposedService;
import io.github.libxposed.service.XposedServiceHelper;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** App-side only. No Flutter dependency, network commands, or arbitrary root operations. */
public final class LocalCustomization {
    public static final String MODULE = "/data/adb/modules/node_cockpit_system";
    public static final String CARRIER_MODULE = "/data/adb/modules/tn_5g_cfgdb_wildcard";
    private static final String CARRIER_ASSET = "node-cockpit-carrier";
    private static final String CARRIER_DB_HASH = "17faf3c27a4f8939f712eb280118e2b15fdef3ea7564ac921535cfcb1c1c3a6e";
    private static volatile XposedService framework;
    private static volatile String frameworkError = "Not connected: enable Node Cockpit in the Xposed manager";
    private static Context app;
    private static boolean initialized;
    private static volatile JSONObject rootHealth = new JSONObject();
    private static volatile JSONObject carrierRootHealth = new JSONObject();
    private static volatile long rootCheckedAt;
    private static long rootSuccessElapsed;
    private static int rootBoot=-1, rootFailures;
    private static String lastPublished="";
    private static final Object LOCK = new Object();
    private static final ExecutorService healthWorker = Executors.newSingleThreadExecutor();
    private static final java.util.concurrent.atomic.AtomicBoolean probing = new java.util.concurrent.atomic.AtomicBoolean();

    public static synchronized void initialize(Context context) {
        if (initialized) return;
        app = context.getApplicationContext();
        initialized = true;
        // Existing trial users retain their opt-in as the feature becomes persistent.
        try{
            SharedPreferences p=store(app);
            if(!p.contains("notificationUndo")){
                String priorUndo=new JSONObject(p.getString("hookMetrics","{}")).optString("notificationUndo","");
                boolean used=NotificationUndoSamples.state(app).optInt("posts",0)>0||java.util.regex.Pattern.compile("(?:^|;)held=[1-9][0-9]*(?:;|$)").matcher(priorUndo).find();
                p.edit().putString("notificationUndo",used&&!p.getBoolean("emergency",false)?NotificationUndoSettings.MIGRATED:NotificationUndoSettings.DEFAULT).commit();
            }
        }catch(Exception e){android.util.Log.w("NodeNotificationUndo","Settings migration unavailable",e);}
        restoreRootLease();
        XposedServiceHelper.registerListener(new XposedServiceHelper.OnServiceListener() {
            @Override public void onServiceBind(XposedService service) {
                framework = service; lastPublished="";
                try { publish(); frameworkError = ""; }
                catch (Throwable e) { frameworkError = e.toString(); }
            }
            @Override public void onServiceDied(XposedService service) {
                if (framework == service) framework = null;
                frameworkError = "Framework connection lost";
            }
        });
        refreshSafetyIfNeeded();
    }
    private static int bootCount() {
        return android.provider.Settings.Global.getInt(app.getContentResolver(),android.provider.Settings.Global.BOOT_COUNT,-1);
    }
    private static void restoreRootLease() {
        try {
            SharedPreferences p=store(app);
            carrierRootHealth=new JSONObject(p.getString("carrierRootSnapshot","{}"));
            rootBoot=p.getInt("rootBoot",-1); rootSuccessElapsed=p.getLong("rootSuccessElapsed",0);
            if (FeaturePolicy.safetyLeaseValid(bootCount(),rootBoot,android.os.SystemClock.elapsedRealtime(),rootSuccessElapsed))
                rootHealth=new JSONObject(p.getString("rootSnapshot","{}"));
        } catch (Exception ignored) { rootHealth=new JSONObject(); }
    }
    private static boolean rootLeaseValid() {
        return FeaturePolicy.safetyLeaseValid(bootCount(),rootBoot,android.os.SystemClock.elapsedRealtime(),rootSuccessElapsed);
    }
    static void recordEvent(Context context,String type,String detail) {
        synchronized (LOCK) {
            try {
                SharedPreferences p=store(context);
                org.json.JSONArray old=new org.json.JSONArray(p.getString("healthEvents","[]"));
                org.json.JSONArray next=new org.json.JSONArray();
                for (int i=Math.max(0,old.length()-19);i<old.length();i++) next.put(old.get(i));
                next.put(new JSONObject().put("at",System.currentTimeMillis()).put("type",type).put("detail",detail==null?"":detail.substring(0,Math.min(300,detail.length()))));
                p.edit().putString("healthEvents",next.toString()).apply();
            } catch (Exception ignored) {}
        }
    }
    public static void refreshSafetyIfNeeded() {
        if (!store(app).getBoolean("rootApproved", false) || System.currentTimeMillis()-rootCheckedAt < 15000 || !probing.compareAndSet(false,true)) return;
        healthWorker.execute(() -> {
            try { probeRootBackground(); publish(); }
            catch (Exception ignored) {}
            finally { probing.set(false); }
        });
    }
    /**
     * The hook can start before the recovery helper has produced its first heartbeat.
     * Do this bounded check on the provider/bridge worker instead of returning a false
     * disabled configuration and hoping an app process survives long enough to refresh it.
     */
    static void refreshSafetyNowIfNeeded() {
        if (!store(app).getBoolean("rootApproved", false) || rootLeaseValid()
            || (rootCheckedAt > 0 && System.currentTimeMillis()-rootCheckedAt < 2000)) return;
        refreshWakeSafety();
    }
    static void refreshWakeSafety() {
        if (!store(app).getBoolean("rootApproved",false)) return;
        probeRootBackground();
    }
    public static SharedPreferences store(Context context) {
        return context.createDeviceProtectedStorageContext().getSharedPreferences("local_customization_v1", Context.MODE_PRIVATE);
    }
    public static JSONObject config(Context context) throws Exception {
        SharedPreferences p = store(context);
        return new JSONObject().put("schemaVersion", 1).put("revision", p.getLong("revision", 0))
            .put("enabled", p.getBoolean("enabled", false)).put("emergencyDisabled", p.getBoolean("emergency", false))
            .put("cameraRing",p.getString("cameraRing",CameraRingSettings.DEFAULT))
            .put("notificationUndo",p.getString("notificationUndo",NotificationUndoSettings.DEFAULT))
            .put("intervalMs", p.getInt("interval", 1000)).put("thresholdKB", p.getInt("threshold", 1))
            .put("textSize", p.getInt("textSize", 10)).put("indicatorHeight",p.getInt("indicatorHeight",16))
            .put("rateWidth",p.getInt("rateWidth",38)).put("stackedTextSize",p.getInt("stackedTextSize",8))
            .put("arrowScale",p.getInt("arrowScale",140)).put("arrowGap",p.getInt("arrowGap",0))
            .put("directionGap",p.getInt("directionGap",6)).put("iconGap",p.getInt("iconGap",6))
            .put("boldValue",p.getBoolean("boldValue",false)).put("boldText",p.getBoolean("boldText",false))
            .put("unitGap",p.getInt("unitGap",1)).put("unitScale",p.getInt("unitScale",100))
            .put("unitLabel",p.getString("unitLabel","full")).put("unitSuffix",p.getString("unitSuffix","B/s"))
            .put("horizontalPosition",p.getInt("horizontalPosition",-1)).put("indicatorDesign",p.getString("indicatorDesign","plain"))
            .put("verticalOffset",p.getInt("verticalOffset",0)).put("hideIdle", p.getBoolean("hideIdle", true))
            .put("showUpload",p.getBoolean("showUpload",true)).put("showArrows",p.getBoolean("showArrows",true))
            .put("position",p.getString("position","left")).put("layout",p.getString("layout","stacked")).put("units",p.getString("units","bytes")).put("decimals",p.getInt("decimals",1))
            .put("edgePanelTextDurationMs",p.getInt("edgePanelTextDurationMs",-1)).put("edgePanelTextTone",p.getInt("edgePanelTextTone",-1)).put("edgePanelTextAdaptation",p.getBoolean("edgePanelTextAdaptation",false)).put("edgePanelEnabled",p.getBoolean("edgePanelEnabled",false)).put("edgePanelPosition",p.getInt("edgePanelPosition",50))
            .put("edgePanelWidth",p.getInt("edgePanelWidth",260)).put("edgePanelHeight",p.getInt("edgePanelHeight",520)).put("edgePanelOpacity",p.getInt("edgePanelOpacity",68))
            .put("edgePanelBlur",p.getInt("edgePanelBlur",48)).put("edgeHandleHeight",p.getInt("edgeHandleHeight",72))
            .put("edgeHandleOpacity",p.getInt("edgeHandleOpacity",p.getInt("edgePanelOpacity",68))).put("edgeHandleBlur",p.getInt("edgeHandleBlur",p.getInt("edgePanelBlur",48)))
            .put("edgePanelTintMode",p.getString("edgePanelTintMode","auto")).put("edgeHandleTintMode",p.getString("edgeHandleTintMode","auto"))
            .put("edgePanelSide",p.getString("edgePanelSide","right")).put("edgePanelApps",p.getString("edgePanelApps",""))
            .put("edgePanelFolderNames",p.getString("edgePanelFolderNames","{}"))
            .put("shadeGlassEnabled",false).put("lockGlassEnabled",false)
            .put("edgePanelNativeGlass",RetiredGlassSettings.edge(p.getString("edgePanelNativeGlass","{}"))).put("systemGlassStyle","{}")
            .put("recoveryReason", p.getString("recoveryReason", ""));
    }
    private static boolean anyFeatureEnabled(JSONObject value) {
        return NotificationUndoSettings.safe(value.optString("notificationUndo",NotificationUndoSettings.DEFAULT)).enabled||CameraRingSettings.safe(value.optString("cameraRing",CameraRingSettings.DEFAULT)).enabled||value.optBoolean("enabled")||value.optBoolean("edgePanelEnabled");
    }
    private static boolean anyFeatureEnabled(SharedPreferences value) {
        return NotificationUndoSettings.safe(value.getString("notificationUndo",NotificationUndoSettings.DEFAULT)).enabled||CameraRingSettings.safe(value.getString("cameraRing",CameraRingSettings.DEFAULT)).enabled||value.getBoolean("enabled",false)||value.getBoolean("edgePanelEnabled",false);
    }
    private static void save(JSONObject c) throws Exception {
        RetiredGlassSettings.normalize(c);
        new CameraRingSettings(c.optString("cameraRing",CameraRingSettings.DEFAULT));
        new NotificationUndoSettings(c.optString("notificationUndo",NotificationUndoSettings.DEFAULT));
        if(c.has("edgePanelTextDurationMs")&&(!(c.opt("edgePanelTextDurationMs") instanceof Number)||c.getDouble("edgePanelTextDurationMs")!=c.getInt("edgePanelTextDurationMs")||!TextAdaptationDuration.valid(c.getInt("edgePanelTextDurationMs"))))throw new IllegalArgumentException("Invalid panel text duration");
        if(c.has("edgePanelTextTone")&&(!(c.opt("edgePanelTextTone") instanceof Number)||c.getDouble("edgePanelTextTone")!=c.getInt("edgePanelTextTone")||!TextTone.valid(c.getInt("edgePanelTextTone"))))throw new IllegalArgumentException("Invalid panel text tone");
        if(c.has("edgePanelTextAdaptation")&&!(c.opt("edgePanelTextAdaptation") instanceof Boolean))throw new IllegalArgumentException("Invalid panel text adaptation");
        if (c.optInt("schemaVersion", 1) != 1 || !FeaturePolicy.valid(c.getInt("intervalMs"), c.getInt("thresholdKB"), c.getInt("textSize"))
            || !FeaturePolicy.validLayout(c.optInt("indicatorHeight",16),c.optInt("rateWidth",38),c.optInt("stackedTextSize",8),c.optInt("arrowScale",140),c.optInt("arrowGap",0),c.optInt("directionGap",6),c.optInt("iconGap",6),c.optInt("verticalOffset",0))
            || !FeaturePolicy.validEdgePanel(c.optInt("edgePanelPosition",50),c.optInt("edgePanelWidth",260),c.optInt("edgePanelHeight",520),c.optInt("edgePanelOpacity",68),c.optInt("edgePanelBlur",48),c.optInt("edgeHandleHeight",72))
            || c.optInt("edgeHandleOpacity",68)<0 || c.optInt("edgeHandleOpacity",68)>95 || c.optInt("edgeHandleBlur",48)<0 || c.optInt("edgeHandleBlur",48)>100
            || !FeaturePolicy.validEdgeTintMode(c.optString("edgePanelTintMode","auto")) || !FeaturePolicy.validEdgeTintMode(c.optString("edgeHandleTintMode","auto"))
            || !FeaturePolicy.validEdgeSide(c.optString("edgePanelSide","right")) || !FeaturePolicy.validEdgeApps(c.optString("edgePanelApps","")))
            throw new IllegalArgumentException("Unsupported configuration values");
        if (!java.util.Arrays.asList("left","right").contains(c.optString("position","left")) || !java.util.Arrays.asList("stacked","inline").contains(c.optString("layout","stacked")) || !java.util.Arrays.asList("bytes","bits").contains(c.optString("units","bytes")) || c.optInt("decimals",1)<0 || c.optInt("decimals",1)>2)
            throw new IllegalArgumentException("Unsupported indicator style");
        if (c.optInt("horizontalPosition",-1)<-1 || c.optInt("horizontalPosition",-1)>1000
            || !java.util.Arrays.asList("plain","pill","outline","mono","glass","box","split","badge").contains(c.optString("indicatorDesign","plain")))
            throw new IllegalArgumentException("Unsupported indicator design or placement");
        String suffix=c.optString("unitSuffix","B/s");
        if (!java.util.Arrays.asList("full","unit","prefix","none","custom").contains(c.optString("unitLabel","full"))
            || suffix.length()>12 || suffix.chars().anyMatch(ch -> Character.isISOControl(ch))
            || c.optInt("unitGap",1)<-4 || c.optInt("unitGap",1)>8 || c.optInt("unitScale",100)<50 || c.optInt("unitScale",100)>120)
            throw new IllegalArgumentException("Unsupported unit formatting");
        SharedPreferences p = store(app);
        String previous = config(app).toString();
        JSONObject before=new JSONObject(previous);
        for (String flag:new String[]{"enabled","edgePanelEnabled","shadeGlassEnabled","lockGlassEnabled"})
            if (before.optBoolean(flag)!=c.optBoolean(flag)) recordEvent(app,"featureChoice",flag+"="+c.optBoolean(flag));
        if (!p.edit().putString("previous", previous).putLong("revision", p.getLong("revision", 0) + 1)
            .putLong("configAt", System.currentTimeMillis())
            .putBoolean("enabled", c.getBoolean("enabled")).putBoolean("emergency", false)
            .putString("cameraRing",c.optString("cameraRing",CameraRingSettings.DEFAULT))
            .putString("notificationUndo",c.optString("notificationUndo",NotificationUndoSettings.DEFAULT))
            .putInt("interval", c.getInt("intervalMs")).putInt("threshold", c.getInt("thresholdKB"))
            .putInt("textSize", c.getInt("textSize")).putInt("indicatorHeight",c.optInt("indicatorHeight",16))
            .putInt("rateWidth",c.optInt("rateWidth",38)).putInt("stackedTextSize",c.optInt("stackedTextSize",8))
            .putInt("arrowScale",c.optInt("arrowScale",140)).putInt("arrowGap",c.optInt("arrowGap",0))
            .putInt("directionGap",c.optInt("directionGap",6)).putInt("iconGap",c.optInt("iconGap",6))
            .putBoolean("boldValue",c.optBoolean("boldValue",false)).putBoolean("boldText",c.optBoolean("boldText",false))
            .putInt("unitGap",c.optInt("unitGap",1)).putInt("unitScale",c.optInt("unitScale",100))
            .putString("unitLabel",c.optString("unitLabel","full")).putString("unitSuffix",suffix)
            .putInt("horizontalPosition",c.optInt("horizontalPosition",-1)).putString("indicatorDesign",c.optString("indicatorDesign","plain"))
            .putInt("verticalOffset",c.optInt("verticalOffset",0)).putBoolean("hideIdle", c.getBoolean("hideIdle"))
            .putBoolean("showUpload",c.optBoolean("showUpload",true)).putBoolean("showArrows",c.optBoolean("showArrows",true))
            .putString("position",c.optString("position","left")).putString("layout",c.optString("layout","stacked")).putString("units",c.optString("units","bytes")).putInt("decimals",c.optInt("decimals",1))
            .putInt("edgePanelTextDurationMs",c.optInt("edgePanelTextDurationMs",-1)).putInt("edgePanelTextTone",c.optInt("edgePanelTextTone",-1)).putBoolean("edgePanelTextAdaptation",c.optBoolean("edgePanelTextAdaptation",false)).putBoolean("edgePanelEnabled",c.optBoolean("edgePanelEnabled",false)).putInt("edgePanelPosition",c.optInt("edgePanelPosition",50))
            .putInt("edgePanelWidth",c.optInt("edgePanelWidth",260)).putInt("edgePanelHeight",c.optInt("edgePanelHeight",520)).putInt("edgePanelOpacity",c.optInt("edgePanelOpacity",68))
            .putInt("edgePanelBlur",c.optInt("edgePanelBlur",48)).putInt("edgeHandleHeight",c.optInt("edgeHandleHeight",72))
            .putInt("edgeHandleOpacity",c.optInt("edgeHandleOpacity",68)).putInt("edgeHandleBlur",c.optInt("edgeHandleBlur",48))
            .putString("edgePanelTintMode",c.optString("edgePanelTintMode","auto")).putString("edgeHandleTintMode",c.optString("edgeHandleTintMode","auto"))
            .putString("edgePanelSide",c.optString("edgePanelSide","right")).putString("edgePanelApps",c.optString("edgePanelApps",""))
            .putString("edgePanelFolderNames",c.optString("edgePanelFolderNames","{}"))
            .putBoolean("shadeGlassEnabled",c.optBoolean("shadeGlassEnabled",false)).putBoolean("lockGlassEnabled",c.optBoolean("lockGlassEnabled",false))
            .putString("edgePanelNativeGlass",c.optString("edgePanelNativeGlass","{}")).putString("systemGlassStyle","{}")
            .putString("recoveryReason", "").commit()) throw new IOException("Cannot persist configuration");
    }
    public static void publish() throws Exception {
        synchronized (LOCK) {
        XposedService s = framework;
        if (s == null) return;
        JSONObject c = hookConfiguration();
        if ((s.getFrameworkProperties() & XposedService.PROP_CAP_REMOTE) == 0) throw new IllegalStateException("Framework lacks remote configuration");
        String signature=c.toString();
        if (signature.equals(lastPublished)) return;
        if (!s.getRemotePreferences(FeaturePolicy.GROUP).edit()
            .putInt("schema",1).putLong("revision",c.getLong("revision"))
            .putString("cameraRing",c.getString("cameraRing"))
            .putString("notificationUndo",c.getString("notificationUndo"))
            .putBoolean("enabled",c.getBoolean("enabled")).putInt("interval",c.getInt("interval"))
            .putInt("threshold",c.getInt("threshold")).putInt("textSize",c.getInt("textSize"))
            .putInt("indicatorHeight",c.getInt("indicatorHeight")).putInt("rateWidth",c.getInt("rateWidth"))
            .putInt("stackedTextSize",c.getInt("stackedTextSize")).putInt("arrowScale",c.getInt("arrowScale"))
            .putInt("arrowGap",c.getInt("arrowGap")).putInt("directionGap",c.getInt("directionGap"))
            .putInt("iconGap",c.getInt("iconGap")).putInt("verticalOffset",c.getInt("verticalOffset"))
            .putBoolean("boldValue",c.getBoolean("boldValue")).putBoolean("boldText",c.getBoolean("boldText"))
            .putInt("unitGap",c.getInt("unitGap")).putInt("unitScale",c.getInt("unitScale"))
            .putString("unitLabel",c.getString("unitLabel")).putString("unitSuffix",c.getString("unitSuffix"))
            .putInt("horizontalPosition",c.getInt("horizontalPosition")).putString("indicatorDesign",c.getString("indicatorDesign"))
            .putBoolean("hideIdle",c.getBoolean("hideIdle")).putBoolean("showUpload",c.getBoolean("showUpload"))
            .putBoolean("showArrows",c.getBoolean("showArrows")).putString("position",c.getString("position")).putString("layout",c.getString("layout"))
            .putString("units",c.getString("units")).putInt("decimals",c.getInt("decimals"))
            .putInt("edgePanelTextDurationMs",c.optInt("edgePanelTextDurationMs",-1)).putInt("edgePanelTextTone",c.optInt("edgePanelTextTone",-1)).putBoolean("edgePanelTextAdaptation",c.optBoolean("edgePanelTextAdaptation",false)).putBoolean("edgePanelEnabled",c.getBoolean("edgePanelEnabled")).putInt("edgePanelPosition",c.getInt("edgePanelPosition"))
            .putInt("edgePanelWidth",c.getInt("edgePanelWidth")).putInt("edgePanelHeight",c.getInt("edgePanelHeight")).putInt("edgePanelOpacity",c.getInt("edgePanelOpacity"))
            .putInt("edgePanelBlur",c.getInt("edgePanelBlur")).putInt("edgeHandleHeight",c.getInt("edgeHandleHeight"))
            .putInt("edgeHandleOpacity",c.getInt("edgeHandleOpacity")).putInt("edgeHandleBlur",c.getInt("edgeHandleBlur"))
            .putString("edgePanelTintMode",c.getString("edgePanelTintMode")).putString("edgeHandleTintMode",c.getString("edgeHandleTintMode"))
            .putString("edgePanelSide",c.getString("edgePanelSide")).putString("edgePanelApps",c.getString("edgePanelApps"))
            .putString("edgePanelFolderNames",c.getString("edgePanelFolderNames"))
            .putBoolean("shadeGlassEnabled",c.getBoolean("shadeGlassEnabled")).putBoolean("lockGlassEnabled",c.getBoolean("lockGlassEnabled"))
            .putString("edgePanelNativeGlass",c.optString("edgePanelNativeGlass","{}")).putString("systemGlassStyle",c.getString("systemGlassStyle"))
            .putLong("safetyAt",rootSuccessElapsed).putInt("safetyBoot",rootBoot).commit()) throw new IOException("Framework rejected configuration");
        lastPublished=signature;
        }
    }
    static JSONObject hookConfiguration() throws Exception {
        synchronized (LOCK) {
            JSONObject source=config(app);
            boolean enabled=source.getBoolean("enabled") && !source.getBoolean("emergencyDisabled")
                && FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT) && rootLeaseValid()
                && rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState"));
            boolean edgeEnabled=source.optBoolean("edgePanelEnabled") && !source.getBoolean("emergencyDisabled")
                && FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT) && rootLeaseValid()
                && rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState"));
            boolean ringAllowed=!source.optBoolean("emergencyDisabled")&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)&&rootLeaseValid()&&rootHealth.optBoolean("authorized")&&"healthy".equals(rootHealth.optString("moduleState"));
            return new JSONObject(source.toString()).put("cameraRing",ringAllowed?source.getString("cameraRing"):CameraRingSettings.disabled(source.getString("cameraRing")))
                .put("notificationUndo",ringAllowed?source.getString("notificationUndo"):NotificationUndoSettings.disabled(source.getString("notificationUndo")))
                .put("schema",1).put("enabled",enabled)
                .put("edgePanelEnabled",edgeEnabled)
                .put("shadeGlassEnabled",source.optBoolean("shadeGlassEnabled")&&!source.optBoolean("emergencyDisabled")&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)&&rootLeaseValid()&&rootHealth.optBoolean("authorized")&&"healthy".equals(rootHealth.optString("moduleState")))
                .put("lockGlassEnabled",source.optBoolean("lockGlassEnabled")&&!source.optBoolean("emergencyDisabled")&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)&&rootLeaseValid()&&rootHealth.optBoolean("authorized")&&"healthy".equals(rootHealth.optString("moduleState")))
                .put("interval",source.getInt("intervalMs")).put("threshold",source.getInt("thresholdKB"))
                .put("safetyAt",rootSuccessElapsed).put("safetyBoot",rootBoot);
        }
    }
    static Bundle hookConfigurationBundle() throws Exception {
        JSONObject c=hookConfiguration();
        Bundle out=new Bundle();
        for (String key:new String[]{"notificationUndo","cameraRing","position","layout","units","indicatorDesign","unitLabel","unitSuffix","edgePanelTintMode","edgeHandleTintMode","edgePanelSide","edgePanelApps","edgePanelFolderNames","edgePanelNativeGlass","systemGlassStyle"}) out.putString(key,c.getString(key));
        for (String key:new String[]{"schema","interval","threshold","textSize","indicatorHeight","rateWidth","stackedTextSize","arrowScale","arrowGap","directionGap","iconGap","verticalOffset","horizontalPosition","unitGap","unitScale","decimals","edgePanelTextDurationMs","edgePanelTextTone","edgePanelPosition","edgePanelWidth","edgePanelHeight","edgePanelOpacity","edgePanelBlur","edgeHandleHeight","edgeHandleOpacity","edgeHandleBlur","safetyBoot"}) out.putInt(key,c.getInt(key));
        for (String key:new String[]{"enabled","hideIdle","showUpload","showArrows","boldValue","boldText","edgePanelTextAdaptation","edgePanelEnabled","shadeGlassEnabled","lockGlassEnabled"}) out.putBoolean(key,c.getBoolean(key));
        out.putLong("revision",c.getLong("revision")); out.putLong("safetyAt",c.getLong("safetyAt"));
        return out;
    }
    private static JSONObject packageInfo(String id) {
        JSONObject out = new JSONObject();
        try {
            android.content.pm.PackageInfo info = app.getPackageManager().getPackageInfo(id, 0);
            out.put("installed", true).put("version", info.versionName).put("package", id);
        } catch (Exception e) { try { out.put("installed", false).put("package", id); } catch (Exception ignored) {} }
        return out;
    }
    private static void addOperators(java.util.Set<String> values, String raw) {
        if (raw == null) return;
        for (String value : raw.split(",")) {
            String clean=value.trim();
            if (clean.matches("[0-9]{5,6}")) values.add(clean);
        }
    }
    private static JSONObject carrierStatus() throws Exception {
        JSONObject out=new JSONObject(carrierRootHealth.toString());
        java.util.LinkedHashSet<String> operators=new java.util.LinkedHashSet<>();
        addOperators(operators,out.optString("simOperators"));
        addOperators(operators,out.optString("networkOperators"));
        int carrierId=-1, dataType=TelephonyManager.NETWORK_TYPE_UNKNOWN, subId=SubscriptionManager.INVALID_SUBSCRIPTION_ID;
        try {
            TelephonyManager tm=(TelephonyManager)app.getSystemService(Context.TELEPHONY_SERVICE);
            subId=SubscriptionManager.getDefaultDataSubscriptionId();
            if (SubscriptionManager.isValidSubscriptionId(subId)) tm=tm.createForSubscriptionId(subId);
            carrierId=tm.getSimCarrierId();
            addOperators(operators,tm.getSimOperator());
            addOperators(operators,tm.getNetworkOperator());
            dataType=tm.getDataNetworkType();
        } catch (SecurityException e) { out.put("telephonyWarning","Android restricted detailed telephony state"); }
        org.json.JSONArray sims=new org.json.JSONArray();
        boolean supported=carrierId==1731 || carrierId==1936;
        for (String operator : operators) {
            String name="Other";
            int expectedId=0;
            if ("60502".equals(operator)) { name="Tunisie Telecom"; expectedId=1731; supported=true; }
            if ("60501".equals(operator)) { name="Orange Tunisia"; expectedId=1936; supported=true; }
            sims.put(new JSONObject().put("mccmnc",operator).put("name",name).put("expectedCarrierId",expectedId));
        }
        boolean valid="true".equals(out.optString("configValid")) && CARRIER_DB_HASH.equals(out.optString("sourceHash"));
        boolean mounted="true".equals(out.optString("overrideMounted"));
        boolean active="true".equals(out.optString("overrideActive"));
        String state=out.optString("moduleState","absent");
        boolean installed=!"absent".equals(state);
        boolean updatePending="true".equals(out.optString("updatePending"));
        boolean updateRequired=installed && !updatePending && (!"2.0.0".equals(out.optString("moduleVersion")) || !"1".equals(out.optString("protocol")));
        boolean pending=updatePending || "true".equals(out.optString("pendingReboot")) || ("disabled".equals(state) && mounted);
        out.put("installed",installed).put("backendAvailable",rootHealth.optBoolean("authorized") && "true".equals(rootHealth.optString("ksuAvailable")))
            .put("supportedCarrierDetected",supported).put("activeSims",sims).put("defaultDataSubscriptionId",subId)
            .put("currentCarrierId",carrierId).put("dataNetworkType",dataType).put("dataNetworkName",networkTypeName(dataType))
            .put("configurationValid",valid).put("mounted",mounted).put("active",active)
            .put("updateRequired",updateRequired).put("rebootRequired",pending)
            .put("intendedProfile",supported ? "wildcard_5g" : "Not applicable")
            .put("mappings",new org.json.JSONArray().put("1731 → wildcard_5g").put("1936 → wildcard_5g"));
        return out;
    }
    private static String networkTypeName(int type) {
        if (type==TelephonyManager.NETWORK_TYPE_NR) return "NR (5G)";
        if (type==TelephonyManager.NETWORK_TYPE_LTE) return "LTE";
        if (type==TelephonyManager.NETWORK_TYPE_UNKNOWN) return "Unknown";
        return "Type "+type;
    }
    public static JSONObject probe(boolean requestRoot) throws Exception {
        if (requestRoot) probeRoot(); else refreshSafetyNowIfNeeded();
        refreshSafetyIfNeeded();
        JSONObject c = config(app);
        JSONObject xp = new JSONObject().put("connected", framework != null).put("error", frameworkError);
        XposedService s = framework;
        if (s != null) {
            try {
                xp.put("name", s.getFrameworkName()).put("version", s.getFrameworkVersion()).put("api", s.getApiVersion())
                    .put("remoteConfig", (s.getFrameworkProperties() & XposedService.PROP_CAP_REMOTE) != 0)
                    .put("systemCapability", (s.getFrameworkProperties() & XposedService.PROP_CAP_SYSTEM) != 0)
                    .put("scope", new org.json.JSONArray(s.getScope()));
                if (s.getApiVersion() >= 102) xp.put("runningTargets", s.getRunningTargets().size());
            } catch (Throwable e) { xp.put("connected", false).put("error", e.toString()); }
        }
        SharedPreferences p = store(app);
        long age = p.getInt("hookBoot",-1)==bootCount() && p.contains("hookElapsed") ? android.os.SystemClock.elapsedRealtime()-p.getLong("hookElapsed",0) : Long.MAX_VALUE;
        JSONObject hook = new JSONObject().put("observed", p.contains("hookAt")).put("fresh", age >= 0 && age < 15000)
            .put("ageMs", age==Long.MAX_VALUE?-1:age).put("state", p.getString("hookState", "Not observed"))
            .put("error", p.getString("hookError", "")).put("revision", p.getLong("hookRevision", -1))
            .put("pid", p.getInt("hookPid", 0)).put("version", p.getString("hookVersion", ""));
        JSONObject metrics=new JSONObject(p.getString("hookMetrics","{}"));
        hook.put("metrics",metrics);
        boolean supported = FeaturePolicy.supported(Build.VERSION.SDK_INT, Build.FINGERPRINT);
        org.json.JSONArray blockers = new org.json.JSONArray();
        if (app.getPackageManager().isSafeMode()) blockers.put("Android safe mode is active");
        if (!supported) blockers.put("Android/SystemUI build has not been validated");
        if (!hook.optBoolean("fresh")) blockers.put("SystemUI hook has not reported health; activation or a SystemUI restart may be required");
        else if ("unsupported".equals(hook.optString("state")) || "error".equals(hook.optString("state"))) blockers.put("SystemUI hook reported a compatibility or runtime failure");
        boolean hookBridge=hook.optBoolean("fresh") && !"unsupported".equals(hook.optString("state")) && !"error".equals(hook.optString("state"));
        if (!xp.optBoolean("connected") && !hookBridge) blockers.put("Enable Node Cockpit in Vector/compatible Xposed manager");
        else if (xp.optBoolean("connected") && !hookBridge) {
            if (!xp.optBoolean("remoteConfig")) blockers.put("Framework does not support remote configuration");
            if (xp.optJSONArray("scope")==null || !xp.optJSONArray("scope").toString().contains("com.android.systemui")) blockers.put("SystemUI is outside the module scope");
        }
        if (!rootHealth.optBoolean("authorized")) blockers.put("Root access has not been verified");
        if (!"healthy".equals(rootHealth.optString("moduleState"))) blockers.put("KernelSU recovery module is not running");
        if (!rootLeaseValid()) blockers.put("Refresh root/backend health before enabling");
        org.json.JSONArray capabilities = new org.json.JSONArray();
        if (supported) capabilities.put("device.validatedSystemUi");
        if ((xp.optBoolean("connected") && xp.optBoolean("remoteConfig")) || hookBridge) capabilities.put("xposed.remoteConfiguration");
        if (xp.optBoolean("connected") && hook.optBoolean("fresh") && !"unsupported".equals(hook.optString("state")) && !"error".equals(hook.optString("state")) && xp.optJSONArray("scope") != null && xp.getJSONArray("scope").toString().contains("com.android.systemui")) capabilities.put("xposed.systemuiHook");
        if (rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState")) && rootLeaseValid()) capabilities.put("root.recoveryWatchdog");
        JSONObject carrier=carrierStatus();
        if (carrier.optBoolean("backendAvailable")) capabilities.put("root.carrierProfileOverride");
        if (carrier.optBoolean("supportedCarrierDetected")) capabilities.put("carrier.tunisia5gSupported");
        return new JSONObject().put("config", c).put("supported", supported).put("android", Build.VERSION.RELEASE)
            .put("capabilities", capabilities).put("safeMode", app.getPackageManager().isSafeMode())
            .put("sdk", Build.VERSION.SDK_INT).put("fingerprint", Build.FINGERPRINT).put("device", Build.MODEL)
            .put("vector", packageInfo("org.matrix.vector.manager")).put("lsposed", packageInfo("org.lsposed.manager"))
            .put("kernelsu", packageInfo("me.weishu.kernelsu")).put("xposed", xp).put("root", rootHealth).put("carrier",carrier)
            .put("rootCheckedAt", rootCheckedAt).put("hook", hook).put("blockers", blockers)
            .put("canEnable", blockers.length() == 0).put("protocol", 1)
            .put("restartRequired", c.optBoolean("enabled") && System.currentTimeMillis()-p.getLong("configAt",0)>15000 && (!hook.optBoolean("fresh") || hook.optLong("revision") != c.optLong("revision")))
            .put("hookUpdateRequired",hook.optBoolean("observed") && !String.valueOf(FeaturePolicy.HOOK_VERSION).equals(hook.optString("version")))
            .put("events",new org.json.JSONArray(p.getString("healthEvents","[]")))
            .put("safetyLeaseRemainingMs",Math.max(0,FeaturePolicy.SAFETY_LEASE_MS-(android.os.SystemClock.elapsedRealtime()-rootSuccessElapsed)))
            .put("savedSetups",setupList(false)).put("hasPrevious", p.contains("previous")).put("hasLastGood", p.contains("lastGood"));
    }
    private static String root(String command) throws Exception {
        Process process = new ProcessBuilder("su", "-c", command).redirectErrorStream(true).start();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        Thread reader = new Thread(() -> {
            try (InputStream in = process.getInputStream()) {
                byte[] b = new byte[2048]; int n;
                while ((n = in.read(b)) >= 0) if (output.size() < 65536) output.write(b, 0, Math.min(n, 65536 - output.size()));
            } catch (IOException ignored) {}
        });
        reader.setDaemon(true); reader.start();
        if (!process.waitFor(30, TimeUnit.SECONDS)) { process.destroyForcibly(); throw new IOException("Root request timed out; approve Node Cockpit in KernelSU"); }
        reader.join(1500);
        String result = output.toString("UTF-8").trim();
        if (process.exitValue() != 0) throw new IOException(result.isEmpty() ? "Root access denied" : result);
        return result;
    }
    private static String collectRootHealth(boolean includeCarrier) throws Exception {
            return root("[ \"$(id -u)\" = 0 ] || exit 1; echo AUTHORIZED; " +
                "if [ -f " + MODULE + "/disable ]; then echo moduleState=disabled; " +
                "elif [ -f " + MODULE + "/remove ]; then echo moduleState=removalPending; " +
                "elif [ -x " + MODULE + "/control.sh ]; then " + MODULE + "/control.sh status; " +
                "elif [ -d /data/adb/modules_update/node_cockpit_system ]; then echo moduleState=pendingReboot; " +
                "else echo moduleState=absent; fi; " +
                "if [ -x /data/adb/ksud ]; then echo ksuAvailable=true; /data/adb/ksud -V 2>/dev/null; else echo ksuAvailable=false; fi; " +
                "echo verifiedBootRaw=$(grep '^androidboot[.]verifiedbootstate ' /proc/bootconfig 2>/dev/null | cut -d '\"' -f 2); " +
                "echo verifiedBoot=$(getprop ro.boot.verifiedbootstate); echo bootloaderLocked=$(getprop ro.boot.flash.locked); echo selinux=$(getenforce); " + (includeCarrier ? carrierProbeCommand() : ""));
    }
    /** Background shell collection cannot stall live visual edits behind LOCK. */
    private static void probeRootBackground() {
        long previousCheck=rootCheckedAt;
        String output=null; Exception failure=null;
        try { output=collectRootHealth(false); } catch (Exception error) { failure=error; }
        synchronized (LOCK) {
            // A newer explicit check wins over a background result collected earlier.
            if (rootCheckedAt!=previousCheck) return;
            acceptRootHealth(output,failure);
        }
    }
    private static void probeRoot() {
        synchronized (LOCK) {
            String output=null; Exception failure=null;
            try { output=collectRootHealth(true); } catch (Exception error) { failure=error; }
            acceptRootHealth(output,failure);
        }
    }
    private static void acceptRootHealth(String output,Exception collectionError) {
        JSONObject r = new JSONObject();
        try {
            if (collectionError!=null) throw collectionError;
            if (!output.startsWith("AUTHORIZED")) throw new IOException("Root identity not verified");
            r.put("authorized", true);
            JSONObject carrier=new JSONObject();
            for (String line : output.split("\n")) {
                int equal = line.indexOf('=');
                if (equal > 0 && equal < 64) {
                    String key=line.substring(0,equal), value=line.substring(equal+1);
                    if (key.startsWith("carrier.")) carrier.put(key.substring(8),value); else r.put(key,value);
                }
            }
            if (carrier.length()>0) { carrierRootHealth=carrier; store(app).edit().putString("carrierRootSnapshot",carrier.toString()).apply(); }
            if ("true".equals(r.optString("quarantined"))) {
                String reason = r.optString("quarantineReason");
                if ("crashloop".equals(reason)) emergency(app,"SystemUI restart protection quarantined customization");
                else if ("user".equals(reason)) emergency(app,"Disabled by user");
                else if (!store(app).getBoolean("emergency",false)) emergency(app,"Recovery backend quarantined customization");
            }
            if (!"1".equals(r.optString("protocol")) && !"absent".equals(r.optString("moduleState")) && !"pendingReboot".equals(r.optString("moduleState")) && !"disabled".equals(r.optString("moduleState"))) r.put("moduleState", "incompatibleProtocol");
            if ("healthy".equals(r.optString("moduleState")) && !r.has("watchdogAt")) r.put("moduleState","heartbeatDelayed").put("probeWarning","Watchdog did not report a heartbeat timestamp");
            if (r.has("watchdogAt")) {
                long age = System.currentTimeMillis()/1000 - Long.parseLong(r.getString("watchdogAt"));
                r.put("watchdogAgeSeconds", age);
                if ((age < 0 || age > 20) && "healthy".equals(r.optString("moduleState"))) {
                    if (!"true".equals(r.optString("quarantined")) && rootLeaseValid() && rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState"))) {
                        JSONObject retained=new JSONObject(rootHealth.toString());
                        retained.put("probeWarning","Watchdog heartbeat delayed; checking again").put("watchdogAgeSeconds",age);
                        rootHealth=retained; rootCheckedAt=System.currentTimeMillis();
                        return; // Do not extend the lease using an unverified heartbeat.
                    }
                    r.put("moduleState","heartbeatDelayed").put("probeWarning","Waiting for a fresh watchdog heartbeat");
                }
            }
            store(app).edit().putBoolean("rootApproved",true).apply();
            rootFailures=0;
            if ("healthy".equals(r.optString("moduleState"))) {
                rootSuccessElapsed=android.os.SystemClock.elapsedRealtime(); rootBoot=bootCount();
                store(app).edit().putLong("rootSuccessElapsed",rootSuccessElapsed).putInt("rootBoot",rootBoot).putString("rootSnapshot",r.toString()).apply();
            }

        } catch (Exception e) {
            rootFailures++;
            String message=String.valueOf(e.getMessage());
            String lower=message.toLowerCase(java.util.Locale.ROOT);
            boolean denied=lower.contains("permission denied") || lower.contains("access denied") || lower.contains("not allowed") || lower.contains("root access denied");
            if (!denied && rootLeaseValid() && rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState"))) {
                try { r=new JSONObject(rootHealth.toString()).put("probeWarning",message).put("consecutiveFailures",rootFailures); } catch (Exception ignored) {}
            } else {
                try { r.put("authorized",false).put("moduleState",denied?"accessDenied":"checkFailed").put("error",message).put("consecutiveFailures",rootFailures); } catch (Exception ignored) {}
            }
            if (rootFailures==1) recordEvent(app,"healthCheck",message);
            if (denied) store(app).edit().putBoolean("rootApproved",false).apply();
        }
        rootHealth=r; rootCheckedAt=System.currentTimeMillis();
        String module=r.optString("moduleState");
        // Confirmed framework disable/removal/denial is terminal. Delayed checks suspend only
        // the effective output; they do not erase the user's desired feature toggle.
        if (anyFeatureEnabled(store(app))
            && java.util.Arrays.asList("disabled","removalPending","absent","incompatibleProtocol","accessDenied").contains(module))
            emergency(app,"Recovery backend "+module+"; customization stopped");
    }
    private static String carrierProbeCommand() {
        String update="/data/adb/modules_update/tn_5g_cfgdb_wildcard";
        return "if [ -d " + update + " ]; then echo carrier.updatePending=true; else echo carrier.updatePending=false; fi; " +
            "if [ -x " + CARRIER_MODULE + "/control.sh ]; then " + CARRIER_MODULE + "/control.sh status; " +
            "elif [ -d " + CARRIER_MODULE + " ]; then " +
            "echo carrier.protocol=legacy; " +
            "if [ -f " + CARRIER_MODULE + "/remove ]; then echo carrier.moduleState=removalPending; elif [ -f " + CARRIER_MODULE + "/disable ]; then echo carrier.moduleState=disabled; else echo carrier.moduleState=enabled; fi; " +
            "echo carrier.moduleVersion=$(sed -n 's/^version=//p' " + CARRIER_MODULE + "/module.prop 2>/dev/null | head -n 1); " +
            "echo carrier.sourceFound=$([ -f " + CARRIER_MODULE + "/cfg.db ] && echo true || echo false); " +
            "echo carrier.sourceHash=$(sha256sum " + CARRIER_MODULE + "/cfg.db 2>/dev/null | awk '{print $1}'); " +
            "echo carrier.targetHash=$(sha256sum /vendor/firmware/carrierconfig/cfg.db 2>/dev/null | awk '{print $1}'); " +
            "echo carrier.configValid=$([ \"$(sha256sum " + CARRIER_MODULE + "/cfg.db 2>/dev/null | awk '{print $1}')\" = \"" + CARRIER_DB_HASH + "\" ] && echo true || echo false); " +
            "echo carrier.overrideMounted=$(grep -F ' /vendor/firmware/carrierconfig/cfg.db ' /proc/self/mountinfo >/dev/null 2>&1 && echo true || echo false); " +
            "echo carrier.overrideActive=$([ \"$(sha256sum /vendor/firmware/carrierconfig/cfg.db 2>/dev/null | awk '{print $1}')\" = \"" + CARRIER_DB_HASH + "\" ] && grep -F ' /vendor/firmware/carrierconfig/cfg.db ' /proc/self/mountinfo >/dev/null 2>&1 && echo true || echo false); " +
            "echo carrier.simOperators=$(getprop gsm.sim.operator.numeric); echo carrier.networkOperators=$(getprop gsm.operator.numeric); " +
            "else echo carrier.protocol=0; echo carrier.moduleState=$([ -d " + update + " ] && echo pendingReboot || echo absent); fi";
    }
    public static JSONObject apply(JSONObject requested) throws Exception {
        return applyOwned(requested,false);
    }
    private static JSONObject applyOwned(JSONObject requested,boolean ownsRing) throws Exception {return applyOwned(requested,ownsRing,false);}
    private static JSONObject applyOwned(JSONObject requested,boolean ownsRing,boolean ownsUndo) throws Exception {
        synchronized (LOCK) {
            CameraRingSettings.mergeOwnership(requested,config(app).getString("cameraRing"),ownsRing);
            NotificationUndoSettings.mergeOwnership(requested,config(app).getString("notificationUndo"),ownsUndo);
            boolean requestedActive=anyFeatureEnabled(requested);
            if (requestedActive) {
                JSONObject health = probe(true);
                if (!health.getBoolean("canEnable")) throw new IllegalStateException(health.getJSONArray("blockers").toString());
            }
            save(requested);
            recordEvent(app,"configuration","Applied revision "+store(app).getLong("revision",0));
            try {
                if (rootHealth.optBoolean("authorized") && "healthy".equals(rootHealth.optString("moduleState"))) {
                    JSONObject c = config(app);
                    boolean anyEnabled=anyFeatureEnabled(c);
                    root(MODULE + "/control.sh apply " + c.getLong("revision") + " " + (anyEnabled ? 1 : 0));
                    JSONObject applied=new JSONObject(rootHealth.toString()).put("revision",String.valueOf(c.getLong("revision")))
                        .put("enabled",anyEnabled?"1":"0").put("quarantined","false");
                    applied.remove("quarantineReason");
                    rootHealth=applied;
                    // The helper acknowledged the write. Update its known config without
                    // extending the independently verified watchdog lease.
                    store(app).edit().putString("rootSnapshot",applied.toString()).apply();
                } else if (requestedActive) throw new IllegalStateException("Recovery backend unavailable");
                publish();
            } catch (Exception e) { emergency(app, "Apply failed: " + e.getMessage()); throw e; }
            return probe(false);
        }
    }
    /** Feature-owned merge preserves unrelated current choices. */
    public static JSONObject applyCameraRing(String raw) throws Exception {
        new CameraRingSettings(raw);
        synchronized(LOCK){applyOwned(config(app).put("cameraRing",raw),true);return cameraRingState();}
    }
    public static JSONObject cameraRingState()throws Exception{
        JSONObject p=new JSONObject(store(app).getString("hookMetrics","{}"));
        return new JSONObject().put("config",new JSONObject(config(app).getString("cameraRing")))
            .put("aodEnabled",android.provider.Settings.Secure.getInt(app.getContentResolver(),"doze_always_on",0)==1)
            .put("supported",FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT))
            .put("status",p.optString("cameraRing","Waiting for SystemUI hook"));
    }
    public static JSONObject notificationUndoState()throws Exception{
        JSONObject metrics=new JSONObject(store(app).getString("hookMetrics","{}"));
        return new JSONObject().put("supported",FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)).put("config",new JSONObject(config(app).getString("notificationUndo"))).put("status",metrics.optString("notificationUndo","Waiting for SystemUI hook")).put("sample",NotificationUndoSamples.state(app)).put("notificationsAllowed",app.getSystemService(android.app.NotificationManager.class).areNotificationsEnabled()).put("notificationPermissionGranted",Build.VERSION.SDK_INT<33||app.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED);
    }
    public static JSONObject applyNotificationUndo(String raw)throws Exception{
        new NotificationUndoSettings(raw);
        synchronized(LOCK){applyOwned(config(app).put("notificationUndo",raw),false,true);return notificationUndoState();}
    }
    public static JSONObject postNotificationUndoSample()throws Exception{NotificationUndoSamples.post(app);return notificationUndoState();}
    public static JSONObject testCameraRing()throws Exception{
        return testCameraRing(false);
    }
    public static JSONObject testCameraRing(boolean ambient)throws Exception{
        JSONObject health=probe(true);
        if(!health.optBoolean("canEnable")||config(app).optBoolean("emergencyDisabled"))throw new IllegalStateException("Resume System integration safely before testing");
        if(ambient&&android.provider.Settings.Secure.getInt(app.getContentResolver(),"doze_always_on",1)!=0)throw new IllegalStateException("Turn Always-on display off for this test");
        root("am broadcast --user 0 -a com.nodecockpit.customization.CAMERA_RING_PROBE -p com.android.systemui --ez start true --ez ambient "+ambient);
        return cameraRingState();
    }
    public static JSONObject stopCameraRingTest()throws Exception{
        root("am broadcast --user 0 -a com.nodecockpit.customization.CAMERA_RING_PROBE -p com.android.systemui --ez start false");
        return cameraRingState();
    }
    /** Visual/content edits do not need a root probe or watchdog command. */
    public static JSONObject applyVisual(JSONObject requested) throws Exception {
        synchronized (LOCK) {
            JSONObject current=config(app);
            CameraRingSettings.mergeOwnership(requested,current.getString("cameraRing"),false);
            if (CameraRingSettings.safe(requested.optString("cameraRing",CameraRingSettings.DEFAULT)).enabled!=CameraRingSettings.safe(current.optString("cameraRing",CameraRingSettings.DEFAULT)).enabled||requested.optBoolean("enabled")!=current.optBoolean("enabled")||requested.optBoolean("edgePanelEnabled")!=current.optBoolean("edgePanelEnabled")||requested.optBoolean("shadeGlassEnabled")!=current.optBoolean("shadeGlassEnabled")||requested.optBoolean("lockGlassEnabled")!=current.optBoolean("lockGlassEnabled")||current.optBoolean("emergencyDisabled"))
                throw new IllegalStateException("Enablement requires the safety apply path");
            save(requested);
            recordEvent(app,"configuration","Applied visual revision "+store(app).getLong("revision",0));
            publish();
            app.getContentResolver().notifyChange(Uri.parse("content://com.example.remote_control.customization.health/configuration"),null);
            return new JSONObject().put("config",config(app));
        }
    }
    /** Bounded placement update sent by the SystemUI handle after a drag. */
    static Bundle applyEdgePlacement(int position,String side) throws Exception {
        synchronized (LOCK) {
            if (position<5||position>95||!FeaturePolicy.validEdgeSide(side)) throw new IllegalArgumentException("Invalid edge placement");
            JSONObject current=config(app).put("edgePanelPosition",position).put("edgePanelSide",side);
            save(current); publish();
            Bundle result=new Bundle(); result.putLong("revision",store(app).getLong("revision",0)); return result;
        }
    }
    /** Bounded user drag result; nested JSON participates in existing edge Save/Restore. */
    static Bundle applyEdgeSearchPlacement(double x,double y) throws Exception {
        synchronized(LOCK){
            if(!Double.isFinite(x)||!Double.isFinite(y)||x<0||x>1||y<0||y>1)throw new IllegalArgumentException("Invalid search placement");
            JSONObject current=config(app),glass=new JSONObject(current.optString("edgePanelNativeGlass","{}"));
            JSONObject search=glass.optJSONObject("searchTray");if(search==null)search=new JSONObject();search.put("x",x).put("y",y);search.remove("docked");glass.put("searchTray",search);current.put("edgePanelNativeGlass",glass.toString());
            save(current);publish();Bundle result=new Bundle();result.putLong("revision",store(app).getLong("revision",0));return result;
        }
    }
    static Bundle applyEdgeApps(String apps,String names) throws Exception {
        synchronized (LOCK) {
            if (!FeaturePolicy.validEdgeApps(apps)) throw new IllegalArgumentException("Invalid edge apps");
            if (names==null||names.length()>2048) throw new IllegalArgumentException("Invalid folder names");
            JSONObject parsed=new JSONObject(names); java.util.Iterator<String> keys=parsed.keys();
            while (keys.hasNext()) { String key=keys.next(); if (!FeaturePolicy.validEdgeApps(key)||parsed.getString(key).length()>40) throw new IllegalArgumentException("Invalid folder name"); }
            JSONObject current=config(app).put("edgePanelApps",apps).put("edgePanelFolderNames",parsed.toString()); save(current); publish();
            Bundle result=new Bundle(); result.putLong("revision",store(app).getLong("revision",0)); return result;
        }
    }
    public static void emergency(Context context, String reason) {
        synchronized (LOCK) {
        SharedPreferences p = store(context);
        if (p.getBoolean("emergency",false) && reason.equals(p.getString("recoveryReason",""))) return;
        recordEvent(context,"recovery",reason);
        SharedPreferences.Editor recovery=p.edit();
        // Suspension must not destroy desired preferences. Only an explicit disable does.
        if (FeaturePolicy.clearDesiredOnEmergency(reason)) recovery.putString("notificationUndo",NotificationUndoSettings.disabled(p.getString("notificationUndo",NotificationUndoSettings.DEFAULT))).putString("cameraRing",CameraRingSettings.disabled(p.getString("cameraRing",CameraRingSettings.DEFAULT))).putBoolean("enabled",false).putBoolean("edgePanelEnabled",false).putBoolean("shadeGlassEnabled",false).putBoolean("lockGlassEnabled",false);
        recovery.putBoolean("emergency", true)
            .putLong("revision", p.getLong("revision", 0) + 1).putString("recoveryReason", reason).commit();
        try { publish(); } catch (Exception ignored) {}
        }
    }
    public static JSONObject disable() throws Exception {
        synchronized (LOCK) {
        emergency(app, "Disabled by user");
        if (rootHealth.optBoolean("authorized")) {
            try { root(MODULE + "/control.sh disable"); } catch (Exception ignored) {}
        }
        return probe(false);
        }
    }
    private static org.json.JSONArray setupList(boolean full) throws Exception {
        org.json.JSONArray saved=new org.json.JSONArray(store(app).getString("savedSetups","[]"));
        if (full) return saved;
        org.json.JSONArray metadata=new org.json.JSONArray();
        for (int i=0;i<saved.length();i++) { JSONObject item=saved.getJSONObject(i); metadata.put(new JSONObject().put("id",item.getString("id")).put("name",item.getString("name")).put("at",item.getLong("at")).put("updatedAt",item.optLong("updatedAt",item.getLong("at"))).put("feature",item.optString("feature","all"))); }
        return metadata;
    }
    private static void checkpoint(String name) throws Exception {
        JSONObject snapshot=config(app); snapshot.remove("revision"); snapshot.remove("emergencyDisabled"); snapshot.remove("recoveryReason");
        JSONObject entry=new JSONObject().put("id",java.util.UUID.randomUUID().toString()).put("name",name).put("at",System.currentTimeMillis()).put("config",snapshot);
        org.json.JSONArray old=setupList(true), saved=new org.json.JSONArray().put(entry);
        for (int i=0;i<old.length()&&saved.length()<12;i++) saved.put(old.getJSONObject(i));
        if (!store(app).edit().putString("savedSetups",saved.toString()).commit()) throw new IOException("Could not save setup");
    }
    public static JSONObject saveSetup(String name) throws Exception {
        synchronized (LOCK) {
            name=name==null?"":name.trim();
            if (name.isEmpty()||name.length()>60) throw new IllegalArgumentException("Use a setup name of 1 to 60 characters");
            checkpoint(name); recordEvent(app,"setupSaved",name); return probe(false);
        }
    }
    public static JSONObject updateSetup(String id,String scope) throws Exception {
        if (!SavedSetupScope.valid(scope)) throw new IllegalArgumentException("Unknown setup feature");
        synchronized (LOCK) {
            org.json.JSONArray saved=setupList(true); JSONObject current=config(app);
            for (int i=0;i<saved.length();i++) {
                JSONObject entry=saved.getJSONObject(i);
                if (!entry.getString("id").equals(id)) continue;
                JSONObject target=entry.getJSONObject("config");
                java.util.Iterator<String> keys=current.keys();
                while (keys.hasNext()) { String key=keys.next(); if (SavedSetupScope.owns(scope,key)) target.put(key,current.get(key)); }
                entry.put("updatedAt",System.currentTimeMillis()).put("feature",scope);
                org.json.JSONArray recent=new org.json.JSONArray().put(entry);
                for (int j=0;j<saved.length();j++) if (j!=i) recent.put(saved.getJSONObject(j));
                if (!store(app).edit().putString("savedSetups",recent.toString()).commit()) throw new IOException("Could not update setup");
                recordEvent(app,"setupUpdated",entry.getString("name")+" ("+scope+")"); return probe(false);
            }
            throw new IllegalArgumentException("Saved setup no longer exists");
        }
    }
    public static JSONObject restoreSetup(String id) throws Exception { return restoreSetup(id,"all"); }
    public static JSONObject restoreSetup(String id,String scope) throws Exception {
        if (!SavedSetupScope.valid(scope)) throw new IllegalArgumentException("Unknown setup feature");
        synchronized (LOCK) {
            org.json.JSONArray saved=setupList(true);
            for (int i=0;i<saved.length();i++) {
                JSONObject entry=saved.getJSONObject(i);
                if (!entry.getString("id").equals(id)) continue;
                JSONObject snapshot=entry.getJSONObject("config");
                JSONObject selected="all".equals(scope)?new JSONObject(snapshot.toString()):config(app);
                if (!"all".equals(scope)) {
                    java.util.Iterator<String> keys=snapshot.keys();
                    while (keys.hasNext()) { String key=keys.next(); if (SavedSetupScope.owns(scope,key)) selected.put(key,snapshot.get(key)); }
                }
                checkpoint("Before restore"+("all".equals(scope)?"":" ("+scope+")")+": "+entry.getString("name"));
                JSONObject result=applyOwned(selected,"all".equals(scope)); recordEvent(app,"setupRestored",entry.getString("name")+" ("+scope+")"); return result;
            }
            throw new IllegalArgumentException("Saved setup no longer exists");
        }
    }
    public static JSONObject rollback() throws Exception {
        String raw = store(app).getString("lastGood", store(app).getString("previous", null));
        if (raw == null) throw new IllegalStateException("No previous configuration");
        JSONObject c = new JSONObject(raw); c.put("enabled", false).put("shadeGlassEnabled",false).put("lockGlassEnabled",false);
        return apply(c);
    }
    public static JSONObject restartSystemUi() throws Exception {
        probeRoot();
        if (!FeaturePolicy.supported(Build.VERSION.SDK_INT, Build.FINGERPRINT) || !rootHealth.optBoolean("authorized") || !"healthy".equals(rootHealth.optString("moduleState")))
            throw new IllegalStateException("Validated device and healthy recovery backend required");
        recordEvent(app,"systemUiRestart","Requested; configuration preserved");
        // Fixed target only; no caller-supplied PID, executable, signal or command.
        root("p=$(pidof com.android.systemui); [ -n \"$p\" ] && kill -TERM $p");
        return probe(false);
    }
    static void recoverMissingBootHook() {
        try {
            SharedPreferences p=store(app);
            int currentBoot=bootCount();
            if (currentBoot<0 || p.getInt("bootRecoveryAttemptBoot",-1)==currentBoot) return;
            if (!anyFeatureEnabled(config(app))) return;
            long hookAge=System.currentTimeMillis()-p.getLong("hookAt",0);
            if (p.getInt("hookBoot",-1)==currentBoot && hookAge>=0 && hookAge<45_000) return;
            p.edit().putInt("bootRecoveryAttemptBoot",currentBoot).commit();
            probeRoot();
            if (!FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)
                || !rootHealth.optBoolean("authorized") || !"healthy".equals(rootHealth.optString("moduleState"))) {
                recordEvent(app,"bootRecovery","Skipped; recovery backend was not healthy");
                return;
            }
            recordEvent(app,"bootRecovery","SystemUI hook missing after boot; one bounded restart requested");
            root("p=$(pidof com.android.systemui); [ -n \"$p\" ] && kill -TERM $p");
        } catch (Throwable e) {
            recordEvent(app,"bootRecovery","Failed: "+String.valueOf(e.getMessage()));
        }
    }
    public static JSONObject install() throws Exception {
        probeRoot();
        if (!rootHealth.optBoolean("authorized") || !"true".equals(rootHealth.optString("ksuAvailable"))) throw new IllegalStateException("Approve root access through KernelSU first");
        String state = rootHealth.optString("moduleState");
        if (!state.equals("absent")) throw new IllegalStateException("Module already present: " + state + ". It will not be re-enabled or overwritten automatically.");
        installAsset("node-cockpit-system");
        probeRoot(); return probe(false);
    }
    private static void installAsset(String asset) throws Exception {
        File zip = new File(app.getCacheDir(), asset + ".zip");
        try (InputStream in = app.getAssets().open(asset + ".zip"); OutputStream out = new FileOutputStream(zip)) { byte[] b = new byte[8192]; int n; while ((n=in.read(b))>=0) out.write(b,0,n); }
        String expected;
        try (InputStream in = app.getAssets().open(asset + ".sha256")) {
            byte[] bytes = new byte[128]; int n = in.read(bytes);
            expected = new String(bytes, 0, Math.max(0,n), java.nio.charset.StandardCharsets.US_ASCII).trim();
        }
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(zip)) { byte[] b = new byte[8192]; int n; while ((n=in.read(b))>=0) digest.update(b,0,n); }
        StringBuilder hex = new StringBuilder(); for (byte b : digest.digest()) hex.append(String.format("%02x", b));
        if (!hex.toString().equals(expected)) throw new SecurityException("Bundled module checksum mismatch");
        try { root("/data/adb/ksud module install '" + zip.getCanonicalPath().replace("'", "'\\''") + "'"); }
        finally { zip.delete(); }
    }
    public static JSONObject installCarrier() throws Exception {
        probeRoot();
        JSONObject carrier=carrierStatus();
        if (!carrier.optBoolean("backendAvailable")) throw new IllegalStateException("Approve root access through KernelSU first");
        String state=carrier.optString("moduleState","absent");
        if (!"absent".equals(state) && !carrier.optBoolean("updateRequired"))
            throw new IllegalStateException("Carrier backend is already current");
        if ("removalPending".equals(state)) throw new IllegalStateException("Carrier backend is pending removal; reboot before installing it again");
        installAsset(CARRIER_ASSET);
        recordEvent(app,"carrierProfile",("absent".equals(state)?"Installed":"Updated")+" Tunisia 5G backend; reboot required");
        probeRoot();
        return probe(false);
    }
    public static JSONObject setCarrierEnabled(boolean enabled) throws Exception {
        probeRoot();
        JSONObject carrier=carrierStatus();
        if (!carrier.optBoolean("backendAvailable")) throw new IllegalStateException("KernelSU root access is unavailable");
        if (!carrier.optBoolean("installed")) throw new IllegalStateException("Install the carrier backend first");
        if (carrier.optBoolean("updateRequired")) throw new IllegalStateException("Update the carrier backend before changing its state");
        if (carrier.optBoolean("rebootRequired")) throw new IllegalStateException("A carrier backend change is already waiting for reboot");
        if ("removalPending".equals(carrier.optString("moduleState"))) throw new IllegalStateException("Carrier backend is pending removal");
        root(CARRIER_MODULE + "/control.sh " + (enabled ? "enable" : "disable"));
        recordEvent(app,"carrierProfile",enabled ? "Enable staged; reboot required" : "Stock behavior staged; reboot required");
        probeRoot();
        return probe(false);
    }
    public static void openFramework(Context c) {
        Intent vector = c.getPackageManager().getLaunchIntentForPackage("org.matrix.vector.manager");
        if (vector != null) {
            // Vector's public launch contract accepts the bare "modules" URI and
            // switches its Compose shell directly to the Modules tab.
            vector.setData(Uri.parse("modules"));
            c.startActivity(vector.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return;
        }
        Intent legacy = c.getPackageManager().getLaunchIntentForPackage("org.lsposed.manager");
        if (legacy != null) {
            c.startActivity(legacy.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return;
        }
        throw new IllegalStateException("Open your Xposed framework manager manually");
    }
    public static void openFrameworkModule(Context c) {
        Intent vector = c.getPackageManager().getLaunchIntentForPackage("org.matrix.vector.manager");
        if (vector == null) {
            openFramework(c);
            return;
        }
        int userId = android.os.Process.myUid() / 100000;
        Uri destination = new Uri.Builder()
            .scheme("module")
            .encodedAuthority(c.getPackageName() + ":" + userId)
            .build();
        vector.setData(destination);
        c.startActivity(vector.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
    public static void openVectorDownload(Context c) {
        Intent intent = new Intent(Intent.ACTION_VIEW,
            Uri.parse("https://github.com/JingMatrix/Vector/releases/latest"));
        if (intent.resolveActivity(c.getPackageManager()) == null)
            throw new IllegalStateException("No browser is available to download Vector");
        c.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
    public static void openKernelSuDownload(Context c) {
        Intent intent = new Intent(Intent.ACTION_VIEW,
            Uri.parse("https://github.com/tiann/KernelSU/releases/latest"));
        if (intent.resolveActivity(c.getPackageManager()) == null)
            throw new IllegalStateException("No browser is available to download KernelSU");
        c.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
    public static void openKernelSu(Context c) {
        Intent intent = c.getPackageManager().getLaunchIntentForPackage("me.weishu.kernelsu");
        if (intent == null) throw new IllegalStateException("KernelSU manager is not installed");
        c.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
    private LocalCustomization() {}
}

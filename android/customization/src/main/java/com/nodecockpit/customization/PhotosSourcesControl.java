package com.nodecockpit.customization;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Build;
import android.os.Process;
import android.provider.Settings;

import org.json.JSONException;
import org.json.JSONObject;

/** Wirehelm owns Sources settings. Only counts and lifecycle state return from Photos. */
public final class PhotosSourcesControl {
    static final String PHOTOS = "com.google.android.apps.photos";
    static final Uri URI = Uri.parse("content://com.example.remote_control.photos.sources");
    static final String[] RULES = {"messengerNames", "facebookNames", "whatsappNames"};
    static final String[] FOLDERS = {"cameraFolder", "whatsappFolder", "videosFolder"};

    record Config(boolean enabled, String development, boolean messengerNames, boolean facebookNames,
                  boolean whatsappNames, String cameraFolder, String whatsappFolder, String videosFolder) {
        static Config from(Bundle bundle) {
            return new Config(bundle.getBoolean("enabled", true), bundle.getString("development", "existing"),
                    bundle.getBoolean(RULES[0], true), bundle.getBoolean(RULES[1], true), bundle.getBoolean(RULES[2], true),
                    bundle.getString(FOLDERS[0], ""), bundle.getString(FOLDERS[1], ""), bundle.getString(FOLDERS[2], ""));
        }
    }

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("photos_sources_control", Context.MODE_PRIVATE);
    }

    static Bundle settings(Context context) {
        SharedPreferences preferences = prefs(context);
        Bundle settings = new Bundle();
        settings.putBoolean("enabled", preferences.getBoolean("enabled", true));
        settings.putString("development", preferences.getString("development", "existing"));
        for (String rule : RULES) settings.putBoolean(rule, preferences.getBoolean(rule, true));
        for (String folder : FOLDERS) settings.putString(folder, preferences.getString(folder, ""));
        return settings;
    }

    public static JSONObject status(Context context) throws JSONException {
        Bundle settings = settings(context);
        JSONObject result = new JSONObject();
        for (String key : settings.keySet()) result.put(key, settings.get(key));
        PackageInfo photos = packageInfo(context, PHOTOS);
        long version = versionCode(photos);
        SharedPreferences p = prefs(context);
        PackageInfo wirehelm = packageInfo(context, context.getPackageName());
        boolean current = isCurrent(p, photos, wirehelm, boot(context));
        result.put("photosVersion", photos == null ? "" : photos.versionName)
                .put("supported", version == CloudCameraOrigin.PHOTOS_VERSION_CODE)
                .put("scope", LocalCustomization.photosScope())
                .put("reportedAt", current ? p.getLong("reportedAt", 0) : 0)
                .put("backgroundReady", current && p.getBoolean("backgroundReady", false))
                .put("downloadState", current ? p.getString("downloadState", "unknown") : "unknown");
        for (String key : new String[]{"done", "skipped", "total"}) {
            result.put(key, current ? p.getInt(key, 0) : 0);
        }
        return result;
    }

    public static JSONObject save(Context context, JSONObject values) throws JSONException {
        String development = values.getString("development");
        if (!development.equals("existing") && !development.equals("on") && !development.equals("off")) {
            throw new IllegalArgumentException("Invalid Development setting");
        }
        SharedPreferences.Editor edit = prefs(context).edit()
                .putBoolean("enabled", values.getBoolean("enabled")).putString("development", development);
        for (String rule : RULES) edit.putBoolean(rule, values.getBoolean(rule));
        for (String folder : FOLDERS) edit.putString(folder, folderPath(values.getString(folder)));
        if (!edit.commit()) throw new IllegalStateException("Could not save Photos Sources settings");
        return status(context);
    }

    static String folderPath(String text) {
        String path = text.trim();
        if (path.isEmpty()) return "";
        if (path.length() > 240 || path.startsWith("/") || path.contains("\\")
                || path.chars().anyMatch(Character::isISOControl)) {
            throw new IllegalArgumentException("Enter a folder relative to internal storage, such as DCIM/Camera");
        }
        if (path.endsWith("/")) path = path.substring(0, path.length() - 1);
        for (String part : path.split("/", -1)) {
            if (part.isBlank() || part.startsWith(".")) throw new IllegalArgumentException("Invalid device folder");
        }
        return path + "/";
    }

    static synchronized void report(Context context, Bundle report) {
        PackageInfo photos = packageInfo(context, PHOTOS);
        PackageInfo wirehelm = packageInfo(context, context.getPackageName());
        if (photos == null || wirehelm == null || versionCode(photos) != CloudCameraOrigin.PHOTOS_VERSION_CODE) return;
        String state = report.getString("downloadState", "unknown");
        SharedPreferences p = prefs(context);
        int boot = boot(context);
        SharedPreferences.Editor edit = p.edit()
                .putLong("photosUpdate", photos.lastUpdateTime).putLong("wirehelmUpdate", wirehelm.lastUpdateTime)
                .putInt("boot", boot).putLong("reportedAt", System.currentTimeMillis())
                .putBoolean("backgroundReady", report.getBoolean("backgroundReady"));
        if (!isCurrent(p, photos, wirehelm, boot)) {
            edit.remove("downloadState").remove("total").remove("done").remove("skipped");
        }
        if (state.equals("waiting") || state.equals("running") || state.equals("paused") || state.equals("complete")) {
            int total = Math.max(0, Math.min(1_000_000, report.getInt("total")));
            int done = Math.max(0, Math.min(total, report.getInt("done")));
            int skipped = Math.max(0, Math.min(total - done, report.getInt("skipped")));
            edit.putString("downloadState", state).putInt("total", total).putInt("done", done).putInt("skipped", skipped);
        }
        edit.apply();
    }

    private static boolean isCurrent(SharedPreferences p, PackageInfo photos, PackageInfo wirehelm, int boot) {
        return photos != null && wirehelm != null
                && p.getLong("photosUpdate", -1) == photos.lastUpdateTime
                && p.getLong("wirehelmUpdate", -1) == wirehelm.lastUpdateTime
                && p.getInt("boot", -2) == boot;
    }

    static boolean isPhotos(Context context, int uid, String callingPackage) {
        PackageInfo info = packageInfo(context, PHOTOS);
        return PHOTOS.equals(callingPackage) && info != null && info.applicationInfo != null
                && info.applicationInfo.uid == uid && uid != Process.myUid();
    }

    private static PackageInfo packageInfo(Context context, String name) {
        try {
            return context.getPackageManager().getPackageInfo(name, 0);
        } catch (PackageManager.NameNotFoundException missing) {
            return null;
        }
    }

    private static int boot(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT, -1);
    }

    private static long versionCode(PackageInfo info) {
        if (info == null) return 0;
        return Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
    }
}

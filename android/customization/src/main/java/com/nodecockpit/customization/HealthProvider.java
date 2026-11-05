package com.nodecockpit.customization;
import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
/** Bounded diagnostics only; no configuration or root operations are exported. */
public final class HealthProvider extends ContentProvider {
    @Override public boolean onCreate() {
        LocalCustomization.initialize(getContext());
        return true;
    }
    @Override public Bundle call(String method, String arg, Bundle extras) {
        try {
            int expected = getContext().getPackageManager().getApplicationInfo("com.android.systemui", 0).uid;
            if (Binder.getCallingUid() != expected || extras == null) throw new SecurityException("SystemUI only");
            if ("wakeConfiguration".equals(method)) { LocalCustomization.refreshWakeSafety(); Bundle response=new Bundle(); response.putBundle("configuration",LocalCustomization.hookConfigurationBundle()); return response; }
            if ("configuration".equals(method)) { Bundle response=new Bundle(); response.putBundle("configuration",LocalCustomization.hookConfigurationBundle()); return response; }
            if ("edgeSearchPlacement".equals(method)) return LocalCustomization.applyEdgeSearchPlacement(extras.getDouble("x",-1),extras.getDouble("y",-1));
            if ("edgePlacement".equals(method)) return LocalCustomization.applyEdgePlacement(extras.getInt("position",-1),extras.getString("side",""));
            if ("edgeApps".equals(method)) return LocalCustomization.applyEdgeApps(extras.getString("apps",""),extras.getString("names","{}"));
            if (!"report".equals(method)) throw new SecurityException("Unsupported SystemUI operation");
            String state = extras.getString("state", "unknown");
            if (!java.util.Arrays.asList("loaded", "active", "disabled", "unsupported", "error", "waitingForStatusBar").contains(state)) throw new IllegalArgumentException("Invalid diagnostic state");
            String error = extras.getString("error", ""); if (error == null) error = ""; if (error.length() > 300) error = error.substring(0, 300);
            android.content.SharedPreferences p = LocalCustomization.store(getContext());
            LocalCustomization.refreshSafetyNowIfNeeded();
            LocalCustomization.refreshSafetyIfNeeded();
            long now=System.currentTimeMillis(), elapsed=SystemClock.elapsedRealtime(), revision=extras.getLong("revision",-1);
            int boot=android.provider.Settings.Global.getInt(getContext().getContentResolver(),android.provider.Settings.Global.BOOT_COUNT,-1);
            if ("error".equals(state) && !error.equals(p.getString("hookError",""))) LocalCustomization.recordEvent(getContext(),"hookError",error);
            if ("error".equals(state) && revision==p.getLong("revision",0)) LocalCustomization.emergency(getContext(),"Hook disabled itself: "+error);
            org.json.JSONObject metrics=new org.json.JSONObject();
            String reason=extras.getString("visibilityReason","unknown");
            if (!java.util.Arrays.asList("showing","idle","disabled","quarantined","safetyCheckOverdue","screenOff","detached","statusBarHidden","statusBarCrowded","waitingForStatusBar","unknown").contains(reason)) reason="unknown";
            metrics.put("visibilityReason",reason);
            for (String key:new String[]{"attached","visible","textClipped","interactive","wakePending"}) metrics.put(key,extras.getBoolean(key,false));
            for (String key:new String[]{"sampleAgeMs","downloadBps","uploadBps"}) metrics.put(key,Math.max(-1,Math.min(1000000000000000L,extras.getLong(key,-1))));
            for (String key:new String[]{"attachments","detachments","counterResets","preferenceUpdates","recoveryScans","wakeRecoveries","deliveryFailures","settingsCallbacks","safetyOnlyCallbacks","healthCallbacks","headerHooks","headerCallers","textHooks","optionalTextFailures","edgeFailures","placementRequestedLeft","placementActualLeft","placementBlocks","placementAdjustments"}) metrics.put(key,Math.max(0,Math.min(1000000000,extras.getInt(key,0))));
            String ring=extras.getString("cameraRingDiagnostics","");if(ring!=null&&!ring.isEmpty())metrics.put("cameraRing",ring.substring(0,Math.min(1000,ring.length())));
            String undo=extras.getString("notificationUndoDiagnostics","");if(undo!=null&&!undo.isEmpty())metrics.put("notificationUndo",undo.substring(0,Math.min(1000,undo.length())));
            String edgeError=extras.getString("edgeError","");
            if (edgeError!=null&&!edgeError.isEmpty()) metrics.put("edgeError",edgeError.length()>300?edgeError.substring(0,300):edgeError);
            String edgeDiagnostics=extras.getString("edgeDiagnostics","");
            if (edgeDiagnostics!=null&&!edgeDiagnostics.isEmpty()) metrics.put("edgePanel",edgeDiagnostics.length()>1200?edgeDiagnostics.substring(0,1200):edgeDiagnostics);
            String version=extras.getString("version","1");
            if (version==null || !version.matches("[0-9]{1,4}")) version="unknown";
            if (p.getInt("hookPid",0)!=Binder.getCallingPid()) LocalCustomization.recordEvent(getContext(),"hookProcess","SystemUI hook connected, PID "+Binder.getCallingPid());
            android.content.SharedPreferences.Editor edit = p.edit().putLong("hookAt", now).putString("hookState", state)
                .putString("hookError", error).putLong("hookRevision", revision).putInt("hookPid", Binder.getCallingPid())
                .putString("hookVersion",version).putInt("hookBoot",boot).putLong("hookElapsed",elapsed).putString("hookMetrics",metrics.toString());
            if ("active".equals(state) && revision == p.getLong("revision", 0)) {
                long since = p.getLong("stableSince", now);
                if (p.getLong("stableRevision",-1)!=revision || p.getInt("hookPid",0)!=Binder.getCallingPid() || p.getInt("hookBoot",-1)!=boot || elapsed-p.getLong("hookElapsed",0)>15000) since=now;
                edit.putLong("stableSince", since).putLong("stableRevision", revision);
                if (now - since > 60000) edit.putString("lastGood", LocalCustomization.config(getContext()).toString());
            } else edit.remove("stableSince");
            edit.apply();
            Bundle result = new Bundle();
            result.putBoolean("emergencyDisabled", p.getBoolean("emergency", false));
            result.putBundle("configuration", LocalCustomization.hookConfigurationBundle());
            return result;
        } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new IllegalStateException(e); }
    }
    @Override public Cursor query(Uri u,String[] p,String s,String[] a,String o) { throw new UnsupportedOperationException(); }
    @Override public String getType(Uri u) { return null; }
    @Override public Uri insert(Uri u,ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u,String s,String[] a) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u,ContentValues v,String s,String[] a) { throw new UnsupportedOperationException(); }
}

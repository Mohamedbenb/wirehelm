package com.example.remote_control

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.AtomicFile
import com.nodecockpit.customization.LocalCustomization
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

internal class DeviceSnapshot(private val context: Context) {
    private val baseline = AtomicFile(File(context.noBackupFilesDir, "device-baseline-v1.json"))

    fun readBaseline(): JSONObject = try {
        JSONObject(baseline.readFully().toString(Charsets.UTF_8))
    } catch (_: FileNotFoundException) {
        JSONObject()
    }

    fun saveBaseline(includeModules: Boolean): JSONObject {
        val snapshot = capture(includeModules)
        val output = baseline.startWrite()
        try {
            output.write(snapshot.toString().toByteArray(Charsets.UTF_8))
            baseline.finishWrite(output)
        } catch (e: Exception) {
            baseline.failWrite(output)
            throw e
        }
        return snapshot
    }

    fun capture(includeModules: Boolean): JSONObject {
        val capturedAt = System.currentTimeMillis()
        val sections = JSONObject().put("Android", JSONObject()
            .put("Android version", Build.VERSION.RELEASE)
            .put("Build", Build.ID)
            .put("Build fingerprint", Build.FINGERPRINT)
            .put("Security patch", Build.VERSION.SECURITY_PATCH))
            .put("Apps", apps())
        val unavailable = JSONObject()
        val hook = LocalCustomization.lastHookReport()
        val version = hook.optString("version")
        if (hook.optBoolean("fresh") && version.isNotBlank()) {
            sections.put("SystemUI hook", JSONObject()
                .put("Wirehelm hook version", version)
                .put("Reported state", hook.getString("state")))
        } else {
            unavailable.put("SystemUI hook", "No recent SystemUI hook report was available.")
        }
        if (includeModules) {
            runCatching { modules() }
                .onSuccess { sections.put("Root modules", it) }
                .onFailure {
                    unavailable.put("Root modules", "Module inventory unavailable. Check Wirehelm’s root authorization.")
                }
        } else {
            unavailable.put("Root modules", "Root module inventory was skipped.")
        }
        return JSONObject().put("capturedAt", capturedAt)
            .put("sections", sections).put("unavailable", unavailable)
    }

    @Suppress("DEPRECATION")
    private fun apps(): JSONObject {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val names = pm.queryIntentActivities(launcher, 0).mapNotNull { it.activityInfo?.packageName }.toSet() +
            context.packageName
        val apps = JSONObject()
        for (name in names.sorted()) {
            val info = try {
                pm.getPackageInfo(name, 0)
            } catch (_: PackageManager.NameNotFoundException) {
                continue
            }
            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
            val version = info.versionName?.takeIf { it.isNotBlank() }
            apps.put(name, if (version == null) "Build $code" else "$version (build $code)")
        }
        return apps
    }

    private fun modules(): JSONObject {
        val lines = LocalCustomization.readRootModuleInventory().lines()
        check(lines.lastOrNull() == "inventory complete") { "Incomplete root module inventory" }
        val modules = JSONObject()
        for (line in lines.dropLast(1)) {
            val parts = line.split('\t', limit = 4)
            if (parts.size != 4 || parts[0] != "module") continue
            val version = parts[3].filterNot { it.isISOControl() }.trim().take(160)
            modules.put(parts[1], if (version.isEmpty()) parts[2] else "${parts[2]} · $version")
        }
        return modules
    }
}

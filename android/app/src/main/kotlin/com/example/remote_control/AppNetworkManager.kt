package com.example.remote_control

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import com.nodecockpit.customization.FeaturePolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal class AppNetworkBridge(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remote_control/app_network")
    private val manager = AppNetworkManager(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            AppNetworkManager.executor.execute {
                try {
                    val value = when (call.method) {
                        "list" -> manager.list()
                        "allowTemporarily" -> {
                            manager.allowTemporarily(requireNotNull(call.argument<String>("package")))
                            manager.list()
                        }
                        "alarmSettings" -> {
                            check(Build.VERSION.SDK_INT >= 31)
                            context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                android.net.Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            true
                        }
                        "restore" -> {
                            manager.restore()
                            manager.list()
                        }
                        "setBlocked" -> {
                            manager.setBlocked(
                                requireNotNull(call.argument<String>("package")),
                                requireNotNull(call.argument<Boolean>("blocked")),
                            )
                            manager.list()
                        }
                        else -> null
                    }
                    main.post { if (value == null) result.notImplemented() else result.success(value) }
                } catch (e: Exception) {
                    main.post { result.error("APP_NETWORK", e.message ?: "Network rule failed", null) }
                }
            }
        }
    }

    fun detach() = channel.setMethodCallHandler(null)
}

/** Reconciles saved rules and re-arms the next temporary exception when needed. */
class AppNetworkReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = AppNetworkManager(context.applicationContext)
        if (!manager.hasRules()) return
        if (intent.action == Intent.ACTION_PACKAGE_FULLY_REMOVED &&
            !manager.hasRule(intent.data?.schemeSpecificPart)) return
        val pending = goAsync()
        AppNetworkManager.executor.execute {
            try {
                manager.restore()
            } catch (e: Exception) {
                android.util.Log.w("WirehelmNetwork", "Could not reconcile saved network rules", e)
            } finally {
                pending.finish()
            }
        }
    }
}

@Suppress("DEPRECATION")
internal class AppNetworkManager(private val context: Context) {
    private data class Rule(
        val uid: Int, val installedAt: Long, val allowPending: Boolean = false,
        val allowUntil: Long = 0, val boot: Int = -1,
    ) {
        fun matches(info: PackageInfo): Boolean =
            info.applicationInfo?.uid == uid && info.firstInstallTime == installedAt
    }
    private data class Firewall(val enabled: Boolean, val denied: Set<Int>)

    private val pm = context.packageManager
    private val prefs = context.getSharedPreferences("app_network", Context.MODE_PRIVATE)
    private val launchIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private fun boot() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun canSchedule() = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()

    private fun scheduleExpiry(owned: Map<String, Rule>) {
        val alarm = PendingIntent.getBroadcast(context, 872, Intent(context, AppNetworkReceiver::class.java)
            .setAction("com.example.remote_control.APP_NETWORK_EXPIRY"), PendingIntent.FLAG_IMMUTABLE)
        val currentBoot = boot()
        val deadline = owned.values.filter { it.allowUntil > 0 && it.boot == currentBoot }
            .minOfOrNull { it.allowUntil }
        if (deadline == null || !canSchedule()) alarms.cancel(alarm)
        else alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, deadline, alarm)
    }

    fun hasRules(): Boolean = prefs.contains("rules")
    fun hasRule(name: String?): Boolean = name != null && name in rules()

    private fun checkSupported() {
        check(android.os.Process.myUid() in 10000..19999 &&
            FeaturePolicy.supported(Build.VERSION.SDK_INT, Build.FINGERPRINT)) {
            "App network controls require the supported Pixel firmware and the owner profile."
        }
    }

    private fun eligible(info: PackageInfo): Boolean {
        val app = info.applicationInfo ?: return false
        return app.uid in 10000..19999 &&
            app.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0 &&
            info.sharedUserId == null && info.packageName != context.packageName &&
            info.packageName !in protectedPackages &&
            info.requestedPermissions?.contains(android.Manifest.permission.INTERNET) == true
    }

    private fun rules(): MutableMap<String, Rule> {
        val json = JSONObject(prefs.getString("rules", "{}") ?: "{}")
        return json.keys().asSequence().associateWith { name ->
            val entry = json.getJSONObject(name)
            Rule(entry.getInt("uid"), entry.getLong("installedAt"), entry.optBoolean("allowPending"),
                entry.optLong("allowUntil"), entry.optInt("boot", -1))
        }.toMutableMap()
    }

    private fun save(rules: Map<String, Rule>) {
        val editor = prefs.edit()
        if (rules.isEmpty()) editor.remove("rules") else {
            val json = JSONObject()
            rules.forEach { (name, rule) ->
                json.put(name, JSONObject().put("uid", rule.uid).put("installedAt", rule.installedAt)
                    .put("allowPending", rule.allowPending).put("allowUntil", rule.allowUntil).put("boot", rule.boot))
            }
            editor.putString("rules", json.toString())
        }
        check(editor.commit()) { "Could not save the network rules." }
    }

    private fun root(command: String): String {
        val process = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
        val deadline = watchdog.schedule({ process.destroyForcibly() }, 8, TimeUnit.SECONDS)
        try {
            val output = process.inputStream.bufferedReader().use { reader ->
                val buffer = CharArray(4096)
                val text = StringBuilder()
                while (true) {
                    val count = reader.read(buffer)
                    if (count < 0) break
                    check(text.length + count <= 2 * 1024 * 1024) { "Firewall output exceeded its size limit." }
                    text.append(buffer, 0, count)
                }
                text.toString().trim()
            }
            check(process.waitFor() == 0) {
                "Root firewall command failed. Check Wirehelm's root authorization."
            }
            return output
        } finally {
            deadline.cancel(false)
            process.destroy()
        }
    }

    private fun snapshot(): Firewall {
        val chain = root("/system/bin/cmd connectivity get-chain3-enabled")
        check(chain == "chain:enabled" || chain == "chain:disabled") {
            "Android's app firewall is unavailable."
        }
        val denied = NativeFirewallReadback.deniedUids(
            root("/system/bin/dumpsys -t 5 connectivity trafficcontroller"),
        )
        return Firewall(chain == "chain:enabled", denied)
    }

    private fun write(uid: Int, blocked: Boolean) {
        check(uid in 10000..19999)
        val apk = context.applicationInfo.sourceDir.replace("'", "'\\''")
        val action = if (blocked) "block" else "allow"
        root("CLASSPATH='$apk' /system/bin/app_process /system/bin com.example.remote_control.NetworkFirewallWorker $action $uid")
    }

    private fun allowActivation(firewall: Firewall, owned: Map<String, Rule>) {
        check(firewall.enabled || firewall.denied.all { uid -> owned.values.any { it.uid == uid } }) {
            "Another tool has rules in Android's disabled firewall chain."
        }
    }

    private fun enableChain() {
        root("/system/bin/cmd connectivity set-chain3-enabled true")
    }

    fun list(): List<Map<String, Any>> {
        checkSupported()
        val now = SystemClock.elapsedRealtime()
        val boot = boot()
        val canSchedule = canSchedule()
        var owned = rules()
        if (owned.values.any { it.allowUntil > 0 && (it.allowUntil <= now || it.boot != boot || !canSchedule) }) {
            restore()
            owned = rules()
        }
        val firewall = snapshot()
        return pm.queryIntentActivities(launchIntent, 0).mapNotNull { it.activityInfo?.packageName }
            .distinct().mapNotNull { name ->
                val info = packageInfo(name) ?: return@mapNotNull null
                if (!eligible(info)) return@mapNotNull null
                val app = info.applicationInfo ?: return@mapNotNull null
                val current = owned[name]?.takeIf { it.matches(info) }
                val denied = app.uid in firewall.denied
                mapOf(
                    "name" to name,
                    "label" to pm.getApplicationLabel(app).toString(),
                    "saved" to (current != null && !current.allowPending),
                    "retry" to (current?.allowPending == true),
                    "blocked" to (firewall.enabled && denied),
                    "external" to (denied && current == null),
                    "temporarySeconds" to (if (!denied && current != null && current.allowUntil > now)
                        (current.allowUntil - now + 999) / 1000 else 0L),
                    "canSchedule" to canSchedule,
                )
            }.sortedBy { it["label"].toString().lowercase(java.util.Locale.ROOT) }
    }

    private fun packageInfo(name: String): PackageInfo? =
        try { pm.getPackageInfo(name, PackageManager.GET_PERMISSIONS) }
        catch (_: PackageManager.NameNotFoundException) { null }

    fun allowTemporarily(name: String) {
        checkSupported()
        check(canSchedule()) { "Allow exact alarms before creating a timed exception." }
        val boot = boot()
        check(boot >= 0) { "Could not verify this boot." }
        val info = packageInfo(name) ?: error("The app is no longer installed.")
        check(eligible(info)) { "This app cannot be managed." }
        val owned = rules()
        val rule = owned[name]?.takeIf { !it.allowPending && it.allowUntil == 0L && it.matches(info) }
            ?: error("An active Wirehelm block is required.")
        val before = snapshot()
        check(before.enabled && rule.uid in before.denied) { "The saved block is inactive." }
        owned[name] = rule.copy(allowUntil = SystemClock.elapsedRealtime() + 300_000L, boot = boot)
        save(owned)
        try {
            scheduleExpiry(owned)
            write(rule.uid, false)
            check(rule.uid !in snapshot().denied) { "Android did not confirm the temporary exception." }
        } catch (error: Exception) {
            owned[name] = rule
            save(owned)
            runCatching { restore() }.exceptionOrNull()?.let(error::addSuppressed)
            throw error
        }
    }

    fun setBlocked(name: String, blocked: Boolean) {
        checkSupported()
        val info = packageInfo(name) ?: error("The app is no longer installed.")
        check(eligible(info)) { "This app cannot be managed." }
        val rule = Rule(requireNotNull(info.applicationInfo).uid, info.firstInstallTime)
        val owned = rules()
        val firewall = snapshot()
        val current = owned[name]
        check(current == null || current.matches(info)) {
            "This app was reinstalled. Refresh after its old rule is reconciled."
        }
        check(rule.uid !in firewall.denied || current != null) {
            "This app's rule is managed outside Wirehelm."
        }
        if (blocked) {
            allowActivation(firewall, owned)
            owned[name] = rule
            save(owned)
            if (rule.uid !in firewall.denied) write(rule.uid, true)
            if (!firewall.enabled) {
                allowActivation(snapshot(), owned)
                enableChain()
            }
        } else if (current != null) {
            owned[name] = current.copy(allowPending = true)
            save(owned)
            if (rule.uid in firewall.denied) write(rule.uid, false)
        }
        val after = snapshot()
        check(if (blocked) after.enabled && rule.uid in after.denied else rule.uid !in after.denied) {
            "Android did not confirm the requested rule."
        }
        if (!blocked) {
            owned.remove(name)
            save(owned)
        }
        scheduleExpiry(owned)
    }

    fun restore() {
        if (!hasRules()) return
        checkSupported()
        val owned = rules()
        val before = snapshot()
        val stale = owned.filter { (name, rule) ->
            val info = packageInfo(name)
            rule.allowPending || info == null || !eligible(info) || !rule.matches(info)
        }
        stale.values.filter { it.uid in before.denied }.forEach { write(it.uid, false) }
        if (stale.isNotEmpty()) {
            val denied = snapshot().denied
            check(stale.values.none { it.uid in denied }) { "Could not clear an old app rule." }
            stale.keys.forEach { owned.remove(it) }
            save(owned)
        }
        val now = SystemClock.elapsedRealtime()
        val boot = boot()
        val canSchedule = canSchedule()
        val toBlock = owned.filterValues {
            it.allowUntil == 0L || it.boot != boot || it.allowUntil <= now || !canSchedule
        }
        if (toBlock.isEmpty()) {
            scheduleExpiry(owned)
            return
        }
        val firewall = snapshot()
        allowActivation(firewall, owned)
        toBlock.values.filter { it.uid !in firewall.denied }.forEach { write(it.uid, true) }
        if (!firewall.enabled) {
            allowActivation(snapshot(), owned)
            enableChain()
        }
        val after = snapshot()
        check(after.enabled && toBlock.values.all { it.uid in after.denied }) {
            "Could not verify the restored network rules."
        }
        if (toBlock.values.any { it.allowUntil > 0 }) {
            toBlock.forEach { (name, rule) -> owned[name] = rule.copy(allowUntil = 0, boot = -1) }
            save(owned)
        }
        scheduleExpiry(owned)
    }

    companion object {
        val executor = Executors.newSingleThreadExecutor()
        private val watchdog = Executors.newSingleThreadScheduledExecutor()
        private val protectedPackages = setOf("me.weishu.kernelsu", "org.matrix.vector.manager", "org.lsposed.manager")
    }
}

internal object NativeFirewallReadback {
    private val whitespace = Regex("\\s+")

    fun deniedUids(output: String): Set<Int> {
        val denied = mutableSetOf<Int>()
        var inOwnerMap = false
        for (raw in output.lineSequence()) {
            val line = raw.trim()
            if (!inOwnerMap) {
                inOwnerMap = line == "sUidOwnerMap:"
                continue
            }
            if (line == "sIngressDiscardMap:") return denied
            if (line.isEmpty()) continue
            val fields = line.split(whitespace)
            val uid = fields.first().toIntOrNull()
            check(uid != null && uid >= 0 && fields.size > 1) {
                "Android returned an unreadable firewall UID entry."
            }
            if ("OEM_DENY_3_MATCH" in fields) denied.add(uid)
        }
        error(if (inOwnerMap) "Android returned an incomplete firewall UID table."
            else "Android did not expose its firewall UID table.")
    }
}

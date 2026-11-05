package com.example.remote_control

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.remotecontrol.tsnet.tsnetbridge.Node
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit

/** Explicit, temporary debugging session. No VPN, framework, boot or authentication changes. */
class AdbRelaySession(context: Context, private val node: Node, private val worker: Executor) {
    private val appContext = context.applicationContext
    private val saved = context.applicationContext.getSharedPreferences("temporary_adb_relay", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val listenAddress = "tcp:127.0.0.1:37127"
    private val expiry = Runnable { worker.execute { runCatching { expireIfDue() } } }
    private var cleanupError: String? = null
    private var mode = ""
    private var lastProbeError = ""

    @Synchronized fun start(pc: String, allowTemporaryRoot: Boolean): String {
        require(pc.isNotBlank()) { "Select the permitted PC first" }
        AdbRelayService.start(appContext)
        try { stopInternal() } catch (error: Exception) { AdbRelayService.stop(appContext); throw error }
        saved.edit().putString("lastAttempt", JSONObject().put("at", System.currentTimeMillis())
            .put("phase", "starting").put("adapter", "legacy-port-v2").toString()).commit()
        try {
            val localPort: Int
            if (allowTemporaryRoot) {
                check(listeners().isEmpty()) { "The temporary local port is already in use" }
                check(root("getprop ro.adb.secure").trim() == "1") { "Authenticated ADB is required" }
                root("command -v iptables >/dev/null && command -v ip6tables >/dev/null")
                val previous = root("getprop service.adb.listen_addrs").trim()
                val previousPort = root("getprop service.adb.tcp.port").trim()
                val running = root("getprop init.svc.adbd").trim() == "running"
                val tag = "node-adb-" + UUID.randomUUID().toString().take(8)
                check(saved.edit().putString("previousListen", previous).putString("previousPort", previousPort)
                    .putString("appliedListen", "").putString("previousPid", root("pidof adbd || true").trim())
                    .putBoolean("wasRunning", running).putString("guardTag", tag)
                    .putBoolean("owned", true).commit()) { "Cannot save ADB restoration state" }
                // Some adbd builds ignore listen_addrs. Fence the private port
                // before enabling the legacy TCP setting; never open it on LAN.
                for (tool in listOf("iptables", "ip6tables")) {
                    root("$tool -w 3 -I INPUT 1 ${guardRule(tag)}")
                    root("$tool -w 3 -C INPUT ${guardRule(tag)}")
                }
                // An address override has precedence over tcp.port. Select the
                // legacy path by clearing it, behind both verified local fences.
                root("setprop service.adb.listen_addrs '' && setprop service.adb.tcp.port 37127 && setprop ctl.restart adbd")
                check(root("getprop service.adb.listen_addrs").trim().isEmpty() &&
                    root("getprop service.adb.tcp.port").trim() == "37127") { "Temporary ADB properties were not applied" }
                // Init restart is asynchronous; a two-second socket-only check
                // cannot distinguish delayed startup from an app-domain denial.
                val deadline = android.os.SystemClock.elapsedRealtime() + 12000
                var ready = listening(37127)
                while (!ready && android.os.SystemClock.elapsedRealtime() < deadline) {
                    Thread.sleep(150)
                    ready = listening(37127)
                }
                val diagnostics = startupDiagnostics(ready)
                saved.edit().putString("lastAttempt", diagnostics.toString()).commit()
                check(ready) {
                    "Local ADB could not be reached. adbd=${diagnostics.optString("service")}; " +
                    "listener=${diagnostics.optString("listener")}; app=${diagnostics.optString("appSocket")}. " +
                    "Open Connection diagnostics below for details."
                }
                // Recheck both fences after daemon startup before tailnet access.
                for (tool in listOf("iptables", "ip6tables")) root("$tool -w 3 -C INPUT ${guardRule(tag)}")
                localPort = 37127
                mode = "Temporary protected local ADB"
            } else {
                var port = property("service.adb.tls.port").toIntOrNull() ?: 0
                if (port !in 1..65535) port = runCatching { root("getprop service.adb.tls.port").trim().toInt() }.getOrDefault(0)
                check(port in 1..65535 && listening(port)) { "No existing wireless ADB listener. Enable wireless debugging on Wi-Fi, or select temporary root mode for mobile data." }
                localPort = port
                mode = "Existing wireless ADB"
            }
            node.startDebugRelayWithDuration(localPort.toLong(), pc, saved.getInt("durationMinutes", 30).toLong())
            scheduleExpiry()
            AdbRelayService.update(appContext, JSONObject(node.debugRelayStatus()).optLong("expiresAt"))
            return status()
        } catch (error: Exception) {
            val details = runCatching { JSONObject(saved.getString("lastAttempt", "{}") ?: "{}") }.getOrDefault(JSONObject())
            details.put("phase", "failed").put("error", error.message).put("adapter", "legacy-port-v2")
            saved.edit().putString("lastAttempt", details.toString()).commit()
            runCatching { stop() }.onFailure { cleanupError = it.message }
            throw error
        }
    }

    @Synchronized fun setDuration(minutes: Long): String {
        require(minutes in 5..1440) { "Session duration must be 5..1440 minutes" }
        if (JSONObject(node.debugRelayStatus()).optBoolean("enabled")) {
            node.setDebugRelayDuration(minutes)
            scheduleExpiry()
            AdbRelayService.update(appContext, JSONObject(node.debugRelayStatus()).optLong("expiresAt"))
        }
        check(saved.edit().putInt("durationMinutes", minutes.toInt()).commit()) { "Cannot save session duration" }
        return status()
    }

    @Synchronized private fun expireIfDue() {
        val current = JSONObject(node.debugRelayStatus())
        if (current.optBoolean("enabled") && current.optLong("expiresAt") > System.currentTimeMillis()) scheduleExpiry()
        else stop()
    }

    private fun scheduleExpiry() {
        main.removeCallbacks(expiry)
        val deadline = JSONObject(node.debugRelayStatus()).optLong("expiresAt")
        main.postDelayed(expiry, (deadline - System.currentTimeMillis()).coerceAtLeast(0))
    }

    @Synchronized fun stop() {
        try { stopInternal() } finally { AdbRelayService.stop(appContext) }
    }

    private fun stopInternal() {
        main.removeCallbacks(expiry)
        node.stopDebugRelay()
        if (saved.getBoolean("owned", false)) {
            try {
                // Restore only properties still owned by this session. Keep
                // port guards until the temporary listener is confirmed gone.
                var changed = false
                if (root("getprop service.adb.listen_addrs").trim() == saved.getString("appliedListen", listenAddress)) {
                    root("setprop service.adb.listen_addrs ${quote(saved.getString("previousListen", "") ?: "")}")
                    changed = true
                }
                if (saved.contains("previousPort") && root("getprop service.adb.tcp.port").trim() == "37127") {
                    root("setprop service.adb.tcp.port ${quote(saved.getString("previousPort", "") ?: "")}")
                    changed = true
                }
                if (changed) {
                    val action = if (saved.getBoolean("wasRunning", false)) "restart" else "stop"
                    root("setprop ctl.$action adbd")
                }
                val tag = saved.getString("guardTag", null)
                if (tag != null) {
                    val deadline = android.os.SystemClock.elapsedRealtime() + 12000
                    while (listeners().isNotEmpty() && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(200)
                    check(listeners().isEmpty()) { "Temporary ADB listener is still active; local-only guards retained. Retry Stop / restore." }
                    for (tool in listOf("iptables", "ip6tables")) {
                        // Missing rules after reboot are normal. A failed delete
                        // remains an error, preserving retryable cleanup state.
                        val rule = guardRule(tag)
                        root("$tool -w 3 -C INPUT $rule 2>/dev/null; guard_code=\$?; if [ \"\$guard_code\" -eq 0 ]; then $tool -w 3 -D INPUT $rule; elif [ \"\$guard_code\" -ne 1 ]; then exit \"\$guard_code\"; fi")
                    }
                }
                saved.edit().remove("owned").remove("previousListen").remove("previousPort")
                    .remove("wasRunning").remove("guardTag").remove("appliedListen").remove("previousPid").commit()
                cleanupError = null
            } catch (error: Exception) { cleanupError = error.message; throw error }
        }
        mode = ""
    }

    @Synchronized fun status(): String {
        val result = JSONObject(node.debugRelayStatus())
        if (!result.optBoolean("enabled") && saved.getBoolean("owned", false)) {
            runCatching { stop() }.onFailure { cleanupError = it.message }
        }
        result.put("backgroundProtected", AdbRelayService.isRunning)
        result.put("mode", mode).put("temporaryRoot", saved.getBoolean("owned", false))
            .put("preferredDurationMinutes", saved.getInt("durationMinutes", 30))
        cleanupError?.let { result.put("cleanupError", it) }
        saved.getString("lastAttempt", null)?.let { runCatching { result.put("diagnostics", JSONObject(it)) } }
        return result.toString()
    }

    private fun listening(port: Int): Boolean = try {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 250) }
        lastProbeError = "connected"
        true
    } catch (error: Exception) {
        lastProbeError = "${error.javaClass.simpleName}: ${error.message}".take(240)
        false
    }

    private fun startupDiagnostics(ready: Boolean): JSONObject {
        val appSocket = lastProbeError
        fun read(command: String) = runCatching { root(command).trim().take(300) }.getOrElse { "unavailable: ${it.message}" }
        // Only report the requested port; do not expose unrelated app connections.
        val bound = runCatching { listeners().joinToString().ifEmpty { "not found" } }
            .getOrElse { "unavailable: ${it.message}" }
        val tag = saved.getString("guardTag", null)
        val pid = read("pidof adbd").split(Regex("\\s+")).firstOrNull().orEmpty()
        val daemon = JSONObject()
        if (pid.matches(Regex("[0-9]+"))) {
            daemon.put("executable", read("readlink /proc/$pid/exe"))
            daemon.put("addressOverrideSupported", read("grep -a -o 'service.adb.listen_addrs' /proc/$pid/exe"))
            daemon.put("portFromDaemonMountNamespace", read("nsenter -t $pid -m -- /system/bin/getprop service.adb.tcp.port"))
            daemon.put("startupLog", runCatching {
                root("logcat --pid=$pid -d -v brief -t 120").lineSequence()
                    .filter { it.contains(Regex("listen|socket|bind|started|port|denied|error|fatal", RegexOption.IGNORE_CASE)) }
                    .toList().takeLast(16).joinToString("\n").take(2500).ifEmpty { "No relevant entries" }
            }.getOrElse { "unavailable: ${it.message}" })
        }
        return JSONObject().put("at", System.currentTimeMillis()).put("adapter", "legacy-port-v2")
            .put("phase", if (ready) "listener-ready" else "listener-unavailable").put("appReachedListener", ready)
            .put("service", read("getprop init.svc.adbd")).put("pid", pid)
            .put("previousPid", saved.getString("previousPid", "")).put("daemon", daemon)
            .put("tlsPortProperty", read("getprop service.adb.tls.port"))
            .put("listenProperty", read("getprop service.adb.listen_addrs"))
            .put("listener", bound).put("tcpPortProperty", read("getprop service.adb.tcp.port"))
            .put("ipv4Guard", tag?.let { runCatching { root("iptables -w 3 -C INPUT ${guardRule(it)}"); true }.getOrDefault(false) } ?: false)
            .put("ipv6Guard", tag?.let { runCatching { root("ip6tables -w 3 -C INPUT ${guardRule(it)}"); true }.getOrDefault(false) } ?: false)
            .put("appSocket", appSocket).put("usbDebugEnabled", read("settings get global adb_enabled"))
            .put("wifiDebugEnabled", read("settings get global adb_wifi_enabled"))
    }

    private fun guardRule(tag: String): String {
        require(tag.matches(Regex("node-adb-[0-9a-f-]{8}"))) { "Invalid saved guard ownership" }
        return "! -i lo -p tcp --dport 37127 -m comment --comment $tag -j DROP"
    }

    private fun listeners(): List<String> = root("cat /proc/net/tcp /proc/net/tcp6")
        .lineSequence().map { it.trim().split(Regex("\\s+")) }
        .filter { it.size > 3 && it[1].endsWith(":9107", true) && it[3] == "0A" }
        .map { it[1] }.toList()

    private fun property(key: String): String = runCatching { execute(listOf("/system/bin/getprop", key)) }.getOrDefault("").trim()
    private fun root(command: String): String = execute(listOf("su", "-c", command))
    private fun execute(command: List<String>): String {
        val process = ProcessBuilder(command).redirectErrorStream(true).start()
        val bytes = ByteArrayOutputStream()
        var overflow = false
        val reader = Thread {
            runCatching { process.inputStream.use { input ->
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer); if (count < 0) break
                    if (bytes.size() + count <= 1024 * 1024) bytes.write(buffer, 0, count) else overflow = true
                }
            } }
        }.apply { isDaemon = true; start() }
        if (!process.waitFor(15, TimeUnit.SECONDS)) { process.destroyForcibly(); reader.join(1000); error("Root/debugging request timed out") }
        reader.join(1500)
        check(!reader.isAlive && !overflow) { "Root/debugging diagnostic output incomplete" }
        val output = bytes.toString("UTF-8")
        check(process.exitValue() == 0) { output.trim().ifEmpty { "Root/debugging request failed" } }
        return output
    }
    private fun quote(value: String): String = "'" + value.replace("'", "'\"'\"'") + "'"
}

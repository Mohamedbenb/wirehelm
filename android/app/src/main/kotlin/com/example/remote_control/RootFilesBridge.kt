package com.example.remote_control

import android.app.KeyguardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.example.remote_control.files.RootFilePolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RootFilesBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remote_control/root_files")
    private val executor = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var scope: String? = null
    private var scopeIdentity: String? = null
    private var advanced = false
    private var deadline = 0L
    private var generation = 0L
    @Volatile private var attached = true

    @Synchronized fun lock() { scope = null; scopeIdentity = null; advanced = false; deadline = 0; generation++ }
    @Synchronized private fun ticket(): Long = generation
    @Synchronized private fun access(expected: Long): String {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        check(attached && expected == generation && SystemClock.elapsedRealtime() < deadline && !keyguard.isDeviceLocked) {
            "Write access expired or was locked. Unlock the folder again."
        }
        return scope ?: error("Folder is read-only")
    }
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "lock") { lock(); result.success(null); return@setMethodCallHandler }
            val expected = ticket()
            executor.execute {
                try {
                    check(attached) { "Explorer closed" }
                    val args = JSONObject(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    val value = when (call.method) {
                        "backupFolder" -> JSONObject().put("path", backupFolder())
                        "unlock" -> {
                            val requestedAdvanced = args.optBoolean("advanced", false)
                            val value = run(JSONObject().put("op", "list").put("path", args.getString("path")))
                            check(value.getBoolean(if (requestedAdvanced) "advancedUnlockable" else "unlockable")) { "This location is write-protected" }
                            val canonical = value.getString("path")
                            RootFilePolicy.scope(RootFilePolicy.path(canonical), requestedAdvanced)
                            if (requestedAdvanced) RootFilePolicy.confirmation(RootFilePolicy.path(canonical), args.optString("confirmation"))
                            synchronized(this) {
                                check(expected == generation && attached && !context.getSystemService(KeyguardManager::class.java).isDeviceLocked) { "Explorer was locked" }
                                scope = canonical
                                advanced = requestedAdvanced
                                scopeIdentity = value.getString("scopeIdentity")
                                deadline = SystemClock.elapsedRealtime() + 300_000
                            }
                            JSONObject().put("scope", canonical).put("seconds", 300).put("advanced", requestedAdvanced)
                        }
                        "list", "read" -> run(args.put("op", call.method))
                        "mkdir", "rename", "copy", "trash", "save" -> {
                            val root = access(expected)
                            // Never accept a scope supplied by Flutter.
                            val identity = synchronized(this) { access(expected); scopeIdentity ?: error("Folder is locked") }
                            val advancedMode = synchronized(this) { access(expected); advanced }
                            if (RootFilePolicy.customizationPath(RootFilePolicy.path(args.getString("path"))) && call.method in listOf("save", "copy")) {
                                args.put("backupRoot", backupFolder()).put("backupUid", android.os.Process.myUid())
                            }
                            run(args.put("op", call.method).put("scope", root).put("scopeIdentity", identity).put("advanced", advancedMode), expected)
                        }
                        else -> error("Unsupported file operation")
                    }
                    main.post { if (attached) result.success(value.toString()) }
                } catch (e: Exception) {
                    main.post { if (attached) result.error("ROOT_FILES", e.message ?: "File operation failed", null) }
                }
            }
        }
    }
    private fun backupFolder(): String {
        val folder = java.io.File(context.noBackupFilesDir, "root-file-backups")
        check(folder.isDirectory || folder.mkdirs()) { "Cannot create private backup folder" }
        android.system.Os.chmod(folder.absolutePath, 448) // 0700
        return folder.canonicalPath
    }
    private fun quote(s: String) = "'" + s.replace("'", "'\\''") + "'"
    private fun run(request: JSONObject, writeTicket: Long? = null): JSONObject {
        if (writeTicket != null) access(writeTicket)
        // Only the installed APK path enters a shell. User paths and text travel as JSON on stdin.
        val command = "CLASSPATH=${quote(context.applicationInfo.sourceDir)} /system/bin/app_process /system/bin com.example.remote_control.files.RootFileWorker"
        val process = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
        val timeout = watchdog.schedule({ process.destroyForcibly() }, 20, TimeUnit.SECONDS)
        try {
            process.outputStream.use { it.write(request.toString().toByteArray(Charsets.UTF_8)) }
            val out = ByteArrayOutputStream()
            process.inputStream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    check(out.size() + n <= 2 * 1024 * 1024) { "Response exceeds the explorer limit" }
                    out.write(buffer, 0, n)
                }
            }
            check(process.waitFor() == 0) { "Root operation failed or timed out. Grant root access to Node Cockpit and retry." }
            val line = out.toString("UTF-8").lineSequence().lastOrNull { it.startsWith("{") }
                ?: error("Root helper unavailable. Grant root access to Node Cockpit and retry.")
            val value = JSONObject(line)
            if (value.has("error")) error(value.getString("error"))
            return value
        } finally { timeout.cancel(false); process.destroy() }
    }
    fun detach() {
        attached = false
        lock()
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        watchdog.shutdownNow()
    }
}

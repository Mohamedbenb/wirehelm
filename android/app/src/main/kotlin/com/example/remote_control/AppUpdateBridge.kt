package com.example.remote_control

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

class AppUpdateBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    private data class Transfer(val file: File, val stream: java.io.BufferedOutputStream, val expected: Long, var received: Long = 0)
    private val channel = MethodChannel(messenger, "remote_control/app_update")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val directory = File(activity.cacheDir, "app-updates").apply { mkdirs() }
    private val transfers = mutableMapOf<String, Transfer>()
    private val prepared = mutableMapOf<String, File>()
    private val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { s -> MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) } }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun validate(file: File): Map<String, Any> {
        val candidate = activity.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("This file is not a valid APK.")
        val current = activity.packageManager.getPackageInfo(activity.packageName, flags)
        check(candidate.packageName == activity.packageName) { "This APK belongs to a different app." }
        val currentKeys = certificates(current)
        check(currentKeys.isNotEmpty() && certificates(candidate) == currentKeys) { "The APK signing key does not match the installed app. Use the same signing key when building updates." }
        check(version(candidate) >= version(current)) { "This APK is older than the installed app." }
        return mapOf("version" to (candidate.versionName ?: "?"), "build" to version(candidate), "installedVersion" to (current.versionName ?: "?"), "installedBuild" to version(current), "bytes" to file.length())
    }

    init {
        // Old cached packages are bounded and never exposed as arbitrary paths.
        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000L }?.forEach { it.delete() }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "installed") {
                val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                result.success(mapOf("version" to (info.versionName ?: ""), "build" to version(info)))
                return@setMethodCallHandler
            }
            if (call.method == "install") {
                val id = call.argument<String>("id")
                worker.execute {
                    try {
                        val file = prepared[id] ?: error("Download and verify the APK first.")
                        validate(file)
                        main.post {
                            try {
                                if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                                    result.success("permission_required")
                                } else {
                                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                                    activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                    result.success("installer_opened")
                                }
                            } catch (e: Exception) { result.error("INSTALL_FAILED", e.message, null) }
                        }
                    } catch (e: Exception) { main.post { result.error("UPDATE_FAILED", e.message, null) } }
                }
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val id = call.argument<String>("id")
                    var response: Any? = null
                    when (call.method) {
                        "begin" -> {
                            check(transfers.isEmpty()) { "An update is already downloading." }
                            val expected = call.argument<Number>("size")!!.toLong()
                            check(expected in 1..314572800L) { "Invalid APK size (maximum 300 MB)." }
                            prepared.values.forEach { it.delete() }; prepared.clear()
                            directory.listFiles()?.forEach { it.delete() }
                            val token = UUID.randomUUID().toString()
                            val file = File(directory, "$token.apk")
                            transfers[token] = Transfer(file, java.io.BufferedOutputStream(FileOutputStream(file), 262144), expected)
                            response = token
                        }
                        "append" -> {
                            val t = transfers[id] ?: error("Update download expired.")
                            val bytes = call.argument<ByteArray>("bytes")!!
                            check(t.received + bytes.size <= t.expected) { "APK exceeds its reported size." }
                            t.stream.write(bytes)
                            t.received += bytes.size
                        }
                        "finish" -> {
                            val t = transfers[id] ?: error("Update download expired.")
                            t.stream.close()
                            check(t.file.length() == t.expected) { "Incomplete APK download. Try again." }
                            response = validate(t.file)
                            transfers.remove(id)
                            prepared[id!!] = t.file
                        }
                        "cancel" -> {
                            transfers.remove(id)?.let { t -> try { t.stream.close() } finally { t.file.delete() } }
                            prepared.remove(id)?.delete()
                        }
                        else -> error("Unknown update operation")
                    }
                    main.post { result.success(response) }
                } catch (e: Exception) { main.post { result.error("UPDATE_FAILED", e.message, null) } }
            }
        }
    }
    fun detach() {
        channel.setMethodCallHandler(null)
        worker.execute {
            transfers.values.forEach { t -> try { t.stream.close() } finally { t.file.delete() } }
            transfers.clear()
        }
        worker.shutdown()
    }
}

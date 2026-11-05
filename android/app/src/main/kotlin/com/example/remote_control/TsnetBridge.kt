package com.example.remote_control

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.Network
import android.net.LinkProperties
import android.os.Handler
import android.os.Looper
import com.remotecontrol.tsnet.tsnetbridge.Tsnetbridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

/** Blocking Go calls run on workers; a read never blocks writes or socket close. */
class TsnetBridge(context: Context, messenger: BinaryMessenger) {
    companion object {
        private val node = Tsnetbridge.newNode()
        private val workers = Executors.newCachedThreadPool()
        @Volatile private var debugSession: AdbRelaySession? = null
        internal fun observeRemoteAdb(context: Context, owner: Any) { TsnetNetworkMonitor.acquire(context, node, owner) }
        internal fun releaseRemoteAdb(owner: Any) { TsnetNetworkMonitor.release(owner) }
        internal fun stopRemoteAdb() { workers.execute { runCatching { debugSession?.stop() } } }
    }

    private val appContext = context.applicationContext
    private val debugging = synchronized(node) {
        debugSession ?: AdbRelaySession(appContext, node, workers).also { debugSession = it }
    }
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "remote_control/tsnet")
    private val lanDiscovery = LanDiscovery(appContext)

    init {
        go.Seq.setContext(appContext)
        TsnetNetworkMonitor.acquire(appContext, node, this)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "discoverLan") {
                lanDiscovery.discover(result)
            } else if (call.method == "openLogin") {
                try {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    require(uri.scheme == "https" && uri.host == "login.tailscale.com") {
                        "Invalid Tailscale login URL"
                    }
                    appContext.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                } catch (error: Exception) {
                    result.error("TSNET_LOGIN", error.message, null)
                }
            } else {
                workers.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "start" -> {
                                node.updateNetwork(TsnetNetworkMonitor.snapshot(appContext))
                                node.start(File(appContext.noBackupFilesDir, "tsnet").absolutePath,
                                    "remote-control-android", "")
                                null
                            }
                            "wait" -> { node.waitReady(number(call, "timeoutMs", 15000)); null }
                            "status" -> node.status()
                            "peers" -> node.peers()
                            "lanInfo" -> TsnetNetworkMonitor.snapshot(appContext)
                            "dial" -> node.dial(call.argument<String>("host") ?: "",
                                number(call, "port", 22), number(call, "timeoutMs", 10000))
                            "read" -> node.read(number(call, "id"), number(call, "maxBytes", 65536),
                                number(call, "timeoutMs", 1000))
                            "write" -> node.write(number(call, "id"), call.argument<ByteArray>("data")
                                ?: throw IllegalArgumentException("Missing data"), number(call, "timeoutMs", 10000))
                            "close" -> { node.closeConnection(number(call, "id")); null }
                            "debugStatus" -> debugging.status()
                            "setDebugRelayDuration" -> debugging.setDuration(number(call, "minutes"))
                            "startDebugRelay" -> debugging.start(call.argument<String>("pc") ?: "", call.argument<Boolean>("temporaryRoot") == true)
                            "stopDebugRelay" -> { debugging.stop(); null }
                            "stop" -> { debugging.stop(); node.close(); null }
                            else -> { main.post { result.notImplemented() }; return@execute }
                        }
                        main.post { result.success(value) }
                    } catch (error: Exception) {
                        val code = if (error.message?.contains("TSNET_READ_TIMEOUT") == true)
                            "TSNET_READ_TIMEOUT" else "TSNET_ERROR"
                        main.post { result.error(code, error.message, null) }
                    }
                }
            }
        }
    }

    private fun number(call: MethodCall, key: String, fallback: Long? = null): Long =
        call.argument<Number>(key)?.toLong() ?: fallback
        ?: throw IllegalArgumentException("Missing $key")

    // Activity/engine recreation must not destroy the process-owned identity or sockets.

    fun detach() {
        channel.setMethodCallHandler(null)
        lanDiscovery.close()
        TsnetNetworkMonitor.release(this)
    }
}

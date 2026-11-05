package com.example.remote_control

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

/** Finite DNS-SD browse. Resolves serially for older Android NSD implementations. */
@Suppress("DEPRECATION")
class LanDiscovery(context: Context) {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val handler = Handler(Looper.getMainLooper())
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val services = linkedMapOf<String, JSONObject>()
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var result: MethodChannel.Result? = null
    private var resolving = false
    private var generation = 0
    private var deadline: Runnable? = null

    fun discover(reply: MethodChannel.Result) {
        if (result != null) { reply.error("LAN_BUSY", "Discovery is already running", null); return }
        result = reply
        generation++
        val run = generation
        services.clear(); pending.clear()
        for (type in listOf("_ssh._tcp.", "_workstation._tcp.", "_http._tcp.", "_smb._tcp.")) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(t: String) {}
                override fun onDiscoveryStopped(t: String) {}
                override fun onStartDiscoveryFailed(t: String, code: Int) { runCatching { manager.stopServiceDiscovery(this) } }
                override fun onStopDiscoveryFailed(t: String, code: Int) {}
                override fun onServiceLost(info: NsdServiceInfo) {}
                override fun onServiceFound(info: NsdServiceInfo) { handler.post { if (generation == run && result != null) { pending.add(info); resolveNext(run) } } }
            }
            listeners.add(listener)
            runCatching { manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
        }
        deadline = Runnable { finish() }.also { handler.postDelayed(it, 6000) }
    }

    private fun resolveNext(run: Int) {
        if (resolving || pending.isEmpty() || result == null || run != generation) return
        resolving = true
        val next = pending.removeFirst()
        val callback = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) { handler.post { if (run == generation) { resolving = false; resolveNext(run) } } }
            override fun onServiceResolved(info: NsdServiceInfo) { handler.post {
                if (run != generation || result == null) return@post
                val host = info.host?.hostAddress
                if (host != null) {
                    services["$host:${info.port}"] = JSONObject().put("name", info.serviceName).put("host", host).put("port", info.port).put("service", info.serviceType)
                }
                resolving = false; resolveNext(run)
            } }
        }
        try { manager.resolveService(next, callback) } catch (_: Exception) { resolving = false; resolveNext(run) }
    }

    private fun finish() {
        deadline?.let { handler.removeCallbacks(it) }
        listeners.forEach { runCatching { manager.stopServiceDiscovery(it) } }
        listeners.clear(); pending.clear(); resolving = false
        generation++
        val reply = result; result = null
        reply?.success(JSONArray(services.values.toList()).toString())
    }

    fun close() = finish()
}

package com.example.remote_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.LinkProperties
import com.remotecontrol.tsnet.tsnetbridge.Node
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** One network observer shared by the UI and active background ADB service. */
internal object TsnetNetworkMonitor {
    private val owners = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Any, Boolean>())
    private var observer: Observer? = null
    @Synchronized fun acquire(context: Context, node: Node, owner: Any) {
        owners.add(owner)
        if (observer == null) observer = Observer(context.applicationContext, node)
    }
    @Synchronized fun release(owner: Any) {
        owners.remove(owner)
        if (owners.isEmpty()) { observer?.close(); observer = null }
    }
    private class Observer(private val context: Context, private val node: Node) {
        private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        private val updates = Executors.newSingleThreadExecutor()
        private val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update()
            override fun onLost(network: Network) = update()
            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = update()
        }
        init { connectivity.registerDefaultNetworkCallback(callback) }
        private fun update() { runCatching { updates.execute { runCatching { node.updateNetwork(snapshot(context)) } } } }
        fun close() { runCatching { connectivity.unregisterNetworkCallback(callback) }; updates.shutdown() }
    }
    fun snapshot(appContext: Context): String {
        val connectivity = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val active = connectivity.activeNetwork
        val current = active?.let { connectivity.getLinkProperties(it) }
        val interfaces = JSONArray()
        connectivity.allNetworks.forEach { network ->
            val link = connectivity.getLinkProperties(network) ?: return@forEach
            val name = link.interfaceName ?: return@forEach
            val index = runCatching { java.net.NetworkInterface.getByName(name)?.index }.getOrNull() ?: 0
            val addresses = JSONArray()
            link.linkAddresses.forEach { address ->
                addresses.put("${address.address.hostAddress?.substringBefore('%')}/${address.prefixLength}")
            }
            interfaces.put(JSONObject().put("name", name).put("index", index)
                .put("mtu", if (link.mtu > 0) link.mtu else 1500).put("addresses", addresses))
        }
        val gateway = current?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress ?: ""
        return JSONObject().put("defaultInterface", current?.interfaceName ?: "")
            .put("deviceName", android.provider.Settings.Global.getString(appContext.contentResolver, "device_name") ?: android.os.Build.MODEL)
            .put("model", android.os.Build.MODEL)
            .put("wifi", connectivity.getNetworkCapabilities(active)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true)
            .put("gateway", gateway).put("interfaces", interfaces).toString()
    }

}

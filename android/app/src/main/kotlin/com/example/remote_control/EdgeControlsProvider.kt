package com.example.remote_control

import android.app.ActivityOptions
import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.UserManager
import com.nodecockpit.customization.LocalCustomization
import com.nodecockpit.customization.ProcessWork
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** Fixed Wirehelm operations for the unlocked SystemUI Edge panel. */
class EdgeControlsProvider : ContentProvider() {
    private val main = Handler(Looper.getMainLooper())
    private var active: Request? = null
    private var fallback: Fallback? = null
    private val closeIdleFallback = Runnable { fallback?.destroy() }
    private var appMessenger: BinaryMessenger? = null
    private var appChannel: MethodChannel? = null
    private var appReady = false
    private val closedKeyboardOwners = linkedSetOf<String>()
    private val keyboardKeys = setOf("Enter", "Tab", "Escape", "Backspace", "Up", "Down", "Left", "Right", "Copy", "Paste")
    private val app get() = requireNotNull(context).applicationContext

    override fun onCreate(): Boolean {
        instance = this
        return true
    }

    private fun setAppMessenger(messenger: BinaryMessenger?) {
        appChannel?.setMethodCallHandler(null)
        if (active?.channel != null && active?.channel === appChannel) {
            finish(controlError("The Wirehelm connection closed. Refresh to retry."))
        }
        appMessenger = messenger
        appReady = false
        appChannel = messenger?.let { binary ->
            MethodChannel(binary, "remote_control/shared_edge_controls").also { channel ->
                bind(channel) { appReady = true }
            }
        }
    }

    companion object {
        internal var instance: EdgeControlsProvider? = null
            private set

        internal fun attachApp(messenger: BinaryMessenger) = instance?.setAppMessenger(messenger)

        internal fun detachApp(messenger: BinaryMessenger) {
            instance?.takeIf { it.appMessenger === messenger }?.setAppMessenger(null)
        }
    }

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        val systemUi = app.packageManager.getApplicationInfo("com.android.systemui", 0).uid
        if (Binder.getCallingUid() != systemUi) throw SecurityException("SystemUI only")
        require(arg != null && arg.matches(Regex("[a-f0-9-]{36}")))
        if (method == "pcUnlockIntent") {
            if (!isUnlocked()) return controlError("Unlock the phone to use this control.")
            val device = LocalCustomization.edgeControlDevice(app, "power")
            if (device.isEmpty()) return controlError("Choose a CachyOS PC in Wirehelm’s Panel actions.")
            if (device != extras?.getString("device")) return controlError("The selected PC changed. Refresh to continue.")
            return Bundle().apply { putParcelable("unlockIntent", unlockIntent(device)) }
        }
        if (method == "close" || method == "closeKeyboard") {
            if (method == "closeKeyboard") main.post {
                closedKeyboardOwners.add(arg)
                if (closedKeyboardOwners.size > 16) closedKeyboardOwners.remove(closedKeyboardOwners.first())
                val args = mapOf("owner" to arg)
                if (appReady) appChannel?.invokeMethod("closeOwner", args)
                fallback?.channel?.takeIf { fallback?.ready == true }?.invokeMethod("closeOwner", args)
            }
            return Bundle.EMPTY
        }

        val bundle = requireNotNull(extras)
        val reply = CompletableFuture<Bundle>()
        val control = when (method) {
            "read", "power", "white", "color" -> "bulb"
            "pcRead", "pcPower" -> "power"
            "textRead", "textApply" -> "text"
            "keyboardRead", "keyboardSend" -> "keyboard"
            else -> throw IllegalArgumentException("Unsupported control")
        }
        val arguments = when (method) {
            "read", "pcRead", "textRead", "keyboardRead" -> emptyMap()
            "keyboardSend" -> {
                val key = bundle.getString("key")
                val value = bundle.getString("text")
                require((key == null) != (value == null))
                if (key != null) {
                    require(key in keyboardKeys)
                    mapOf("key" to key)
                } else {
                    require(!value.isNullOrEmpty() && value.toByteArray().size <= 16_384 && '\u0000' !in value)
                    mapOf("text" to value)
                }
            }
            "textApply" -> mapOf("halfPoints" to bundle.bounded("halfPoints", 12..64))
            "pcPower" -> {
                val action = bundle.getString("action")
                require(action != null && action in setOf("lock", "sleep", "lockAndSleep", "restart", "shutDown"))
                mapOf("action" to action)
            }
            "power" -> {
                require(bundle.containsKey("on"))
                mapOf("on" to bundle.getBoolean("on"))
            }
            "white" -> mapOf(
                "brightness" to bundle.bounded("brightness", 1..100),
                "temperature" to bundle.bounded("temperature", 0..100)
            )
            "color" -> mapOf(
                "brightness" to bundle.bounded("brightness", 1..100),
                "hue" to bundle.bounded("hue", 0..359),
                "saturation" to bundle.bounded("saturation", 0..100)
            )
            else -> throw IllegalArgumentException("Unsupported control")
        }
        main.post {
            if (!isUnlocked()) {
                reply.fail("Unlock the phone to use this control.")
                return@post
            }
            if (control == "keyboard" && arg in closedKeyboardOwners) {
                reply.fail("The keyboard page is closed.")
                return@post
            }
            val device = LocalCustomization.edgeControlDevice(app, control)
            if (device.isEmpty()) {
                reply.fail("Choose a host in Wirehelm’s Panel actions.")
                return@post
            }
            submit(Request(arg, method, control, device, arguments, { reply.complete(it) }))
        }
        return try {
            reply.get(if (method == "keyboardSend") 150 else 45, TimeUnit.SECONDS)
        } catch (_: TimeoutException) {
            controlError("The request timed out. Refresh to try again.")
        }
    }

    private fun isUnlocked(): Boolean =
        app.getSystemService(UserManager::class.java).isUserUnlocked &&
            app.getSystemService(PowerManager::class.java).isInteractive &&
            !app.getSystemService(KeyguardManager::class.java).isKeyguardLocked

    private fun unlockIntent(device: String): PendingIntent {
        val intent = Intent(app, EdgeDesktopUnlockActivity::class.java)
            .setData(Uri.parse("wirehelm-edge://unlock/${UUID.randomUUID()}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("device", device)
            .putExtra("expiresAt", SystemClock.elapsedRealtime() + 10_000)
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 35) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            )
        }
        return PendingIntent.getActivity(
            app, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT, options.toBundle()
        )
    }

    internal fun unlock(activity: EdgeDesktopUnlockActivity, device: String, reply: (Bundle) -> Unit) {
        submit(Request(UUID.randomUUID().toString(), "pcUnlock", "power", device, emptyMap(), reply, activity))
    }

    internal fun cancelUnlock(activity: EdgeDesktopUnlockActivity) {
        if (active?.unlockActivity !== activity) return
        val worker = fallback?.takeIf { it.channel === active?.channel }
        finish(controlError("PC unlock canceled."))
        worker?.destroy()
    }

    private class Request(
        val owner: String,
        val method: String,
        val control: String,
        val device: String,
        val args: Map<String, Any>,
        val deliver: (Bundle) -> Unit,
        val unlockActivity: EdgeDesktopUnlockActivity? = null,
    ) {
        val id = UUID.randomUUID().toString()
        var channel: MethodChannel? = null
        var work: ProcessWork.Token? = null
        var timeout: Runnable? = null
    }

    private fun allowed(request: Request): Boolean =
        active === request &&
            isUnlocked() &&
            LocalCustomization.edgeControlDevice(app, request.control) == request.device &&
            request.owner !in closedKeyboardOwners &&
            request.unlockActivity?.isFinishing != true

    private fun submit(request: Request) {
        if (active != null) {
            request.deliver(controlError("The control is busy. Refresh in a moment."))
            return
        }
        active = request
        request.work = ProcessWork.begin("Edge panel controls")
        request.timeout = Runnable {
            val worker = fallback?.takeIf { it.channel === request.channel || request.channel == null }
            finish(controlError("The request timed out. Refresh to try again."))
            worker?.destroy()
        }.also { main.postDelayed(it, if (request.method in setOf("keyboardSend", "pcUnlock")) 145_000 else 40_000) }
        val currentApp = appChannel?.takeIf { appReady }
        if (currentApp == null) useFallback(request)
        else dispatch(request, currentApp, shared = true)
    }

    private fun useFallback(request: Request) {
        if (!allowed(request)) {
            finish(controlError("The Controls page is unavailable."))
            return
        }
        request.channel = null
        main.removeCallbacks(closeIdleFallback)
        val worker = fallback
        if (worker == null) Fallback().also { fallback = it }.start()
        else worker.dispatchReady()
    }

    private fun bind(channel: MethodChannel, onReady: () -> Unit) {
        channel.setMethodCallHandler { call, reply ->
            val request = active?.takeIf { it.channel === channel }
            when (call.method) {
                "ready" -> {
                    reply.success(null)
                    onReady()
                }
                "canRun" -> reply.success(request != null && request.id == call.arguments && allowed(request))
                "authenticateUnlock" -> {
                    val activity = request?.unlockActivity
                    if (request == null || activity == null ||
                        request.id != call.argument<String>("request") || !allowed(request)
                    ) {
                        reply.success(false)
                    } else {
                        activity.authenticate(call.argument<String>("device").orEmpty(), reply)
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun dispatch(request: Request, channel: MethodChannel, shared: Boolean = false) {
        if (!allowed(request)) {
            finish(controlError("The Controls page is unavailable."))
            return
        }
        request.channel = channel
        channel.invokeMethod(
            request.method, request.args + mapOf("device" to request.device, "owner" to request.owner, "request" to request.id),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    if (active !== request) return
                    val state = value as? Map<*, *>
                    if (shared && state?.get("noSession") == true) {
                        useFallback(request)
                        return
                    }
                    val bundle = controlState(request.control, state)
                    if (request.method == "pcRead" && bundle.getBoolean("ready")) {
                        bundle.putString("device", request.device)
                    }
                    finish(bundle)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (active === request) {
                        finish(controlError("Could not reach the selected host. Refresh to retry."))
                    }
                }

                override fun notImplemented() {
                    if (active !== request) return
                    if (shared) useFallback(request)
                    else finish(controlError("Could not start the control."))
                }
            },
        )
    }

    private fun controlState(control: String, state: Map<*, *>?): Bundle {
        val error = state?.get("error") as? String
        if (error != null) return controlError(error.take(180))
        if (state == null) return controlError("The host did not return a control state.")
        if (control != "bulb" && state["ready"] == true) return Bundle().apply {
            putBoolean("ready", true)
            putString("deviceName", (state["deviceName"] as? String)?.take(80))
            val size = state["size"] as? Double
            if (size != null && size.isFinite() && size > 0) putDouble("size", size)
            putBoolean("sizesMatch", state["sizesMatch"] == true)
            val unlock = state["unlock"] as? String
            if (unlock in setOf("ready", "displayUnconfirmed", "cancelled")) putString("unlock", unlock)
        }
        val on = state["on"] as? Boolean ?: return controlError("The host did not return a control state.")
        return Bundle().apply {
            putBoolean("on", on)
            putBoolean("color", state["color"] == true)
            for (key in listOf("whiteBrightness", "colorBrightness", "temperature", "hue", "saturation")) {
                val number = state[key] as? Int
                if (number != null) putInt(key, number)
            }
        }
    }

    private fun finish(result: Bundle) {
        val request = active ?: return
        active = null
        request.timeout?.let(main::removeCallbacks)
        request.work?.close()
        if (fallback?.let { request.channel == null || it.channel === request.channel } == true) {
            main.postDelayed(closeIdleFallback, 25_000)
        }
        request.deliver(result)
    }

    private inner class Fallback {
        private var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
            private set
        var ready = false
            private set
        private var tsnetBridge: TsnetBridge? = null

        fun start() {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(app)
                loader.ensureInitializationCompleteAsync(app, null, main) {
                    if (fallback !== this) return@ensureInitializationCompleteAsync
                    try {
                        ScreenOffShutdown.attach(app)
                        val worker = FlutterEngine(app).also { engine = it }
                        val messenger = worker.dartExecutor.binaryMessenger
                        tsnetBridge = TsnetBridge(app, messenger, closeOwnedSockets = true)
                        channel = MethodChannel(messenger, "remote_control/edge_controls").also {
                            bind(it) { ready = true; dispatchReady() }
                        }
                        worker.dartExecutor.executeDartEntrypoint(
                            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "edgeControlsMain")
                        )
                    } catch (_: Exception) {
                        startFailed()
                    }
                }
            } catch (_: Exception) {
                startFailed()
            }
        }

        fun dispatchReady() {
            val request = active ?: return
            val workerChannel = channel ?: return
            if (ready && request.channel == null) dispatch(request, workerChannel)
        }

        private fun startFailed() {
            finish(controlError("Could not start the control."))
            destroy()
        }

        fun destroy() {
            if (fallback !== this) return
            fallback = null
            main.removeCallbacks(closeIdleFallback)
            channel?.setMethodCallHandler(null)
            tsnetBridge?.detach()
            engine?.destroy()
        }
    }

    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, s: String?, a: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, s: String?, a: Array<out String>?): Int = throw UnsupportedOperationException()
}

private fun Bundle.bounded(key: String, range: IntRange): Int =
    getInt(key, -1).also { require(it in range) }

private fun CompletableFuture<Bundle>.fail(message: String) {
    complete(controlError(message))
}

private fun controlError(message: String) = Bundle().apply { putString("error", message) }

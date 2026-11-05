package com.example.remote_control

import android.content.Context
import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.nodecockpit.customization.LocalCustomization
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors

class CustomizationBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remote_control/customization")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var notificationPermissionResult: MethodChannel.Result? = null
    companion object { private const val NOTIFICATION_PERMISSION_REQUEST = 59173 }
    init {
        LocalCustomization.initialize(context)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "requestSampleNotificationPermission") {
                main.post {
                    try {
                        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            result.success(LocalCustomization.notificationUndoState().toString())
                        } else {
                            val activity = context as? Activity ?: error("Open this page in the app to request notification permission")
                            check(notificationPermissionResult == null) { "Notification permission request already open" }
                            notificationPermissionResult = result
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
                        }
                    } catch (e: Exception) {
                        if (notificationPermissionResult === result) notificationPermissionResult = null
                        result.error("CUSTOMIZATION_FAILED", e.message, null)
                    }
                }
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val value = when (call.method) {
                        "cameraRingState" -> LocalCustomization.cameraRingState()
                        "notificationUndoState" -> LocalCustomization.notificationUndoState()
                        "applyNotificationUndo" -> LocalCustomization.applyNotificationUndo(call.argument<String>("config") ?: error("Missing Undo configuration"))
                        "postNotificationUndoSample" -> LocalCustomization.postNotificationUndoSample()
                        "openSampleNotificationSettings" -> { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)); JSONObject() }
                        "applyCameraRing" -> LocalCustomization.applyCameraRing(call.argument<String>("config") ?: error("Missing ring configuration"))
                        "testCameraRing" -> LocalCustomization.testCameraRing(call.argument<Boolean>("ambient") == true)
                        "stopCameraRingTest" -> LocalCustomization.stopCameraRingTest()
                        "openDisplaySettings" -> { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_DISPLAY_SETTINGS).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)); JSONObject() }
                        "notificationApps" -> launcherApps(true)
                        "probe" -> LocalCustomization.probe(call.argument<Boolean>("requestRoot") == true)
                        "apply" -> LocalCustomization.apply(JSONObject(call.argument<String>("config") ?: error("Missing configuration")))
                        "applyVisual" -> LocalCustomization.applyVisual(JSONObject(call.argument<String>("config") ?: error("Missing configuration")))
                        "disable" -> LocalCustomization.disable()
                        "rollback" -> LocalCustomization.rollback()
                        "saveSetup" -> LocalCustomization.saveSetup(call.argument<String>("name"))
                        "updateSetup" -> LocalCustomization.updateSetup(call.argument<String>("id"), call.argument<String>("scope"))
                        "restoreSetup" -> LocalCustomization.restoreSetup(call.argument<String>("id"), call.argument<String>("scope") ?: "all")
                        "restartSystemUi" -> LocalCustomization.restartSystemUi()
                        "install" -> LocalCustomization.install()
                        "installCarrier" -> LocalCustomization.installCarrier()
                        "enableCarrier" -> LocalCustomization.setCarrierEnabled(true)
                        "disableCarrier" -> LocalCustomization.setCarrierEnabled(false)
                        "framework" -> { LocalCustomization.openFramework(context); JSONObject() }
                        "frameworkModule" -> { LocalCustomization.openFrameworkModule(context); JSONObject() }
                        "installVector" -> { LocalCustomization.openVectorDownload(context); JSONObject() }
                        "installKernelSu" -> { LocalCustomization.openKernelSuDownload(context); JSONObject() }
                        "kernelSu" -> { LocalCustomization.openKernelSu(context); JSONObject() }
                        "launcherApps" -> launcherApps()
                        else -> error("Unsupported customization operation")
                    }
                    main.post { result.success(value.toString()) }
                } catch (e: Exception) { main.post { result.error("CUSTOMIZATION_FAILED", e.message, null) } }
            }
        }
    }
    fun onNotificationPermissionResult(requestCode: Int) {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val result = notificationPermissionResult ?: return
        notificationPermissionResult = null
        try { result.success(LocalCustomization.notificationUndoState().toString()) }
        catch (e: Exception) { result.error("CUSTOMIZATION_FAILED", e.message, null) }
    }
    private fun launcherApps(includeSelf: Boolean = false): JSONObject {
        val intent = android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val apps = JSONArray()
        context.packageManager.queryIntentActivities(intent, 0)
            .sortedBy { it.loadLabel(context.packageManager).toString().lowercase() }
            .forEach { info ->
                val packageName = info.activityInfo.packageName
                if ((includeSelf || packageName != context.packageName) && seen.add(packageName)) {
                    apps.put(JSONObject().put("package", packageName).put("label", info.loadLabel(context.packageManager).toString())
                        .put("icon", launcherIcon(info.loadIcon(context.packageManager))))
                }
            }
        return JSONObject().put("apps", apps)
    }
    private fun launcherIcon(drawable: android.graphics.drawable.Drawable): String {
        val size = (48 * context.resources.displayMetrics.density).toInt().coerceAtLeast(48)
        val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap); drawable.setBounds(0, 0, size, size); drawable.draw(canvas)
        val bytes = java.io.ByteArrayOutputStream(); bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, bytes); bitmap.recycle()
        return android.util.Base64.encodeToString(bytes.toByteArray(), android.util.Base64.NO_WRAP)
    }
    fun detach() { channel.setMethodCallHandler(null); worker.shutdown() }
}

package com.example.remote_control

import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.EventChannel
import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.nodecockpit.customization.EdgeBuiltinShortcuts
import com.nodecockpit.customization.LocalCustomization
import com.nodecockpit.customization.PhotosSourcesControl
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors

class CustomizationBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remote_control/customization")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val deviceSnapshot = DeviceSnapshot(context.applicationContext)
    private var notificationPermissionResult: MethodChannel.Result? = null
    companion object { private const val NOTIFICATION_PERMISSION_REQUEST = 59173 }
    private val shelfEvents=EventChannel(messenger,"remote_control/clipboard_shelf_events")
    private var shelfReceiver:BroadcastReceiver?=null
    private fun stopShelfEvents(){shelfReceiver?.let{runCatching{context.unregisterReceiver(it)}};shelfReceiver=null}
    init {
        shelfEvents.setStreamHandler(object:EventChannel.StreamHandler{
            override fun onListen(arguments:Any?,events:EventChannel.EventSink){
                stopShelfEvents()
                shelfReceiver=object:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){events.success(null)}}.also{
                    val filter=IntentFilter("com.example.remote_control.CLIPBOARD_SHELF_CHANGED")
                    if(Build.VERSION.SDK_INT>=33)context.registerReceiver(it,filter,Context.RECEIVER_NOT_EXPORTED) else context.registerReceiver(it,filter)
                }
            }
            override fun onCancel(arguments:Any?){stopShelfEvents()}
        })

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
                        "buttonShortcutsStatus" -> ButtonShortcutService.status(context)
                        "saveButtonShortcuts" -> ButtonShortcutService.save(context,
                            requireNotNull(call.argument<String>("up")),
                            requireNotNull(call.argument<String>("down")),
                            requireNotNull(call.argument<Number>("holdMs")).toLong(),
                            call.argument<Map<String, String>>("extra").orEmpty(),
                            call.argument<Number>("torchMinutes")?.toInt() ?: 5)
                        "startButtonShortcuts" -> ButtonShortcutService.start(context)
                        "stopButtonShortcuts" -> ButtonShortcutService.stop(context)
                        "buttonShortcutAccess" -> {
                            ButtonShortcutActions.openSettings(context, requireNotNull(call.argument<String>("type")))
                            JSONObject()
                        }
                        "buttonBookmarks" -> ButtonShortcutActions.bookmarks(context)
                        "updateButtonBookmark" -> ButtonShortcutActions.updateBookmark(context,
                            requireNotNull(call.argument<String>("id")), requireNotNull(call.argument<String>("note")))
                        "deviceSnapshotBaseline" -> deviceSnapshot.readBaseline()
                        "saveDeviceSnapshot" -> deviceSnapshot.saveBaseline(call.argument<Boolean>("includeModules") == true)
                        "captureDeviceSnapshot" -> deviceSnapshot.capture(call.argument<Boolean>("includeModules") == true)
                        "photosSourcesStatus" -> PhotosSourcesControl.status(context)
                        "otaDevice" -> {
                            val rootVersion = runCatching {
                                context.packageManager.getPackageInfo("me.weishu.kernelsu", 0).versionName
                            }.getOrNull() ?: ""
                            JSONObject().put("device", Build.DEVICE).put("build", Build.FINGERPRINT)
                                .put("timestamp", Build.TIME / 1000).put("kernelSuVersion", rootVersion)
                        }
                        "savePhotosSources" -> PhotosSourcesControl.save(
                            context, JSONObject(requireNotNull(call.argument<String>("config"))))
                        "openGooglePhotos" -> {
                            val intent = context.packageManager.getLaunchIntentForPackage("com.google.android.apps.photos")
                                ?: error("Google Photos is unavailable")
                            context.startActivity(intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                            JSONObject()
                        }
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
                        "edgeActions" -> LocalCustomization.edgeActionSettings()
                        "saveEdgeActions" -> LocalCustomization.saveEdgeActionSettings(call.argument<String>("raw") ?: error("Missing panel actions"))
                        "setEdgeControlVisibility" -> LocalCustomization.setEdgeControlVisibility(
                            requireNotNull(call.argument<String>("control")),
                            requireNotNull(call.argument<Boolean>("shown")),
                            call.argument<String>("device") ?: ""
                        )
                        "addClipboardEdgeShortcut" -> LocalCustomization.addClipboardEdgeShortcut()
                        "clipboardApps" -> launcherApps(true,false)
                        "clipboardShelf" -> {
                            val extras=android.os.Bundle().apply {
                                putString("query",call.argument<String>("query") ?: "")
                                putBoolean("pinned",call.argument<Boolean>("pinned") == true)
                                putLong("id",call.argument<Number>("id")?.toLong() ?: 0)
                                putBoolean("value",call.argument<Boolean>("value") == true)
                                putBoolean("includePins",call.argument<Boolean>("includePins") == true)
                                call.argument<String>("config")?.let{putString("config",it)}
                            }
                            val op=call.argument<String>("op") ?: "list"
                            require(op in setOf("list","configure","pin","delete","clear","copy","detail"))
                            val response=context.contentResolver.call(android.net.Uri.parse("content://${context.packageName}.clipboard.shelf"),op,null,extras)
                            JSONObject(response?.getString("data") ?: error("Clipboard shelf unavailable"))
                        }
                        "batteryUsage", "batteryUsageConfigure" -> {
                            val extras=android.os.Bundle().apply {
                                putLong("session",call.argument<Number>("session")?.toLong() ?: 0)
                                putBoolean("enabled",call.argument<Boolean>("enabled") == true)
                                putBoolean("estimates",call.argument<Boolean>("estimates") == true)
                            }
                            val response=context.contentResolver.call(android.net.Uri.parse("content://${context.packageName}.battery.usage"),
                                if(call.method=="batteryUsage")"get" else "configure",null,extras)
                            JSONObject(response?.getString("data") ?: error("Battery tracker unavailable"))
                        }
                        "carrierCatalog" -> LocalCustomization.carrierCatalog(call.argument<String>("query") ?: "")
                        "configureCarriers" -> LocalCustomization.configureCarriers(call.argument<String>("carriers"))
                        "installCarrier" -> LocalCustomization.installCarrier()
                        "enableCarrier" -> LocalCustomization.setCarrierEnabled(true)
                        "disableCarrier" -> LocalCustomization.setCarrierEnabled(false)
                        "framework" -> { LocalCustomization.openFramework(context); JSONObject() }
                        "frameworkModule" -> { LocalCustomization.openFrameworkModule(context); JSONObject() }
                        "installVector" -> { LocalCustomization.openVectorDownload(context); JSONObject() }
                        "installKernelSu" -> { LocalCustomization.openKernelSuDownload(context); JSONObject() }
                        "kernelSu" -> { LocalCustomization.openKernelSu(context); JSONObject() }
                        "launcherApps" -> launcherApps(call.argument<Boolean>("includeSelf") == true,builtins=call.argument<Boolean>("edgeShortcuts") == true)
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
    private fun launcherApps(includeSelf: Boolean = false, icons: Boolean = true, builtins: Boolean = false): JSONObject {
        val intent = android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val apps = JSONArray()
        context.packageManager.queryIntentActivities(intent, 0)
            .sortedBy { it.loadLabel(context.packageManager).toString().lowercase() }
            .forEach { info ->
                val packageName = info.activityInfo.packageName
                if ((includeSelf || packageName != context.packageName) && seen.add(packageName)) {
                    apps.put(JSONObject().put("package", packageName).put("label", info.loadLabel(context.packageManager).toString())
                        .apply{if(icons)put("icon", launcherIcon(info.loadIcon(context.packageManager)))})
                }
            }
        if(builtins){
            apps.put(JSONObject().put("package",EdgeBuiltinShortcuts.CLIPBOARD).put("label",EdgeBuiltinShortcuts.LABEL).put("builtin",true)
                .put("icon",launcherIcon(context.packageManager.getApplicationIcon(context.packageName))))
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
    fun detach() { stopShelfEvents(); shelfEvents.setStreamHandler(null); channel.setMethodCallHandler(null); worker.shutdown() }
}

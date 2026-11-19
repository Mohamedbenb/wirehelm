package com.example.remote_control

import android.content.Intent
import android.os.Build
import com.nodecockpit.customization.EdgeBuiltinShortcuts

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tsnetBridge: TsnetBridge? = null
    private var remoteAudioBridge: RemoteAudioBridge? = null
    private var downloadBridge: DownloadBridge? = null
    private var appUpdateBridge: AppUpdateBridge? = null
    private var uploadBridge: UploadBridge? = null
    private var customizationBridge: CustomizationBridge? = null
    private var rootFilesBridge: RootFilesBridge? = null
    private var appNetworkBridge: AppNetworkBridge? = null

    override fun getInitialRoute():String? = EdgeBuiltinShortcuts.route(intent?.getStringExtra(EdgeBuiltinShortcuts.EXTRA)) ?: super.getInitialRoute()
    override fun onNewIntent(intent:Intent){
        super.onNewIntent(intent)
        setIntent(intent)
        EdgeBuiltinShortcuts.route(intent.getStringExtra(EdgeBuiltinShortcuts.EXTRA))?.let{flutterEngine?.navigationChannel?.pushRoute(it)}
    }

    override fun onPause() {
        rootFilesBridge?.lock()
        super.onPause()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        customizationBridge?.onNotificationPermissionResult(requestCode)
    }

    companion object {
        private const val CHANNEL =
            "remote_control/background_keep_alive"
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(
            flutterEngine
        )
        ScreenOffShutdown.attach(this)
        val workMessenger = SleepAwareMessenger(flutterEngine.dartExecutor.binaryMessenger)
        tsnetBridge = TsnetBridge(this, workMessenger)
        remoteAudioBridge = RemoteAudioBridge(workMessenger)
        downloadBridge = DownloadBridge(this, workMessenger)
        appUpdateBridge = AppUpdateBridge(this, workMessenger)
        uploadBridge = UploadBridge(this, workMessenger)
        customizationBridge = CustomizationBridge(this, workMessenger)
        rootFilesBridge = RootFilesBridge(this, workMessenger)
        appNetworkBridge = AppNetworkBridge(this, workMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("remote_control/termux_terminal", NativeTerminalBridge(workMessenger))

        MethodChannel(
            workMessenger,
            CHANNEL
        ).setMethodCallHandler {
                call,
                result ->

            when (call.method) {
                "beginWork" -> result.success(ScreenOffShutdown.beginDart(call.argument<String>("reason") ?: "active work"))
                "endWork" -> { call.argument<Number>("token")?.toLong()?.let(ScreenOffShutdown::end); result.success(null) }
                "sleepStatus" -> result.success(ScreenOffShutdown.status())
                "start" -> {
                    try {
                        val intent =
                            Intent(
                                this,
                                KeepAliveService::class.java
                            )

                        if (
                            Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.O
                        ) {
                            startForegroundService(
                                intent
                            )
                        } else {
                            startService(
                                intent
                            )
                        }

                        result.success(
                            null
                        )
                    } catch (
                        e: Exception
                    ) {
                        result.error(
                            "START_FAILED",
                            e.message,
                            null
                        )
                    }
                }

                "stop" -> {
                    try {
                        stopService(
                            Intent(
                                this,
                                KeepAliveService::class.java
                            )
                        )

                        result.success(
                            null
                        )
                    } catch (
                        e: Exception
                    ) {
                        result.error(
                            "STOP_FAILED",
                            e.message,
                            null
                        )
                    }
                }

                "isRunning" -> {
                    result.success(
                        KeepAliveService
                            .isRunning
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == UploadBridge.REQUEST) uploadBridge?.selected(resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val cleanup = ScreenOffShutdown.begin("native engine cleanup")
        try {
        appNetworkBridge?.detach()
        appNetworkBridge = null
        rootFilesBridge?.detach()
        rootFilesBridge = null
        customizationBridge?.detach()
        customizationBridge = null
        uploadBridge?.detach()
        uploadBridge = null
        appUpdateBridge?.detach()
        appUpdateBridge = null
        downloadBridge?.detach()
        downloadBridge = null
        remoteAudioBridge?.detach()
        remoteAudioBridge = null
        tsnetBridge?.detach()
        tsnetBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
        } finally {
            // SSH connections and their transfer owners live in this Dart engine.
            // Remote ADB and button services have independent native ownership.
            stopService(Intent(this, KeepAliveService::class.java))
            ScreenOffShutdown.detachRuntime()
            ScreenOffShutdown.end(cleanup)
        }
    }
}

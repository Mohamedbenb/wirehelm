package com.example.remote_control

import android.content.Intent
import android.os.Build

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
        tsnetBridge = TsnetBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        remoteAudioBridge = RemoteAudioBridge(flutterEngine.dartExecutor.binaryMessenger)
        downloadBridge = DownloadBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        appUpdateBridge = AppUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        uploadBridge = UploadBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        customizationBridge = CustomizationBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        rootFilesBridge = RootFilesBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("remote_control/termux_terminal", NativeTerminalBridge(flutterEngine.dartExecutor.binaryMessenger))

        MethodChannel(
            flutterEngine
                .dartExecutor
                .binaryMessenger,
            CHANNEL
        ).setMethodCallHandler {
                call,
                result ->

            when (call.method) {
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
    }
}

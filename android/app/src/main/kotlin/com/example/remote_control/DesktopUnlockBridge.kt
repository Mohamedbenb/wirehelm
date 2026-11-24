package com.example.remote_control

import android.app.Activity
import android.app.KeyguardManager
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class DesktopUnlockBridge(
    private val activity: Activity,
    messenger: BinaryMessenger? = null,
) {
    private val channel = messenger?.let { MethodChannel(it, "remote_control/desktop_unlock") }
    private var pending: MethodChannel.Result? = null
    private var signal: CancellationSignal? = null

    init {
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "authenticate") {
                authenticate(call.argument<String>("device").orEmpty(), result)
            } else {
                result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    fun authenticate(device: String, result: MethodChannel.Result) {
        if (pending != null || !activity.hasWindowFocus()) {
            result.error("AUTH_UNAVAILABLE", "Open Wirehelm to confirm the desktop unlock.", null)
            return
        }
        val keyguard = activity.getSystemService(KeyguardManager::class.java)
        if (!keyguard.isDeviceSecure) {
            result.error("NO_SCREEN_LOCK", "Set a screen lock on this phone to unlock the PC.", null)
            return
        }
        val description = "Confirm to unlock ${device.take(80)}"
        pending = result
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                val intent = keyguard.createConfirmDeviceCredentialIntent("Unlock desktop", description)
                    ?: error("Phone authentication is unavailable.")
                activity.startActivityForResult(intent, REQUEST)
                return
            }
            val cancellation = CancellationSignal()
            signal = cancellation
            BiometricPrompt.Builder(activity)
                .setTitle("Unlock desktop")
                .setSubtitle(description)
                .setAllowedAuthenticators(Authenticators.BIOMETRIC_STRONG or Authenticators.DEVICE_CREDENTIAL)
                .build()
                .authenticate(cancellation, activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                        if (pending === result) finish(true)
                    }

                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        if (pending !== result) return
                        when (code) {
                            BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                            BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED -> finish(false)
                            else -> fail(message.toString())
                        }
                    }
                })
        } catch (error: RuntimeException) {
            fail(error.message ?: "Phone authentication is unavailable.")
        }
    }

    private fun finish(approved: Boolean) {
        val result = pending
        pending = null
        signal = null
        result?.success(approved)
    }

    private fun fail(message: String) {
        val result = pending
        pending = null
        signal = null
        result?.error("AUTH_FAILED", message, null)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode == REQUEST) finish(resultCode == Activity.RESULT_OK)
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        val current = signal
        finish(false)
        current?.cancel()
    }

    companion object {
        private const val REQUEST = 4621
    }
}

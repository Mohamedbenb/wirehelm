package com.example.remote_control

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel

/** Opened by a one-shot PendingIntent issued to SystemUI for the selected PC. */
class EdgeDesktopUnlockActivity : Activity() {
    private val authentication = DesktopUnlockBridge(this)
    private lateinit var status: TextView
    private var target: String? = null
    private var disposed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val device = intent.getStringExtra("device")
        if (savedInstanceState != null || device.isNullOrEmpty() ||
            SystemClock.elapsedRealtime() >= intent.getLongExtra("expiresAt", 0)
        ) {
            finish()
            return
        }

        title = "Unlock PC"
        status = TextView(this).apply { text = "Checking the PC’s Plasma session…" }
        val cancel = Button(this).apply {
            text = getString(android.R.string.cancel)
            setOnClickListener { finish() }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
            addView(status)
            addView(cancel)
        })
        target = device
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val device = target ?: return
        if (!hasFocus || isFinishing) return
        target = null
        val provider = EdgeControlsProvider.instance
        if (provider == null) {
            showResult("PC unlock is unavailable.")
            return
        }
        provider.unlock(this, device) { result ->
            if (isFinishing || disposed) return@unlock
            val message = result.getString("error") ?: when (result.getString("unlock")) {
                "ready" -> "PC is unlocked. Display is awake."
                "displayUnconfirmed" -> "PC is unlocked. Display wake could not be confirmed."
                "cancelled" -> "PC unlock canceled."
                else -> "PC unlock could not be confirmed."
            }
            showResult(message)
        }
    }

    internal fun authenticate(device: String, result: MethodChannel.Result) {
        status.text = "Confirm on your phone to unlock the PC."
        authentication.authenticate(device, result)
    }

    private fun showResult(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        authentication.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        disposed = true
        EdgeControlsProvider.instance?.cancelUnlock(this)
        authentication.detach()
        super.onDestroy()
    }
}

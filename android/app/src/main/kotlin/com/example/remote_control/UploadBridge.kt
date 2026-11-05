package com.example.remote_control

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.io.InputStream
import java.util.concurrent.Executors

class UploadBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    companion object { const val REQUEST = 7412 }
    private val channel = MethodChannel(messenger, "remote_control/uploads")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var selection: MethodChannel.Result? = null
    private var stream: InputStream? = null
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "pick") {
                if (selection != null) { result.error("UPLOAD_BUSY", "File picker is already open.", null) }
                else {
                    selection = result
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        }, REQUEST)
                    } catch (e: Exception) { selection = null; result.error("UPLOAD_FAILED", e.message, null) }
                }
            } else worker.execute {
                try {
                    val response = when (call.method) {
                        "open" -> {
                            stream?.close()
                            stream = activity.contentResolver.openInputStream(Uri.parse(call.argument<String>("uri") ?: error("Missing file URI"))) ?: error("Cannot open selected file.")
                            null
                        }
                        "read" -> {
                            val buffer = ByteArray(256 * 1024)
                            val count = (stream ?: error("Select a file first.")).read(buffer)
                            if (count < 0) ByteArray(0) else buffer.copyOf(count)
                        }
                        "close" -> { stream?.close(); stream = null; null }
                        else -> error("Unknown upload operation")
                    }
                    main.post { result.success(response) }
                } catch (e: Exception) { main.post { result.error("UPLOAD_FAILED", e.message, null) } }
            }
        }
    }
    fun selected(code: Int, data: Intent?) {
        val result = selection ?: return
        selection = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(null); return }
        worker.execute {
            try {
                var name = "upload.bin"
                var size: Long? = null
                activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val n = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val s = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (n >= 0) name = cursor.getString(n)
                        if (s >= 0 && !cursor.isNull(s)) size = cursor.getLong(s)
                    }
                }
                val info = mapOf("name" to name, "size" to size, "uri" to uri.toString())
                main.post { result.success(info) }
            } catch (e: Exception) { main.post { result.error("UPLOAD_FAILED", e.message, null) } }
        }
    }
    fun detach() {
        channel.setMethodCallHandler(null)
        selection?.error("UPLOAD_CANCELLED", "File picker closed.", null)
        selection = null
        worker.execute { stream?.close(); stream = null }
        worker.shutdown()
    }
}

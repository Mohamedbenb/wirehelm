package com.example.remote_control

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

class DownloadBridge(private val context: Context, messenger: BinaryMessenger) {
    private data class Transfer(val uri: Uri, val stream: OutputStream)
    private val transfers = mutableMapOf<String, Transfer>()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "remote_control/downloads")
    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    if (Build.VERSION.SDK_INT < 29) error("Downloads require Android 10 or newer.")
                    val id = call.argument<String>("id")
                    var response: Any? = null
                    when (call.method) {
                        "begin" -> {
                            val name = call.argument<String>("name")!!.substringAfterLast('/').substringAfterLast('\\')
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                put(MediaStore.MediaColumns.MIME_TYPE, if (name.endsWith(".png")) "image/png" else "application/octet-stream")
                                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Node Cockpit")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Cannot create download")
                            val stream = try { context.contentResolver.openOutputStream(uri) ?: error("Cannot open download") }
                            catch (e: Exception) { context.contentResolver.delete(uri, null, null); throw e }
                            val token = UUID.randomUUID().toString()
                            transfers[token] = Transfer(uri, java.io.BufferedOutputStream(stream, 256 * 1024))
                            response = token
                        }
                        "append" -> (transfers[id] ?: error("Download expired")).stream.write(call.argument<ByteArray>("bytes")!!)
                        "finish" -> {
                            val transfer = transfers[id] ?: error("Download expired")
                            transfer.stream.close()
                            context.contentResolver.update(transfer.uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                            transfers.remove(id)
                        }
                        "cancel" -> transfers.remove(id)?.let { t -> try { t.stream.close() } finally { context.contentResolver.delete(t.uri, null, null) } }
                        else -> error("Unknown download operation")
                    }
                    main.post { result.success(response) }
                } catch (e: Exception) { main.post { result.error("DOWNLOAD_FAILED", e.message, null) } }
            }
        }
    }
    fun detach() {
        channel.setMethodCallHandler(null)
        worker.execute {
            transfers.values.forEach { t -> try { t.stream.close() } finally { context.contentResolver.delete(t.uri, null, null) } }
            transfers.clear()
        }
        worker.shutdown()
    }
}

package com.example.remote_control

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class RemoteAudioBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remote_control/audio")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var track: AudioTrack? = null
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        stop()
                        val size = AudioTrack.getMinBufferSize(16000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                        require(size > 0) { "PCM playback unavailable" }
                        track = AudioTrack.Builder()
                            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                            .setAudioFormat(AudioFormat.Builder().setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                            .setBufferSizeInBytes(size * 4).setTransferMode(AudioTrack.MODE_STREAM).build().also { it.play() }
                        result.success(null)
                    }
                    "write" -> {
                        val data = call.arguments as ByteArray
                        val target = track ?: throw IllegalStateException("Playback stopped")
                        worker.execute {
                            try {
                                var offset = 0
                                while (offset < data.size && track === target) {
                                    val written = target.write(data, offset, data.size - offset, AudioTrack.WRITE_BLOCKING)
                                    check(written > 0) { "Audio playback failed: $written" }
                                    offset += written
                                }
                                main.post { result.success(null) }
                            } catch (e: Exception) { main.post { result.error("AUDIO", e.message, null) } }
                        }
                    }
                    "stop" -> { stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("AUDIO", e.message, null) }
        }
    }
    private fun stop() {
        val old = track
        track = null
        runCatching { old?.pause(); old?.flush(); old?.release() }
    }
    fun detach() { channel.setMethodCallHandler(null); stop(); worker.shutdownNow() }
}

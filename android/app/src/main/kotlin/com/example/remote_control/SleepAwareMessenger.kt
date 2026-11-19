package com.example.remote_control

import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.atomic.AtomicBoolean

/** Protect asynchronous native operations until their actual reply, not just dispatch. */
class SleepAwareMessenger(private val target: BinaryMessenger,
    private val begin: (String) -> Long = ScreenOffShutdown::begin,
    private val end: (Long) -> Unit = ScreenOffShutdown::end) : BinaryMessenger by target {
    private fun track(channel: String, handler: BinaryMessenger.BinaryMessageHandler?): BinaryMessenger.BinaryMessageHandler? =
        handler?.let { original -> BinaryMessenger.BinaryMessageHandler { message, reply ->
            val token = begin("native:$channel")
            val done = AtomicBoolean()
            fun finish() { if (done.compareAndSet(false, true)) end(token) }
            try { original.onMessage(message) { result -> try { reply.reply(result) } finally { finish() } } }
            catch (e: Throwable) { finish(); throw e }
        } }
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        target.setMessageHandler(channel, track(channel, handler))
    }
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?, queue: BinaryMessenger.TaskQueue?) {
        target.setMessageHandler(channel, track(channel, handler), queue)
    }
}

package com.example.remote_control

import android.content.Context
import android.graphics.Typeface
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import com.termux.terminal.KeyHandler
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalView
import com.termux.view.TerminalViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.lang.reflect.Proxy

/** Termux owns emulation and input; Dart owns the SSH transport and lifetime. */
class NativeTerminalBridge(messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val channel = MethodChannel(messenger, "remote_control/native_terminal")
    private val sessions = mutableMapOf<Int, RemoteSession>()

    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Int>("id")!!
            if (call.method == "create") sessions.getOrPut(id) { RemoteSession(id) }
            val session = sessions[id]
            if (session == null) { result.error("SESSION_CLOSED", "Terminal closed", null); return@setMethodCallHandler }
            try {
                when (call.method) {
                    "create" -> Unit
                    "compatibility" -> session.engine.setWindowsResizeCompatibility(call.argument<Boolean>("windows") == true)
                    "append" -> session.append(call.argument<String>("text")!!)
                    "paste" -> session.engine.paste(call.argument<String>("text")!!)
                    "key" -> session.key(call.argument<String>("key")!!, call.argument<Boolean>("ctrl") == true, call.argument<Boolean>("alt") == true)
                    "text" -> { result.success(if (call.argument<Boolean>("all") == true) session.engine.screen.transcriptText else session.view?.selectedText.orEmpty()); return@setMethodCallHandler }
                    "keyboard" -> session.view?.let {
                        val ime = it.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                        if (call.argument<Boolean>("show") == true) { it.requestFocus(); ime.showSoftInput(it, InputMethodManager.SHOW_IMPLICIT) }
                        else ime.hideSoftInputFromWindow(it.windowToken, 0)
                    }
                    "bottom" -> session.view?.let { it.topRow = 0; it.invalidate() }
                    "style" -> session.view?.setTextSize(((call.argument<Double>("fontSize") ?: 13.0) * session.view!!.resources.displayMetrics.density).toInt())
                    "dispose" -> { session.view?.clearFocus(); sessions.remove(id) }
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (e: Exception) { result.error("TERMINAL_ERROR", e.message, null) }
        }
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val values = args as Map<*, *>
        val session = sessions.getOrPut((values["id"] as Number).toInt()) { RemoteSession((values["id"] as Number).toInt()) }
        val view = TerminalView(context, null)
        view.isFocusable = true
        view.isFocusableInTouchMode = true
        view.setTextSize(((values["fontSize"] as Number).toDouble() * context.resources.displayMetrics.density).toInt())
        view.setTypeface(Typeface.MONOSPACE)
        view.setTerminalViewClient(ViewClient(view))
        session.view = view
        android.util.Log.i("NativeTerminal", "View attached to session ${session.id}")
        view.attachSession(session)
        return object : PlatformView {
            override fun getView(): View = view
            override fun dispose() { view.setTerminalCursorBlinkerState(false, false); if (session.view === view) session.view = null }
        }
    }

    private inner class RemoteSession(val id: Int) : TerminalSession("", "", emptyArray(), emptyArray(), 10000, null) {
        var view: TerminalView? = null
        private var protocol = false
        private val client = Proxy.newProxyInstance(TerminalSessionClient::class.java.classLoader, arrayOf(TerminalSessionClient::class.java)) { _, method, _ ->
            if (method.name == "onTerminalCursorStateChange") view?.invalidate()
            null
        } as TerminalSessionClient
        val engine = TerminalEmulator(this, 80, 24, 8, 16, 10000, client)
        override fun getEmulator(): TerminalEmulator = engine
        override fun getTitle(): String? = engine.title
        override fun isRunning(): Boolean = true
        override fun finishIfRunning() = Unit
        override fun reset() { engine.reset(); view?.onScreenUpdated() }
        override fun updateSize(columns: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int) {
            engine.resize(columns, rows, cellWidthPixels, cellHeightPixels)
            android.util.Log.i("NativeTerminal", "Grid $columns x $rows, cell $cellWidthPixels x $cellHeightPixels")
            channel.invokeMethod("resize", mapOf("id" to id, "width" to columns, "height" to rows, "pixelWidth" to columns * cellWidthPixels, "pixelHeight" to rows * cellHeightPixels))
        }
        override fun write(data: ByteArray, offset: Int, count: Int) {
            channel.invokeMethod("output", mapOf("id" to id, "data" to data.copyOfRange(offset, offset + count), "protocol" to protocol))
        }
        fun append(text: String) {
            val bytes = text.toByteArray(Charsets.UTF_8)
            protocol = true
            try { engine.append(bytes, bytes.size) } finally { protocol = false }
            view?.onScreenUpdated()
        }
        override fun titleChanged(oldTitle: String?, newTitle: String?) = Unit
        override fun onColorsChanged() { view?.onScreenUpdated() }
        override fun onBell() = Unit
        override fun onCopyTextToClipboard(text: String) { channel.invokeMethod("copy", mapOf("id" to id, "text" to text)) }
        // Route through the Flutter confirmation flow so multiline paste remains reviewable.
        override fun onPasteTextFromClipboard() { channel.invokeMethod("pasteRequest", mapOf("id" to id)) }
        fun key(name: String, ctrl: Boolean, alt: Boolean) {
            val code = mapOf("enter" to KeyEvent.KEYCODE_ENTER, "escape" to KeyEvent.KEYCODE_ESCAPE, "tab" to KeyEvent.KEYCODE_TAB, "home" to KeyEvent.KEYCODE_MOVE_HOME, "end" to KeyEvent.KEYCODE_MOVE_END, "arrowUp" to KeyEvent.KEYCODE_DPAD_UP, "arrowDown" to KeyEvent.KEYCODE_DPAD_DOWN, "arrowLeft" to KeyEvent.KEYCODE_DPAD_LEFT, "arrowRight" to KeyEvent.KEYCODE_DPAD_RIGHT, "pageUp" to KeyEvent.KEYCODE_PAGE_UP, "pageDown" to KeyEvent.KEYCODE_PAGE_DOWN)[name] ?: return
            val modifiers = (if (ctrl) KeyHandler.KEYMOD_CTRL else 0) or (if (alt) KeyHandler.KEYMOD_ALT else 0)
            KeyHandler.getCode(code, modifiers, engine.isCursorKeysApplicationMode, engine.isKeypadApplicationMode)?.let { write(it) }
        }
    }

    private class ViewClient(private val view: TerminalView) : TerminalViewClient {
        override fun onScale(scale: Float): Float = scale
        override fun onSingleTapUp(e: MotionEvent) { view.requestFocus(); (view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(view, InputMethodManager.SHOW_IMPLICIT) }
        override fun shouldBackButtonBeMappedToEscape() = false
        override fun shouldEnforceCharBasedInput() = false
        override fun shouldUseCtrlSpaceWorkaround() = false
        override fun isTerminalViewSelected() = true
        override fun copyModeChanged(copyMode: Boolean) = Unit
        override fun onKeyDown(keyCode: Int, e: KeyEvent, session: TerminalSession) = false
        override fun onKeyUp(keyCode: Int, e: KeyEvent) = false
        override fun onLongPress(event: MotionEvent) = false
        override fun readControlKey() = false
        override fun readAltKey() = false
        override fun readShiftKey() = false
        override fun readFnKey() = false
        override fun onCodePoint(codePoint: Int, ctrlDown: Boolean, session: TerminalSession) = false
        override fun onEmulatorSet() { view.setTerminalCursorBlinkerState(true, true) }
        override fun logError(tag: String, message: String) = Unit
        override fun logWarn(tag: String, message: String) = Unit
        override fun logInfo(tag: String, message: String) = Unit
        override fun logDebug(tag: String, message: String) = Unit
        override fun logVerbose(tag: String, message: String) = Unit
        override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) = Unit
        override fun logStackTrace(tag: String, e: Exception) = Unit
    }
}

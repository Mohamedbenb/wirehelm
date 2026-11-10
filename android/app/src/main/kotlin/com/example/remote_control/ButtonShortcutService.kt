package com.example.remote_control

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import com.nodecockpit.customization.FeaturePolicy
import org.json.JSONObject
import java.util.concurrent.Executors

class ButtonShortcutService : Service() {
    companion object {
        private const val CHANNEL = "screen_off_buttons"
        private const val NOTICE = 4220
        private const val STOP = "com.example.remote_control.STOP_BUTTON_SHORTCUTS"
        private const val READY = "WIREHELM_KEYS_READY"
        private const val OBSERVE_BUTTONS = """
            [ "$(id -u)" = 0 ] || exit 1
            for input in /sys/class/input/event*; do
                [ "$(cat "${'$'}input/device/name" 2>/dev/null)" = gpio_keys ] || continue
                node="/dev/input/$(basename "${'$'}input")"
                [ -c "${'$'}node" ] || exit 1
                exec 3<&0
                /system/bin/getevent -lt "${'$'}node" &
                observer=$!
                ( read -r unused <&3; kill "${'$'}observer" 2>/dev/null ) &
                guard=$!
                printf 'WIREHELM_KEYS_READY\n'
                wait "${'$'}observer"
                result=$?
                kill "${'$'}guard" 2>/dev/null
                exit "${'$'}result"
            done
            exit 1
        """

        @Volatile private var state = "Stopped"
        @Volatile private var error = ""
        internal var torchExpiry: (() -> Unit)? = null
        private fun supported() = android.os.Process.myUid() in 10000..19999 &&
            FeaturePolicy.supported(Build.VERSION.SDK_INT, Build.FINGERPRINT)
        private fun prefs(context: Context) = context.getSharedPreferences(CHANNEL, Context.MODE_PRIVATE)
        private fun powerAvailable(context: Context) = runCatching {
            val resolver = context.contentResolver
            when (Settings.Secure.getInt(resolver, "double_tap_power_button_gesture_enabled", -1)) {
                0 -> true
                -1 -> Settings.Secure.getInt(resolver, "camera_double_tap_power_gesture_disabled", 0) == 1
                else -> false
            }
        }.getOrDefault(false)
        private fun read(context: Context) = prefs(context).let {
            ButtonShortcutSettings(ButtonAction.parse(it.getString("up", null)),
                ButtonAction.parse(it.getString("down", null)), it.getLong("holdMs", 800),
                ButtonShortcutSettings.extraKeys.associateWith { key -> ButtonAction.parse(it.getString(key, null)) },
                it.getInt("torchMinutes", 5))
        }

        fun status(context: Context): JSONObject {
            if (supported()) runCatching { ButtonShortcutActions.finishDnd(context) }
            val settings = read(context)
            return JSONObject().put("up", settings.up.id).put("down", settings.down.id)
                .put("extra", JSONObject(settings.extra.mapValues { it.value.id }))
                .put("torchMinutes", settings.torchMinutes)
                .put("holdMs", settings.holdMs).put("state", state).put("error", error)
                .put("supported", supported()).put("dndAccess", ButtonShortcutActions.dndAccess(context))
                .put("alarmAccess", supported() && ButtonShortcutActions.canSchedule(context))
                .put("powerAvailable", supported() && powerAvailable(context))
        }

        fun save(context: Context, up: String, down: String, holdMs: Long, extra: Map<String, String>, torchMinutes: Int): JSONObject {
            require(ButtonAction.entries.any { it.id == up } && ButtonAction.entries.any { it.id == down })
            require(holdMs in 500..2000)
            require(torchMinutes in 1..15)
            require(extra.keys.all(ButtonShortcutSettings.extraKeys::contains) &&
                extra.values.all { id -> ButtonAction.entries.any { it.id == id } })
            val edit = prefs(context).edit().putString("up", up).putString("down", down)
                .putLong("holdMs", holdMs).putInt("torchMinutes", torchMinutes)
            for (key in ButtonShortcutSettings.extraKeys) edit.putString(key, extra[key])
            check(edit.commit()) { "Could not save button shortcuts" }
            if (!read(context).assigned()) stop(context)
            return status(context)
        }

        fun start(context: Context): JSONObject {
            check(supported()) { "This feature requires the supported rooted Pixel and owner profile" }
            val settings = read(context)
            check(settings.assigned()) { "Assign a button first" }
            if (state == "Stopped") {
                error = ""
                state = "Starting"
                try {
                    context.startForegroundService(Intent(context, ButtonShortcutService::class.java))
                } catch (e: Exception) {
                    state = "Stopped"
                    throw e
                }
            }
            return status(context)
        }

        fun stop(context: Context): JSONObject {
            context.stopService(Intent(context, ButtonShortcutService::class.java))
            state = "Stopped"
            return status(context)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val reader = Executors.newSingleThreadExecutor()
    private val gesture = ButtonHoldGesture()
    private val powerGesture = PowerTapGesture()
    private lateinit var audio: AudioManager
    private lateinit var power: PowerManager
    private lateinit var camera: CameraManager
    private var cameraId: String? = null
    private var torchOn: Boolean? = null
    private var timedTorchUntil = 0L
    private val torchTimer = Runnable { expireTorch() }
    private var tapWakeLock: PowerManager.WakeLock? = null
    private var tapDeadline = 0L
    private var screenWasOff = false
    private var screenOnAt = -1L
    private val finishTaps = Runnable {
        val onTime = SystemClock.elapsedRealtime() <= tapDeadline + 250
        clearTapTimer()
        if (running && onTime) {
            val settings = read(this)
            if (powerGesture.waiting()) {
                powerGesture.finish(audioInactive() && powerAvailable(this), settings)
                    ?.let { runAction(it, settings, fromPower = true) }
            } else gesture.finishTaps(volumeEligible(), settings)?.let { runAction(it, settings) }
        } else cancelGesture()
    }
    @Volatile private var running = false
    private val processLock = Any()
    private var process: Process? = null
    private var audioRegistered = false
    private var cameraRegistered = false
    private var screenRegistered = false
    private val startupDeadline = Runnable {
        if (running && state == "Starting") {
            error = "Physical buttons did not start. Check Wirehelm’s root authorization."
            stopSelf()
        }
    }

    private val playback = object : AudioManager.AudioPlaybackCallback() {
        override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>) {
            if (configs.isNotEmpty()) cancelGesture()
        }
    }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_OFF) {
                screenWasOff = true
                screenOnAt = -1
            } else if (intent.action == Intent.ACTION_SCREEN_ON) {
                if (screenWasOff) screenOnAt = SystemClock.elapsedRealtime()
                screenWasOff = false
            }
            // Power taps can cause the screen transition. Volume gestures cannot span it.
            gesture.cancel()
            if (!powerGesture.waiting()) clearTapTimer()
        }
    }
    private val torch = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(id: String, enabled: Boolean) {
            if (id == cameraId) {
                torchOn = enabled
                if (!enabled && timedTorchUntil != 0L) clearTorchTimer()
            }
        }
        override fun onTorchModeUnavailable(id: String) {
            if (id == cameraId) {
                torchOn = null
                if (timedTorchUntil != 0L) clearTorchTimer()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Screen-off buttons", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, NOTICE,
            Intent(this, ButtonShortcutService::class.java).setAction(STOP),
            PendingIntent.FLAG_IMMUTABLE)
        startForeground(NOTICE, Notification.Builder(this, CHANNEL).setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Screen-off buttons").setContentText("Watching for your assigned button gestures")
            .setOngoing(true).addAction(Notification.Action.Builder(null, "Stop", stop).build()).build())
        try {
            audio = getSystemService(AudioManager::class.java)
            power = getSystemService(PowerManager::class.java)
            screenWasOff = !power.isInteractive
            camera = getSystemService(CameraManager::class.java)
            audio.registerAudioPlaybackCallback(playback, main)
            audioRegistered = true
            runCatching {
                cameraId = camera.cameraIdList.firstOrNull { id ->
                    val c = camera.getCameraCharacteristics(id)
                    c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK &&
                        c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                }
                camera.registerTorchCallback(torch, main)
                cameraRegistered = true
            }
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(screen, filter, Context.RECEIVER_NOT_EXPORTED)
            else @Suppress("DEPRECATION") registerReceiver(screen, filter)
            screenRegistered = true
            running = true
            torchExpiry = { expireTorch() }
            main.postDelayed(startupDeadline, 15000)
            reader.execute(::readButtons)
        } catch (e: Exception) {
            error = "Could not start the button monitor"
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun readButtons() {
        try {
            val input = ProcessBuilder("su", "-c", OBSERVE_BUTTONS).redirectErrorStream(true).start()
            synchronized(processLock) {
                if (!running) {
                    input.outputStream.close()
                    input.destroy()
                    return
                }
                process = input
            }
            input.inputStream.bufferedReader().useLines { lines ->
                for (line in lines) {
                    if (!running) break
                    if (line == READY) main.post {
                        main.removeCallbacks(startupDeadline)
                        if (running) state = "Listening"
                    }
                    else if (line.contains("SYN_DROPPED")) main.post {
                        clearTapTimer()
                        gesture.reset()
                        powerGesture.reset()
                    }
                    else ButtonEvent.parse(line)?.let { event -> main.post { receive(event) } }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("WirehelmButtons", "Button monitor ended", e)
        } finally {
            main.post {
                if (running) {
                    error = "Physical button input unavailable. Check Wirehelm’s root authorization."
                    stopSelf()
                }
            }
        }
    }

    private fun receive(event: ButtonEvent) {
        if (!running) return
        clearTapTimer()
        val settings = read(this)
        val idle = audioInactive()
        gesture.accept(event, idle && !power.isInteractive, settings)?.let { runAction(it, settings) }
        val isPower = event.button == PhysicalButton.POWER
        powerGesture.accept(event, isPower && idle && powerAvailable(this),
            isPower && event.down && startedScreenOff(event), settings)
        val delay = when {
            powerGesture.waiting() -> PowerTapGesture.QUIET_MS
            gesture.waitingForThirdTap() -> ButtonHoldGesture.TAP_GAP_MS
            else -> 0L
        }
        if (delay > 0) {
            tapDeadline = SystemClock.elapsedRealtime() + delay
            tapWakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "wirehelm:volume-tap").apply {
                setReferenceCounted(false)
                acquire(delay + 250)
            }
            main.postDelayed(finishTaps, delay)
        }
    }

    private fun clearTapTimer() {
        main.removeCallbacks(finishTaps)
        tapWakeLock?.let { if (it.isHeld) it.release() }
        tapWakeLock = null
    }

    private fun cancelGesture() {
        clearTapTimer()
        gesture.cancel()
        powerGesture.cancel()
    }

    private fun startedScreenOff(event: ButtonEvent): Boolean {
        if (screenWasOff || !power.isInteractive) return true
        val elapsed = SystemClock.elapsedRealtime()
        if (screenOnAt < 0 || elapsed - screenOnAt !in 0..300) return false
        // Compare only timestamps that can be correlated with a recent local clock.
        return listOf(SystemClock.uptimeMillis(), elapsed, System.currentTimeMillis()).any { now ->
            val age = now - event.timeMs
            age in 0..350 && elapsed - age <= screenOnAt
        }
    }

    private fun audioInactive() = runCatching {
        audio.mode == AudioManager.MODE_NORMAL &&
            !audio.isMusicActive && audio.activePlaybackConfigurations.isEmpty()
    }.getOrDefault(false)
    private fun volumeEligible() = !power.isInteractive && audioInactive()

    private fun runAction(action: ButtonAction, settings: ButtonShortcutSettings, fromPower: Boolean = false) {
        if (!audioInactive() || (if (fromPower) !powerAvailable(this) else power.isInteractive)) return
        runCatching {
            when (action) {
                ButtonAction.TORCH -> {
                    camera.setTorchMode(requireNotNull(cameraId), !requireNotNull(torchOn))
                    if (timedTorchUntil != 0L) clearTorchTimer()
                }
                ButtonAction.TIMED_TORCH -> startTimedTorch(settings.torchMinutes)
                ButtonAction.RINGER -> {
                    audio.ringerMode = if (audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE) {
                        AudioManager.RINGER_MODE_NORMAL
                    } else AudioManager.RINGER_MODE_VIBRATE
                }
                ButtonAction.DND -> ButtonShortcutActions.startDnd(this)
                ButtonAction.BOOKMARK -> ButtonShortcutActions.addBookmark(this)
                ButtonAction.RESUME_MEDIA -> {
                    audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY))
                    audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY))
                }
                ButtonAction.NONE -> Unit
            }
            error = ""
        }.onFailure { error = it.message ?: "Could not run the selected shortcut" }
    }

    private fun startTimedTorch(minutes: Int) {
        val id = checkNotNull(cameraId) { "Flashlight unavailable" }
        val enabled = checkNotNull(torchOn) { "Flashlight unavailable" }
        check(!enabled || timedTorchUntil != 0L) { "Flashlight is already on" }
        val previous = timedTorchUntil
        val delay = minutes * 60_000L
        val deadline = SystemClock.elapsedRealtime() + delay
        ButtonShortcutActions.schedule(this, ButtonShortcutActions.TORCH_ALARM, deadline)
        try {
            if (!enabled) camera.setTorchMode(id, true)
        } catch (failure: Exception) {
            if (previous == 0L) ButtonShortcutActions.cancel(this, ButtonShortcutActions.TORCH_ALARM)
            else runCatching { ButtonShortcutActions.schedule(this, ButtonShortcutActions.TORCH_ALARM, previous) }
            throw failure
        }
        timedTorchUntil = deadline
        main.removeCallbacks(torchTimer)
        main.postDelayed(torchTimer, delay)
    }

    private fun clearTorchTimer() {
        timedTorchUntil = 0L
        main.removeCallbacks(torchTimer)
        ButtonShortcutActions.cancel(this, ButtonShortcutActions.TORCH_ALARM)
    }

    private fun expireTorch(force: Boolean = false) {
        if (timedTorchUntil == 0L || (!force && SystemClock.elapsedRealtime() < timedTorchUntil)) return
        runCatching { camera.setTorchMode(requireNotNull(cameraId), false) }
            .onFailure { error = it.message ?: "Could not turn off the timed flashlight" }
        clearTorchTimer()
    }

    override fun onDestroy() {
        running = false
        main.removeCallbacks(startupDeadline)
        cancelGesture()
        torchExpiry = null
        expireTorch(force = true)
        state = "Stopped"
        if (screenRegistered) unregisterReceiver(screen)
        if (audioRegistered) audio.unregisterAudioPlaybackCallback(playback)
        if (cameraRegistered) camera.unregisterTorchCallback(torch)
        synchronized(processLock) {
            process?.let { input ->
                runCatching { input.outputStream.close() }
                input.destroy()
            }
            process = null
        }
        reader.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

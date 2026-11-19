package com.example.remote_control

import android.app.ActivityManager
import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import com.nodecockpit.customization.ProcessWork
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Own app runtime only. Never force-stops the package, UID, SystemUI or Photos. */
object ScreenOffShutdown {
    private val main = Handler(Looper.getMainLooper())
    private val policy = ScreenOffExitPolicy()
    private val serial = AtomicLong()
    private val dartWork = ConcurrentHashMap.newKeySet<Long>()
    private val work = ConcurrentHashMap<Long, String>()
    private var context: Context? = null
    private var alarm: AlarmManager? = null
    private val expiry = AlarmManager.OnAlarmListener { evaluate() }
    private val check = Runnable { evaluate() }
    private val changedCheck = Runnable { if (policy.remaining(SystemClock.elapsedRealtime()) == 0L) evaluate() }

    // Attach only for a real Flutter/UI runtime. An on-demand native provider
    // process must not enter a kill/restart cycle servicing SystemUI reports.
    fun attach(c: Context) {
        if (context != null) return
        context = c.applicationContext
        ProcessWork.onChanged { changed() }
        alarm = c.getSystemService(AlarmManager::class.java)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_SCREEN_OFF) off() else on()
            }
        }
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF).apply { addAction(Intent.ACTION_SCREEN_ON) }
        if (Build.VERSION.SDK_INT >= 33) c.applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else c.applicationContext.registerReceiver(receiver, filter)
        if (!c.getSystemService(PowerManager::class.java).isInteractive) off()
    }
    @Synchronized fun begin(reason: String): Long = serial.incrementAndGet().also { work[it] = reason.take(80) }
    fun beginDart(reason: String): Long = begin(reason).also { dartWork.add(it) }
    fun detachRuntime() { dartWork.toList().forEach { end(it) }; dartWork.clear() }
    @Synchronized fun end(token: Long) { work.remove(token); dartWork.remove(token); changed() }
    fun changed() { main.removeCallbacks(changedCheck); main.postDelayed(changedCheck, 300) }
    private fun on() {
        policy.screenOn(); main.removeCallbacks(check); main.removeCallbacks(changedCheck); alarm?.cancel(expiry)
        record("screen on", emptyList())
    }
    private fun off() {
        policy.screenOff(SystemClock.elapsedRealtime())
        val delay = policy.remaining(SystemClock.elapsedRealtime())
        main.removeCallbacks(check); alarm?.cancel(expiry)
        main.postDelayed(check, delay)
        // Listener alarm does not restart an already-dead app. No held wake lock.
        runCatching { alarm?.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime()+delay, "WirehelmScreenOffExit", expiry, main) }
        record("waiting 30 seconds", emptyList())
    }
    @Suppress("DEPRECATION")
    private fun requiredServices(c: Context): List<String> {
        // Android exposes an app's own services here. A queued start also protects
        // the interval before onCreate; same-process services cannot outlive a kill.
        return c.getSystemService(ActivityManager::class.java).getRunningServices(100)
            .filter { it.uid == android.os.Process.myUid() && it.process == c.packageName && (it.started || it.foreground || it.clientCount > 0) }
            .map { it.service.shortClassName }
    }
    @Synchronized private fun evaluate() {
        val c = context ?: return
        if (c.getSystemService(PowerManager::class.java).isInteractive) { on(); return }
        if (policy.remaining(SystemClock.elapsedRealtime()) != 0L) return
        main.removeCallbacks(check); alarm?.cancel(expiry)
        val reasons = try { work.values.toList()+ProcessWork.reasons()+requiredServices(c) }
            catch (e: RuntimeException) { record("service check unavailable; kept alive", emptyList()); return }
        if (!policy.shouldExit(SystemClock.elapsedRealtime(), false, reasons.isNotEmpty())) { record("required work kept alive", reasons); return }
        // Recheck at the point of exit. New work on the main thread cannot race
        // this decision; background operations claim their token before dispatch.
        if (work.isNotEmpty() || ProcessWork.reasons().isNotEmpty() || c.getSystemService(PowerManager::class.java).isInteractive) return
        record("idle process exit", emptyList())
        android.os.Process.killProcess(android.os.Process.myPid())
    }
    private fun record(state: String, reasons: List<String>) {
        val c = context ?: return
        c.createDeviceProtectedStorageContext().getSharedPreferences("screen_off_shutdown", Context.MODE_PRIVATE).edit()
            .putString("state", state).putString("reasons", reasons.distinct().sorted().joinToString(","))
            .putInt("pid", android.os.Process.myPid()).putLong("elapsed", SystemClock.elapsedRealtime()).commit()
    }
    fun status(): Map<String, Any> = mapOf("delayMs" to ScreenOffExitPolicy.DELAY_MS, "pendingCalls" to work.size,
        "remainingMs" to policy.remaining(SystemClock.elapsedRealtime()))
}

package com.example.remote_control

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Session-scoped protection. No automatic listener after process death, reboot or expiry. */
class AdbRelayService : Service() {
    companion object {
        private const val CHANNEL = "remote_control_adb"
        private const val ID = 4218
        private const val STOP = "com.example.remote_control.STOP_REMOTE_ADB"
        @Volatile var isRunning = false
            private set
        fun start(context: Context) { context.startForegroundService(Intent(context, AdbRelayService::class.java)) }
        fun update(context: Context, expiresAt: Long) {
            context.startService(Intent(context, AdbRelayService::class.java).putExtra("expiresAt", expiresAt))
        }
        fun stop(context: Context) { context.stopService(Intent(context, AdbRelayService::class.java)) }
    }
    private var lock: PowerManager.WakeLock? = null
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Remote ADB", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        isRunning = true
        TsnetBridge.observeRemoteAdb(this, this)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deadline = intent?.getLongExtra("expiresAt", 0) ?: 0
        val open = PendingIntent.getActivity(this, 4218, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 4219, Intent(this, AdbRelayService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL).setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Remote ADB").setContentText(if (deadline > 0) "Connected in background · session expires automatically" else "Starting protected connection…")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(null, "Stop / restore", stop).build())
        if (deadline > 0) notification.setWhen(deadline).setUsesChronometer(true).setChronometerCountDown(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) startForeground(ID, notification.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        else startForeground(ID, notification.build())
        lock?.let { if (it.isHeld) it.release() }
        lock = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "node_cockpit:remote_adb").apply {
            setReferenceCounted(false)
            acquire(if (deadline > 0) (deadline - System.currentTimeMillis() + 20000).coerceIn(1000, 86420000) else 60000)
        }
        if (intent?.action == STOP) TsnetBridge.stopRemoteAdb()
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        lock?.let { if (it.isHeld) it.release() }; lock = null
        isRunning = false
        TsnetBridge.releaseRemoteAdb(this)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

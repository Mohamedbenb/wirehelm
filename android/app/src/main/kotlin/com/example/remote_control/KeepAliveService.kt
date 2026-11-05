package com.example.remote_control

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID =
            "remote_control_ssh"

        const val NOTIFICATION_ID =
            4217

        @Volatile
        var isRunning: Boolean =
            false
            private set
    }

    private var wakeLock:
            PowerManager.WakeLock? =
        null

    override fun onCreate() {
        super.onCreate()

        isRunning = true

        createNotificationChannel()

        acquireWakeLock()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        val notification =
            createNotification()

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.Q
        ) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo
                    .FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(
                NOTIFICATION_ID,
                notification
            )
        }

        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()

        isRunning = false

        super.onDestroy()
    }

    override fun onBind(
        intent: Intent?
    ): IBinder? {
        return null
    }

    private fun acquireWakeLock() {
        if (
            wakeLock?.isHeld ==
            true
        ) {
            return
        }

        val powerManager =
            getSystemService(
                Context.POWER_SERVICE
            ) as PowerManager

        wakeLock =
            powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "remote_control:ssh_keep_alive"
            ).apply {
                setReferenceCounted(
                    false
                )

                acquire()
            }
    }

    private fun releaseWakeLock() {
        try {
            if (
                wakeLock?.isHeld ==
                true
            ) {
                wakeLock?.release()
            }
        } catch (
            _: Exception
        ) {
        }

        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val manager =
            getSystemService(
                NotificationManager::class.java
            )

        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "SSH connection",
                NotificationManager
                    .IMPORTANCE_LOW
            ).apply {
                description =
                    "Keeps active SSH connections alive"

                setShowBadge(
                    false
                )
            }

        manager.createNotificationChannel(
            channel
        )
    }

    private fun createNotification():
            Notification {

        val openAppIntent =
            Intent(
                this,
                MainActivity::class.java
            ).apply {
                flags =
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

        val builder =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.O
            ) {
                Notification.Builder(
                    this,
                    CHANNEL_ID
                )
            } else {
                Notification.Builder(
                    this
                )
            }

        return builder
            .setContentTitle(
                "Remote Control"
            )
            .setContentText(
                "Keeping SSH connection alive"
            )
            .setSmallIcon(
                R.mipmap.ic_launcher
            )
            .setContentIntent(
                pendingIntent
            )
            .setOngoing(
                true
            )
            .setOnlyAlertOnce(
                true
            )
            .setCategory(
                Notification.CATEGORY_SERVICE
            )
            .build()
    }
}
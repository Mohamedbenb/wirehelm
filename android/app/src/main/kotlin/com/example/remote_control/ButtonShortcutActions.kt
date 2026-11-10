package com.example.remote_control

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal object ButtonShortcutActions {
    const val TORCH_ALARM = "com.example.remote_control.TIMED_BUTTON_TORCH"
    const val DND_ALARM = "com.example.remote_control.TIMED_BUTTON_DND"
    private const val DND_UNTIL = "button_dnd_until"
    private const val DND_BOOT = "button_dnd_boot"
    private fun prefs(context: Context) = context.getSharedPreferences("screen_off_button_actions", Context.MODE_PRIVATE)
    private fun alarm(context: Context, action: String) = PendingIntent.getBroadcast(
        context, 0, Intent(context, ButtonShortcutAlarmReceiver::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE,
    )
    fun canSchedule(context: Context): Boolean =
        context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    fun schedule(context: Context, action: String, deadline: Long) {
        val manager = context.getSystemService(AlarmManager::class.java)
        check(manager.canScheduleExactAlarms()) { "Allow Alarms & reminders to use timed shortcuts" }
        manager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, deadline, alarm(context, action))
    }

    fun cancel(context: Context, action: String) {
        context.getSystemService(AlarmManager::class.java).cancel(alarm(context, action))
    }

    fun openSettings(context: Context, type: String) {
        val intent = when (type) {
            "policy" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            "alarms" -> Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
            "power" -> Intent(Settings.ACTION_SETTINGS)
            else -> error("Unknown shortcut settings")
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun dndAccess(context: Context) =
        context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted

    private fun boot(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    @Synchronized fun startDnd(context: Context) {
        check(dndAccess(context)) { "Allow Do Not Disturb access first" }
        val boot = boot(context)
        check(boot >= 0) { "Could not verify the current boot" }
        val deadline = SystemClock.elapsedRealtime() + 30 * 60_000L
        val saved = prefs(context)
        val previous = saved.getLong(DND_UNTIL, 0)
        val previousBoot = saved.getInt(DND_BOOT, -1)
        check(saved.edit().putLong(DND_UNTIL, deadline).putInt(DND_BOOT, boot).commit()) { "Could not save Do Not Disturb timer" }
        try {
            schedule(context, DND_ALARM, deadline)
            // On the supported firmware this controls Wirehelm's implicit rule only.
            context.getSystemService(NotificationManager::class.java)
                .setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        } catch (e: Exception) {
            saved.edit().putLong(DND_UNTIL, previous).putInt(DND_BOOT, previousBoot).commit()
            if (previous > 0 && previousBoot == boot) {
                runCatching { schedule(context, DND_ALARM, previous) }
            } else cancel(context, DND_ALARM)
            throw e
        }
    }

    @Synchronized fun finishDnd(context: Context, force: Boolean = false) {
        val saved = prefs(context)
        val deadline = saved.getLong(DND_UNTIL, 0)
        if (deadline == 0L || !dndAccess(context)) return
        if (!force && saved.getInt(DND_BOOT, -1) == boot(context) &&
            SystemClock.elapsedRealtime() < deadline && canSchedule(context)) {
            val scheduled = PendingIntent.getBroadcast(context, 0,
                Intent(context, ButtonShortcutAlarmReceiver::class.java).setAction(DND_ALARM),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
            if (scheduled == null) schedule(context, DND_ALARM, deadline)
            return
        }
        context.getSystemService(NotificationManager::class.java)
            .setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        saved.edit().remove(DND_UNTIL).remove(DND_BOOT).commit()
        cancel(context, DND_ALARM)
    }

    private fun readBookmarks(context: Context) = JSONArray(prefs(context).getString("bookmarks", "[]"))
    private fun saveBookmarks(context: Context, entries: JSONArray) {
        check(prefs(context).edit().putString("bookmarks", entries.toString()).commit()) { "Could not save bookmark" }
    }

    @Synchronized fun addBookmark(context: Context) {
        val old = readBookmarks(context)
        val entries = JSONArray().put(JSONObject().put("id", UUID.randomUUID().toString())
            .put("at", System.currentTimeMillis()).put("note", ""))
        for (index in 0 until minOf(old.length(), 49)) entries.put(old.getJSONObject(index))
        saveBookmarks(context, entries)
    }

    @Synchronized fun bookmarks(context: Context): JSONObject =
        JSONObject().put("bookmarks", readBookmarks(context))

    @Synchronized fun updateBookmark(context: Context, id: String, note: String): JSONObject {
        require(note.length <= 500)
        val old = readBookmarks(context)
        val entries = JSONArray()
        for (index in 0 until old.length()) {
            val item = old.getJSONObject(index)
            if (item.getString("id") == id) item.put("note", note)
            entries.put(item)
        }
        saveBookmarks(context, entries)
        return JSONObject().put("bookmarks", entries)
    }
}

class ButtonShortcutAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                ButtonShortcutActions.TORCH_ALARM -> ButtonShortcutService.torchExpiry?.invoke()
                ButtonShortcutActions.DND_ALARM -> ButtonShortcutActions.finishDnd(context)
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                    ButtonShortcutActions.finishDnd(context, force = true)
            }
        } catch (error: Exception) {
            android.util.Log.w("WirehelmButtons", "Could not expire timed shortcut", error)
        }
    }
}

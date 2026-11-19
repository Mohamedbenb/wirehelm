package com.example.remote_control.battery

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.os.*
import com.example.remote_control.MainActivity
import com.example.remote_control.R
import java.io.File

/** Dedicated native observer: no Flutter, no wake lock and no periodic wakeup alarm. */
class BatteryUsageService:Service(){
    private lateinit var recorder:BatteryUsageRecorder
    private val main=Handler(Looper.getMainLooper())
    private val observers=mutableListOf<FileObserver>()
    private val refresh=Runnable{recorder.observe()}
    private val periodic=object:Runnable{override fun run(){recorder.observe(true);main.postDelayed(this,15*60*1000L)}}
    private val receiver=object:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){recorder.observe()}}
    override fun onCreate(){
        super.onCreate();recorder=BatteryUsageRecorder.get(this)
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("wirehelm_battery","Battery usage",NotificationManager.IMPORTANCE_LOW).apply{setShowBadge(false)})
        val open=PendingIntent.getActivity(this,8731,Intent(this,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n=Notification.Builder(this,"wirehelm_battery").setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Battery usage tracking")
            .setContentText("Records unplugged sessions · no screen wakeups").setOngoing(true).setOnlyAlertOnce(true).setContentIntent(open).build()
        if(Build.VERSION.SDK_INT>=34)startForeground(8731,n,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(8731,n)
        val filter=IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply{addAction(Intent.ACTION_SCREEN_ON);addAction(Intent.ACTION_SCREEN_OFF)}
        if(Build.VERSION.SDK_INT>=33)registerReceiver(receiver,filter,RECEIVER_NOT_EXPORTED) else registerReceiver(receiver,filter)
        fun watch(dir:File,names:Set<String>){dir.mkdirs();observers.add(object:FileObserver(dir.absolutePath,FileObserver.MOVED_TO or FileObserver.CLOSE_WRITE){
            override fun onEvent(event:Int,path:String?){if(path in names){main.removeCallbacks(refresh);main.postDelayed(refresh,500)}}
        }.also{it.startWatching()})}
        watch(File(createDeviceProtectedStorageContext().dataDir,"shared_prefs"),setOf("local_customization_v1.xml"))
        watch(File(dataDir,"shared_prefs"),setOf("screen_off_buttons.xml","app_network.xml"))
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int{
        if(!recorder.enabled()){stopSelf();return START_NOT_STICKY}
        recorder.start();main.removeCallbacks(periodic);main.postDelayed(periodic,15*60*1000L)
        return START_STICKY
    }
    override fun onDestroy(){observers.forEach{it.stopWatching()};main.removeCallbacksAndMessages(null);unregisterReceiver(receiver);recorder.stopped();super.onDestroy()}
    override fun onBind(intent:Intent?)=null
}

class BatteryUsageBootReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        if(intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED))return
        if(BatteryUsageRecorder.get(context).enabled())runCatching{context.startForegroundService(Intent(context,BatteryUsageService::class.java))}
    }
}

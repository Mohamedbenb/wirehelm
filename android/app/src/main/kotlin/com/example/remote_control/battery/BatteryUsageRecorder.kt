package com.example.remote_control.battery

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Single writer in :battery. Broadcasts/file changes do not acquire a wake lock. */
class BatteryUsageRecorder private constructor(private val context:Context) {
    companion object {
        @Volatile private var instance:BatteryUsageRecorder?=null
        fun get(c:Context):BatteryUsageRecorder=instance ?: synchronized(this){instance ?: BatteryUsageRecorder(c.applicationContext).also{instance=it}}
    }
    private val worker=Executors.newSingleThreadExecutor()
    private val prefs=context.createDeviceProtectedStorageContext().getSharedPreferences("battery_usage",Context.MODE_PRIVATE)
    private val store=BatteryUsageStore(context)
    @Volatile var running=false
    private var session:BatterySession?=null
    private var gate=BatteryDischargeGate()
    private var id=0L
    private var summary=linkedMapOf<String,String>()
    private var configurations=JSONArray()
    private var configChanges=0
    private var baseline:BatteryPowerReport?=null
    private var current:BatteryPowerReport?=null
    private var rootAt=0L
    private var rootError=""
    private var lastSaved=0L
    private var lastEnergyAttempt=0L
    private val ownUid=context.applicationInfo.uid
    private val systemUid=runCatching{context.packageManager.getApplicationInfo("com.android.systemui",0).uid}.getOrDefault(-1)
    fun enabled()=prefs.getBoolean("enabled",false)
    private fun enqueue(action:()->Unit){worker.execute{try{action()}catch(e:Exception){running=false;prefs.edit().putString("error","Tracker interrupted: "+e.javaClass.simpleName).commit();context.stopService(android.content.Intent(context,BatteryUsageService::class.java))}}}
    fun start(){enqueue{if(!running){store.interruptOld();session=null;id=0;gate=BatteryDischargeGate();running=true;prefs.edit().remove("error").commit();capture(true)}}}
    fun observe(force:Boolean=false){enqueue{if(running)capture(force)}}
    fun setOptions(enabled:Boolean,estimates:Boolean):JSONObject=worker.submit<JSONObject>{
        if(!enabled&&running){capture(true);finish("Tracking stopped");running=false}
        prefs.edit().putBoolean("enabled",enabled).putBoolean("estimates",estimates).commit()
        data(0)
    }.get(30,TimeUnit.SECONDS)
    fun state(selected:Long):JSONObject=worker.submit<JSONObject>{if(running)capture(true);data(selected)}.get(30,TimeUnit.SECONDS)
    fun stopped(){enqueue{running=false;persist(true)}}
    private fun point():BatteryPoint? {
        val intent=context.registerReceiver(null,IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val scale=intent.getIntExtra(BatteryManager.EXTRA_SCALE,100)
        val level=intent.getIntExtra(BatteryManager.EXTRA_LEVEL,-1)
        val plugged=intent.getIntExtra(BatteryManager.EXTRA_PLUGGED,-1)
        if(level<0||scale<=0||plugged<0)return null
        val charge=context.getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER).toLong().takeIf{it>0}
        return BatteryPoint(System.currentTimeMillis(),SystemClock.elapsedRealtime(),Settings.Global.getInt(context.contentResolver,Settings.Global.BOOT_COUNT,-1),
            (level*100.0/scale).toInt(),charge,plugged,intent.getIntExtra(BatteryManager.EXTRA_STATUS,0)==BatteryManager.BATTERY_STATUS_CHARGING,
            context.getSystemService(PowerManager::class.java).isInteractive)
    }
    private fun capture(force:Boolean){
        val p=point() ?: return
        val boundary=gate.observe(p.onBattery)
        val config=BatteryCustomizationSource.read(context,p.interactive,p.boot)
        val priorFlags=session?.flags?.toSet();val priorInteractive=session?.last?.interactive;val priorSummary=summary.toMap()
        if(session!=null&&!session!!.accept(p,config.flags,config.known))finish("Monitoring interrupted")
        if(!p.onBattery){
            if(session!=null){if(prefs.getBoolean("estimates",false))energy();finish("Power connected")}
            summary=LinkedHashMap(config.summary);return
        }
        if(session==null){
            // A real battery transition after waiting on external power is complete;
            // enabling/restarting while already unplugged is explicitly partial.
            val partial=boundary?.partial ?: true
            session=BatterySession(p,partial).also{it.flags=config.flags;it.reportingKnown=config.known}
            id=0;configurations=JSONArray();configChanges=0;baseline=null;current=null;rootAt=0;rootError="";lastEnergyAttempt=0
            summary=linkedMapOf();recordConfig(config.summary,p.wall)
            if(prefs.getBoolean("estimates",false)){energy();baseline=current}
            persist(true)
        }else{
            recordConfig(config.summary,p.wall)
            if(prefs.getBoolean("estimates",false)&&p.elapsed-lastEnergyAttempt>=15*60*1000)energy()
            persist(force||priorFlags!=config.flags||priorInteractive!=p.interactive||priorSummary!=summary)
        }
    }
    private fun recordConfig(value:Map<String,String>,at:Long){
        if(summary==value)return
        if(configurations.length()>0)configChanges++
        summary=LinkedHashMap(value)
        if(configurations.length()<32)configurations.put(JSONObject().put("at",at).put("values",JSONObject(summary as Map<*,*>)))
    }
    private fun energy(){
        lastEnergyAttempt=SystemClock.elapsedRealtime()
        if(systemUid<0){rootError="SystemUI energy attribution unavailable";return}
        try{
            val command="timeout -s KILL 8 sh -c 'dumpsys batterystats --usage; dumpsys batterystats --charged ${context.packageName} | grep Start.clock.time'"
            val process=ProcessBuilder("su","-c",command).redirectErrorStream(true).start()
            val output=StringBuilder();val readOk=java.util.concurrent.atomic.AtomicBoolean(false)
            val reader=Thread{runCatching{process.inputStream.bufferedReader().use{r->val buf=CharArray(4096);while(true){val n=r.read(buf);if(n<0)break;if(output.length<524288)output.append(buf,0,n)}};readOk.set(true)}}.apply{isDaemon=true;start()}
            if(!process.waitFor(10,TimeUnit.SECONDS)){process.destroyForcibly();process.inputStream.close();error("timeout")};reader.join(500);check(!reader.isAlive&&readOk.get()){"incomplete report"}
            check(process.exitValue()==0){"permission"}
            current=BatteryPowerReport.parse(output.toString(),setOf(ownUid,systemUid));rootAt=System.currentTimeMillis();rootError=""
        }catch(_:Exception){rootError="Android estimates unavailable; battery accounting continues"}
    }
    private fun json(active:Boolean,reason:String=""):JSONObject {
        val s=session ?: return JSONObject()
        return JSONObject().put("active",active).put("start",s.start.wall).put("end",s.last.wall).put("startElapsed",s.start.elapsed)
            .put("durationMs",s.durationMs).put("screenOnMs",s.screenOnMs).put("screenOffMs",s.screenOffMs).put("screenOnRate",s.screenOnRate ?: JSONObject.NULL).put("screenOffRate",s.screenOffRate ?: JSONObject.NULL)
            .put("startLevel",s.start.level).put("lastLevel",s.last.level).put("lostPercent",s.lostPercent)
            .put("lostMah",s.lostMah ?: JSONObject.NULL).put("mahPerHour",s.mahPerHour ?: JSONObject.NULL)
            .put("partial",s.partial).put("counterAdjusted",s.counterAdjusted).put("endReason",reason)
            .put("features",JSONObject(s.featureMs as Map<*,*>)).put("unknownActivityMs",s.unknownActivityMs)
            .put("configuration",JSONObject(summary as Map<*,*>)).put("configurations",configurations).put("configChanges",configChanges)
            .put("wirehelmMah",BatteryPowerReport.delta(baseline,current,ownUid) ?: JSONObject.NULL)
            .put("systemuiMah",BatteryPowerReport.delta(baseline,current,systemUid) ?: JSONObject.NULL)
            .put("energyAt",rootAt).put("energyError",rootError)
            .put("energyReset",baseline!=null&&current!=null&&baseline!!.window!=current!!.window)
    }
    private fun persist(force:Boolean){
        val s=session ?: return
        if(!force&&s.last.elapsed-lastSaved<60000)return
        id=store.save(id,json(true));store.sample(id,s.last);lastSaved=s.last.elapsed
    }
    private fun finish(reason:String){
        if(session==null)return
        id=store.save(id,json(false,reason));store.sample(id,session!!.last)
        session=null;id=0
    }
    private fun data(selected:Long):JSONObject {
        val rows=store.recent();val chosen=if((0 until rows.length()).any{rows.getJSONObject(it).getLong("id")==selected})selected else if(rows.length()>0)rows.getJSONObject(0).getLong("id") else 0
        val config=point()?.let{BatteryCustomizationSource.read(context,it.interactive,it.boot)}
        return JSONObject().put("trackerError",prefs.getString("error","")).put("enabled",enabled()).put("running",running).put("estimates",prefs.getBoolean("estimates",config?.rootApproved==true))
            .put("rootApproved",config?.rootApproved==true).put("sessions",rows).put("selected",chosen).put("samples",if(chosen>0)store.samples(chosen) else JSONArray())
    }
}

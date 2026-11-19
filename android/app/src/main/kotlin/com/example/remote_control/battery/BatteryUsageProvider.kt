package com.example.remote_control.battery

import android.content.*
import android.database.Cursor
import android.net.Uri
import android.os.Bundle

/** Private same-UID IPC; the recorder and store have one process and one writer. */
class BatteryUsageProvider:ContentProvider(){
    override fun onCreate()=true
    override fun call(method:String,arg:String?,extras:Bundle?):Bundle {
        val c=context ?: error("Battery tracker unavailable")
        val recorder=BatteryUsageRecorder.get(c)
        val data=when(method){
            "get"->recorder.state(extras?.getLong("session",0) ?: 0)
            "configure"->{
                val enabled=extras?.getBoolean("enabled") ?: false
                val value=recorder.setOptions(enabled,extras?.getBoolean("estimates") ?: false)
                if(enabled){try{c.startForegroundService(Intent(c,BatteryUsageService::class.java))}catch(e:Exception){recorder.setOptions(false,extras?.getBoolean("estimates") ?: false);throw e}}
                else c.stopService(Intent(c,BatteryUsageService::class.java))
                value
            }
            else->error("Unknown battery operation")
        }
        return Bundle().apply{putString("data",data.toString())}
    }
    override fun query(u:Uri,p:Array<out String>?,s:String?,a:Array<out String>?,o:String?):Cursor?=throw UnsupportedOperationException()
    override fun getType(u:Uri):String?=null
    override fun insert(u:Uri,v:ContentValues?):Uri?=throw UnsupportedOperationException()
    override fun update(u:Uri,v:ContentValues?,s:String?,a:Array<out String>?)=throw UnsupportedOperationException()
    override fun delete(u:Uri,s:String?,a:Array<out String>?)=throw UnsupportedOperationException()
}

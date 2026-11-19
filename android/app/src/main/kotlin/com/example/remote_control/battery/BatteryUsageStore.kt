package com.example.remote_control.battery

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

class BatteryUsageStore(context:Context):SQLiteOpenHelper(context.createDeviceProtectedStorageContext(),"battery_usage.db",null,1){
    override fun onCreate(db:SQLiteDatabase){
        db.execSQL("CREATE TABLE sessions(id INTEGER PRIMARY KEY AUTOINCREMENT,data TEXT NOT NULL)")
        db.execSQL("CREATE TABLE samples(id INTEGER PRIMARY KEY AUTOINCREMENT,session INTEGER NOT NULL,elapsed INTEGER NOT NULL,level INTEGER NOT NULL,charge INTEGER)")
        db.execSQL("CREATE INDEX samples_session ON samples(session,id)")
    }
    override fun onUpgrade(db:SQLiteDatabase,old:Int,new:Int){error("Unsupported battery schema upgrade")}
    fun save(id:Long,data:JSONObject):Long {
        val values=ContentValues().apply{put("data",data.toString())}
        val result=if(id==0L)writableDatabase.insertOrThrow("sessions",null,values) else {writableDatabase.update("sessions",values,"id=?",arrayOf(id.toString()));id}
        writableDatabase.execSQL("DELETE FROM sessions WHERE id NOT IN (SELECT id FROM sessions ORDER BY id DESC LIMIT 60)")
        writableDatabase.execSQL("DELETE FROM samples WHERE session NOT IN (SELECT id FROM sessions)")
        return result
    }
    fun sample(id:Long,p:BatteryPoint){
        val v=ContentValues().apply{put("session",id);put("elapsed",p.elapsed);put("level",p.level);if(p.charge==null)putNull("charge") else put("charge",p.charge)}
        writableDatabase.insertOrThrow("samples",null,v)
        writableDatabase.execSQL("DELETE FROM samples WHERE session=? AND id NOT IN (SELECT id FROM samples WHERE session=? ORDER BY id DESC LIMIT 2048)",arrayOf(id,id))
    }
    fun recent():JSONArray {
        val result=JSONArray()
        readableDatabase.rawQuery("SELECT id,data FROM sessions ORDER BY id DESC LIMIT 60",null).use{c->while(c.moveToNext()){val o=JSONObject(c.getString(1));o.put("id",c.getLong(0));result.put(o)}}
        return result
    }
    fun samples(id:Long):JSONArray {
        val result=JSONArray()
        readableDatabase.rawQuery("SELECT elapsed,level,charge FROM samples WHERE session=? ORDER BY id",arrayOf(id.toString())).use{c->while(c.moveToNext())result.put(JSONObject().put("elapsed",c.getLong(0)).put("level",c.getInt(1)).put("charge",if(c.isNull(2))JSONObject.NULL else c.getLong(2)))}
        return result
    }
    fun interruptOld(){
        val all=recent()
        for(i in 0 until all.length()){val row=all.getJSONObject(i);if(row.optBoolean("active")){row.put("active",false).put("endReason","Monitoring interrupted").put("interrupted",true);save(row.getLong("id"),row)}}
    }
}

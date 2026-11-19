package com.example.remote_control.clipboard

import android.app.KeyguardManager
import android.content.*
import android.database.Cursor
import android.net.Uri
import android.os.*
import androidx.core.content.FileProvider
import org.json.*
import java.io.File

/** SystemUI may read policy and submit clips. Only Wirehelm may read or edit history. */
class ClipboardShelfProvider:ContentProvider(){
    private lateinit var store:ClipboardShelfStore
    private lateinit var prefs:SharedPreferences
    override fun onCreate():Boolean{val c=context!!;store=ClipboardShelfStore(c);prefs=c.getSharedPreferences("clipboard_shelf",0);return true}
    private fun unlocked()=context!!.getSystemService(UserManager::class.java).isUserUnlocked&&!context!!.getSystemService(KeyguardManager::class.java).isDeviceLocked
    private fun policy()=ShelfPolicy.parse(JSONObject(prefs.getString("policy","{}")!!))
    @Synchronized override fun call(method:String,arg:String?,extras:Bundle?):Bundle {
        val c=context!!;val owner=Binder.getCallingUid()==c.applicationInfo.uid
        val system=c.packageManager.getApplicationInfo("com.android.systemui",0).uid==Binder.getCallingUid()
        if(!owner&&!system)throw SecurityException("Wirehelm or SystemUI only")
        if(!owner&&method !in setOf("policy","capture"))throw SecurityException("History is private to Wirehelm")
        if(method=="policy"){
            prefs.edit().putLong("observerAt",System.currentTimeMillis()).putInt("observerBoot",extras?.getInt("boot",-1) ?: -1).putInt("observerVersion",extras?.getInt("version",0) ?: 0).apply()
            val p=policy();return Bundle().apply{putBoolean("enabled",p.enabled&&unlocked());putBoolean("images",p.images);putBoolean("screenshots",p.screenshots&&p.images);putStringArrayList("excluded",ArrayList(p.excluded))}
        }
        if(!unlocked())throw SecurityException("Unlock the phone to use clipboard history")
        var p=policy();val e=extras ?: Bundle()
        if(method=="capture"){
            val source=e.getString("source","");val sensitive=e.getBoolean("sensitive",true)
            var stored=false
            if(p.accepts(source,sensitive,true)&&(!e.getBoolean("screenshot")||p.screenshots&&p.images)){
                val fd=e.getParcelable<ParcelFileDescriptor>("image")
                stored=try{if(fd!=null)fd.use{store.addImage(it,source,p)} else store.addText(e.getString("text","") ?: "",source,p)}finally{store.prune(p)}
            }else e.getParcelable<ParcelFileDescriptor>("image")?.close()
            prefs.edit().putString("lastResult",if(stored)"Clip saved" else "Clip skipped by privacy, type or size limits").apply()
            if(stored){val identity=Binder.clearCallingIdentity();try{c.sendBroadcast(Intent("com.example.remote_control.CLIPBOARD_SHELF_CHANGED").setPackage(c.packageName))}finally{Binder.restoreCallingIdentity(identity)}}
            return Bundle().apply{putBoolean("stored",stored)}
        }
        require(owner)
        when(method){
            "configure"->{p=ShelfPolicy.parse(JSONObject(e.getString("config") ?: error("Missing shelf options")));prefs.edit().putString("policy",p.json().toString()).commit()}
            "pin"->store.pin(e.getLong("id"),e.getBoolean("value"))
            "delete"->store.delete(e.getLong("id"))
            "clear"->store.clear(e.getBoolean("includePins"))
            "copy"->{
                store.prune(p);val item=store.entry(e.getLong("id")) ?: error("Clip no longer available")
                val clip=if(item.getString("kind")=="text")ClipData.newPlainText("Wirehelm shelf",item.getString("text")) else {
                    val original=File(item.getString("image"));check(original.isFile){"Saved image is unavailable"}
                    val dir=File(c.cacheDir,"clipboard-copies").apply{mkdirs()}
                    dir.listFiles()?.filter{System.currentTimeMillis()-it.lastModified()>86400000}?.forEach{it.delete()}
                    val copy=File(dir,original.name);if(!copy.exists())original.copyTo(copy);copy.setLastModified(System.currentTimeMillis())
                    var bytes=dir.listFiles()?.sumOf{it.length()} ?: 0
                    for(old in dir.listFiles()?.sortedBy{it.lastModified()} ?: emptyList()){
                        if(bytes<=ShelfPolicy.IMAGE_BUDGET)break
                        if(old!=copy){val length=old.length();if(old.delete())bytes-=length}
                    }
                    ClipData.newUri(c.contentResolver,"Wirehelm shelf",FileProvider.getUriForFile(c,"${c.packageName}.clipboard.files",copy))
                }
                c.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
            }
            "detail"->{store.prune(p);return Bundle().apply{putString("data",(store.entry(e.getLong("id")) ?: error("Clip no longer available")).toString())}}
            "list"->{}
            else->error("Unknown clipboard operation")
        }
        store.prune(p)
        val rows=store.list(e.getString("query","") ?: "",e.getBoolean("pinned"))
        for(i in 0 until rows.length()){val row=rows.getJSONObject(i);val source=row.getString("source");val label=runCatching{c.packageManager.getApplicationLabel(c.packageManager.getApplicationInfo(source,0)).toString()}.getOrDefault(source);row.put("app",if(source=="com.android.systemui"&&row.optString("kind")=="image")"Screenshots" else label)}
        val boot=android.provider.Settings.Global.getInt(c.contentResolver,android.provider.Settings.Global.BOOT_COUNT,-1)
        val result=JSONObject().put("policy",p.json()).put("entries",rows).put("observerAt",if(prefs.getInt("observerBoot",-2)==boot)prefs.getLong("observerAt",0) else 0)
            .put("observerVersion",prefs.getInt("observerVersion",0)).put("lastResult",prefs.getString("lastResult",""))
        return Bundle().apply{putString("data",result.toString())}
    }
    override fun query(u:Uri,p:Array<out String>?,s:String?,a:Array<out String>?,o:String?):Cursor?=throw UnsupportedOperationException()
    override fun getType(u:Uri):String?=null
    override fun insert(u:Uri,v:ContentValues?):Uri?=throw UnsupportedOperationException()
    override fun update(u:Uri,v:ContentValues?,s:String?,a:Array<out String>?)=throw UnsupportedOperationException()
    override fun delete(u:Uri,s:String?,a:Array<out String>?)=throw UnsupportedOperationException()
}

class ClipboardImageProvider:FileProvider()

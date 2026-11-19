package com.example.remote_control.clipboard

import android.content.*
import android.database.sqlite.*
import android.graphics.*
import android.os.ParcelFileDescriptor
import android.webkit.MimeTypeMap
import org.json.*
import java.io.*
import java.security.MessageDigest

/** Credential-protected, excluded from Android backup. Provider serializes all operations. */
class ClipboardShelfStore(private val context:Context):SQLiteOpenHelper(context,
    File(context.noBackupFilesDir,"clipboard/shelf.db").also{it.parentFile!!.mkdirs()}.path,null,1) {
    val directory=File(context.noBackupFilesDir,"clipboard").apply{mkdirs()}
    override fun onCreate(db:SQLiteDatabase) { db.execSQL("CREATE TABLE clips(id INTEGER PRIMARY KEY AUTOINCREMENT, hash TEXT UNIQUE NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, source TEXT NOT NULL, stamp INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, image TEXT NOT NULL DEFAULT '', thumb TEXT NOT NULL DEFAULT '', mime TEXT NOT NULL DEFAULT '')") }
    override fun onUpgrade(db:SQLiteDatabase,old:Int,new:Int)=error("Unsupported clipboard schema")
    fun addText(text:String,source:String,policy:ShelfPolicy):Boolean {
        if(text.isBlank()||text.length>ShelfPolicy.MAX_TEXT)return false
        return insert("text",text,source,"","","text/plain",digest(text.toByteArray(Charsets.UTF_8)),policy)
    }
    fun addImage(fd:ParcelFileDescriptor,source:String,policy:ShelfPolicy):Boolean {
        if(!policy.images)return false
        // Only finite seekable files; never consume an unbounded provider pipe.
        val size=fd.statSize
        if(size<=0||size>ShelfPolicy.MAX_IMAGE)return false
        val bytes=ParcelFileDescriptor.AutoCloseInputStream(fd).use{input->
            val out=ByteArrayOutputStream();val buffer=ByteArray(8192);var total=0
            while(total<=size){val count=input.read(buffer,0,minOf(buffer.size,size.toInt()+1-total));if(count<0)break;out.write(buffer,0,count);total+=count};out.toByteArray()
        }
        if(bytes.size.toLong()!=size)return false
        val options=BitmapFactory.Options().apply{inJustDecodeBounds=true}
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,options)
        if(options.outWidth<=0||options.outHeight<=0||options.outWidth.toLong()*options.outHeight>50_000_000)return false
        val mime=options.outMimeType ?: return false
        if(!mime.startsWith("image/"))return false
        val hash=digest(bytes);val ext=MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "img"
        val image="$hash.$ext";val thumb="$hash.thumb.jpg"
        var sample=1;while(options.outWidth/sample>512||options.outHeight/sample>512)sample*=2
        val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size,BitmapFactory.Options().apply{inSampleSize=sample}) ?: return false
        try { File(directory,thumb).outputStream().use{bitmap.compress(Bitmap.CompressFormat.JPEG,85,it)} } finally{bitmap.recycle()}
        if(!File(directory,image).exists())File(directory,image).writeBytes(bytes)
        return insert("image","",source,image,thumb,mime,hash,policy)
    }
    private fun insert(kind:String,text:String,source:String,image:String,thumb:String,mime:String,hash:String,p:ShelfPolicy):Boolean {
        val key="$kind:$hash";val v=ContentValues().apply{put("kind",kind);put("text",text);put("source",source);put("stamp",System.currentTimeMillis());put("image",image);put("thumb",thumb);put("mime",mime)}
        if(writableDatabase.update("clips",v,"hash=?",arrayOf(key))==0){v.put("hash",key);writableDatabase.insertOrThrow("clips",null,v)}
        prune(p)
        return readableDatabase.rawQuery("SELECT id FROM clips WHERE hash=?",arrayOf(key)).use{it.moveToFirst()}
    }
    fun prune(p:ShelfPolicy) {
        writableDatabase.delete("clips","pinned=0 AND stamp<?",arrayOf((System.currentTimeMillis()-p.days*86400000L).toString()))
        writableDatabase.execSQL("DELETE FROM clips WHERE pinned=0 AND id NOT IN (SELECT id FROM clips WHERE pinned=0 ORDER BY stamp DESC,id DESC LIMIT ${p.limit})")
        cleanFiles()
        var budget=directory.listFiles()?.filter{it.name!="shelf.db"&&!it.name.startsWith("shelf.db-") }?.sumOf{it.length()} ?: 0
        while(budget>ShelfPolicy.IMAGE_BUDGET){
            val oldest=readableDatabase.rawQuery("SELECT id FROM clips WHERE pinned=0 AND kind='image' ORDER BY stamp,id LIMIT 1",null).use{if(it.moveToFirst())it.getLong(0) else null} ?: break
            writableDatabase.delete("clips","id=?",arrayOf(oldest.toString()));cleanFiles()
            budget=directory.listFiles()?.filter{it.name!="shelf.db"&&!it.name.startsWith("shelf.db-") }?.sumOf{it.length()} ?: 0
        }
    }
    private fun cleanFiles(){
        val keep=hashSetOf<String>()
        readableDatabase.rawQuery("SELECT image,thumb FROM clips",null).use{c->while(c.moveToNext()){keep.add(c.getString(0));keep.add(c.getString(1))}}
        directory.listFiles()?.filter{it.name!="shelf.db"&&!it.name.startsWith("shelf.db-")&&it.name !in keep}?.forEach{it.delete()}
    }
    fun entry(id:Long):JSONObject?=readableDatabase.rawQuery("SELECT id,kind,text,source,stamp,pinned,image,thumb,mime FROM clips WHERE id=?",arrayOf(id.toString())).use{c->if(c.moveToFirst())row(c,true) else null}
    fun list(query:String,pinned:Boolean):JSONArray {
        val out=JSONArray();val q=query.take(200)
        readableDatabase.rawQuery("SELECT id,kind,text,source,stamp,pinned,image,thumb,mime FROM clips WHERE (?='' OR instr(lower(text),lower(?))>0 OR instr(lower(source),lower(?))>0) AND (?='0' OR pinned=1) ORDER BY pinned DESC,stamp DESC,id DESC LIMIT 225",arrayOf(q,q,q,if(pinned)"1" else "0")).use{c->while(c.moveToNext())out.put(row(c,false))};return out
    }
    private fun row(c:android.database.Cursor,full:Boolean):JSONObject {
        val text=c.getString(2)
        return JSONObject().put("id",c.getLong(0)).put("kind",c.getString(1)).put("text",if(full)text else text.take(500)).put("length",text.length)
            .put("source",c.getString(3)).put("at",c.getLong(4)).put("pinned",c.getInt(5)==1).put("mime",c.getString(8))
            .put("image",if(c.getString(6).isEmpty())"" else File(directory,c.getString(6)).path)
            .put("thumb",if(c.getString(7).isEmpty())"" else File(directory,c.getString(7)).path)
    }
    fun pin(id:Long,value:Boolean){
        if(value){val count=readableDatabase.rawQuery("SELECT count(*) FROM clips WHERE pinned=1",null).use{it.moveToFirst();it.getInt(0)};require(count<ShelfPolicy.MAX_PINS||entry(id)?.optBoolean("pinned")==true){"Up to 25 clips can be pinned"}}
        writableDatabase.update("clips",ContentValues().apply{put("pinned",if(value)1 else 0)},"id=?",arrayOf(id.toString()))
    }
    fun delete(id:Long){writableDatabase.delete("clips","id=?",arrayOf(id.toString()));cleanFiles()}
    fun clear(includePins:Boolean){writableDatabase.delete("clips",if(includePins)null else "pinned=0",null);cleanFiles()}
    private fun digest(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
}

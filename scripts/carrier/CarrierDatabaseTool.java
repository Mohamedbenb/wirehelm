package com.nodecockpit.carrier;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Root-side, firmware-local database preparation. No modem commands or mounts. */
public final class CarrierDatabaseTool {
    private static String quote(String s) { return "\""+s.replace("\"","\"\"")+"\""; }
    private static String hex(byte[] b) { StringBuilder s=new StringBuilder();for(byte v:b)s.append(String.format(Locale.ROOT,"%02x",v&255));return s.toString(); }
    private static String hash(File f)throws Exception {
        MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}return hex(d.digest());
    }
    private static void copy(File a,File b)throws Exception {
        try(InputStream in=new FileInputStream(a);FileOutputStream out=new FileOutputStream(b)){byte[] buf=new byte[65536];int n;while((n=in.read(buf))!=-1)out.write(buf,0,n);out.getFD().sync();}
    }
    private static SQLiteDatabase open(File f,boolean writable) {
        return SQLiteDatabase.openDatabase(f.getAbsolutePath(),null,(writable?SQLiteDatabase.OPEN_READWRITE:SQLiteDatabase.OPEN_READONLY)|SQLiteDatabase.NO_LOCALIZED_COLLATORS, db -> { throw new IllegalStateException("Corrupt database; source left intact"); });
    }
    private static String one(SQLiteDatabase db,String sql,String...args)throws Exception {
        try(Cursor c=db.rawQuery(sql,args)){if(!c.moveToFirst())throw new IOException("Missing database value");String v=c.getString(0);if(c.moveToNext())throw new IOException("Ambiguous database value");return v;}
    }
    private static void integrity(SQLiteDatabase db)throws Exception {
        if(!"ok".equals(one(db,"PRAGMA integrity_check")))throw new IOException("Database integrity failure");
    }
    private static final class Plan {
        String profile; final LinkedHashMap<String,String> carriers=new LinkedHashMap<>();
    }
    private static Plan plan(SQLiteDatabase db,String requested)throws Exception {
        Plan p=new Plan();String[] profile=stockProfile(db);String id=profile[0];p.profile=profile[1];
        for(String mcc:requested.split(",",-1)){
            if(!mcc.matches("[0-9]{5,6}")||p.carriers.containsKey(mcc))throw new IOException("Invalid or duplicate carrier selection");
            String carrier=one(db,"SELECT DISTINCT carrier_id FROM carrier_info WHERE mccmnc=?",mcc);
            if(carrier==null||!carrier.matches("[0-9]{1,10}")||carrier.equals(id)||carrier.equals("0"))throw new IOException("Unsupported or ambiguous carrier identity");
            p.carriers.put(mcc,carrier);
        }
        if(p.carriers.isEmpty()||p.carriers.size()>32)throw new IOException("Unsupported selection size");
        return p;
    }
    private static String[] stockProfile(SQLiteDatabase db)throws Exception {
        integrity(db);
        String id=one(db,"SELECT carrier_id FROM confnames WHERE name=?","wildcard_5g");
        String profile=one(db,"SELECT confman FROM confmap WHERE carrier_id=?",id);
        if(profile==null||!profile.matches("[a-f0-9]{40,64}"))throw new IOException("Unsupported profile identifier");
        if(Integer.parseInt(one(db,"SELECT count(*) FROM "+quote("confman_"+profile)))<=0)throw new IOException("Empty stock profile");
        Set<String> columns=new HashSet<>();
        try(Cursor c=db.rawQuery("PRAGMA table_info(confmap)",null)){while(c.moveToNext())columns.add(c.getString(1));}
        if(!columns.equals(new HashSet<>(Arrays.asList("carrier_id","parent_id","confman"))))throw new IOException("Unsupported confmap schema");
        return new String[]{id,profile};
    }
    private static String json(String value) {
        StringBuilder out=new StringBuilder("\"");
        for(char c:value.toCharArray()){
            if(c=='"'||c=='\\')out.append('\\').append(c);
            else if(c<32)out.append(String.format(Locale.ROOT,"\\u%04x",(int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    private static void catalog(SQLiteDatabase db,String encoded,String chosen)throws Exception {
        String profileId=stockProfile(db)[0];
        if(!encoded.startsWith("q:"))throw new IOException("Invalid catalog request");
        String query=new String(Base64.getDecoder().decode(encoded.substring(2)),StandardCharsets.UTF_8).trim().toLowerCase(Locale.ROOT);
        if(query.length()>80)throw new IOException("Search is too long");
        Set<String> selected=new HashSet<>(Arrays.asList(chosen.split(",")));
        boolean names=false;try{names=Integer.parseInt(one(db,"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='carrier_name'"))==1;}catch(Exception ignored){}
        String sql="SELECT i.mccmnc,MIN(i.carrier_id),"+(names?"MIN(n.name)":"NULL")+" FROM carrier_info i "+(names?"LEFT JOIN carrier_name n ON n.carrier_id=i.carrier_id ":"")+"GROUP BY i.mccmnc HAVING COUNT(DISTINCT i.carrier_id)=1 ORDER BY i.mccmnc";
        ArrayList<String> items=new ArrayList<>(),current=new ArrayList<>();boolean more=false;
        try(Cursor c=db.rawQuery(sql,null)){
            while(c.moveToNext()){
                String code=c.getString(0),id=c.getString(1),name=c.getString(2);
                if(code==null||!code.matches("[0-9]{5,6}")||id==null||!id.matches("[0-9]{1,10}")||id.equals("0")||id.equals(profileId))continue;
                if(name==null||name.trim().isEmpty())name="Carrier "+id;
                name=name.replaceAll("[\\p{Cntrl}]"," ").trim();if(name.length()>80)name=name.substring(0,80);
                String row="{\"mccmnc\":"+json(code)+",\"carrierId\":"+json(id)+",\"name\":"+json(name)+"}";
                if(selected.contains(code))current.add(row);
                if(query.isEmpty()||code.contains(query)||name.toLowerCase(Locale.ROOT).contains(query)){
                    if(items.size()<100)items.add(row);else more=true;
                }
            }
        }
        String result="{\"items\":["+String.join(",",items)+"],\"selected\":["+String.join(",",current)+"],\"more\":"+more+"}";
        System.out.println("catalog="+Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
    }
    // Hash every typed value, preserving duplicates; skip only explicitly selected map rows.
    private static String logical(SQLiteDatabase db,String table,Collection<String> skip)throws Exception {
        ArrayList<String> rows=new ArrayList<>();
        try(Cursor c=db.rawQuery("SELECT * FROM "+quote(table),null)){
            int id=table.equals("confmap")?c.getColumnIndex("carrier_id"):-1;
            while(c.moveToNext()){
                if(id>=0&&skip.contains(c.getString(id)))continue;
                ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
                for(int i=0;i<c.getColumnCount();i++){
                    int t=c.getType(i);out.writeInt(t);
                    if(t==Cursor.FIELD_TYPE_INTEGER)out.writeLong(c.getLong(i));
                    else if(t==Cursor.FIELD_TYPE_FLOAT)out.writeLong(Double.doubleToLongBits(c.getDouble(i)));
                    else if(t!=Cursor.FIELD_TYPE_NULL){byte[] v=t==Cursor.FIELD_TYPE_BLOB?c.getBlob(i):c.getString(i).getBytes(StandardCharsets.UTF_8);out.writeInt(v.length);out.write(v);}
                }
                rows.add(hex(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray())));
            }
        }
        Collections.sort(rows);MessageDigest hash=MessageDigest.getInstance("SHA-256");for(String r:rows)hash.update(r.getBytes(StandardCharsets.US_ASCII));return hex(hash.digest());
    }
    private static void verify(SQLiteDatabase base,SQLiteDatabase patched,Plan p)throws Exception {
        integrity(patched);
        if(!logical(base,"sqlite_master",Collections.emptySet()).equals(logical(patched,"sqlite_master",Collections.emptySet())))throw new IOException("Schema changed");
        try(Cursor c=base.rawQuery("SELECT name FROM sqlite_master WHERE type='table'",null)){
            while(c.moveToNext()){
                String table=c.getString(0);
                if(!logical(base,table,p.carriers.values()).equals(logical(patched,table,p.carriers.values())))throw new IOException("Unrelated database rows changed: "+table);
            }
        }
        for(String id:p.carriers.values()){
            if(!p.profile.equals(one(patched,"SELECT confman FROM confmap WHERE carrier_id=?",id)))throw new IOException("Mapping validation failed");
            // Updating an existing mapping must preserve its parent (including SQL NULL).
            try(Cursor b=base.rawQuery("SELECT parent_id FROM confmap WHERE carrier_id=?",new String[]{id});Cursor a=patched.rawQuery("SELECT parent_id FROM confmap WHERE carrier_id=?",new String[]{id})){
                if(!a.moveToFirst())throw new IOException("Mapping missing");
                if(b.moveToFirst()&&!Objects.equals(b.getString(0),a.getString(0)))throw new IOException("Carrier parent changed");
            }
        }
    }
    private static void publish(File temp,File dest)throws IOException {Files.move(temp.toPath(),dest.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
    public static void main(String[] args) {
        try {
            if((args.length!=4&&!(args.length==5&&args[0].equals("catalog")))||!(args[0].equals("inspect")||args[0].equals("prepare")||args[0].equals("catalog")))throw new IOException("Expected inspect|prepare vendor-db state-dir mccmnc-list");
            File input=new File(args[1]),state=new File(args[2]);
            if(!input.isFile()||input.length()<512||input.length()>33554432)throw new IOException("Vendor database missing or too large");
            try(SQLiteDatabase db=open(input,false)){
                if(args[0].equals("catalog")){catalog(db,args[3],args.length==5?args[4]:"");return;}
                Plan p=plan(db,args[3]);
                if(args[0].equals("inspect")){System.out.println("compatible=true\nprofile="+p.profile+"\ncarrierIds="+String.join(",",p.carriers.values()));return;}
            }
            if(!state.isDirectory()&&!state.mkdirs())throw new IOException("Cannot create private state directory");
            File stock=new File(state,"stock.db.tmp"),output=new File(state,"patched.db.tmp");
            // A timeout/power loss may leave a hot journal. Never replay it onto
            // a newly copied database from a later OTA.
            for(File scratch:Arrays.asList(stock,output))
                for(String suffix:Arrays.asList("-journal","-wal","-shm",""))
                    Files.deleteIfExists(new File(scratch.getPath()+suffix).toPath());
            copy(input,stock);String baseHash=hash(stock);copy(stock,output);
            Plan p;
            try(SQLiteDatabase base=open(stock,false);SQLiteDatabase patched=open(output,true)){
                p=plan(base,args[3]);try(Cursor journal=patched.rawQuery("PRAGMA journal_mode=DELETE",null)){journal.moveToFirst();}
                patched.beginTransaction();
                try {
                    for(String id:p.carriers.values()){
                        patched.execSQL("UPDATE confmap SET confman=? WHERE carrier_id=?",new Object[]{p.profile,id});
                        patched.execSQL("INSERT INTO confmap(carrier_id,parent_id,confman) SELECT ?,NULL,? WHERE NOT EXISTS(SELECT 1 FROM confmap WHERE carrier_id=?)",new Object[]{id,p.profile,id});
                    }
                    patched.setTransactionSuccessful();
                } finally {patched.endTransaction();}
                verify(base,patched,p);
            }
            if(!hash(input).equals(baseHash))throw new IOException("Vendor source changed during preparation");
            File backups=new File(state,"stock-backups");if(!backups.isDirectory()&&!backups.mkdirs())throw new IOException("Cannot create backup directory");
            File backup=new File(backups,baseHash+".db");
            if(!backup.exists()){File temporary=new File(backups,baseHash+".tmp");copy(stock,temporary);publish(temporary,backup);}
            if(!hash(backup).equals(baseHash))throw new IOException("Stock backup verification failed");
            String patchedHash=hash(output);
            // Publish data first and manifest last. A partial publication cannot pass script checks.
            publish(stock,new File(state,"stock.db"));publish(output,new File(state,"patched.db"));
            File manifest=new File(state,"prepared.properties.tmp");
            try(FileOutputStream out=new FileOutputStream(manifest)){
                String report="baseHash="+baseHash+"\npatchedHash="+patchedHash+"\nprofile="+p.profile+"\ncarrierIds="+String.join(",",p.carriers.values())+"\ncarriers="+args[3]+"\n";
                out.write(report.getBytes(StandardCharsets.US_ASCII));out.getFD().sync();
            }
            publish(manifest,new File(state,"prepared.properties"));System.out.println("prepared=true\nbaseHash="+baseHash+"\npatchedHash="+patchedHash);
        } catch(Throwable e){System.err.println("Carrier preparation refused: "+e.getClass().getSimpleName()+": "+e.getMessage());System.exit(1);}
    }
}

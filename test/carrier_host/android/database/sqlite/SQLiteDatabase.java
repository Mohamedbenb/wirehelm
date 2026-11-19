package android.database.sqlite;
import android.database.Cursor;
import java.sql.*;
import java.util.*;
import org.sqlite.SQLiteConfig;
/** Test adapter only: runs production SQL/validation with real host SQLite. */
public final class SQLiteDatabase implements AutoCloseable {
 public static final int OPEN_READWRITE=0,OPEN_READONLY=1,NO_LOCALIZED_COLLATORS=16;
 private Connection db;private boolean success;
 public static SQLiteDatabase openDatabase(String path,Object ignored,int flags){try{SQLiteDatabase d=new SQLiteDatabase();SQLiteConfig c=new SQLiteConfig();c.setReadOnly((flags&OPEN_READONLY)!=0);d.db=DriverManager.getConnection("jdbc:sqlite:"+path,c.toProperties());return d;}catch(Exception e){throw new RuntimeException(e);}}
 public static SQLiteDatabase openDatabase(String path,Object ignored,int flags,android.database.DatabaseErrorHandler handler){return openDatabase(path,ignored,flags);}
 public Cursor rawQuery(String sql,String[] args){try(PreparedStatement s=db.prepareStatement(sql)){if(args!=null)for(int i=0;i<args.length;i++)s.setString(i+1,args[i]);try(ResultSet r=s.executeQuery()){ArrayList<Object[]> rows=new ArrayList<>();int n=r.getMetaData().getColumnCount();String[] names=new String[n];for(int i=0;i<n;i++)names[i]=r.getMetaData().getColumnName(i+1);while(r.next()){Object[] row=new Object[n];for(int i=0;i<n;i++)row[i]=r.getObject(i+1);rows.add(row);}return new Rows(rows,names);}}catch(Exception e){throw new RuntimeException(e);}}
 public void execSQL(String sql){execSQL(sql,new Object[0]);}
 public void execSQL(String sql,Object[] args){try(PreparedStatement s=db.prepareStatement(sql)){for(int i=0;i<args.length;i++)s.setObject(i+1,args[i]);s.execute();}catch(Exception e){throw new RuntimeException(e);}}
 public void beginTransaction(){try{db.setAutoCommit(false);success=false;}catch(Exception e){throw new RuntimeException(e);}}
 public void setTransactionSuccessful(){success=true;}
 public void endTransaction(){try{if(success)db.commit();else db.rollback();db.setAutoCommit(true);}catch(Exception e){throw new RuntimeException(e);}}
 public void close(){try{db.close();}catch(Exception e){throw new RuntimeException(e);}}
 private static final class Rows implements Cursor {
  final List<Object[]> rows;final String[] names;int pos=-1;
  Rows(List<Object[]> rows,String[] names){this.rows=rows;this.names=names;}
  Object get(int i){return rows.get(pos)[i];}
  public boolean moveToFirst(){pos=0;return pos<rows.size();}public boolean moveToNext(){return ++pos<rows.size();}
  public int getColumnCount(){return names.length;}public int getColumnIndex(String name){return Arrays.asList(names).indexOf(name);}
  public int getType(int i){Object o=get(i);return o==null?0:o instanceof byte[]?4:o instanceof Float||o instanceof Double?2:o instanceof Number?1:3;}
  public String getString(int i){Object o=get(i);return o==null?null:o.toString();}public long getLong(int i){return ((Number)get(i)).longValue();}public double getDouble(int i){return ((Number)get(i)).doubleValue();}public byte[] getBlob(int i){return (byte[])get(i);}public void close(){}
 }
}

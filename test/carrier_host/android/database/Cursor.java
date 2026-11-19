package android.database;
public interface Cursor extends AutoCloseable {
 int FIELD_TYPE_NULL=0,FIELD_TYPE_INTEGER=1,FIELD_TYPE_FLOAT=2,FIELD_TYPE_STRING=3,FIELD_TYPE_BLOB=4;
 boolean moveToFirst();boolean moveToNext();int getColumnCount();int getColumnIndex(String name);int getType(int i);String getString(int i);long getLong(int i);double getDouble(int i);byte[] getBlob(int i);void close();
}

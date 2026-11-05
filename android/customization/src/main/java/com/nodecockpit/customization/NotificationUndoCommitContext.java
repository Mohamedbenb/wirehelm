package com.nodecockpit.customization;
import java.util.*;
/** Original attached-child input exposed only inside the synchronous native dismissal call. */
final class NotificationUndoCommitContext {
    private Thread owner;
    private final Map<Object,List<?>> snapshots=new IdentityHashMap<>();
    void begin(Map<Object,List<?>> originals){
        if(owner!=null)throw new IllegalStateException("Nested Undo commit");
        for(Map.Entry<Object,List<?>> item:originals.entrySet())snapshots.put(item.getKey(),new ArrayList<>(item.getValue()));
        owner=Thread.currentThread();
    }
    List<?> children(Object entry){
        if(Thread.currentThread()!=owner)return null;
        List<?> captured=snapshots.get(entry);
        // Native R8 code casts this method's result to ArrayList.
        return captured==null?null:new ArrayList<>(captured);
    }
    void clear(){owner=null;snapshots.clear();}
}

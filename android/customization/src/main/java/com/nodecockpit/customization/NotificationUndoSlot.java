package com.nodecockpit.customization;

/** Single in-memory identity/generation lease. Never stores notification content. */
final class NotificationUndoSlot {
    static final long WINDOW_MS=5000;
    private long serial;
    private Pending pending;
    static final class Pending {
        final long token,deadline;
        final String key;
        final Object entry,generation;
        Pending(long token,long deadline,String key,Object entry,Object generation){this.token=token;this.deadline=deadline;this.key=key;this.entry=entry;this.generation=generation;}
    }
    Pending begin(String key,Object entry,Object generation,long now){
        if(key==null||key.isEmpty()||entry==null||generation==null)throw new IllegalArgumentException("Missing original identity");
        return pending=new Pending(++serial,now+WINDOW_MS,key,entry,generation);
    }
    Pending peek(){return pending;}
    boolean matches(String key,Object entry,Object generation){return pending!=null&&pending.key.equals(key)&&pending.entry==entry&&pending.generation==generation;}
    boolean undoable(long now){return pending!=null&&now<pending.deadline;}
    Pending clear(long token){if(pending==null||pending.token!=token)return null;Pending old=pending;pending=null;return old;}
}

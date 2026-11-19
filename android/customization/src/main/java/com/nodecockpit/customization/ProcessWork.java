package com.nodecockpit.customization;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
/** App-process support requests. Does not keep the CPU awake or schedule work. */
public final class ProcessWork {
 private static final AtomicLong serial=new AtomicLong();
 private static final Map<Long,String> active=new LinkedHashMap<>();
 private static volatile Runnable changed=()->{};
 private ProcessWork(){}
 public static void onChanged(Runnable listener){changed=listener;}
 public static synchronized Token begin(String reason){long id=serial.incrementAndGet();active.put(id,reason);return new Token(id);}
 public static synchronized List<String> reasons(){return new ArrayList<>(active.values());}
 public static final class Token implements AutoCloseable {
  private final long id;private boolean closed;
  private Token(long id){this.id=id;}
  @Override public void close(){synchronized(ProcessWork.class){if(closed)return;closed=true;active.remove(id);}changed.run();}
 }
}

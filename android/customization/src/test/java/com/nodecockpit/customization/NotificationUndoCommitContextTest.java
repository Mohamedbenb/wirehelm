package com.nodecockpit.customization;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import static org.junit.Assert.*;
public class NotificationUndoCommitContextTest {
    @Test public void outsideCommitUsesNativeGetter(){assertNull(new NotificationUndoCommitContext().children(new Object()));}
    @Test public void capturesChildrenBeforeFilteredUiChanges(){Object summary=new Object(),child=new Object();List<Object> children=new ArrayList<>(Arrays.asList(child));Map<Object,List<?>> source=new IdentityHashMap<>();source.put(summary,children);NotificationUndoCommitContext c=new NotificationUndoCommitContext();c.begin(source);children.clear();source.clear();assertEquals(Arrays.asList(child),c.children(summary));assertTrue(c.children(summary) instanceof ArrayList<?>);}
    @Test public void nativeConsumerCannotMutateCapture(){Object summary=new Object(),child=new Object();NotificationUndoCommitContext c=new NotificationUndoCommitContext();c.begin(Collections.singletonMap(summary,Arrays.asList(child)));c.children(summary).clear();assertEquals(Arrays.asList(child),c.children(summary));}
    @Test public void clearAfterFailureStopsOverride(){Object summary=new Object();NotificationUndoCommitContext c=new NotificationUndoCommitContext();try{c.begin(Collections.singletonMap(summary,Collections.emptyList()));throw new IllegalStateException();}catch(IllegalStateException expected){}finally{c.clear();}assertNull(c.children(summary));}
    @Test public void unrelatedEntryAndThreadUseNativeGetter()throws Exception{Object summary=new Object();NotificationUndoCommitContext c=new NotificationUndoCommitContext();c.begin(Collections.singletonMap(summary,Collections.emptyList()));assertNull(c.children(new Object()));AtomicReference<List<?>> other=new AtomicReference<>();Thread t=new Thread(()->other.set(c.children(summary)));t.start();t.join();assertNull(other.get());}
}

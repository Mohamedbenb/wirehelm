package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class CameraRingWindowTest {
    private static final class Registration {
        boolean registered=true,attached=false;
        int removes;
        void remove(){removes++;if(!registered)throw new IllegalArgumentException("not registered");registered=false;}
    }
    @Test public void wakeBeforeFirstAttachmentStillUnregisters(){
        Registration nativeWindow=new Registration();CameraRingWindow<Registration> owner=new CameraRingWindow<>();
        owner.claim(nativeWindow,nativeWindow::remove);
        assertFalse(nativeWindow.attached);owner.release();
        assertFalse(nativeWindow.registered);assertNull(owner.get());assertEquals(1,nativeWindow.removes);
        owner.release();assertEquals(1,nativeWindow.removes);
    }
    @Test public void externalRemovalAllowsOwnershipToClear(){
        Registration nativeWindow=new Registration();CameraRingWindow<Registration> owner=new CameraRingWindow<>();
        owner.claim(nativeWindow,nativeWindow::remove);nativeWindow.registered=false;owner.release();assertNull(owner.get());
    }
    @Test public void failedRemovalRetainsExactOwnerAndPreventsDuplicateWindow(){
        Object view=new Object();int[] attempts={0};CameraRingWindow<Object> owner=new CameraRingWindow<>();
        owner.claim(view,()->{if(attempts[0]++==0)throw new IllegalStateException("transient failure");});
        try{owner.release();fail();}catch(IllegalStateException expected){}
        assertSame(view,owner.get());
        try{owner.claim(new Object(),()->{});fail();}catch(IllegalStateException expected){}
        owner.release();assertNull(owner.get());assertEquals(2,attempts[0]);
    }
}

package com.nodecockpit.customization;
import android.app.Notification;
import android.service.notification.StatusBarNotification;
import java.lang.reflect.*;
import java.util.*;

/** Exact-firmware final shade list -> metadata. No message content or stock mutations. */
final class CameraRingNotifications {
    static List<CameraRingSelection.Notice> snapshot(Collection<?> visible,ClassLoader loader)throws ReflectiveOperationException{
        Class<?> leaf=Class.forName("com.android.systemui.statusbar.notification.collection.NotificationEntry",false,loader);
        Class<?> group=Class.forName("com.android.systemui.statusbar.notification.collection.GroupEntry",false,loader);
        Class<?> bundle=Class.forName("com.android.systemui.statusbar.notification.collection.BundleEntry",false,loader);
        Field children=group.getField("mUnmodifiableChildren"),bundled=bundle.getField("children");
        Field sbnField=leaf.getField("mSbn"),dismiss=leaf.getField("mDismissState"),cancel=leaf.getField("mCancellationReason");
        Deque<Object> queue=new ArrayDeque<>(visible);Set<Object> seen=Collections.newSetFromMap(new IdentityHashMap<>());
        List<CameraRingSelection.Notice> out=new ArrayList<>();int budget=2048;
        while(!queue.isEmpty()){
            Object entry=queue.removeFirst();if(!seen.add(entry))continue;if(--budget<0)throw new IllegalStateException("Notification budget exceeded");
            if(group.isInstance(entry)){queue.addAll((Collection<?>)children.get(entry));continue;}
            if(bundle.isInstance(entry)){queue.addAll((Collection<?>)bundled.get(entry));continue;}
            if(!leaf.isInstance(entry))throw new IllegalStateException("Unknown final notification entry");
            Object state=dismiss.get(entry);
            if(!(state instanceof Enum)||!((Enum<?>)state).name().equals("NOT_DISMISSED")||cancel.getInt(entry)!=-1)continue;
            StatusBarNotification sbn=(StatusBarNotification)sbnField.get(entry);
            if(sbn==null||!sbn.getUser().equals(android.os.Process.myUserHandle()))continue;
            int flags=sbn.getNotification().flags;
            out.add(new CameraRingSelection.Notice(sbn.getKey(),sbn.getPackageName(),sbn.getPostTime(),(flags&(Notification.FLAG_ONGOING_EVENT|Notification.FLAG_FOREGROUND_SERVICE))!=0,(flags&Notification.FLAG_GROUP_SUMMARY)!=0));
        }return List.copyOf(out);
    }
}

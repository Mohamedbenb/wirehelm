package com.nodecockpit.customization;

import android.app.*;
import android.content.*;
import android.os.Bundle;
import org.json.JSONObject;

/** User-posted test card only. Keeps counters, never reply text or copied notifications. */
final class NotificationUndoSamples {
    private static final int ID=57051;
    private static final String CHANNEL="notification_undo_sample";
    static final String REPLY="com.nodecockpit.customization.UNDO_SAMPLE_REPLY",DELETE="com.nodecockpit.customization.UNDO_SAMPLE_DELETE";
    private static SharedPreferences prefs(Context c){return c.getSharedPreferences("notification_undo_samples_v1",0);}
    static JSONObject state(Context c)throws Exception{return new JSONObject().put("posts",prefs(c).getInt("posts",0)).put("replies",prefs(c).getInt("replies",0)).put("deletes",prefs(c).getInt("deletes",0));}
    static void post(Context c){
        NotificationManager manager=c.getSystemService(NotificationManager.class);
        if(!manager.areNotificationsEnabled())throw new IllegalStateException("Allow Node Cockpit notifications before posting the sample");
        prefs(c).edit().putInt("posts",prefs(c).getInt("posts",0)+1).apply();show(c,"Swipe away, tap Undo, then try tapping the card or replying.");
    }
    private static PendingIntent action(Context c,String action,int code,int flags){return PendingIntent.getBroadcast(c,code,new Intent(c,NotificationUndoSampleReceiver.class).setAction(action),PendingIntent.FLAG_UPDATE_CURRENT|flags);}
    private static void show(Context c,String text){
        NotificationManager manager=c.getSystemService(NotificationManager.class);manager.createNotificationChannel(new NotificationChannel(CHANNEL,"Notification Undo sample",NotificationManager.IMPORTANCE_DEFAULT));
        Intent launch=c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());if(launch==null)throw new IllegalStateException("App launcher unavailable");
        PendingIntent open=PendingIntent.getActivity(c,ID,launch,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        RemoteInput input=new RemoteInput.Builder("sample_reply").setLabel("Test reply").build();
        Notification.Action reply=new Notification.Action.Builder(android.R.drawable.ic_menu_send,"Reply",action(c,REPLY,ID+1,PendingIntent.FLAG_MUTABLE)).addRemoteInput(input).build();
        Notification n=new Notification.Builder(c,CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Notification Undo sample").setContentText(text).setStyle(new Notification.BigTextStyle().bigText(text)).setContentIntent(open).setAutoCancel(false).setOnlyAlertOnce(true).setDeleteIntent(action(c,DELETE,ID+2,PendingIntent.FLAG_IMMUTABLE)).addAction(reply).build();
        manager.notify(ID,n);
    }
    static void receive(Context c,Intent intent){
        if(DELETE.equals(intent.getAction()))prefs(c).edit().putInt("deletes",prefs(c).getInt("deletes",0)+1).apply();
        else if(REPLY.equals(intent.getAction())){
            Bundle results=RemoteInput.getResultsFromIntent(intent);
            if(results!=null&&results.getCharSequence("sample_reply")!=null){prefs(c).edit().putInt("replies",prefs(c).getInt("replies",0)+1).apply();show(c,"Original Reply action received successfully. Reply text was not stored.");}
        }
    }
}

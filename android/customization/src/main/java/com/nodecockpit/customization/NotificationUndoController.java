package com.nodecockpit.customization;

import android.app.*;
import android.content.*;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.hardware.display.DisplayManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.*;
import android.service.notification.StatusBarNotification;
import android.view.*;
import android.widget.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Persistent original-notification Undo. Sensors exist only during a pending grace. */
final class NotificationUndoController {
    private final Context context;
    private final Handler handler;
    private final BooleanSupplier allowed;
    private final Runnable changed;
    private final NotificationUndoSlot slot=new NotificationUndoSlot();
    private Object collection,row,stack,stats,summary,summaryGeneration,summaryRow;
    private String groupKey;
    private NotificationUndoGroup group;
    private static final int GROUP_DISMISSIBLE=1<<16;
    private final Map<Object,NotificationUndoGroup.Member> groupHidden=new IdentityHashMap<>();
    private boolean primarySummary;
    private final Map<Object,List<?>> attachedSnapshots=new IdentityHashMap<>();
    private final NotificationUndoCommitContext commitContext=new NotificationUndoCommitContext();
    private int lockedAttempts,lockedHolds,lockedUndos;
    private Object bubbleMetadata,summaryBubbleMetadata;
    private int bubbleState,summaryBubbleState,bubbleHolds;
    private WindowManager windows;
    private View banner;
    private NotificationUndoSettings options=NotificationUndoSettings.safe(NotificationUndoSettings.DEFAULT);
    private String configurationRaw="";
    private long configurationRevision=-1;
    private boolean suspended;
    private boolean shakeEnabled=true;
    private int shakeSensitivity=1,shakeUndos;
    private SensorManager sensors;
    private SensorEventListener shakeListener;
    private String shakeError="";
    private int held,undone,committed,invalidated,attempts,skipped;
    private String status="inactive",error="",lastSkip="none",lastSkipApp="",attemptApp="";
    private final Runnable timeout=()->safe(()->commit("expired"));
    NotificationUndoController(Context c,Handler h,BooleanSupplier allowed,Runnable changed){
        context=c;handler=h;this.allowed=allowed;this.changed=changed;
        IntentFilter f=new IntentFilter(FeaturePolicy.ACTION_DISABLE);f.addAction(Intent.ACTION_SCREEN_OFF);f.addAction("android.intent.action.USER_SWITCHED");
        c.registerReceiver(new BroadcastReceiver(){public void onReceive(Context c,Intent i){safe(()->{
            if(FeaturePolicy.ACTION_DISABLE.equals(i.getAction()))suspend("integration disabled");
            else if(Intent.ACTION_SCREEN_OFF.equals(i.getAction())){commit("screen off");stopShake();hideBanner();setStatus(active()?"enabled":"disabled");}
            else discard("Android user changed");
        });}},f,android.Manifest.permission.DUMP,h,Context.RECEIVER_EXPORTED);
    }
    void configure(String raw,long revision){
        if(raw.equals(configurationRaw)&&revision==configurationRevision)return;
        boolean choicesChanged=!raw.equals(configurationRaw);
        configurationRevision=revision;
        if(!choicesChanged&&!suspended)return;
        safe(()->{
            commit("settings changed");
            options=NotificationUndoSettings.safe(raw);configurationRaw=raw;
            shakeEnabled=options.shake;shakeSensitivity=options.sensitivity;suspended=false;error="";
            setStatus(active()?"enabled":"disabled");
        });
    }
    void collection(Object value){collection=value;}
    boolean active(){return options.enabled&&!suspended&&collection!=null&&allowed.getAsBoolean();}
    boolean hold(View candidate,boolean accessibility){
        if(!active())return false;
        attempts++;attemptApp="";
        boolean locked=context.getSystemService(KeyguardManager.class).isKeyguardLocked();if(locked)lockedAttempts++;
        if(Looper.myLooper()!=handler.getLooper())return false;
        if(!candidate.isShown())return skip("row is no longer visible");
        try{
            if(!accessibility&&slot.peek()!=null&&row==candidate&&current())return true;
            if(slot.peek()!=null)commit("next dismissal");
            if(accessibility)return skip("focus-restoring or accessibility dismissal");
            if(collection==null)return skip("native collection unavailable");
            if(!interactive())return skip("screen is off");
            String key=(String)field(candidate,"mKey");Object entry=getEntry(key);
            if(entry==null)return skip("original entry no longer active");
            attemptApp=((StatusBarNotification)field(entry,"mSbn")).getPackageName();
            if(field(entry,"row")!=candidate)return skip("native row was replaced");
            Object owner=findStack(candidate);if(owner==null)return skip("outside native notification stack");
            String excluded=nativeExclusion(entry,candidate,false);if(!excluded.isEmpty())return skip(excluded);
            if((Boolean)field(owner,"mClearAllInProgress"))return skip("Clear all in progress");
            Object callback=field(candidate,"mOnUserInteractionCallback");if(callback==null)return skip("native interaction callback unavailable");
            Object dismissedStats=callback.getClass().getMethod("getDismissedByUserStats",entry.getClass()).invoke(callback,entry);
            StatusBarNotification original=(StatusBarNotification)field(entry,"mSbn");
            boolean capturedSummary=(original.getNotification().flags&Notification.FLAG_GROUP_SUMMARY)!=0;
            String capturedGroupKey=original.isGroup()?original.getGroupKey():null;
            if(capturedSummary&&capturedGroupKey==null)return skip("original group membership unavailable");
            List<NotificationUndoGroup.Member> capturedMembers=capturedGroupKey==null?Collections.emptyList():groupMembers(capturedGroupKey);
            Map<Object,NotificationUndoGroup.Member> hidden=new IdentityHashMap<>();
            if(capturedSummary)for(NotificationUndoGroup.Member member:capturedMembers){
                if(member.entry==entry||(member.state&GROUP_DISMISSIBLE)==0)continue;
                String reason=nativeExclusion(member.entry,(View)member.row,true);
                if(!reason.isEmpty())return skip("group child: "+reason);
                hidden.put(member.entry,member);
            }
            // Native commit already handles summary/children and bubble interception.
            Object companion=capturedSummary?null:collection.getClass().getMethod("fetchSummaryToDismiss",entry.getClass()).invoke(collection,entry);
            if(companion!=null){
                String reason=nativeExclusion(companion,(View)field(companion,"row"),true);
                if(!reason.isEmpty())return skip("group summary: "+reason);
            }
            groupKey=capturedGroupKey;primarySummary=capturedSummary;
            group=capturedGroupKey==null?null:new NotificationUndoGroup(capturedMembers);
            groupHidden.clear();groupHidden.putAll(hidden);
            attachedSnapshots.clear();
            if(capturedSummary&&!captureChildren(entry)||companion!=null&&!captureChildren(companion)){
                clearReferences();return skip("group membership is changing");
            }
            summary=companion;summaryGeneration=companion==null?null:field(companion,"mSbn");
            summaryRow=companion==null?null:field(companion,"row");
            bubbleMetadata=original.getNotification().getBubbleMetadata();bubbleState=bubbleState(original.getNotification());
            Notification companionNotification=companion==null?null:((StatusBarNotification)summaryGeneration).getNotification();
            summaryBubbleMetadata=companionNotification==null?null:companionNotification.getBubbleMetadata();
            summaryBubbleState=companionNotification==null?0:bubbleState(companionNotification);
            row=candidate;stack=owner;stats=dismissedStats;
            slot.begin(key,entry,field(entry,"mSbn"),SystemClock.elapsedRealtime());
            if(options.button)showBanner();startShake();
            if(!options.button&&shakeListener==null){discard("no Undo method available");return false;}
            handler.post(this::rebuildSafely);handler.postDelayed(timeout,NotificationUndoSlot.WINDOW_MS);
            held++;if(locked)lockedHolds++;if(bubbleMetadata!=null||(bubbleState&Notification.FLAG_BUBBLE)!=0)bubbleHolds++;setStatus("original hidden: Undo available");return true;
        }catch(Throwable e){failure(e);discard("hold unavailable");return false;}
    }
    private boolean captureChildren(Object entry)throws Exception{
        Object children=entry.getClass().getMethod("getAttachedNotifChildren").invoke(entry);
        if(children instanceof List<?>){
            for(Object child:(List<?>)children){
                StatusBarNotification sbn=(StatusBarNotification)field(child,"mSbn");
                if(!Objects.equals(groupKey,sbn.getGroupKey())||getEntry(sbn.getKey())!=child||((Number)field(child,"mCancellationReason")).intValue()!=-1||!((Enum<?>)field(child,"mDismissState")).name().equals("NOT_DISMISSED"))return false;
            }
            attachedSnapshots.put(entry,new ArrayList<>((List<?>)children));
        }
        return true;
    }
    List<?> childrenDuringCommit(Object entry){return commitContext.children(entry);}
    boolean hides(Object entry){
        NotificationUndoSlot.Pending p=slot.peek();if(p==null)return false;
        try{
            if(entry==p.entry&&slot.matches(p.key,entry,field(entry,"mSbn"))||entry==summary&&field(entry,"mSbn")==summaryGeneration)return true;
            NotificationUndoGroup.Member child=groupHidden.get(entry);
            return child!=null&&field(entry,"mSbn")==child.generation;
        }catch(Throwable e){handler.post(()->safe(()->suspend("filter unavailable")));return false;}
    }
    void collectionChanged(){
        if(slot.peek()==null)return;
        handler.post(()->safe(()->{if(slot.peek()!=null&&!current()){invalidated++;discard("app removed or updated original");}}));
    }
    void beforeBatch(){safe(()->commit("native batch dismissal"));}
    void safetyChanged(){if(options.enabled&&!allowed.getAsBoolean())safe(()->suspend("integration suspended"));}
    private boolean skip(String why){skipped++;lastSkip=why;lastSkipApp=attemptApp;setStatus("stock dismissal: "+why);handler.post(changed);return false;}
    private String nativeExclusion(Object entry,View view,boolean companion)throws Exception{
        if(((Number)field(entry,"mCancellationReason")).intValue()!=-1)return "app already canceled the notification";
        if(!((Enum<?>)field(entry,"mDismissState")).name().equals("NOT_DISMISSED"))return "already dismissed in native pipeline";
        StatusBarNotification sbn=(StatusBarNotification)field(entry,"mSbn");Notification n=sbn.getNotification();
        if(sbn.getUserId()!=-1&&!sbn.getUser().equals(android.os.Process.myUserHandle()))return "another Android user";
        if(Notification.CATEGORY_TRANSPORT.equals(n.category)||n.extras!=null&&n.extras.containsKey(Notification.EXTRA_MEDIA_SESSION))return "media playback notification";
        if((n.flags&Notification.FLAG_FOREGROUND_SERVICE)!=0||((n.flags&Notification.FLAG_ONGOING_EVENT)!=0&&!wirelessAdb(sbn)))return "ongoing notification or foreground service";
        if(!clearable(sbn,view)||(n.flags&Notification.FLAG_NO_CLEAR)!=0)return "not user-clearable";
        // Do not call updateDismissInterceptors here: that mutates native bubble state.
        // An already-running native dismissal belongs to Android, not this grace.
        if(!((List<?>)field(entry,"mDismissInterceptors")).isEmpty())return "native bubble dismissal already in progress";
        if(n.fullScreenIntent!=null||Notification.CATEGORY_CALL.equals(n.category)||Notification.CATEGORY_ALARM.equals(n.category))return "call, alarm or full-screen notification";
        if(field(entry,"mRunningTask")!=null)return "notification content is being rebound";
        if((Boolean)field(entry,"mRemoteEditImeVisible")||(Boolean)field(entry,"mRemoteEditImeAnimatingAway"))return "active reply field";
        if(view!=null){
            if(!companion&&(n.flags&Notification.FLAG_GROUP_SUMMARY)==0&&(Boolean)view.getClass().getMethod("isSummaryWithChildren").invoke(view))return "native bundle has no original group summary";
            WindowInsets insets=view.getRootWindowInsets();
            if(insets!=null&&insets.isVisible(WindowInsets.Type.ime()))return "keyboard is visible";
        }
        return "";
    }
    private boolean interactive(){return context.getSystemService(PowerManager.class).isInteractive();}
    // Exact firmware SystemMessage.NOTE_ADB_WIFI_ACTIVE, posted by Android to UserHandle.ALL.
    private static boolean wirelessAdb(StatusBarNotification sbn){return "android".equals(sbn.getPackageName())&&sbn.getId()==62&&"DEVELOPER_IMPORTANT".equals(sbn.getNotification().getChannelId());}
    private boolean clearable(StatusBarNotification sbn,View view)throws Exception{
        Object provider=view==null?field(collection,"mDismissibilityProvider"):field(view,"mDismissibilityProvider");
        if(provider!=null&&((Set<?>)field(provider,"nonDismissableEntryKeys")).contains(sbn.getKey()))return false;
        return sbn.isClearable()||wirelessAdb(sbn)&&provider!=null;
    }
    private Object findStack(View v){for(ViewParent p=v.getParent();p!=null;p=p.getParent())if(p.getClass().getName().equals("com.android.systemui.statusbar.notification.stack.NotificationStackScrollLayout"))return p;return null;}
    private Object getEntry(String key)throws Exception{return collection.getClass().getMethod("getEntry",String.class).invoke(collection,key);}
    private boolean current()throws Exception{
        NotificationUndoSlot.Pending p=slot.peek();if(p==null)return false;Object now=getEntry(p.key);
        if(now!=p.entry||!slot.matches(p.key,now,field(now,"mSbn"))||((Number)field(now,"mCancellationReason")).intValue()!=-1||!((Enum<?>)field(now,"mDismissState")).name().equals("NOT_DISMISSED"))return false;
        StatusBarNotification sbn=(StatusBarNotification)p.generation;Notification n=sbn.getNotification();
        if(field(now,"row")!=row)return false;
        if(n.getBubbleMetadata()!=bubbleMetadata||bubbleState(n)!=bubbleState)return false;
        if(!((List<?>)field(now,"mDismissInterceptors")).isEmpty())return false;
        if(!Objects.equals(groupKey,sbn.isGroup()?sbn.getGroupKey():null))return false;
        if(group!=null&&!group.matches(groupMembers(groupKey)))return false;
        if(((n.flags&Notification.FLAG_GROUP_SUMMARY)!=0)!=primarySummary)return false;
        Object currentSummary=primarySummary?null:collection.getClass().getMethod("fetchSummaryToDismiss",now.getClass()).invoke(collection,now);
        if(currentSummary!=summary)return false;
        if(summary!=null&&(field(summary,"mSbn")!=summaryGeneration||field(summary,"row")!=summaryRow))return false;
        if(summary!=null){
            Notification sn=((StatusBarNotification)summaryGeneration).getNotification();
            if(sn.getBubbleMetadata()!=summaryBubbleMetadata||bubbleState(sn)!=summaryBubbleState||!((List<?>)field(summary,"mDismissInterceptors")).isEmpty())return false;
        }
        return clearable(sbn,(View)row)&&(n.flags&(Notification.FLAG_FOREGROUND_SERVICE|Notification.FLAG_NO_CLEAR))==0&&((n.flags&Notification.FLAG_ONGOING_EVENT)==0||wirelessAdb(sbn));
    }
    private static int bubbleState(Notification n){
        Notification.BubbleMetadata b=n.getBubbleMetadata();int state=n.flags&Notification.FLAG_BUBBLE;
        if(b!=null){
            if(b.isNotificationSuppressed())state|=1;
            if(b.isBubbleSuppressed())state|=2;
            if(b.getAutoExpandBubble())state|=4;
            if(b.isBubbleSuppressable())state|=8;
        }
        return state;
    }
    private List<NotificationUndoGroup.Member> groupMembers(String key)throws Exception{
        List<NotificationUndoGroup.Member> members=new ArrayList<>();
        for(Object entry:((Map<?,?>)field(collection,"mNotificationSet")).values()){
            StatusBarNotification sbn=(StatusBarNotification)field(entry,"mSbn");
            if(!Objects.equals(key,sbn.getGroupKey()))continue;
            if(((Number)field(entry,"mCancellationReason")).intValue()!=-1||!((Enum<?>)field(entry,"mDismissState")).name().equals("NOT_DISMISSED"))continue;
            boolean autoDismiss=(Boolean)collection.getClass().getMethod("shouldAutoDismissChildren",entry.getClass(),String.class).invoke(null,entry,key);
            members.add(new NotificationUndoGroup.Member(sbn.getKey(),entry,sbn,field(entry,"row"),bubbleState(sbn.getNotification())|(autoDismiss?GROUP_DISMISSIBLE:0)));
        }
        return members;
    }
    private void resetSummary()throws Exception{
        if(summary==null||summaryRow==null)return;
        StatusBarNotification sbn=(StatusBarNotification)summaryGeneration;
        if(getEntry(sbn.getKey())!=summary||field(summary,"mSbn")!=summaryGeneration||field(summary,"row")!=summaryRow)return;
        View view=(View)summaryRow;
        view.getClass().getField("mRemoved").setBoolean(view,false);
        view.getClass().getMethod("reset$1").invoke(view);
        view.getClass().getMethod("resetAllContentAlphas").invoke(view);
        view.requestLayout();
    }
    private void resetGroupRows()throws Exception{
        for(NotificationUndoGroup.Member child:groupHidden.values()){
            if(child.row==null||getEntry(child.key)!=child.entry||field(child.entry,"mSbn")!=child.generation||field(child.entry,"row")!=child.row||((Number)field(child.entry,"mCancellationReason")).intValue()!=-1)continue;
            View view=(View)child.row;
            view.getClass().getField("mRemoved").setBoolean(view,false);
            view.getClass().getMethod("reset$1").invoke(view);
            view.getClass().getMethod("resetAllContentAlphas").invoke(view);view.requestLayout();
        }
    }
    private void undo()throws Exception{
        if(!active()||!interactive()||!slot.undoable(SystemClock.elapsedRealtime())){commit("Undo expired");return;}
        if(!current()){invalidated++;discard("original no longer available");return;}
        NotificationUndoSlot.Pending p=slot.peek();View original=(View)row;
        slot.clear(p.token);stopShake();handler.removeCallbacks(timeout);hideBanner();
        try{resetOriginal(p,original);resetSummary();resetGroupRows();undone++;if(context.getSystemService(KeyguardManager.class).isKeyguardLocked())lockedUndos++;setStatus("same original restored");}
        finally{clearReferences();handler.post(this::rebuildSafely);}
    }
    private void commit(String why)throws Exception{
        NotificationUndoSlot.Pending p=slot.peek();if(p==null)return;
        if(!current()){invalidated++;discard("original replaced or removed");return;}
        Object capturedStats=stats;View original=(View)row;
        slot.clear(p.token);stopShake();handler.removeCallbacks(timeout);hideBanner();
        try{commitContext.begin(attachedSnapshots);collection.getClass().getMethod("dismissNotification",p.entry.getClass(),capturedStats.getClass()).invoke(collection,p.entry,capturedStats);committed++;setStatus(why);}
        catch(Throwable e){try{resetOriginal(p,original);}finally{handler.post(this::rebuildSafely);}throw e;}
        finally{commitContext.clear();clearReferences();}
    }
    private void resetOriginal(NotificationUndoSlot.Pending p,View original)throws Exception{
        if(getEntry(p.key)!=p.entry||field(p.entry,"row")!=original)return;
        if(stack!=null){Object swiped=field(stack,"mSwipedOutViews");if(swiped instanceof Collection<?>)((Collection<?>)swiped).remove(original);}
        original.getClass().getField("mRemoved").setBoolean(original,false);
        original.getClass().getMethod("reset$1").invoke(original);
        original.getClass().getMethod("resetAllContentAlphas").invoke(original);
        original.setAlpha(1);original.requestLayout();
    }
    private void discard(String why){
        NotificationUndoSlot.Pending p=slot.peek();View original=row instanceof View?(View)row:null;
        if(p!=null)slot.clear(p.token);stopShake();handler.removeCallbacks(timeout);hideBanner();
        if(p!=null&&original!=null)try{resetOriginal(p,original);resetSummary();resetGroupRows();}catch(Throwable ignored){}
        clearReferences();setStatus(why);handler.post(this::rebuildSafely);
    }
    private void suspend(String why)throws Exception{suspended=true;commit(why);stopShake();hideBanner();setStatus(why);}
    private void clearReferences(){stopShake();row=null;stack=null;stats=null;summary=null;summaryGeneration=null;summaryRow=null;group=null;groupKey=null;groupHidden.clear();attachedSnapshots.clear();primarySummary=false;bubbleMetadata=null;summaryBubbleMetadata=null;bubbleState=0;summaryBubbleState=0;}
    private void rebuild()throws Exception{if(collection!=null)collection.getClass().getMethod("dispatchEventsAndRebuildList",String.class).invoke(collection,"NodeNotificationUndo");}
    private void rebuildSafely(){safe(()->rebuild());}
    private int dp(Context c,int n){return Math.round(n*c.getResources().getDisplayMetrics().density);}
    private void showBanner()throws Exception{
        hideBanner();Display display=context.getSystemService(DisplayManager.class).getDisplay(0);
        if(display==null)throw new IllegalStateException("Display unavailable");
        Context wc=context.createDisplayContext(display).createWindowContext(2024,null);windows=wc.getSystemService(WindowManager.class);
        LinearLayout box=new LinearLayout(wc);box.setGravity(Gravity.CENTER_VERTICAL);box.setPadding(dp(wc,16),0,dp(wc,8),0);
        GradientDrawable bg=new GradientDrawable();bg.setColor(Color.rgb(40,45,52));bg.setCornerRadius(dp(wc,16));box.setBackground(bg);
        TextView text=new TextView(wc);text.setText("Notification dismissed");text.setTextColor(Color.WHITE);text.setTextSize(14);box.addView(text,new LinearLayout.LayoutParams(0,-2,1));
        Button button=new Button(wc);button.setText("Undo");button.setTextColor(Color.WHITE);button.setOnClickListener(v->safe(()->undo()));box.addView(button,new LinearLayout.LayoutParams(-2,-2));
        WindowManager.LayoutParams p=new WindowManager.LayoutParams(Math.min(dp(wc,340),display.getWidth()-dp(wc,32)),dp(wc,64),2024,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL|WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,PixelFormat.TRANSLUCENT);
        p.gravity=Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL;p.y=dp(wc,72);p.setTitle("NodeCockpit.NotificationUndo");
        WindowManager.LayoutParams.class.getField("privateFlags").setInt(p,0x20000000);
        banner=box;windows.addView(box,p);
    }
    private void startShake(){
        stopShake();shakeError="";
        NotificationUndoSlot.Pending pending=slot.peek();
        if(!shakeEnabled||pending==null)return;
        try{
            sensors=context.getSystemService(SensorManager.class);
            Sensor accelerometer=sensors==null?null:sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
            if(accelerometer==null){shakeError="accelerometer unavailable; use Undo button";return;}
            long now=SystemClock.elapsedRealtimeNanos();
            NotificationUndoShake detector=new NotificationUndoShake(now,now+Math.max(0,pending.deadline-SystemClock.elapsedRealtime())*1_000_000L,shakeSensitivity);
            shakeListener=new SensorEventListener(){
                public void onAccuracyChanged(Sensor sensor,int accuracy){}
                public void onSensorChanged(SensorEvent event){safe(()->{
                    NotificationUndoSlot.Pending current=slot.peek();
                    if(current==null||current.token!=pending.token||!active())return;
                    if(detector.sample(event.timestamp,event.values[0],event.values[1],event.values[2])){
                        int before=undone;undo();if(undone>before){shakeUndos++;handler.post(changed);}
                    }
                });}
            };
            if(!sensors.registerListener(shakeListener,accelerometer,SensorManager.SENSOR_DELAY_GAME,handler)){
                shakeError="accelerometer registration unavailable; use Undo button";stopShake();
            }
        }catch(RuntimeException e){shakeError=e.getClass().getSimpleName()+"; use Undo button";stopShake();}
    }
    private void stopShake(){
        SensorEventListener listener=shakeListener;shakeListener=null;
        if(listener!=null&&sensors!=null)try{sensors.unregisterListener(listener);}catch(RuntimeException ignored){}
    }
    private void hideBanner(){if(banner!=null){View old=banner;banner=null;try{if(old.isAttachedToWindow())windows.removeViewImmediate(old);}catch(RuntimeException e){failure(e);}}windows=null;}
    private static Object field(Object value,String name)throws Exception{return value.getClass().getField(name).get(value);}
    private void setStatus(String value){if(!status.equals(value)){status=value;handler.post(changed);}}
    private void failure(Throwable e){error=(e instanceof InvocationTargetException&&e.getCause()!=null?e.getCause():e).getClass().getSimpleName();android.util.Log.w("NodeNotificationUndo","Undo unavailable",e);}
    private void safe(Action a){try{a.run();}catch(Throwable e){suspended=true;failure(e);if(slot.peek()!=null)discard("Undo unavailable");else{hideBanner();setStatus("Undo unavailable");}}}
    private interface Action{void run()throws Exception;}
    String diagnostics(){return "enabled="+options.enabled+";active="+active()+";collection="+(collection!=null)+";pending="+(slot.peek()!=null)+";buttonEnabled="+options.button+";lockedAttempts="+lockedAttempts+";lockedHolds="+lockedHolds+";lockedUndos="+lockedUndos+";attempts="+attempts+";skipped="+skipped+";lastSkip="+lastSkip+";skipApp="+lastSkipApp+";shakeEnabled="+shakeEnabled+";shakeListening="+(shakeListener!=null)+";shakeUndos="+shakeUndos+";shakeError="+shakeError+";bubbleHolds="+bubbleHolds+";held="+held+";undone="+undone+";committed="+committed+";invalidated="+invalidated+";state="+status+";error="+error;}
}

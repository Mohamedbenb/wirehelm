package com.nodecockpit.customization;

import android.app.AlarmManager;
import android.app.KeyguardManager;
import android.content.*;
import android.database.ContentObserver;
import android.hardware.display.DisplayManager;
import android.os.*;
import android.provider.Settings;
import android.view.Display;
import java.lang.reflect.*;
import java.util.function.*;

/** Native notification-owned ambient sessions, plus the explicit bounded experiment. */
final class CameraRingAmbientController {
    private final Context context;
    private final Handler handler;
    private final BooleanSupplier allowed;
    private final Runnable changed;
    private final CameraRingAmbientSession session=new CameraRingAmbientSession();
    private final CameraRingAmbientAutomatic automatic=new CameraRingAmbientAutomatic();
    private final AlarmManager alarms;
    private final PowerManager power;
    private Object service,machine;
    private boolean requesting;
    private String status="idle",error="";
    private int entries,returns;
    private final AlarmManager.OnAlarmListener expiry=()->safe(()->{if(session.expiredTest(SystemClock.elapsedRealtime()))stop("expired");});
    CameraRingAmbientController(Context context,Handler handler,BooleanSupplier allowed,Runnable changed){
        this.context=context;this.handler=handler;this.allowed=allowed;this.changed=changed;
        alarms=context.getSystemService(AlarmManager.class);power=context.getSystemService(PowerManager.class);
        IntentFilter filter=new IntentFilter(Intent.ACTION_SCREEN_ON);filter.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
        context.registerReceiver(new BroadcastReceiver(){public void onReceive(Context c,Intent i){safe(()->{
            if(Intent.ACTION_SCREEN_ON.equals(i.getAction())){automatic.suspend();stop("wake");}
            else {automatic.nativeOpportunity();evaluate();}
        });}},filter,null,handler,Context.RECEIVER_NOT_EXPORTED);
        context.getContentResolver().registerContentObserver(Settings.Secure.getUriFor("doze_always_on"),false,new ContentObserver(handler){public void onChange(boolean self){safe(()->{automatic.nativeOpportunity();evaluate();});}});
    }
    void demand(String value){safe(()->{automatic.demand(value);if(!automatic.wanted()&&session.automatic())stop("notifications cleared or mode off");evaluate();});}
    void arm(){safe(()->{
        automatic.suspend();stop("replaced");error="";
        if(!allowed.getAsBoolean())throw new IllegalStateException("Integration unavailable");
        if(!aodOff())throw new IllegalStateException("Turn Always-on display off for this test");
        session.arm(SystemClock.elapsedRealtime());
        // One wake-up expiry for a bounded test; no recurring alarm or held wake lock.
        alarms.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP,session.deadline(),"NodeCameraRingAmbientExpiry",expiry,handler);
        setStatus("armed: lock normally");evaluate();
    });}
    void started(Object value){safe(()->{if(service!=value&&session.automatic())session.clear();service=value;machine=field(value,"mDozeMachine");automatic.nativeOpportunity();handler.post(this::check);});}
    void stopped(Object value){safe(()->{if(service==value){alarms.cancel(expiry);automatic.suspend();session.clear();service=null;machine=null;setStatus("native session stopped");}});}
    void nativeShowRequest(){safe(()->{alarms.cancel(expiry);automatic.suspend();session.clear();setStatus("native ambient request took over");});}
    void nativeRequest(Object value,Object requested){safe(()->{
        if(!requesting&&session.deadline()!=0&&requested instanceof Enum<?>){
            if(session.automatic()&&!aodOff()){session.clear();automatic.suspend();setStatus("Android AOD enabled");return;}
            boolean wasOwned=session.owned();session.nativeRequest(value,((Enum<?>)requested).name(),state(value));
            if(session.automatic()&&wasOwned&&!session.owned()){session.clear();automatic.suspend();setStatus("native owner took over");}
        }
    });}
    void transitioned(Object value,Object requested){safe(()->{
        if(value!=machine)return;
        if(!requesting&&requested instanceof Enum<?> && ((Enum<?>)requested).name().equals("DOZE_PULSE_DONE"))automatic.nativeOpportunity();
        if(session.live(SystemClock.elapsedRealtime())||automatic.ready())handler.post(this::check);
    });}
    void nativeSensor(){safe(()->{if(automatic.wanted()){automatic.nativeOpportunity();handler.post(this::check);}});}
    void check(){safe(()->evaluate());}
    void cancel(String why){safe(()->{automatic.suspend();stop(why);});}
    private void evaluate()throws Exception{
        if(session.deadline()==0){
            if(!automatic.ready()||!allowed.getAsBoolean()||!aodOff()||power.isInteractive()||machine==null||service==null||!state(machine).equals("DOZE"))return;
            // Consume before checking safety/proximity: reports and display invalidations
            // cannot repeatedly query the sensor or fight a native suppression.
            if(!automatic.take())return;
            if(!safeNativeState()){setStatus("automatic waiting for native eligibility");return;}
            error="";session.armAutomatic();
        }
        if(!session.live(SystemClock.elapsedRealtime())){stop("expired");return;}
        if(!allowed.getAsBoolean()||!aodOff()){stop("safety or AOD setting changed");return;}
        if(power.isInteractive()||machine==null||service==null)return;
        if(!safeNativeState()) {stop("native state unavailable or suppressed");return;}
        String state=state(machine);
        if(!state.equals("DOZE"))return;
        if(!session.begin(machine,SystemClock.elapsedRealtime()))return;
        Object target=machine;long token=session.generation();
        Object triggers=null;
        for(Object part:(Object[])field(target,"mParts"))if(part.getClass().getName().equals("com.android.systemui.doze.DozeTriggers")){triggers=part;break;}
        if(triggers==null)throw new IllegalStateException("Native proximity check unavailable");
        setStatus("checking native proximity");
        Consumer<Object> result=near->handler.post(()->safe(()->{
            if(token!=session.generation()||target!=machine||!session.live(SystemClock.elapsedRealtime()))return;
            if(!Boolean.FALSE.equals(near)){stop("proximity near or unknown");return;}
            if(!allowed.getAsBoolean()||!aodOff()||power.isInteractive()||!safeNativeState()||!state(target).equals("DOZE")){stop("entry conditions changed");return;}
            if(!session.claim(token,target,SystemClock.elapsedRealtime()))return;
            request(target,"DOZE_AOD");
            String actual=state(target);
            if(actual.equals("DOZE_AOD")){entries++;setStatus(session.automatic()?"notification ambient active":"native AOD entered; stock content may show");}
            else {session.nativeRequest(target,actual);stop("native entry declined: "+actual);}
        }));
        triggers.getClass().getMethod("proximityCheckThenCall",Consumer.class,boolean.class,int.class).invoke(triggers,result,false,0);
    }
    private boolean safeNativeState()throws Exception{
        if(machine==null||executing(machine))return false;
        if(((Number)field(machine,"mUserTracker").getClass().getMethod("getUserId").invoke(field(machine,"mUserTracker"))).intValue()!=0)return false;
        if(((Number)Class.forName("android.app.ActivityManager").getMethod("getCurrentUser").invoke(null)).intValue()!=0)return false;
        Display d=context.getSystemService(DisplayManager.class).getDisplay(0);
        if(d==null||d.getRotation()!=0||!context.getSystemService(KeyguardManager.class).isKeyguardLocked())return false;
        Object host=field(machine,"mDozeHost");
        if((Boolean)field(host,"mAlwaysOnSuppressed")||(Boolean)field(field(host,"mBatteryController"),"mAodPowerSave")||power.isPowerSaveMode())return false;
        Object provisioned=field(host,"mDeviceProvisionedController");
        if(!((java.util.concurrent.atomic.AtomicBoolean)field(provisioned,"deviceProvisioned")).get()||!(Boolean)provisioned.getClass().getMethod("isCurrentUserSetup").invoke(provisioned))return false;
        Object lazy=field(host,"mBiometricUnlockControllerLazy");Object bio=lazy.getClass().getMethod("get").invoke(lazy);
        return !(Boolean)bio.getClass().getMethod("hasPendingAuthentication").invoke(bio);
    }
    private void stop(String why)throws Exception{
        alarms.cancel(expiry);
        Object target=machine;
        boolean release=target!=null&&session.mayRelease(target,state(target))&&!power.isInteractive()&&aodOff()&&!executing(target);
        session.clear();
        if(release){request(target,"DOZE");if(state(target).equals("DOZE"))returns++;}
        setStatus(why);
    }
    private boolean aodOff(){return Settings.Secure.getInt(context.getContentResolver(),"doze_always_on",1)==0;}
    private static Object field(Object value,String name)throws Exception{return value.getClass().getField(name).get(value);}
    private static String state(Object value)throws Exception{return ((Enum<?>)field(value,"mState")).name();}
    private static boolean executing(Object value)throws Exception{return (Boolean)value.getClass().getMethod("isExecutingTransition").invoke(value);}
    @SuppressWarnings({"unchecked","rawtypes"})
    private void request(Object target,String state)throws Exception{
        Class<? extends Enum> type=(Class<? extends Enum>)field(target,"mState").getClass();
        requesting=true;try{target.getClass().getMethod("requestState",type).invoke(target,Enum.valueOf(type,state));}finally{requesting=false;}
    }
    private void setStatus(String value){if(!status.equals(value)){status=value;handler.post(changed);}}
    private void safe(Action action){try{action.run();}catch(Throwable e){automatic.suspend();error=e.getClass().getSimpleName();if(e instanceof InvocationTargetException&&e.getCause()!=null)error=e.getCause().getClass().getSimpleName();try{stop("unavailable");}catch(Throwable cleanup){session.clear();try{alarms.cancel(expiry);}catch(Throwable ignored){}status="cleanup unavailable";}handler.post(changed);android.util.Log.w("NodeCameraRing","Ambient controller unavailable",e);}}
    private interface Action{void run()throws Exception;}
    String diagnostics(){return status+";entries="+entries+";returns="+returns+";owned="+session.owned()+";automatic="+session.automatic()+";demand="+automatic.wanted()+";error="+error;}
}

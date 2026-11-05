package com.nodecockpit.customization;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.net.TrafficStats;
import android.net.Uri;
import android.os.*;
import android.util.TypedValue;
import android.view.*;
import android.widget.*;
import java.lang.reflect.Method;
import java.util.concurrent.*;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedInterface;

/** Generic libxposed API 102; this entry never loads Flutter or requests root. */
public final class NetworkSpeedModule extends XposedModule {
    private Handler main;
    private final ExecutorService diagnostics = Executors.newSingleThreadExecutor();
    private final ExecutorService configurationDelivery=Executors.newSingleThreadExecutor();
    private final java.util.concurrent.atomic.AtomicBoolean configFetchPending=new java.util.concurrent.atomic.AtomicBoolean();
    private final java.util.concurrent.atomic.AtomicBoolean configFetchAgain=new java.util.concurrent.atomic.AtomicBoolean();
    private SharedPreferences prefs;
    private TextView clock;
    private Context context;
    private boolean quarantined, started, listenerRegistered;
    private long previousRx=-1, previousTx=-1, previousTime, lastReport;
    private final java.util.concurrent.atomic.AtomicBoolean reportPending = new java.util.concurrent.atomic.AtomicBoolean();
    private final java.util.concurrent.atomic.AtomicBoolean reportAgain = new java.util.concurrent.atomic.AtomicBoolean();
    private String state="loaded", error="";
    private String functionalSignature="", geometrySignature="", visualSignature="", contentSignature="", safetySignature="";
    private long quarantineRevision = -1;
    private boolean hookInstalled;
    private CameraNotificationRing cameraRing;
    private NotificationUndoController notificationUndo;
    private Object notificationUndoCollection;
    private boolean notificationUndoHooksReady;
    private CameraRingAmbientController cameraRingAmbient;
    private boolean cameraRingAmbientHooksReady;
    private boolean cameraRingArmed;
    private Object cameraRingListBuilder;
    private boolean cameraRingFinalListReady;
    private boolean cameraRingObservationReady;
    private final CameraRingEligibility ringEligibility=new CameraRingEligibility();
    private String cameraRingListError="Waiting for final shade list";
    private boolean ringSnapshotPending;
    public NetworkSpeedModule() {
        // A bounded fallback for runtimes that instantiate an entry but miss package callbacks.
        // Never call framework APIs in the constructor, before attachFramework has completed.
        try {
            Handler bootstrap = new Handler(Looper.getMainLooper());
            bootstrap.postDelayed(new Runnable() {
                int attempts;
                @Override public void run() {
                    try {
                        Class<?> thread = Class.forName("android.app.ActivityThread");
                        android.app.Application application = (android.app.Application) thread.getDeclaredMethod("currentApplication").invoke(null);
                        if (application != null) {
                            if (!"com.android.systemui".equals(application.getPackageName())) return;
                            if (!mainProcess()) return;
                            start(application);
                            installHook(application.getClassLoader());
                            attachExistingWindows();
                            if (meter != null && meter.isAttachedToWindow()) return;
                        }
                    } catch (Throwable e) {
                        if (attempts == 39) android.util.Log.e("NodeCockpit", "Deferred hook initialization failed", e);
                    }
                    if (++attempts < 40) bootstrap.postDelayed(this, 500);
                }
            }, 100);
        } catch (Throwable e) { android.util.Log.e("NodeCockpit", "Deferred hook unavailable", e); }
    }
    private void attachExistingWindows() throws Exception {
        Class<?> global = Class.forName("android.view.WindowManagerGlobal");
        Object instance = global.getDeclaredMethod("getInstance").invoke(null);
        Object windows = global.getDeclaredMethod("getWindowViews").invoke(instance);
        if (windows instanceof java.util.List<?>) {
            int[] budget = {2000};
        }
    }
    private void findStatusBar(View view, int[] budget, int depth) {
        if (--budget[0] < 0 || depth > 30) return;
        if ("com.android.systemui.statusbar.phone.KeyguardStatusBarView".equals(view.getClass().getName())) observeKeyguardCollision(view);
        if ("com.android.systemui.statusbar.phone.PhoneStatusBarView".equals(view.getClass().getName())) { observe(view); return; }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)view;
            for (int i=0;i<group.getChildCount();i++) findStatusBar(group.getChildAt(i),budget,depth+1);
        }
    }
    @Override public void onModuleLoaded(ModuleLoadedParam param) {
        log(android.util.Log.INFO, "NodeCockpit", "Hook protocol 10 loaded in " + param.getProcessName() + "; systemServer=" + param.isSystemServer());
        if (!"com.android.systemui".equals(param.getProcessName()) || param.isSystemServer()) return;
        try {
            log(android.util.Log.INFO, "NodeCockpit", "SystemUI module loaded; waiting for application attachment");
            Method attach = android.app.Application.class.getDeclaredMethod("attach", Context.class);
            hook(attach).intercept(new ApplicationAttachHooker());
        } catch (Throwable e) { log(android.util.Log.ERROR, "NodeCockpit", "Application attachment hook unavailable", e); }
    }
    private IndicatorSettings settings;
    private View statusBar;
    private LinearLayout meter;
    private FrameLayout meterOverlay;
    private View collisionRoot;
    private final java.util.WeakHashMap<View,Boolean> keyguardCollisionRoots=new java.util.WeakHashMap<>();
    private int collisionEndContentId,collisionSystemIconsId;
    private final java.util.ArrayList<View> collisionViews=new java.util.ArrayList<>();
    private final Rect collisionRect=new Rect();
    private final int[] collisionRootLocation=new int[2];
    private int[] collisionIntervals=new int[128];
    private boolean meterCrowded;
    private int placementRequestedLeft,placementActualLeft,placementBlocks,placementAdjustments;
    private final ViewTreeObserver.OnGlobalLayoutListener collisionLayoutListener=() -> {
        try { refreshCollisionViews(); positionFloatingMeter(); } catch (Throwable error) { fail(error); }
    };
    private final ViewTreeObserver.OnPreDrawListener collisionDrawListener=() -> {
        try { positionFloatingMeter(); } catch (Throwable error) { fail(error); }
        return true;
    };
    private String meterDesignSignature="";
    private TextView download, upload, downloadArrow, uploadArrow;
    private LinearLayout downloadGroup, uploadGroup;
    private EdgePanelController edgeController;
    private int settingsCallbacks, safetyOnlyCallbacks, healthCallbacks, edgeFailures;
    private String edgeError="";
    private int boot=-1, attachments, detachments, counterResets, preferenceUpdates, recoveryScans, deliveryFailures;
    private int wakeGeneration,wakeRecoveries;
    private boolean screenInteractive=true, wakePending;
    private boolean wakeFetchPending;
    private long lastRecoveryScan, lastSample;
    private double rxRate, txRate;
    private String hiddenReason="waitingForStatusBar";
    private final java.util.WeakHashMap<View,Boolean> observedRoots = new java.util.WeakHashMap<>();
    private final Runnable configChanged = () -> {
        try {
            if (prefs!=null) acceptSettings(new IndicatorSettings(prefs.getAll()));
        } catch (Throwable e) { fail(e); }
    };
    private final SharedPreferences.OnSharedPreferenceChangeListener configListener = (p,k) -> {
        main.removeCallbacks(configChanged);
        main.post(configChanged);
    };
    private final Runnable tick = new Runnable() { @Override public void run() {
        if (context!=null) {
            PowerManager power=(PowerManager)context.getSystemService(Context.POWER_SERVICE);
            if (power!=null&&!power.isInteractive()) { if (screenInteractive) suspendForSleep(); return; }
        }
        if (!screenInteractive) return;
        try { sample(); } catch (Throwable e) { fail(e); }
        if (context != null && screenInteractive) main.postDelayed(this, interval());
    }};
    @Override public void onPackageReady(PackageReadyParam param) {
        if (!"com.android.systemui".equals(param.getPackageName())) return;
        installHook(param.getClassLoader());
    }
    private synchronized void installHook(ClassLoader loader) {
        if (hookInstalled || !mainProcess()) return;
        try {
            main = new Handler(Looper.getMainLooper());
            android.util.Log.i("NodeCockpit", "SystemUI module entry reached");
            installNotificationUndoHooks(loader);
            try {
                Class<?> dozeService=Class.forName("com.android.systemui.doze.DozeService",false,loader);
                hook(dozeService.getDeclaredMethod("onDreamingStarted")).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    Object result=c.proceed();if(cameraRingAmbient!=null)cameraRingAmbient.started(c.getThisObject());return result;
                }});
                for(String name:new String[]{"onDreamingStopped","onDestroy"})hook(dozeService.getDeclaredMethod(name)).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    if(cameraRingAmbient!=null)cameraRingAmbient.stopped(c.getThisObject());return c.proceed();
                }});
                hook(dozeService.getDeclaredMethod("onRequestShowDoze")).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    if(cameraRingAmbient!=null)cameraRingAmbient.nativeShowRequest();return c.proceed();
                }});
                Class<?> machine=Class.forName("com.android.systemui.doze.DozeMachine",false,loader);
                Class<?> state=Class.forName("com.android.systemui.doze.DozeMachine$State",false,loader);
                Method request=machine.getDeclaredMethod("requestState",state,int.class);deoptimize(request);
                hook(request).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    if(cameraRingAmbient!=null)cameraRingAmbient.nativeRequest(c.getThisObject(),c.getArg(0));return c.proceed();
                }});
                Method transition=machine.getDeclaredMethod("transitionTo",state,int.class);deoptimize(transition);
                hook(transition).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    Object result=c.proceed();if(cameraRingAmbient!=null)cameraRingAmbient.transitioned(c.getThisObject(),c.getArg(0));return result;
                }});
                Class<?> triggers=Class.forName("com.android.systemui.doze.DozeTriggers",false,loader);
                Method sensor=triggers.getDeclaredMethod("onSensor",int.class,float.class,float.class,float[].class);deoptimize(sensor);
                hook(sensor).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    Object result=c.proceed();if(cameraRingAmbient!=null)cameraRingAmbient.nativeSensor();return result;
                }});
                cameraRingAmbientHooksReady=true;
            }catch(Throwable e){cameraRingAmbientHooksReady=false;android.util.Log.w("NodeCameraRing","Ambient proof hooks unavailable",e);}
            try {
                prefs = getRemotePreferences(FeaturePolicy.GROUP);
                acceptSettings(new IndicatorSettings(prefs.getAll()));
                prefs.registerOnSharedPreferenceChangeListener(configListener);
            } catch (Throwable e) {
                prefs=null;
                settings=new IndicatorSettings(java.util.Collections.emptyMap());
                log(android.util.Log.WARN,"NodeCockpit","Remote preferences unavailable; using the manager bridge",e);
            }
            try{
                Class<?> builder=Class.forName("com.android.systemui.statusbar.notification.collection.ShadeListBuilder",false,loader);
                for(java.lang.reflect.Constructor<?> constructor:builder.getDeclaredConstructors())hook(constructor).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    Object result=c.proceed();cameraRingListBuilder=c.getThisObject();return result;
                }});
                Class<?> renderer=Class.forName("com.android.systemui.statusbar.notification.collection.render.RenderStageManager",false,loader);
                Method completed=null;for(Method m:renderer.getDeclaredMethods())if(m.getName().equals("dispatchOnAfterRenderEntries")&&m.getParameterCount()==2&&m.getParameterTypes()[1]==java.util.List.class){completed=m;break;}
                if(completed==null)throw new NoSuchMethodException("Final shade render boundary");
                deoptimize(completed);hook(completed).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                    Object result=c.proceed();cameraRingFinalListReady=true;acceptRingRendered(c.getArg(1),c.getExecutable().getDeclaringClass().getClassLoader());return result;
                }});
                Class<?> collection=Class.forName("com.android.systemui.statusbar.notification.collection.NotifCollection",false,loader);
                Class<?> entry=Class.forName("com.android.systemui.statusbar.notification.collection.NotificationEntry",false,loader);
                for(Method m:new Method[]{collection.getDeclaredMethod("locallyDismissNotifications",java.util.List.class,boolean.class),collection.getDeclaredMethod("tryRemoveNotification",entry)}){
                    deoptimize(m);hook(m).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                        Object result=c.proceed();refreshRingNotifications();return result;
                    }});
                }
                cameraRingObservationReady=true;
            }catch(Throwable e){cameraRingObservationReady=false;cameraRingListError="Shade observer: "+e.getClass().getSimpleName();android.util.Log.w("NodeCameraRing","Filtered notification observation unavailable",e);}
            Class<?> statusBar = Class.forName("com.android.systemui.statusbar.phone.PhoneStatusBarView", false, loader);
            Method inflate = statusBar.getDeclaredMethod("onFinishInflate");
            hook(inflate).intercept(new StatusBarInflateHooker());
            installForegroundWindowHook(loader);
            try{Class<?> keyguardBar=Class.forName("com.android.systemui.statusbar.phone.KeyguardStatusBarView",false,loader);hook(keyguardBar.getDeclaredMethod("onFinishInflate")).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain chain)throws Throwable{Object result=chain.proceed();Object view=chain.getThisObject();if(view instanceof View)observeKeyguardCollision((View)view);return result;}});}catch(Throwable unsupported){android.util.Log.w("NodeCockpit","Keyguard collision root fallback",unsupported);}
            hookInstalled=true;
            log(android.util.Log.INFO, "NodeCockpit", "SystemUI-only hook installed; config defaults disabled");
        } catch (Throwable e) {
            android.util.Log.e("NodeCockpit", "SystemUI hook initialization failed", e);
            log(android.util.Log.ERROR, "NodeCockpit", "Unsupported SystemUI hook point; no hooks installed", e);
        }
    }
    private boolean foregroundWindowHookInstalled;
    private void installForegroundWindowHook(ClassLoader loader){if(foregroundWindowHookInstalled)return;
        for(String name:new String[]{"com.android.systemui.statusbar.phone.SystemBarAttributesListener","com.android.systemui.statusbar.CommandQueue"})try{
            Class<?> type=Class.forName(name,false,loader);for(Method m:type.getDeclaredMethods())if(m.getName().equals("onSystemBarAttributesChanged")&&java.util.Arrays.asList(m.getParameterTypes()).contains(String.class)){
                hook(m).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain chain)throws Throwable{Object result=chain.proceed();try{String pkg=null;for(Object a:chain.getArgs())if(a instanceof String){pkg=(String)a;break;}if(pkg!=null&&!pkg.isEmpty()&&main!=null){final String value=pkg;main.post(()->{try{if(edgeController!=null)edgeController.foregroundPackage(value);}catch(Throwable e){android.util.Log.w("NodeCockpit","Overlay foreground guard",e);}});}}catch(Throwable e){android.util.Log.w("NodeCockpit","Overlay focus observation unavailable",e);}return result;}});foregroundWindowHookInstalled=true;return;
            }
        }catch(Throwable ignored){}android.util.Log.w("NodeCockpit","Overlay focus hook unavailable; task-stack guard retained");
    }
    private final class ApplicationAttachHooker implements XposedInterface.Hooker {
        @Override public Object intercept(XposedInterface.Chain chain) throws Throwable {
            Object result=chain.proceed();
            try {
                Context target=(Context)chain.getArgs().get(0);
                if ("com.android.systemui".equals(target.getPackageName())) { start(target); installHook(target.getClassLoader()); }
            } catch (Throwable e) { log(android.util.Log.ERROR,"NodeCockpit","Application attachment failed",e); }
            return result;
        }
    }
    private final class StatusBarInflateHooker implements XposedInterface.Hooker {
        @Override public Object intercept(XposedInterface.Chain chain) throws Throwable {
            Object result=chain.proceed();
            try {
                View view=(View)chain.getThisObject();
                main.post(() -> { try { observe(view); } catch (Throwable e) { fail(e); } });
            } catch (Throwable e) { log(android.util.Log.ERROR,"NodeCockpit","Indicator attachment failed",e); }
            return result;
        }
    }
    private void installNotificationUndoHooks(ClassLoader loader){
        try{
            Class<?> row=Class.forName("com.android.systemui.statusbar.notification.row.ExpandableNotificationRow",false,loader);
            Class<?> entry=Class.forName("com.android.systemui.statusbar.notification.collection.NotificationEntry",false,loader);
            Class<?> collection=Class.forName("com.android.systemui.statusbar.notification.collection.NotifCollection",false,loader);
            Class<?> stats=Class.forName("com.android.systemui.statusbar.notification.collection.notifcollection.DismissedByUserStats",false,loader);
            for(String name:new String[]{"mKey","mRemoved","mOnUserInteractionCallback","mDismissibilityProvider"})row.getField(name);
            for(String name:new String[]{"reset$1","resetAllContentAlphas","isChildInGroup","isSummaryWithChildren"})row.getMethod(name);
            for(String name:new String[]{"row","mSbn","mCancellationReason","mDismissState","mDismissInterceptors","mRunningTask","mRemoteEditImeVisible","mRemoteEditImeAnimatingAway"})entry.getField(name);
            Class<?> stack=Class.forName("com.android.systemui.statusbar.notification.stack.NotificationStackScrollLayout",false,loader);stack.getField("mClearAllInProgress");stack.getField("mSwipedOutViews");
            collection.getMethod("getEntry",String.class);collection.getMethod("dismissNotification",entry,stats);
            collection.getField("mNotificationSet");collection.getField("mDismissibilityProvider");collection.getMethod("fetchSummaryToDismiss",entry);collection.getMethod("shouldAutoDismissChildren",entry,String.class);
            for(java.lang.reflect.Constructor<?> constructor:collection.getDeclaredConstructors())hook(constructor).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                Object result=c.proceed();notificationUndoCollection=c.getThisObject();if(notificationUndo!=null)notificationUndo.collection(notificationUndoCollection);return result;
            }});
            Method attached=entry.getDeclaredMethod("getAttachedNotifChildren");deoptimize(attached);
            hook(attached).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                java.util.List<?> captured=notificationUndo==null?null:notificationUndo.childrenDuringCommit(c.getThisObject());
                return captured==null?c.proceed():captured;
            }});
            Method dismiss=row.getDeclaredMethod("performDismiss",boolean.class);deoptimize(dismiss);
            hook(dismiss).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                if(notificationUndo!=null&&notificationUndo.hold((View)c.getThisObject(),(Boolean)c.getArg(0)))return null;return c.proceed();
            }});
            Class<?> filter=Class.forName("com.android.systemui.statusbar.notification.collection.coordinator.KeyguardCoordinator$notifFilter$1",false,loader);
            Method shouldFilter=filter.getDeclaredMethod("shouldFilterOut",entry,long.class);deoptimize(shouldFilter);
            hook(shouldFilter).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                Object result=c.proceed();if(Boolean.TRUE.equals(result))return result;return notificationUndo!=null&&notificationUndo.hides(c.getArg(0));
            }});
            Method changed=collection.getDeclaredMethod("dispatchEventsAndRebuildList",String.class);deoptimize(changed);
            hook(changed).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                Object result=c.proceed();if(notificationUndo!=null)notificationUndo.collectionChanged();return result;
            }});
            Method batch=collection.getDeclaredMethod("dismissNotifications",java.util.List.class,boolean.class);deoptimize(batch);
            hook(batch).intercept(new XposedInterface.Hooker(){public Object intercept(XposedInterface.Chain c)throws Throwable{
                if(notificationUndo!=null&&((Boolean)c.getArg(1)||((java.util.List<?>)c.getArg(0)).size()>1))notificationUndo.beforeBatch();return c.proceed();
            }});
            notificationUndoHooksReady=true;
        }catch(Throwable e){notificationUndoHooksReady=false;android.util.Log.w("NodeNotificationUndo","Notification Undo hooks unavailable",e);}
    }
    private void start(Context c) {
        if (!mainProcess()) return;
        if (main==null) main=new Handler(Looper.getMainLooper());
        context=c.getApplicationContext();
        if(notificationUndo==null)try{notificationUndo=new NotificationUndoController(context,main,()->notificationUndoHooksReady&&cameraRingArmed&&!quarantined&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT),()->report(true));if(notificationUndoCollection!=null)notificationUndo.collection(notificationUndoCollection);}catch(Throwable e){android.util.Log.w("NodeNotificationUndo","Notification Undo initialization unavailable",e);}
        if(cameraRing==null)try{cameraRingAmbient=new CameraRingAmbientController(context,main,()->cameraRingAmbientHooksReady&&cameraRingArmed&&!quarantined&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT),()->report(true));cameraRing=new CameraNotificationRing(context,main,()->cameraRingArmed&&!quarantined&&FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT),()->report(true),this::reconcileRingNotifications,cameraRingAmbient);if(settings!=null)cameraRing.configure(settings.cameraRing);refreshRingNotifications();}catch(Throwable e){android.util.Log.w("NodeCameraRing","Notification ring unavailable",e);}
        boolean newEdge=edgeController==null;
        if (newEdge) edgeController=new EdgePanelController(context,main,this::edgeFail);
        boot=android.provider.Settings.Global.getInt(c.getContentResolver(),android.provider.Settings.Global.BOOT_COUNT,-1);
        if(settings!=null&&settings.safetyValid(boot,SystemClock.elapsedRealtime()))cameraRingArmed=true;
        if(notificationUndo!=null&&settings!=null)notificationUndo.configure(settings.notificationUndo,settings.revision);
        if (!started) {
            started=true;
            android.os.PowerManager power=(android.os.PowerManager)context.getSystemService(Context.POWER_SERVICE);
            screenInteractive=power==null||power.isInteractive();
            try { context.getContentResolver().registerContentObserver(Uri.parse("content://com.example.remote_control.customization.health/configuration"),false,
                new android.database.ContentObserver(main) { @Override public void onChange(boolean selfChange) { requestConfiguration(); } });
            } catch (Throwable error) { android.util.Log.w("NodeCockpit","Immediate configuration observer unavailable",error); }
            main.post(tick);
        }
        // Preferences may arrive before context/window creation. Apply them to a new
        // controller immediately instead of waiting for the next safety lease update.
        if (newEdge&&settings!=null) edgeController.apply(settings,visualsAllowed(settings),true,true,true,true);
    }
    private boolean mainProcess() {
        return Build.VERSION.SDK_INT>=28 && "com.android.systemui".equals(android.app.Application.getProcessName());
    }
    private void observe(View view) {
        if (!observedRoots.containsKey(view)) {
            observedRoots.put(view,true);
            view.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
                @Override public void onViewAttachedToWindow(View v) {
                    main.post(() -> { try { if (v.isAttachedToWindow()) attach(v); } catch (Throwable e) { fail(e); } });
                }
                @Override public void onViewDetachedFromWindow(View v) {
                    if (v==statusBar) {
                        detachments++; hiddenReason="detached"; lastRecoveryScan=0;
                        main.postDelayed(() -> { try { attachExistingWindows(); } catch (Throwable ignored) {} },100);
                    }
                }
            });
        }
        if (view.isAttachedToWindow()) attach(view);
    }
    private void attach(View root) {
        if (!root.isAttachedToWindow() || root.getDisplay()==null || root.getDisplay().getDisplayId()!=0) return;
        if (root==statusBar && meter!=null && meter.isAttachedToWindow()) return;
        if (statusBar!=null && statusBar.isAttachedToWindow() && statusBar.isShown() && !root.isShown()) return;
        start(root.getContext());
        if (context.getPackageManager().isSafeMode()) { state="disabled"; report(true); return; }
        if (!FeaturePolicy.supported(Build.VERSION.SDK_INT,Build.FINGERPRINT)) {
            state="unsupported"; error="Android/SystemUI build not validated"; report(true); return;
        }
        int clockId=root.getResources().getIdentifier("clock","id","com.android.systemui");
        View found=root.findViewById(clockId);
        if (!(found instanceof TextView) || !(found.getParent() instanceof LinearLayout)) {
            state="unsupported"; error="Expected clock row not found; layout left untouched"; report(true); return;
        }
        clock=(TextView)found;
        if (edgeController!=null) edgeController.setSignalView(clock);
        LinearLayout parent=(LinearLayout)clock.getParent();
        if (meter!=null && meter.getParent() instanceof ViewGroup) ((ViewGroup)meter.getParent()).removeView(meter);
        if (meterOverlay!=null && meterOverlay.getParent() instanceof ViewGroup) ((ViewGroup)meterOverlay.getParent()).removeView(meterOverlay);
        meterOverlay=null; meterDesignSignature="";
        statusBar=root;
        observeCollisionLayout(root);
        meter=new LinearLayout(root.getContext());
        meter.setTag("node_cockpit_network_speed");
        meter.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> positionFloatingMeter());
        meter.setGravity(Gravity.CENTER_VERTICAL);
        meter.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        // Padding and inter-column spacing are applied from the live settings
        // during render so users can tune the meter for their SystemUI layout.
        download=column(root.getContext()); upload=column(root.getContext());
        downloadArrow=column(root.getContext()); uploadArrow=column(root.getContext());
        downloadGroup=rateGroup(downloadArrow,download); uploadGroup=rateGroup(uploadArrow,upload);
        meter.addView(downloadGroup); meter.addView(uploadGroup);
        refreshCollisionViews();
        placeMeter();
        if (!listenerRegistered) {
            context.registerReceiver(new BroadcastReceiver() {
                @Override public void onReceive(Context c,Intent i) {
                    if (FeaturePolicy.ACTION_DISABLE.equals(i.getAction())) {
                        quarantined=true; quarantineRevision=settings==null?0:settings.revision; render(); report(true);
                    }
                }
            },new IntentFilter(FeaturePolicy.ACTION_DISABLE),Manifest.permission.DUMP,main,Context.RECEIVER_EXPORTED);
            IntentFilter wakeFilter=new IntentFilter(Intent.ACTION_SCREEN_ON); wakeFilter.addAction(Intent.ACTION_USER_PRESENT); wakeFilter.addAction(Intent.ACTION_USER_UNLOCKED); wakeFilter.addAction(Intent.ACTION_SCREEN_OFF);
            context.registerReceiver(new BroadcastReceiver() {
                @Override public void onReceive(Context c,Intent i) {
                    if (Intent.ACTION_SCREEN_OFF.equals(i.getAction())) suspendForSleep();
                    else scheduleWakeRecovery();
                }
            },wakeFilter,null,main,Context.RECEIVER_NOT_EXPORTED);
            listenerRegistered=true;
        }
        attachments++;
        render(); report(true);
    }
    private void suspendForSleep() {
        screenInteractive=false; wakePending=true; wakeGeneration++;
        main.removeCallbacks(tick); previousRx=-1; previousTime=0;
        render(); // Suspend samplers/windows, never change saved preferences.
    }
    private void scheduleWakeRecovery() {
        if (screenInteractive&&wakePending) return; // Coalesce unlock broadcasts for this wake.
        if (screenInteractive&&!wakePending) { render(); if (edgeController!=null) edgeController.recoverAfterWake(); return; }
        screenInteractive=true;
        wakePending=true;
        int generation=++wakeGeneration;
        main.removeCallbacks(tick);
        verifyWake(generation,0);
    }
    private void verifyWake(int generation,int attempt) {
        if (!screenInteractive||generation!=wakeGeneration) return;
        if (wakeFetchPending) { main.postDelayed(() -> verifyWake(generation,attempt),100); return; }
        wakeFetchPending=true;
        configurationDelivery.execute(() -> {
            IndicatorSettings received=null;
            try {
                Bundle response=context.getContentResolver().call(Uri.parse("content://com.example.remote_control.customization.health"),"wakeConfiguration",null,new Bundle());
                Bundle config=response==null?null:response.getBundle("configuration");
                if (config!=null) { java.util.HashMap<String,Object> values=new java.util.HashMap<>(); for(String key:config.keySet()) values.put(key,config.get(key)); received=new IndicatorSettings(values); }
            } catch(Throwable error) { android.util.Log.w("NodeCockpit","Wake safety verification failed",error); }
            final IndicatorSettings next=received;
            main.post(() -> {
                wakeFetchPending=false;
                if (!screenInteractive||generation!=wakeGeneration) return;
                if (next!=null) acceptSettings(next);
                if (next!=null&&next.safetyValid(boot,SystemClock.elapsedRealtime())) {
                    wakePending=false; wakeRecoveries++;
                    try { attachExistingWindows(); } catch (Throwable error) { android.util.Log.w("NodeCockpit","Wake window scan will retry",error); }
                    render();
                    if (edgeController!=null) edgeController.recoverAfterWake();
                    main.removeCallbacks(tick); main.post(tick);
                } else if (attempt<12) main.postDelayed(() -> verifyWake(generation,attempt+1),500);
                else { // Keep fail-closed output; normal health reports continue recovery.
                    wakePending=false; render(); main.removeCallbacks(tick); main.post(tick);
                }
            });
        });
    }
    private boolean visualsAllowed(IndicatorSettings value) {
        return screenInteractive&&!wakePending&&!quarantined&&value!=null&&value.safetyValid(boot,SystemClock.elapsedRealtime());
    }
    private boolean placeMeter() {
        if (statusBar==null || settings==null || meter==null) return false;
        if (settings.horizontalPosition>=0 && statusBar instanceof FrameLayout) {
            if (meterOverlay==null) {
                meterOverlay=new FrameLayout(context);
                meterOverlay.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
                ((FrameLayout)statusBar).addView(meterOverlay,new FrameLayout.LayoutParams(-1,-1));
                meterOverlay.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> positionFloatingMeter());
            }
            if (meter.getParent()!=meterOverlay) {
                if (meter.getParent() instanceof ViewGroup) ((ViewGroup)meter.getParent()).removeView(meter);
                FrameLayout.LayoutParams floating=new FrameLayout.LayoutParams(-2,indicatorHeight(),Gravity.TOP|Gravity.LEFT);
                meterOverlay.addView(meter,floating);
            }
            ViewGroup.LayoutParams floating=meter.getLayoutParams();
            if (floating.height!=indicatorHeight()) { floating.height=indicatorHeight(); meter.setLayoutParams(floating); }
            positionFloatingMeter();
            return true;
        }
        LinearLayout target=(LinearLayout)clock.getParent();
        int index=target.indexOfChild(clock)+1;
        if (settings.right) {
            View end=statusBar.findViewById(statusBar.getResources().getIdentifier("status_bar_end_side_content","id","com.android.systemui"));
            if (!(end instanceof LinearLayout)) end=statusBar.findViewById(statusBar.getResources().getIdentifier("system_icons","id","com.android.systemui"));
            if (!(end instanceof LinearLayout)) {
                meter.setVisibility(View.GONE); state="unsupported"; hiddenReason="unknown";
                return false;
            }
            target=(LinearLayout)end; index=0;
        }
        if (meter.getParent()!=target || target.indexOfChild(meter)!=index) {
            if (meter.getParent() instanceof ViewGroup) ((ViewGroup)meter.getParent()).removeView(meter);
            target.addView(meter,Math.min(index,target.getChildCount()));
        }
        if (meterOverlay!=null) {
            ((ViewGroup)meterOverlay.getParent()).removeView(meterOverlay); meterOverlay=null;
        }
        meterCrowded=false; meter.setAlpha(1f);
        meter.setTranslationX(0);
        LinearLayout.LayoutParams params=meter.getLayoutParams() instanceof LinearLayout.LayoutParams
            ? (LinearLayout.LayoutParams)meter.getLayoutParams()
            : new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,indicatorHeight());
        params.width=ViewGroup.LayoutParams.WRAP_CONTENT;
        params.height=indicatorHeight();
        params.gravity=Gravity.CENTER_VERTICAL;
        meter.setLayoutParams(params);
        meter.setTranslationY(dp(settings.verticalOffset));
        return true;
    }
    private void observeCollisionLayout(View root) {
        if (collisionRoot==root) return;
        if (collisionRoot!=null && collisionRoot.getViewTreeObserver().isAlive()) {
            collisionRoot.getViewTreeObserver().removeOnGlobalLayoutListener(collisionLayoutListener);
            collisionRoot.getViewTreeObserver().removeOnPreDrawListener(collisionDrawListener);
        }
        collisionRoot=root; collisionViews.clear();
        collisionEndContentId=root.getResources().getIdentifier("status_bar_end_side_content","id","com.android.systemui");
        collisionSystemIconsId=root.getResources().getIdentifier("system_icons","id","com.android.systemui");
        root.getViewTreeObserver().addOnGlobalLayoutListener(collisionLayoutListener);
        root.getViewTreeObserver().addOnPreDrawListener(collisionDrawListener);
    }
    private void observeKeyguardCollision(View view){
        if(keyguardCollisionRoots.put(view,true)!=null)return;
        view.getViewTreeObserver().addOnGlobalLayoutListener(collisionLayoutListener);
        view.getViewTreeObserver().addOnPreDrawListener(collisionDrawListener);
        view.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){
            public void onViewAttachedToWindow(View v){}
            public void onViewDetachedFromWindow(View v){keyguardCollisionRoots.remove(v);if(v.getViewTreeObserver().isAlive()){v.getViewTreeObserver().removeOnGlobalLayoutListener(collisionLayoutListener);v.getViewTreeObserver().removeOnPreDrawListener(collisionDrawListener);}v.removeOnAttachStateChangeListener(this);}
        });
    }
    private void refreshCollisionViews() {
        collisionViews.clear();
        collectCollisionViews(collisionRoot,0);
        for(View root:keyguardCollisionRoots.keySet()){
            for(String field:new String[]{"mCarrierLabel","mSystemIconsContainer","mStatusIconArea"})try{java.lang.reflect.Field f=root.getClass().getDeclaredField(field);f.setAccessible(true);Object v=f.get(root);if(v instanceof View)collisionViews.add((View)v);}catch(ReflectiveOperationException ignored){}
        }
    }
    private void collectCollisionViews(View view,int depth) {
        if (view==null || view==meter || view==meterOverlay || depth>24 || collisionViews.size()>=256) return;
        // These containers own virtual/Compose glyphs as well as child Views.
        // Their native measured bounds must be reserved even when leaves do not draw.
        if (view.getId()!=View.NO_ID && ((collisionEndContentId!=0 && view.getId()==collisionEndContentId)
                || (collisionSystemIconsId!=0 && view.getId()==collisionSystemIconsId))) {
            collisionViews.add(view); return;
        }
        if (view instanceof ViewGroup && ((ViewGroup)view).getChildCount()>0) {
            ViewGroup group=(ViewGroup)view;
            for (int i=0;i<group.getChildCount();i++) collectCollisionViews(group.getChildAt(i),depth+1);
        } else if (!(view instanceof Space) && (view instanceof TextView || view instanceof ImageView || !view.willNotDraw() || view.getBackground()!=null)) {
            collisionViews.add(view);
        }
    }
    private boolean collisionVisible(View view) {
        if (!view.isShown() || view.getWidth()<=0 || view.getHeight()<=0) return false;
        View current=view;
        while (current!=null && current!=statusBar && !keyguardCollisionRoots.containsKey(current)) {
            if (current.getAlpha()<0.02f) return false;
            android.view.ViewParent parent=current.getParent();
            current=parent instanceof View?(View)parent:null;
        }
        return current!=null&&current.getAlpha()>=.02f&&(current==statusBar||keyguardCollisionRoots.containsKey(current));
    }
    private int addCollisionInterval(int count,int left,int right) {
        if (right<=left) return count;
        if (count*2+2>collisionIntervals.length) collisionIntervals=java.util.Arrays.copyOf(collisionIntervals,collisionIntervals.length*2);
        collisionIntervals[count*2]=left; collisionIntervals[count*2+1]=right;
        return count+1;
    }
    private void positionFloatingMeter() {
        if (settings==null || settings.horizontalPosition<0 || meterOverlay==null || meter==null || meter.getParent()!=meterOverlay) return;
        int rootWidth=meterOverlay.getWidth(),width=meter.getWidth();
        if (rootWidth<=0 || width<=0) return;
        float y=Math.max(0,(meterOverlay.getHeight()-meter.getHeight())/2f)+dp(settings.verticalOffset);
        meter.setTranslationY(y);
        meterOverlay.getLocationOnScreen(collisionRootLocation);
        int bandTop=collisionRootLocation[1]+Math.round(y),bandBottom=bandTop+meter.getHeight();
        int count=0;
        for (int i=0;i<collisionViews.size();i++) {
            View view=collisionViews.get(i);
            if (!collisionVisible(view) || !view.getGlobalVisibleRect(collisionRect) || collisionRect.bottom<=bandTop || collisionRect.top>=bandBottom) continue;
            count=addCollisionInterval(count,collisionRect.left-collisionRootLocation[0],collisionRect.right-collisionRootLocation[0]);
        }
        int left=statusBar.getPaddingLeft(),right=rootWidth-statusBar.getPaddingRight();
        WindowInsets insets=statusBar.getRootWindowInsets();
        if (insets!=null && insets.getDisplayCutout()!=null) {
            android.view.DisplayCutout cutout=insets.getDisplayCutout();
            left=Math.max(left,cutout.getSafeInsetLeft()); right=Math.min(right,rootWidth-cutout.getSafeInsetRight());
            for (Rect bounds:cutout.getBoundingRects()) {
                if (bounds.bottom>bandTop && bounds.top<bandBottom)
                    count=addCollisionInterval(count,bounds.left-collisionRootLocation[0],bounds.right-collisionRootLocation[0]);
            }
        }
        int preferred=Math.round(Math.max(0,rootWidth-width)*settings.horizontalPosition/1000f);
        int actual=StatusBarPlacement.resolve(preferred,width,left,right,collisionIntervals,count,dp(2));
        placementRequestedLeft=preferred; placementBlocks=count;
        boolean crowded=actual<0;
        if (!crowded) {
            if (placementActualLeft!=actual && actual!=preferred) placementAdjustments++;
            placementActualLeft=actual; meter.setTranslationX(actual);
        }
        meterCrowded=crowded; meter.setAlpha(crowded?0f:1f);
        if (enabled()) {
            boolean idle=(rxRate+(settings.showUpload?txRate:0))<settings.threshold*1024.0;
            meter.setVisibility(crowded || settings.hideIdle && idle?View.INVISIBLE:View.VISIBLE);
            if (crowded) hiddenReason="statusBarCrowded";
            else if ("statusBarCrowded".equals(hiddenReason)) hiddenReason=settings.hideIdle && idle?"idle":"showing";
        }
    }
    private GradientDrawable indicatorSurface(String design,int foreground) {
        boolean light=Color.luminance(foreground)>0.5f;
        int opposite=light?0x000000:0xffffff;
        GradientDrawable surface;
        if ("glass".equals(design)) surface=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0x28000000|(foreground&0xffffff),0x08000000|opposite,0x38000000|(foreground&0xffffff)});
        else {
            surface=new GradientDrawable();
            int alpha="badge".equals(design)?0xff:"outline".equals(design)?0:"box".equals(design)?0x14:0x22;
            surface.setColor((alpha<<24)|(foreground&0xffffff));
        }
        surface.setCornerRadius("box".equals(design)?dp(3):indicatorHeight()/2f);
        if ("outline".equals(design)||"box".equals(design)||"glass".equals(design))
            surface.setStroke(Math.max(1,Math.round(context.getResources().getDisplayMetrics().density*0.65f)),(foreground&0x00ffffff)|("glass".equals(design)?0x40000000:0x78000000));
        return surface;
    }
    private void styleMeter() {
        int foreground=clock.getCurrentTextColor();
        String signature=settings.indicatorDesign+":"+foreground+":"+indicatorHeight()+":"+settings.boldText;
        if (signature.equals(meterDesignSignature)) return;
        meterDesignSignature=signature;
        Typeface face=Typeface.create("mono".equals(settings.indicatorDesign)?"monospace":"sans-serif",Typeface.NORMAL);
        download.setTypeface(face); upload.setTypeface(face);
        downloadArrow.setTypeface(Typeface.create("sans-serif",settings.boldText?Typeface.BOLD:Typeface.NORMAL));
        uploadArrow.setTypeface(downloadArrow.getTypeface());
        String design=settings.indicatorDesign;
        meter.setBackground(java.util.Arrays.asList("plain","mono","split").contains(design)?null:indicatorSurface(design,foreground));
        int inset="split".equals(design)?dp(3):0;
        downloadGroup.setPadding(inset,0,inset,0); uploadGroup.setPadding(inset,0,inset,0);
        downloadGroup.setBackground("split".equals(design)?indicatorSurface("box",foreground):null);
        uploadGroup.setBackground("split".equals(design)?indicatorSurface("box",foreground):null);
    }
    private LinearLayout rateGroup(TextView arrow,TextView value) {
        LinearLayout group=new LinearLayout(context);
        group.setGravity(Gravity.TOP);
        group.addView(arrow); group.addView(value);
        return group;
    }
    private TextView column(Context c) {
        TextView text=new TextView(c);
        text.setGravity(Gravity.CENTER);
        text.setIncludeFontPadding(false);
        text.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
        text.setFontFeatureSettings("tnum");
        text.setLineSpacing(0,0.95f);
        text.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> text.post(() -> protectLineSpacing(text)));
        return text;
    }
    private void protectLineSpacing(TextView text) {
        if (settings==null || !settings.stacked || text.getLayout()==null || text.getLayout().getLineCount()!=2) return;
        String displayed=text.getText().toString(); int newline=displayed.indexOf('\n');
        if (newline<0) return;
        android.graphics.Paint value=new android.graphics.Paint(text.getPaint());
        value.setTypeface(Typeface.create(value.getTypeface(),settings.boldValue?Typeface.BOLD:Typeface.NORMAL));
        android.graphics.Paint unit=new android.graphics.Paint(text.getPaint());
        unit.setTextSize(value.getTextSize()*settings.unitScale/100f);
        unit.setTypeface(Typeface.create(unit.getTypeface(),settings.boldText?Typeface.BOLD:Typeface.NORMAL));
        Rect valueInk=new Rect(),unitInk=new Rect();
        value.getTextBounds("0123456789",0,10,valueInk);
        unit.getTextBounds(displayed,newline+1,displayed.length(),unitInk);
        int advance=text.getLayout().getLineBaseline(1)-text.getLayout().getLineBaseline(0);
        float minimum=valueInk.bottom-unitInk.top+Math.max(1,dp(1)/2f);
        if (advance+0.5f<minimum) text.setLineSpacing(text.getLineSpacingExtra()+minimum-advance,0.95f);
    }
    private int dp(int v) { return Math.round(v*context.getResources().getDisplayMetrics().density); }
    private int indicatorHeight() {
        int desired=dp(settings==null?16:settings.indicatorHeight);
        if (clock!=null && clock.getParent() instanceof View && ((View)clock.getParent()).getHeight()>0)
            desired=Math.min(desired,((View)clock.getParent()).getHeight());
        return desired;
    }
    private int interval() { return settings==null?1000:settings.enabled?settings.interval:5000; }
    private boolean enabled() { return visualsAllowed(settings) && settings.enabled; }
    private void render() {
        if(notificationUndo!=null)notificationUndo.safetyChanged();
        if(cameraRing!=null&&quarantined)cameraRing.configure(CameraRingSettings.disabled(settings==null?CameraRingSettings.DEFAULT:settings.cameraRing));
        if (settings==null) return;
        if (edgeController!=null) edgeController.safetyChanged(visualsAllowed(settings));
        if (meter==null) return;
        if (!enabled()) {
            meter.setVisibility(View.GONE);
            hiddenReason=!screenInteractive?"screenOff":quarantined?"quarantined":settings.enabled?"safetyCheckOverdue":"disabled";
            state=quarantined&&!error.isEmpty()?"error":"disabled";
            return;
        }
        if (!placeMeter()) return;
        styleMeter();
        int available=dp(240);
        if (meter.getParent() instanceof View) {
            View parent=(View)meter.getParent();
            if (!settings.right && parent.getWidth()>0 && meter.getLeft()>0) available=Math.min(available,Math.max(1,parent.getWidth()-meter.getLeft()-parent.getPaddingRight()));
        }
        if (settings.right && meter.getParent() instanceof LinearLayout) {
            LinearLayout row=(LinearLayout)meter.getParent();
            if (row.getParent() instanceof View) {
                View outer=(View)row.getParent();
                int reserved=row.getPaddingLeft()+row.getPaddingRight();
                for (int i=0;i<row.getChildCount();i++) if (row.getChildAt(i)!=meter) reserved+=iconWidth(row.getChildAt(i),0);
                if (outer.getWidth()>0) available=Math.min(available,Math.max(1,outer.getWidth()-outer.getPaddingLeft()-outer.getPaddingRight()-reserved-dp(settings.iconGap)));
            }
        }
        int minPadding=java.util.Arrays.asList("plain","mono","split").contains(settings.indicatorDesign)?0:3;
        int outerGap=dp(Math.max(minPadding,settings.iconGap));
        if (meter.getPaddingLeft()!=outerGap || meter.getPaddingRight()!=outerGap)
            meter.setPadding(outerGap,0,outerGap,0);
        int columnBudget=Math.max(1,(available-meter.getPaddingLeft()-meter.getPaddingRight())/(settings.showUpload?2:1));
        LinearLayout.LayoutParams uploadParams=(LinearLayout.LayoutParams)uploadGroup.getLayoutParams();
        int uploadGap=settings.showUpload?dp(settings.directionGap):0;
        if (uploadParams==null || uploadParams.leftMargin!=uploadGap) {
            uploadParams=new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,indicatorHeight());
            uploadParams.leftMargin=uploadGap;
            uploadGroup.setLayoutParams(uploadParams);
        }
        LinearLayout.LayoutParams downloadParams=downloadGroup.getLayoutParams() instanceof LinearLayout.LayoutParams
            ? (LinearLayout.LayoutParams)downloadGroup.getLayoutParams()
            : new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,indicatorHeight());
        downloadParams.height=indicatorHeight(); downloadGroup.setLayoutParams(downloadParams);
        if (settings.showUpload) columnBudget=Math.max(1,columnBudget-uploadGap/2);
        columnBudget=Math.max(1,columnBudget-downloadGroup.getPaddingLeft()-downloadGroup.getPaddingRight());
        drawColumn(download,downloadArrow,rxRate,false,columnBudget); drawColumn(upload,uploadArrow,txRate,true,columnBudget);
        uploadGroup.setVisibility(settings.showUpload?View.VISIBLE:View.GONE);
        boolean idle=(rxRate+(settings.showUpload?txRate:0))<settings.threshold*1024.0;
        meter.setVisibility(meterCrowded || settings.hideIdle && idle?View.INVISIBLE:View.VISIBLE);
        state="active";
        boolean interactive=((PowerManager)context.getSystemService(Context.POWER_SERVICE)).isInteractive();
        hiddenReason=!interactive?"screenOff":meterCrowded?"statusBarCrowded":!meter.isAttachedToWindow()?"detached":settings.hideIdle&&idle?"idle":!meter.isShown()||meter.getWindowVisibility()!=View.VISIBLE?"statusBarHidden":"showing";
    }
    // Reserve natural widths in the validated status-bar subtree without changing icon visibility.
    private int iconWidth(View view,int depth) {
        if (view.getVisibility()==View.GONE || depth>8) return 0;
        boolean iconContainer=view.getClass().getSimpleName().contains("StatusIconContainer");
        if (view instanceof LinearLayout || iconContainer) {
            ViewGroup group=(ViewGroup)view;
            boolean horizontal=iconContainer || ((LinearLayout)view).getOrientation()==LinearLayout.HORIZONTAL;
            int width=0;
            for (int i=0;i<group.getChildCount();i++) {
                View child=group.getChildAt(i);
                if (iconContainer) {
                    try { if (Boolean.FALSE.equals(child.getClass().getMethod("isIconVisible").invoke(child))) continue; } catch (ReflectiveOperationException ignored) {}
                    try { if (Boolean.TRUE.equals(child.getClass().getMethod("isIconBlocked").invoke(child))) continue; } catch (ReflectiveOperationException ignored) {}
                }
                int childWidth=iconWidth(child,depth+1); width=horizontal?width+childWidth:Math.max(width,childWidth);
            }
            return width+view.getPaddingLeft()+view.getPaddingRight()+horizontalMargins(view);
        }
        return view.getMeasuredWidth()+horizontalMargins(view);
    }
    private int horizontalMargins(View view) {
        ViewGroup.LayoutParams p=view.getLayoutParams();
        if (!(p instanceof ViewGroup.MarginLayoutParams)) return 0;
        ViewGroup.MarginLayoutParams m=(ViewGroup.MarginLayoutParams)p; return m.leftMargin+m.rightMargin;
    }
    private static final class UnitGapSpan extends android.text.style.ReplacementSpan {
        private final int width;
        UnitGapSpan(int width) { this.width=width; }
        @Override public int getSize(android.graphics.Paint paint,CharSequence text,int start,int end,android.graphics.Paint.FontMetricsInt fm) { return width; }
        @Override public void draw(android.graphics.Canvas canvas,CharSequence text,int start,int end,float x,int top,int y,int bottom,android.graphics.Paint paint) {}
    }
    private static final class TightUnitSpan extends android.text.style.ReplacementSpan {
        private final int gap;
        private final String value;
        private final float unitScale;
        private final boolean boldValue;
        TightUnitSpan(int gap,String value,float unitScale,boolean boldValue) { this.gap=gap; this.value=value; this.unitScale=unitScale; this.boldValue=boldValue; }
        private int safeGap(android.graphics.Paint paint,CharSequence text,int start,int end) {
            android.graphics.Paint number=new android.graphics.Paint(paint);
            number.setTextSize(paint.getTextSize()/unitScale);
            number.setTypeface(Typeface.create(paint.getTypeface(),boldValue?Typeface.BOLD:Typeface.NORMAL));
            Rect numberInk=new Rect(),unitInk=new Rect();
            number.getTextBounds(value,0,value.length(),numberInk);
            paint.getTextBounds(text,start,end,unitInk);
            float naturalGap=number.measureText(value)-numberInk.right+unitInk.left;
            return Math.max(gap,(int)Math.ceil(1-naturalGap));
        }
        @Override public int getSize(android.graphics.Paint paint,CharSequence text,int start,int end,android.graphics.Paint.FontMetricsInt fm) {
            if (fm!=null) paint.getFontMetricsInt(fm);
            return Math.max(1,(int)Math.ceil(paint.measureText(text,start,end))+safeGap(paint,text,start,end));
        }
        @Override public void draw(android.graphics.Canvas canvas,CharSequence text,int start,int end,float x,int top,int y,int bottom,android.graphics.Paint paint) {
            canvas.drawText(text,start,end,x+safeGap(paint,text,start,end),y,paint);
        }
    }
    private void drawColumn(TextView text,TextView arrow,double rate,boolean sending,int budget) {
        String[] parts=FeaturePolicy.rateParts(rate,settings.bits,settings.decimals);
        String value=parts[0], unit=settings.formatUnit(parts[1]);
        boolean stacked=settings.stacked&&!unit.isEmpty();
        int height=indicatorHeight(), maxSize=settings.stacked?settings.stackedTextSize:settings.textSize;
        String fitting="fit:"+height+":"+stacked+":"+maxSize+":"+settings.boldValue+":"+settings.boldText+":"+settings.unitGap+":"+settings.unitScale;
        boolean styleChanged=!fitting.equals(text.getTag());
        if (styleChanged) {
            text.setAutoSizeTextTypeUniformWithConfiguration(4,Math.max(4,maxSize),1,TypedValue.COMPLEX_UNIT_SP);
            android.graphics.Paint minimum=new android.graphics.Paint(text.getPaint());
            minimum.setTextSize(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP,4,context.getResources().getDisplayMetrics()));
            float gap=Math.min(dp(settings.unitGap),Math.max(0,height-2*minimum.getFontSpacing()));
            text.setLineSpacing(stacked?gap:0,0.95f);
            text.setTag(fitting);
        }
        int foreground=clock.getCurrentTextColor();
        if ("badge".equals(settings.indicatorDesign)) foreground=Color.luminance(foreground)>0.5f?Color.BLACK:Color.WHITE;
        text.setTextColor(foreground);
        text.setMaxLines(stacked?2:1);
        String displayed=value+(unit.isEmpty()?"":(stacked?"\n":" ")+unit);
        if (styleChanged || !text.getText().toString().equals(displayed)) {
            android.text.SpannableString formatted=new android.text.SpannableString(displayed);
            int flags=android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE;
            formatted.setSpan(new android.text.style.StyleSpan(settings.boldValue?Typeface.BOLD:Typeface.NORMAL),0,value.length(),flags);
            if (!unit.isEmpty()) {
                int from=value.length()+1;
                formatted.setSpan(new android.text.style.StyleSpan(settings.boldText?Typeface.BOLD:Typeface.NORMAL),from,displayed.length(),flags);
                formatted.setSpan(new android.text.style.RelativeSizeSpan(settings.unitScale/100f),from,displayed.length(),flags);
                if (!stacked) {
                    formatted.setSpan(new UnitGapSpan(dp(Math.max(0,settings.unitGap))),value.length(),from,flags);
                    if (settings.unitGap<0) formatted.setSpan(new TightUnitSpan(dp(settings.unitGap),value,settings.unitScale/100f,settings.boldValue),from,displayed.length(),flags);
                }
            }
            text.setText(formatted);
        }
        arrow.setVisibility(settings.showArrows?View.VISIBLE:View.GONE);
        String arrowText=sending?"\u2191":"\u2193"; arrow.setText(arrowText);
        float arrowSize=text.getTextSize()*settings.arrowScale/100f;
        arrow.setTextSize(TypedValue.COMPLEX_UNIT_PX,arrowSize); arrow.setMaxLines(1); arrow.setGravity(Gravity.CENTER);
        arrow.setTextColor(text.getCurrentTextColor());
        LinearLayout.LayoutParams ap=arrow.getLayoutParams() instanceof LinearLayout.LayoutParams
            ? (LinearLayout.LayoutParams)arrow.getLayoutParams():new LinearLayout.LayoutParams(-2,height);
        ap.width=-2; ap.height=height; ap.rightMargin=dp(settings.arrowGap); arrow.setLayoutParams(ap);
        int arrowWidth=settings.showArrows?(int)Math.ceil(arrow.getPaint().measureText(arrowText))+dp(settings.arrowGap):0;
        budget=Math.max(1,budget-Math.max(0,arrowWidth));
        text.post(() -> { protectLineSpacing(text); float size=text.getTextSize()*settings.arrowScale/100f; if (arrow.getTextSize()!=size) arrow.setTextSize(TypedValue.COMPLEX_UNIT_PX,size); });
        int desired=dp(settings.rateWidth+(settings.stacked?0:28)); int width=Math.max(1,Math.min(budget,desired));
        if (text.getLayoutParams()==null || text.getLayoutParams().width!=width || text.getLayoutParams().height!=height)
            text.setLayoutParams(new LinearLayout.LayoutParams(width,height));
    }
    private void sample() {
        long now=SystemClock.elapsedRealtime();
        if ((meter==null || !meter.isAttachedToWindow()) && now-lastRecoveryScan>=2000) {
            lastRecoveryScan=now; recoveryScans++;
            try { attachExistingWindows(); } catch (Throwable ignored) { /* A missing window is retried, not quarantined. */ }
        }
        if (settings==null) { state="loaded"; report(false); return; }
        if (quarantined || !settings.enabled || wakePending) { render(); report(false); return; }
        long rx=TrafficStats.getTotalRxBytes(), tx=TrafficStats.getTotalTxBytes();
        if (rx<0 || tx<0) throw new IllegalStateException("Traffic counters unavailable");
        if (previousRx>=0 && previousTime>0 && now>previousTime) {
            if (rx<previousRx || tx<previousTx) counterResets++;
            rxRate=Math.max(0,rx-previousRx)*1000.0/(now-previousTime);
            txRate=Math.max(0,tx-previousTx)*1000.0/(now-previousTime);
        }
        previousRx=rx; previousTx=tx; previousTime=now; lastSample=now;
        render();
        if (enabled() && (meter==null || !meter.isAttachedToWindow())) { state="waitingForStatusBar"; hiddenReason="detached"; }
        report(false);
    }
    private void fail(Throwable e) {
        quarantined=true; state="error"; error=e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage());
        quarantineRevision=settings==null?0:settings.revision;
        if (meter!=null) meter.setVisibility(View.GONE);
        hiddenReason="quarantined";
        log(android.util.Log.ERROR,"NodeCockpit","Feature disabled after local failure",e); report(true);
    }
    private void edgeFail(Throwable e) {
        edgeFailures++; edgeError=e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage());
        log(android.util.Log.ERROR,"NodeCockpit","Edge panel isolated after local failure",e);
        report(true);
    }
    private void requestConfiguration() {
        if(context==null) return;
        if(!configFetchPending.compareAndSet(false,true)) { configFetchAgain.set(true); return; }
        configurationDelivery.execute(() -> {
            try {
                Bundle response=context.getContentResolver().call(Uri.parse("content://com.example.remote_control.customization.health"),"configuration",null,new Bundle());
                Bundle config=response==null?null:response.getBundle("configuration");
                if(config!=null) { java.util.HashMap<String,Object> values=new java.util.HashMap<>(); for(String key:config.keySet()) values.put(key,config.get(key)); IndicatorSettings next=new IndicatorSettings(values); main.post(() -> acceptSettings(next)); }
            } catch(Throwable error) { android.util.Log.w("NodeCockpit","Immediate configuration delivery failed",error); }
            finally { configFetchPending.set(false); if(configFetchAgain.getAndSet(false)) main.post(this::requestConfiguration); }
        });
    }
    private void report(boolean force) {
        long now=SystemClock.elapsedRealtime(); if (context==null || (!force&&now-lastReport<5000)) return;
        if (!reportPending.compareAndSet(false,true)) { if (force) reportAgain.set(true); return; }
        lastReport=now;
        healthCallbacks++;
        Bundle data=new Bundle(); data.putString("state",state); data.putString("error",error);
        data.putLong("revision",settings==null?-1:settings.revision); data.putString("version",String.valueOf(FeaturePolicy.HOOK_VERSION));
        data.putString("visibilityReason",hiddenReason);
        if(cameraRing!=null)data.putString("cameraRingDiagnostics",cameraRing.diagnostics());
        if(notificationUndo!=null)data.putString("notificationUndoDiagnostics",notificationUndo.diagnostics());
        data.putBoolean("attached",meter!=null&&meter.isAttachedToWindow());
        data.putBoolean("visible","showing".equals(hiddenReason));
        data.putBoolean("textClipped",parentClipped()||clipped(download)||settings!=null&&settings.showUpload&&clipped(upload));
        data.putLong("sampleAgeMs",lastSample==0?-1:now-lastSample);
        data.putLong("downloadBps",(long)rxRate); data.putLong("uploadBps",(long)txRate);
        data.putInt("attachments",attachments); data.putInt("detachments",detachments);
        data.putInt("counterResets",counterResets); data.putInt("preferenceUpdates",preferenceUpdates);
        data.putInt("recoveryScans",recoveryScans); data.putInt("deliveryFailures",deliveryFailures);
        data.putInt("wakeRecoveries",wakeRecoveries); data.putBoolean("interactive",screenInteractive); data.putBoolean("wakePending",wakePending);
        data.putInt("healthCallbacks",healthCallbacks);
        data.putInt("settingsCallbacks",settingsCallbacks); data.putInt("safetyOnlyCallbacks",safetyOnlyCallbacks);
        data.putInt("placementRequestedLeft",placementRequestedLeft); data.putInt("placementActualLeft",placementActualLeft);
        data.putInt("placementBlocks",placementBlocks); data.putInt("placementAdjustments",placementAdjustments);
        data.putInt("edgeFailures",edgeFailures); data.putString("edgeError",edgeError);
        data.putString("edgeDiagnostics",edgeController==null?"unavailable":edgeController.diagnostics());
        final Context c=context;
        diagnostics.execute(() -> {
            try {
                String id=getModuleApplicationInfo().packageName;
                Bundle response=c.getContentResolver().call(Uri.parse("content://"+id+".customization.health"),"report",null,data);
                if (response!=null) {
                    Bundle configuration=response.getBundle("configuration");
                    if (configuration!=null) {
                        java.util.HashMap<String,Object> values=new java.util.HashMap<>();
                        for (String key:configuration.keySet()) values.put(key,configuration.get(key));
                        IndicatorSettings next=new IndicatorSettings(values);
                        main.post(() -> acceptSettings(next));
                    }
                    if (response.getBoolean("emergencyDisabled")) main.post(() -> {
                        if (settings==null || data.getLong("revision",-1)!=settings.revision) return;
                        quarantined=true; quarantineRevision=settings.revision; render();
                    });
                }
            } catch (Throwable e) {
                main.post(() -> {
                    if (deliveryFailures==0) android.util.Log.w("NodeCockpit","Health report failed",e);
                    deliveryFailures++;
                });
            }
            finally { reportPending.set(false); if (reportAgain.getAndSet(false)) main.post(() -> report(true)); }
        });
    }
    private void acceptRingRendered(Object list,ClassLoader loader){
        if(cameraRing==null||!cameraRing.wantsNotifications()){ringEligibility.clear();return;}
        if(!cameraRingObservationReady){ringEligibility.clear();cameraRing.unavailable(cameraRingListError);return;}
        try{
            if(!(list instanceof java.util.Collection))throw new IllegalStateException("Final shade list unavailable");
            ringEligibility.rendered(CameraRingNotifications.snapshot((java.util.Collection<?>)list,loader));
            cameraRing.notifications(ringEligibility.snapshot());
        }catch(Throwable error){ringEligibility.clear();cameraRing.unavailable("Final shade adapter: "+error.getClass().getSimpleName());}
    }
    private void reconcileRingNotifications(){
        if(cameraRing==null||!cameraRing.wantsNotifications()){ringEligibility.clear();return;}
        if(!cameraRingObservationReady||cameraRingListBuilder==null||!cameraRingFinalListReady){ringEligibility.clear();cameraRing.unavailable(cameraRingListError);return;}
        try{
            Object list=cameraRingListBuilder.getClass().getField("mReadOnlyNotifList").get(cameraRingListBuilder);
            java.util.List<CameraRingSelection.Notice> visible=CameraRingNotifications.snapshot((java.util.Collection<?>)list,cameraRingListBuilder.getClass().getClassLoader());
            if(!ringEligibility.ready())ringEligibility.rendered(visible);else ringEligibility.reconcile(visible);
            cameraRing.notifications(ringEligibility.snapshot());
        }catch(Throwable error){ringEligibility.clear();cameraRing.unavailable("Shade reconciliation: "+error.getClass().getSimpleName());}
    }
    private void refreshRingNotifications(){
        if(main==null||ringSnapshotPending)return;ringSnapshotPending=true;
        main.post(()->{ringSnapshotPending=false;reconcileRingNotifications();});
    }
    private void acceptSettings(IndicatorSettings next) {
        if(settings!=null&&next.revision<settings.revision) return;
        settingsCallbacks++;
        if(next.safetyValid(boot,SystemClock.elapsedRealtime()))cameraRingArmed=true;
        if(notificationUndo!=null)notificationUndo.configure(next.notificationUndo,next.revision);
        if(cameraRing!=null){cameraRing.configure(next.cameraRing);refreshRingNotifications();}
        String nextFunctional=next.functionalSignature();
        String nextGeometry=next.edgeGeometrySignature();
        String nextVisual=next.edgeVisualSignature();
        String nextContent=next.edgeContentSignature();
        String nextSafety=next.safetySignature();
        boolean functionalChanged=settings==null||!nextFunctional.equals(functionalSignature);
        boolean geometryChanged=settings==null||!nextGeometry.equals(geometrySignature);
        boolean visualChanged=settings==null||!nextVisual.equals(visualSignature);
        boolean contentChanged=settings==null||!nextContent.equals(contentSignature);
        boolean safetyChanged=settings==null||!nextSafety.equals(safetySignature);
        boolean revisionChanged=settings==null||next.revision!=settings.revision;
        if (!functionalChanged&&!geometryChanged&&!visualChanged&&!contentChanged&&!safetyChanged&&!revisionChanged) return;
        if (safetyChanged&&!functionalChanged&&!geometryChanged&&!visualChanged&&!contentChanged&&!revisionChanged) safetyOnlyCallbacks++;
        boolean wasEnabled=settings!=null && settings.enabled;
        settings=next; functionalSignature=nextFunctional; geometrySignature=nextGeometry;
        visualSignature=nextVisual; contentSignature=nextContent; safetySignature=nextSafety; preferenceUpdates++;
        if (edgeController!=null) edgeController.apply(next,visualsAllowed(next),functionalChanged,geometryChanged,visualChanged,contentChanged);
        if ((settings.enabled||CameraRingSettings.safe(settings.cameraRing).enabled) && settings.revision>quarantineRevision) { quarantined=false; error=""; }
        if (!wasEnabled && settings.enabled) { previousRx=-1; previousTime=0; }
        render();
    }
    private boolean clipped(TextView text) {
        if (text==null || text.getLayout()==null || settings==null || !text.isShown()) return false;
        android.text.Layout layout=text.getLayout();
        if (layout.getLineCount()>(settings.stacked?2:1) || layout.getHeight()>text.getHeight()+1) return true;
        for (int i=0;i<layout.getLineCount();i++) if (layout.getLineWidth(i)>text.getWidth()+1) return true;
        return false;
    }
    private boolean parentClipped() {
        if (meter==null || !meter.isShown() || meter.getWindowVisibility()!=View.VISIBLE) return false;
        android.graphics.Rect visible=new android.graphics.Rect();
        return meter.getGlobalVisibleRect(visible) && visible.width()+1<meter.getWidth();
    }
}

package com.nodecockpit.customization;

import android.content.*;
import android.graphics.*;
import android.hardware.display.DisplayManager;
import android.os.*;
import android.view.*;
import java.util.*;

/** Dedicated native AOD ring. No face authentication or glass integration. */
final class CameraNotificationRing {
    static final String TEST_ACTION="com.nodecockpit.customization.CAMERA_RING_PROBE";
    private final Context context;private final Handler handler;private final Runnable changed,reconcile;
    private final java.util.function.BooleanSupplier allowed;
    private final CameraRingAmbientController ambient;
    private final DisplayManager displays;private final PowerManager power;
    private WindowManager windows;private Ring view;private Context windowContext;
    private CameraRingSettings settings=CameraRingSettings.safe(CameraRingSettings.DEFAULT);
    private String raw="",reason="disabled",failure="",notificationError="",winner="";
    private Collection<CameraRingSelection.Notice> notices=Collections.emptyList();
    private CameraRingSelection.Notice selected;
    private boolean listening,blocked;private int pulseUpdates,draws;private long testUntil,pulseStart;
    private final DisplayManager.DisplayListener listener=new DisplayManager.DisplayListener(){
        public void onDisplayAdded(int id){if(id==0)safe(()->render());}public void onDisplayRemoved(int id){if(id==0)safe(()->remove());}
        public void onDisplayChanged(int id){if(id==0)safe(()->{reconcile.run();render();});}
    };
    private final Runnable pulse=()->safe(()->step());
    private final Runnable expire=()->safe(()->render());
    CameraNotificationRing(Context c,Handler h,java.util.function.BooleanSupplier allowed,Runnable changed,Runnable reconcile,CameraRingAmbientController ambient){
        this.ambient=ambient;
        context=c;handler=h;this.allowed=allowed;this.changed=changed;this.reconcile=reconcile;displays=c.getSystemService(DisplayManager.class);power=c.getSystemService(PowerManager.class);
        IntentFilter filter=new IntentFilter(TEST_ACTION);filter.addAction(FeaturePolicy.ACTION_DISABLE);
        c.registerReceiver(new BroadcastReceiver(){public void onReceive(Context c,Intent i){safe(()->{
            if(FeaturePolicy.ACTION_DISABLE.equals(i.getAction())){blocked=true;testUntil=0;ambient.cancel("disabled");remove();notifyChange();return;}
            if(TEST_ACTION.equals(i.getAction())){testUntil=i.getBooleanExtra("start",false)?SystemClock.elapsedRealtime()+30000:0;handler.removeCallbacks(expire);if(testUntil>0)handler.postDelayed(expire,30000);if(testUntil>0&&i.getBooleanExtra("ambient",false))ambient.arm();else ambient.cancel("not requested");render();}
        });}},filter,android.Manifest.permission.DUMP,h,Context.RECEIVER_EXPORTED);
    }
    void configure(String value){safe(()->{
        if(raw.equals(value)){render();return;}raw=value;settings=CameraRingSettings.safe(value);failure="";
        if(settings.enabled)blocked=false;else notices=Collections.emptyList();render();
    });}
    boolean wantsNotifications(){return settings.enabled;}
    void notifications(Collection<CameraRingSelection.Notice> value){notices=value;notificationError="";safe(()->render());}
    void unavailable(String error){notices=Collections.emptyList();notificationError=error;safe(()->render());}
    private boolean testing(){return testUntil>SystemClock.elapsedRealtime();}
    private void render()throws Exception{
        boolean test=testing();boolean active=(settings.enabled||test)&&!blocked&&allowed.getAsBoolean();
        selected=CameraRingSelection.winner(settings,notices);
        ambient.demand(active&&!test&&settings.ambientOnDemand&&selected!=null?selected.key+"\n"+selected.posted:"");
        String next=test?"test":selected==null?"":selected.pkg;boolean newWinner=!next.equals(winner);winner=next;
        if(active&&!listening){displays.registerDisplayListener(listener,handler);listening=true;}
        if(!active&&listening){displays.unregisterDisplayListener(listener);listening=false;}
        Display d=displays.getDisplay(0);int state=d==null?Display.STATE_UNKNOWN:d.getState();
        String why=!active?"disabled":!failure.isEmpty()?"unavailable":next.isEmpty()?"no matching notifications":d==null?"no display":power.isInteractive()?"screen awake":d.getRotation()!=0?"portrait only":!CameraRingAodPolicy.canDraw(false,state,d.getRotation())?"waiting for AOD":"showing";
        boolean transition=!why.equals(reason);reason=why;
        if(!why.equals("showing")){remove();if(transition||newWinner)notifyChange();return;}
        if(view==null){pulseStart=SystemClock.uptimeMillis();attach(d);view.invalidate();handler.postDelayed(pulse,CameraRingPulse.delay(0,settings.intervalMs));}
        else {view.style();view.invalidate();}
        if(transition||newWinner)notifyChange();
    }
    private void attach(Display display)throws Exception{
        DisplayCutout cutout=display.getCutout();if(cutout==null)throw new IllegalStateException("No camera cutout");
        Path contour=cutout.getCutoutPath();if(contour==null||contour.isEmpty())throw new IllegalStateException("No native cutout contour");
        RectF bounds=new RectF();contour.computeBounds(bounds,true);int screen=display.getMode().getPhysicalWidth();
        if(bounds.width()<=0||bounds.height()<=0||bounds.width()>screen/3f||bounds.top>display.getMode().getPhysicalHeight()/5f)throw new IllegalStateException("Unsupported cutout geometry");
        windowContext=context.createDisplayContext(display).createWindowContext(2024,null);windows=windowContext.getSystemService(WindowManager.class);
        // Fixed maximum-thickness margin: tuning never moves/recreates the window.
        int pad=(int)Math.ceil(14*windowContext.getResources().getDisplayMetrics().density);
        Rect box=new Rect();bounds.roundOut(box);box.inset(-pad,-pad);box.top=Math.max(0,box.top);
        view=new Ring(windowContext,contour,bounds,box);view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        WindowManager.LayoutParams p=new WindowManager.LayoutParams(box.width(),box.height(),2024,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE|WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN|WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,PixelFormat.TRANSLUCENT);
        p.gravity=Gravity.TOP|Gravity.LEFT;p.x=box.left;p.y=box.top;p.layoutInDisplayCutoutMode=WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;p.setFitInsetsTypes(0);
        WindowManager.LayoutParams.class.getField("privateFlags").setInt(p,0x21000050);p.setTitle("NodeCockpit.NotificationRing");windows.addView(view,p);
    }
    private void step()throws Exception{
        if(testUntil>0&&!testing())testUntil=0;
        if(view==null)return;
        Display d=displays.getDisplay(0);int state=d==null?0:d.getState();
        if(blocked||!allowed.getAsBoolean()||d==null||!CameraRingAodPolicy.canDraw(power.isInteractive(),state,d.getRotation())||!settings.enabled&&!testing()){render();return;}
        pulseUpdates++;view.invalidate();handler.postDelayed(pulse,CameraRingPulse.delay(SystemClock.uptimeMillis()-pulseStart,settings.intervalMs));
    }
    private void remove(){handler.removeCallbacks(pulse);if(view!=null){Ring old=view;view=null;try{if(old.isAttachedToWindow())windows.removeViewImmediate(old);}catch(RuntimeException e){failure="Window cleanup: "+e.getClass().getSimpleName();}}windows=null;windowContext=null;pulseStart=0;}
    private void safe(Throwing action){try{action.run();}catch(Throwable e){failure=e.getClass().getSimpleName()+": "+e.getMessage();reason="unavailable";ambient.cancel("ring unavailable");remove();notifyChange();}}
    private interface Throwing{void run()throws Exception;}
    private void notifyChange(){android.util.Log.i("NodeCameraRing",diagnostics());handler.post(changed);}
    String diagnostics(){int priority=selected==null?0:settings.apps.get(selected.pkg).priority;return "state="+reason+",winner="+winner+",priority="+priority+",pending="+notices.size()+",draws="+draws+",pulseUpdates="+pulseUpdates+",fadeMs="+settings.intervalMs+",test="+testing()+",error="+failure+",notificationsError="+notificationError+",ambient="+ambient.diagnostics();}
    private final class Ring extends View {
        final Path original,path=new Path();final RectF bounds;final Rect box;final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        Ring(Context c,Path contour,RectF b,Rect box){super(c);original=new Path(contour);bounds=new RectF(b);this.box=new Rect(box);style();}
        void style(){float width=settings.thickness*getResources().getDisplayMetrics().density;paint.setStrokeWidth(width);paint.setStyle(Paint.Style.STROKE);
            CameraRingSettings.App app=testing()?CameraRingSelection.preview(settings):selected==null?null:settings.apps.get(selected.pkg);
            String color=app==null?"#FFFFFF":app.color;paint.setColor(Color.parseColor(color));paint.setAlpha(Math.round(255*settings.intensity/100f));
            path.set(original);Matrix m=new Matrix();m.setScale((bounds.width()+2*width)/bounds.width(),(bounds.height()+2*width)/bounds.height(),bounds.centerX(),bounds.centerY());path.transform(m);path.offset(-box.left,-box.top);
        }
        protected void onDraw(Canvas canvas){draws++;paint.setAlpha(CameraRingPulse.alpha(SystemClock.uptimeMillis()-pulseStart,settings.intervalMs,settings.intensity));canvas.drawPath(path,paint);}
    }
}

package com.nodecockpit.customization;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.view.*;
import android.view.animation.DecelerateInterpolator;
import android.widget.*;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Owns edge-panel windows, geometry and the single interruptible open-progress gesture. */
final class EdgePanelController {
    private static final int PANEL_HORIZONTAL_PADDING_DP=12;
    private static final int PANEL_EDGE_CLIP_DP=30;
    private static final int LAUNCHER_CELL_DP=56;
    enum GestureState { CLOSED, DRAGGING_OPEN, OPEN, DRAGGING_CLOSED, SETTLING_OPEN, SETTLING_CLOSED }
    interface FailureHandler { void onFailure(Throwable error); }
    private final Context context; private final Handler main; private final WindowManager windows; private final FailureHandler failures;
    private final AdaptiveGlassEngine handleGlass;
    private final AdaptiveGlassEngine[] panelGlass=new AdaptiveGlassEngine[3];
    private final ExecutorService samplingExecutor=Executors.newSingleThreadExecutor(r -> { Thread t=new Thread(r,"NodeCockpitEdgeSampler"); t.setDaemon(true); return t; });
    private EdgeBackdropSampler handleSampler; private final EdgeBackdropSampler[] panelSamplers=new EdgeBackdropSampler[3];
    private IndicatorSettings settings; private View signalView,collapsedHandle;
    private WindowManager.LayoutParams collapsedParams,modalParams;
    private GestureRoot modalRoot; private LinearLayout panel; private View connector;
    private TextView title,placeholder; private ScrollView scroll; private GridLayout appGrid; private LinearLayout actions,bodyContent,catalog;
    private EditText appSearch;
    private LinearLayout appTray; private ScrollView catalogScroll;
    private View searchMergeRegion,nativePanelOwner;
    private boolean searchDragging,searchHasPosition;private float searchFractionX,searchFractionY;
    private int searchAvailableHeight;

    private int imeHeight; private Runnable blankLongPress,folderHover; private String folderTarget; private boolean editLongPress;
    private org.json.JSONObject draftFolderNames=new org.json.JSONObject();
    private FrameLayout folderLayer; private String draggingItem; private final java.util.ArrayList<View> dragCells=new java.util.ArrayList<>();
    private String previewTarget;
    private View headerSeparator,actionSeparator; private final ArrayList<TextView> adaptiveLabels=new ArrayList<>();
    private final ArrayList<ImageView> adaptiveIcons=new ArrayList<>();
    private final java.util.WeakHashMap<View,android.graphics.drawable.Drawable> nativeLabelOriginal=new java.util.WeakHashMap<>();
    private final java.util.WeakHashMap<View,android.graphics.drawable.GradientDrawable> nativeLabelBacking=new java.util.WeakHashMap<>();
    private final EdgeWindowGuard windowGuard;private boolean safetyAllowed,appearanceWatching;
    private EdgeMaterialSurface nativePanel,nativeHandle,nativeTray; private NativeLiquidConfig nativeConfig=new NativeLiquidConfig("{}");
    private ValueAnimator settleAnimator; private GestureState gestureState=GestureState.CLOSED;
    private float openProgress; private boolean enabled;
    private ValueAnimator foregroundAnimator;private int fixedPanelTextColor;
    private final java.util.HashMap<TextView,EdgeBackdropSampler> labelSamplers=new java.util.HashMap<>();
    private final java.util.HashMap<TextView,Integer> labelColors=new java.util.HashMap<>();
    private final java.util.HashMap<TextView,ValueAnimator> labelAnimators=new java.util.HashMap<>();
    private long lastMovingSample;
    private int runtimePosition=50; private String runtimeSide="right"; private boolean movingHandle,editMode;
    private float handleDownX,handleDownY; private long handleDownNanos; private final ArrayList<String> draftApps=new ArrayList<>();
    private Runnable handleLongPress;
    private int windowCreates,windowRemoves,windowRebuilds,geometryUpdates,visualUpdates,gestureTransitions;
    private long lastAppearanceAt,lastSettingsRevision; private String lastChange="initial";
    private int lastSignalToken=Integer.MIN_VALUE;
    private final Runnable watchAppearance=new Runnable() {
        @Override public void run() {
            if (!needsAppearanceWatch()) { appearanceWatching=false; return; }
            int token=handleGlass.signalToken(signalView);
            for (AdaptiveGlassEngine engine:panelGlass) token=31*token+engine.signalToken(signalView);
            if (token!=lastSignalToken) { lastSignalToken=token; updateVisuals(true); }
            if(appearanceWatching)main.postDelayed(this,350);
        }
    };
    private android.window.OnBackInvokedDispatcher backDispatcher; private android.window.OnBackInvokedCallback backCallback;

    EdgePanelController(Context context,Handler main,FailureHandler failures) {
        this.context=context; this.main=main; this.failures=failures;
        windows=(WindowManager)context.getSystemService(Context.WINDOW_SERVICE);
        windowGuard=new EdgeWindowGuard(context,main,samplingExecutor,()->{if(settings!=null)safetyChanged(safetyAllowed);});
        handleGlass=new AdaptiveGlassEngine(context,main,this::onAppearanceChanged);
        for (int i=0;i<panelGlass.length;i++) panelGlass[i]=new AdaptiveGlassEngine(context,main,this::onAppearanceChanged);
    }
    void setSignalView(View view) { signalView=view; }
    void setForegroundAppearance(Boolean light) {
        boolean changed=handleGlass.setForegroundLight(light);
        for (AdaptiveGlassEngine engine:panelGlass) changed|=engine.setForegroundLight(light);
        if (changed&&enabled) { lastSignalToken=Integer.MIN_VALUE; updateVisuals(true); }
    }
    void apply(IndicatorSettings next,boolean safetyAllowed,boolean functionalChanged,boolean geometryChanged,boolean visualChanged,boolean contentChanged) {
        if(settings!=null&&settings.edgePanelTextAdaptation!=next.edgePanelTextAdaptation) { fixedPanelTextColor=next.edgePanelTextAdaptation?0:title==null?0:title.getCurrentTextColor();stopLabelSampling(); }
        if(settings!=null&&settings.edgePanelTextTone!=next.edgePanelTextTone&&next.edgePanelTextTone<0)fixedPanelTextColor=0;
        boolean nativeChanged=settings==null||!settings.edgePanelNativeGlass.equals(next.edgePanelNativeGlass)||settings.edgePanelTextTone!=next.edgePanelTextTone;
        settings=next; this.safetyAllowed=safetyAllowed;lastSettingsRevision=next.revision;
        windowGuard.active(safetyAllowed&&next.edgePanelEnabled);
        boolean previousCard=nativeConfig.card;
        nativeConfig=new NativeLiquidConfig(next.edgePanelNativeGlass,next.edgePanelTextTone);
        if(nativeChanged&&!searchDragging)readSearchPlacement();
        if(previousCard!=nativeConfig.card){closeTrayMaterial();if(nativePanel!=null){nativePanel.close();nativePanel=null;}if(nativeHandle!=null){nativeHandle.close();nativeHandle=null;}}
        if(!nativeConfig.enabled){NativeLiquidSurface.resetCircuit();CardLiquidSurface.resetCircuit();}
        if(nativeChanged){
            if(nativeTray!=null){if(nativeConfig.enabled&&nativeConfig.panel)nativeTray.configure(nativeConfig,dp(18));else closeTrayMaterial();}
            if(nativePanel!=null){if(nativeConfig.enabled&&nativeConfig.panel)nativePanel.configure(nativeConfig,dp(30));else{nativePanel.close();nativePanel=null;}}
            if(nativeHandle!=null){if(nativeConfig.enabled&&nativeConfig.handle&&nativeConfig.liveHandle)nativeHandle.configure(nativeConfig,dp(10));else{nativeHandle.close();nativeHandle=null;}}
        }
        if(nativeChanged&&editMode&&modalRoot!=null&&!searchDragging)layoutModal(bounds());
        if (!movingHandle) { runtimePosition=next.edgePanelPosition; runtimeSide=next.edgePanelSide; }
        boolean shouldEnable=next.edgePanelEnabled&&safetyAllowed&&!windowGuard.blocked();
        NativeLiquidSurface.setBackendEnabled(shouldEnable&&nativeConfig.enabled&&(!nativeConfig.card||nativeConfig.handle&&nativeConfig.liveHandle));
        CardLiquidSurface.setBackendEnabled(shouldEnable&&nativeConfig.enabled&&nativeConfig.card);
        if (functionalChanged || enabled!=shouldEnable) {
            enabled=shouldEnable; lastChange="functional";
            if (!enabled) { stopAppearanceWatch(); closeImmediately(); removeCollapsed(); }
            else { startAppearanceWatch(); if (openProgress<=0f) ensureCollapsed(); }
        }
        if (!enabled) return;
        if (geometryChanged) { geometryUpdates++; lastChange="geometry"; updateGeometryInPlace(); }
        if (visualChanged) { visualUpdates++; lastChange="visual"; updateVisuals(false); }
        if (contentChanged&&modalRoot!=null) { lastChange="content"; populateLaunchers(); }
        if (collapsedHandle==null && modalRoot==null) ensureCollapsed();
    }
    void safetyChanged(boolean allowed) {
        if (settings==null) return;
        this.safetyAllowed=allowed;windowGuard.active(allowed&&settings.edgePanelEnabled);
        boolean shouldEnable=settings.edgePanelEnabled&&allowed&&!windowGuard.blocked();
        NativeLiquidSurface.setBackendEnabled(shouldEnable&&nativeConfig.enabled&&(!nativeConfig.card||nativeConfig.handle&&nativeConfig.liveHandle));
        CardLiquidSurface.setBackendEnabled(shouldEnable&&nativeConfig.enabled&&nativeConfig.card);
        if (enabled==shouldEnable) return;
        enabled=shouldEnable; lastChange="safety";
        if (!enabled) { stopAppearanceWatch(); closeImmediately(); removeCollapsed(); }
        else { startAppearanceWatch(); ensureCollapsed(); }
    }
    void foregroundPackage(String pkg){windowGuard.foreground(pkg);}
    private void ensureCollapsed() {
        if (!enabled || collapsedHandle!=null || openProgress>0f) return;
        try {
            View handle=new View(context); handle.setContentDescription("Open edge panel"); handle.setElevation(0);
            handle.setOnTouchListener((v,e) -> {
                if(!enabled)return true;
                if(nativeHandle!=null)nativeHandle.touch(e);
                switch (e.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        interruptSettling(); handleDownX=e.getRawX(); handleDownY=e.getRawY(); movingHandle=false;
                        handleDownNanos=System.nanoTime(); final long started=handleDownNanos; handle.setTag(started);
                        handleLongPress=() -> { if (handle.getTag() instanceof Long&&((Long)handle.getTag())==started) { movingHandle=true; handle.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS); } };
                        main.postDelayed(handleLongPress,420); return true;
                    case MotionEvent.ACTION_MOVE:
                        if (movingHandle) { moveHandle(e.getRawX(),e.getRawY()); return true; }
                        if (Math.hypot(e.getRawX()-handleDownX,e.getRawY()-handleDownY)>dp(8)) { main.removeCallbacks(handleLongPress); handle.setTag(null); }
                        float progress=clamp(("right".equals(runtimeSide)?handleDownX-e.getRawX():e.getRawX()-handleDownX)/Math.max(1f,panelTravel()));
                        if (progress>0.005f) { ensureModal(false); setGestureState(GestureState.DRAGGING_OPEN); setProgress(progress); }
                        return true;
                    case MotionEvent.ACTION_UP:
                        main.removeCallbacks(handleLongPress); handle.setTag(null);
                        if (movingHandle) { movingHandle=false; persistPlacement(); return true; }
                        float dx="right".equals(runtimeSide)?handleDownX-e.getRawX():e.getRawX()-handleDownX;
                        float seconds=Math.max(0.001f,(System.nanoTime()-handleDownNanos)/1_000_000_000f);
                        float velocity=dx/seconds;
                        if (Math.abs(dx)<dp(4)) animateTo(1f,0f); else settle(velocity);
                        return true;
                    case MotionEvent.ACTION_CANCEL:
                        main.removeCallbacks(handleLongPress); handle.setTag(null); if (movingHandle) { movingHandle=false; persistPlacement(); } else settle(0f); return true;
                }
                return true;
            });
            collapsedHandle=handle;
            collapsedParams=baseParams(dp(12),dp(settings.edgeHandleHeight),false);
            collapsedParams.gravity=("right".equals(runtimeSide)?Gravity.RIGHT:Gravity.LEFT)|Gravity.TOP; updateCollapsedGeometry();
            windows.addView(handle,collapsedParams); windowCreates++;
            handle.post(() -> { startSampling(handle); updateVisuals(false); if (Build.VERSION.SDK_INT>=29) handle.setSystemGestureExclusionRects(
                java.util.Collections.singletonList(new Rect(0,0,handle.getWidth(),handle.getHeight()))); });
        } catch (Throwable e) { failures.onFailure(e); }
    }
    private void ensureModal(boolean touchable) {
        if(!enabled)return;
        if (modalRoot!=null) { setModalTouchable(touchable); return; }
        try {
            Bounds b=bounds();
            GestureRoot root=new GestureRoot(context); root.setFocusableInTouchMode(true); root.setBackgroundColor(Color.TRANSPARENT);
            LinearLayout card=new LinearLayout(context); card.setOrientation(LinearLayout.VERTICAL);
            card.setElevation(0); card.setLongClickable(true); card.setOnLongClickListener(v -> { enterEditMode(); return true; });
            TextView heading=new TextView(context); heading.setText("Quick launch"); heading.setTextSize(18); heading.setSingleLine(true);
            heading.setEllipsize(android.text.TextUtils.TruncateAt.END); heading.setTypeface(android.graphics.Typeface.create("sans-serif-medium",0));
            heading.setGravity(Gravity.CENTER);
            card.addView(heading,new LinearLayout.LayoutParams(-1,-2));
            View topRule=new View(context); LinearLayout.LayoutParams topRuleParams=new LinearLayout.LayoutParams(-1,dp(1)); topRuleParams.setMargins(0,dp(10),0,dp(8)); card.addView(topRule,topRuleParams);
            ScrollView body=new ScrollView(context); body.setFillViewport(false); body.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);
            LinearLayout content=new LinearLayout(context); content.setOrientation(LinearLayout.VERTICAL); content.setGravity(Gravity.CENTER_HORIZONTAL);
            TextView empty=new TextView(context); empty.setText("Add apps from Node Cockpit settings"); empty.setTextSize(15); empty.setPadding(0,dp(10),0,dp(16));
            GridLayout launchers=new GridLayout(context); launchers.setColumnCount(1); launchers.setAlignmentMode(GridLayout.ALIGN_BOUNDS);
            content.addView(empty,new LinearLayout.LayoutParams(-1,-2)); content.addView(launchers,new LinearLayout.LayoutParams(-2,-2));
            body.addView(content,new ScrollView.LayoutParams(-1,-2));
            body.getViewTreeObserver().addOnScrollChangedListener(() -> { for (EdgeBackdropSampler sampler:labelSamplers.values()) sampler.refreshBounds(); });
            body.setOnDragListener((v,event) -> {
                if (!editMode) return false;
                if (event.getAction()==DragEvent.ACTION_DRAG_LOCATION) {
                    if (event.getY()<dp(48)) body.smoothScrollBy(0,-dp(20));
                    else if (event.getY()>body.getHeight()-dp(48)) body.smoothScrollBy(0,dp(20));
                }
                if (event.getAction()==DragEvent.ACTION_DROP) { addDraftApp(event.getClipData().getItemAt(0).getText().toString()); return true; }
                return true;
            });
            body.setOnLongClickListener(v -> { enterEditMode(); return true; });
            content.setOnLongClickListener(v -> { enterEditMode(); return true; });
            empty.setOnLongClickListener(v -> { enterEditMode(); return true; });
            card.addView(body,new LinearLayout.LayoutParams(-1,0,1f));
            View bottomRule=new View(context); LinearLayout.LayoutParams bottomRuleParams=new LinearLayout.LayoutParams(-1,dp(1)); bottomRuleParams.setMargins(0,dp(8),0,dp(6)); card.addView(bottomRule,bottomRuleParams);
            LinearLayout actionBar=new LinearLayout(context); actionBar.setOrientation(LinearLayout.HORIZONTAL);
            card.addView(actionBar,new LinearLayout.LayoutParams(-1,-2));
            View join=new View(context); join.setElevation(dp(24));
            root.addView(card); root.addView(join);
            modalRoot=root; panel=card; connector=join; title=heading; placeholder=empty; scroll=body; appGrid=launchers; actions=actionBar; bodyContent=content;
            appGrid.setOnDragListener((v,event) -> { if (!editMode) return false; switch (event.getAction()) {
                case DragEvent.ACTION_DRAG_STARTED: return event.getClipDescription()!=null&&event.getClipDescription().hasMimeType(android.content.ClipDescription.MIMETYPE_TEXT_PLAIN);
                case DragEvent.ACTION_DROP: String pkg=event.getClipData().getItemAt(0).getText().toString(); addDraftApp(pkg); return true;
                default: return true;
            }});
            headerSeparator=topRule; actionSeparator=bottomRule; adaptiveLabels.add(heading); adaptiveLabels.add(empty);
            modalParams=baseParams(b.width,b.height,touchable); modalParams.gravity=Gravity.LEFT|Gravity.TOP; modalParams.y=b.top;
            modalParams.softInputMode=WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE;
            root.setOnApplyWindowInsetsListener((v,insets) -> {
                int next=insets.getInsets(WindowInsets.Type.ime()).bottom;
                if (imeHeight!=next) { imeHeight=next; if (editMode) root.post(() -> layoutModal(bounds())); }
                return insets;
            });
            windows.addView(root,modalParams); windowCreates++; populateLaunchers(); populateActions();
            layoutModal(b); setProgress(openProgress); root.post(() -> { startSampling(card); updateVisuals(false); registerBack(); if (touchable) root.requestFocus(); });
        } catch (Throwable e) { failures.onFailure(e); removeModal(); }
    }
    private void updateCollapsedGeometry() {
        if (collapsedHandle==null || collapsedParams==null || settings==null) return;
        Bounds b=bounds(); int h=dp(settings.edgeHandleHeight); int anchor=b.top+Math.round(b.height*runtimePosition/100f);
        collapsedParams.gravity=("right".equals(runtimeSide)?Gravity.RIGHT:Gravity.LEFT)|Gravity.TOP;
        collapsedParams.height=h; collapsedParams.y=Math.max(b.top,Math.min(b.bottom-h,anchor-h/2));
        if (collapsedHandle.isAttachedToWindow()) windows.updateViewLayout(collapsedHandle,collapsedParams);
    }
    private void moveHandle(float rawX,float rawY) {
        Bounds b=bounds(); runtimeSide=rawX<b.width/2f?"left":"right";
        runtimePosition=Math.max(5,Math.min(95,Math.round(100f*(rawY-b.top)/Math.max(1,b.height))));
        updateCollapsedGeometry(); updateVisuals(false);
    }
    private void persistPlacement() {
        final int position=runtimePosition; final String side=runtimeSide;
        samplingExecutor.execute(() -> { try {
            android.os.Bundle data=new android.os.Bundle(); data.putInt("position",position); data.putString("side",side);
            context.getContentResolver().call(android.net.Uri.parse("content://com.example.remote_control.customization.health"),"edgePlacement",null,data);
        } catch (Throwable error) { main.post(() -> failures.onFailure(error)); } });
    }
    private void layoutModal(Bounds b) {
        if (modalRoot==null || settings==null) return;
        int width=Math.min(dp(settings.edgePanelWidth),Math.round(b.width*.88f));
        if(editMode&&appTray!=null)width=Math.min(width,Math.max(dp(80),b.width-dp(164)));
        int available=Math.max(dp(56),b.height-(editMode?imeHeight:0)-dp(24));
        int height=Math.min(dp(settings.edgePanelHeight),available);
        int anchor=Math.round(b.height*runtimePosition/100f);
        int top=Math.max(dp(12),Math.min(available-height+dp(12),anchor-height/2));
        int connectorHeight=Math.min(dp(settings.edgeHandleHeight),height-dp(24));
        int connectorTop=Math.max(top+dp(12),Math.min(top+height-dp(12)-connectorHeight,anchor-connectorHeight/2));
        int clippedRadius=editMode?0:dp(PANEL_EDGE_CLIP_DP); int detached=editMode?dp(12):0;
        boolean right="right".equals(runtimeSide);
        panel.setPadding(dp(PANEL_HORIZONTAL_PADDING_DP+(right||editMode?0:PANEL_EDGE_CLIP_DP)),dp(20),dp(PANEL_HORIZONTAL_PADDING_DP+(!right||editMode?0:PANEL_EDGE_CLIP_DP)),dp(20));
        FrameLayout.LayoutParams card=new FrameLayout.LayoutParams(width+clippedRadius,height,Gravity.TOP|(right?Gravity.RIGHT:Gravity.LEFT)); card.topMargin=top;
        if (right) card.rightMargin=editMode?detached:-clippedRadius; else card.leftMargin=editMode?detached:-clippedRadius; panel.setLayoutParams(card);
        FrameLayout.LayoutParams join=new FrameLayout.LayoutParams(dp(12),connectorHeight,Gravity.TOP|(right?Gravity.RIGHT:Gravity.LEFT)); join.topMargin=connectorTop; connector.setLayoutParams(join);
        connector.setVisibility(editMode?View.GONE:View.VISIBLE);
        modalRoot.panelLeft=right?b.width-width-detached:detached; modalRoot.panelRight=right?b.width-detached:width+detached; modalRoot.panelOnRight=right; modalRoot.requestLayout();
        if (appTray!=null) {
            int tw=EdgeSearchPlacement.size(dp(nativeConfig.searchWidth),Math.max(dp(140),b.width-width-dp(36)),b.width,dp(8));
            searchAvailableHeight=Math.max(dp(80),b.height-imeHeight);
            int th=EdgeSearchPlacement.size(dp(nativeConfig.searchHeight),height,searchAvailableHeight,dp(8));
            FrameLayout.LayoutParams tray=new FrameLayout.LayoutParams(tw,th,Gravity.TOP|Gravity.LEFT);
            float x=searchHasPosition?EdgeSearchPlacement.position(searchFractionX,b.width,tw,dp(8)):right?dp(8):b.width-tw-dp(8);
            float y=searchHasPosition?EdgeSearchPlacement.position(searchFractionY,searchAvailableHeight,th,dp(8)):top;
            tray.leftMargin=Math.round(EdgeSearchPlacement.clamp(x,b.width,tw,dp(8)));tray.topMargin=Math.round(EdgeSearchPlacement.clamp(y,searchAvailableHeight,th,dp(8)));
            appTray.setTranslationX(0);appTray.setTranslationY(0);appTray.setLayoutParams(tray);
            layoutSearchMerge();
        }

    }
    private boolean searchMerged(){return editMode&&nativeConfig.enabled&&nativeConfig.card&&nativeConfig.panel&&appTray!=null&&appTray.getVisibility()==View.VISIBLE&&searchMergeRegion!=null;}
    private void readSearchPlacement(){
        try{org.json.JSONObject t=new org.json.JSONObject(settings.edgePanelNativeGlass).optJSONObject("searchTray");searchHasPosition=t!=null&&t.has("x")&&t.has("y");if(searchHasPosition){searchFractionX=clamp((float)t.optDouble("x",0));searchFractionY=clamp((float)t.optDouble("y",0));}}
        catch(Exception ignored){searchHasPosition=false;}
    }
    private void layoutSearchMerge(){
        if(searchMergeRegion==null)return;
        ((EdgeMergeRegion)searchMergeRegion).merging=searchMerged();
        searchMergeRegion.setLayoutParams(new FrameLayout.LayoutParams(bounds().width,searchAvailableHeight,Gravity.TOP|Gravity.LEFT));
        searchMergeRegion.setVisibility(searchMerged()?View.VISIBLE:View.GONE);
    }
    private void removeSearchMergeView(){
        if(nativePanelOwner==searchMergeRegion&&searchMergeRegion!=null){if(nativePanel!=null){nativePanel.close();nativePanel=null;}nativePanelOwner=null;}
        if(searchMergeRegion!=null){for(AdaptiveGlassEngine e:panelGlass)e.releaseSurface(searchMergeRegion);if(modalRoot!=null)modalRoot.removeView(searchMergeRegion);}searchMergeRegion=null;
    }
    private void cancelSearchDrag(){searchDragging=false;}
    private void rememberSearchPosition(){if(appTray==null)return;Bounds b=bounds();searchHasPosition=true;searchFractionX=EdgeSearchPlacement.fraction(appTray.getX(),b.width,appTray.getWidth(),dp(8));searchFractionY=EdgeSearchPlacement.fraction(appTray.getY(),searchAvailableHeight,appTray.getHeight(),dp(8));}
    private void persistSearchPlacement(){final double x=searchFractionX,y=searchFractionY;samplingExecutor.execute(()->{try{android.os.Bundle data=new android.os.Bundle();data.putDouble("x",x);data.putDouble("y",y);context.getContentResolver().call(android.net.Uri.parse("content://com.example.remote_control.customization.health"),"edgeSearchPlacement",null,data);}catch(Throwable error){main.post(()->failures.onFailure(error));}});}
    private void moveSearchBy(int dx,int dy){if(appTray==null)return;Bounds b=bounds();appTray.setX(EdgeSearchPlacement.clamp(appTray.getX()+dp(dx),b.width,appTray.getWidth(),dp(8)));appTray.setY(EdgeSearchPlacement.clamp(appTray.getY()+dp(dy),searchAvailableHeight,appTray.getHeight(),dp(8)));rememberSearchPosition();persistSearchPlacement();}
    private View createSearchGrip(){
        View grip=new View(context){
          @Override public void onInitializeAccessibilityNodeInfo(android.view.accessibility.AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(info);info.addAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT);info.addAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT);info.addAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP);info.addAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN);}
          @Override public boolean performAccessibilityAction(int action,android.os.Bundle args){if(action==android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT.getId()){moveSearchBy(-32,0);return true;}if(action==android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT.getId()){moveSearchBy(32,0);return true;}if(action==android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP.getId()){moveSearchBy(0,-32);return true;}if(action==android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN.getId()){moveSearchBy(0,32);return true;}return super.performAccessibilityAction(action,args);}
private final android.graphics.Paint paint=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);@Override protected void onDraw(android.graphics.Canvas c){super.onDraw(c);float d=getResources().getDisplayMetrics().density,x=getWidth()/2f,y=getHeight()/2f;paint.setStyle(android.graphics.Paint.Style.STROKE);paint.setStrokeCap(android.graphics.Paint.Cap.ROUND);paint.setColor(0xcc10161d);paint.setStrokeWidth(5*d);c.drawLine(x-18*d,y,x+18*d,y,paint);paint.setColor(0xfff8fafd);paint.setStrokeWidth(2*d);c.drawLine(x-18*d,y,x+18*d,y,paint);}};
        grip.setContentDescription("Move app search");grip.setTooltipText("Drag this handle to move search. Glass joins naturally near the panel.");grip.setFocusable(true);
        grip.setOnTouchListener(new View.OnTouchListener(){float downX,downY,startX,startY;boolean moved;int pointer;
            public boolean onTouch(View v,MotionEvent e){if(appTray==null)return false;switch(e.getActionMasked()){
                case MotionEvent.ACTION_DOWN:cancelSearchDrag();pointer=e.getPointerId(0);downX=e.getRawX();downY=e.getRawY();startX=appTray.getX();startY=appTray.getY();rememberSearchPosition();moved=false;v.getParent().requestDisallowInterceptTouchEvent(true);return true;
                case MotionEvent.ACTION_MOVE:if(e.getPointerId(0)!=pointer)return true;float dx=e.getRawX()-downX,dy=e.getRawY()-downY;if(!moved&&Math.hypot(dx,dy)<=android.view.ViewConfiguration.get(context).getScaledTouchSlop())return true;
                    if(!moved){moved=true;searchDragging=true;v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);}
                    Bounds b=bounds();appTray.setX(EdgeSearchPlacement.clamp(startX+dx,b.width,appTray.getWidth(),dp(8)));appTray.setY(EdgeSearchPlacement.clamp(startY+dy,searchAvailableHeight,appTray.getHeight(),dp(8)));
                    return true;
                case MotionEvent.ACTION_UP:v.getParent().requestDisallowInterceptTouchEvent(false);searchDragging=false;if(!moved){v.performClick();return true;}rememberSearchPosition();persistSearchPlacement();return true;
                case MotionEvent.ACTION_CANCEL:v.getParent().requestDisallowInterceptTouchEvent(false);searchDragging=false;if(moved){layoutModal(bounds());updateVisuals(false);}return true;
            }return true;}
        });return grip;
    }
    private void updateGeometryInPlace() {
        try {
            updateCollapsedGeometry();
            if (modalRoot!=null) {
                Bounds b=bounds(); modalParams.width=b.width; modalParams.height=b.height; modalParams.y=b.top;
                windows.updateViewLayout(modalRoot,modalParams); layoutModal(b); populateLaunchers(); setProgress(openProgress);
            }
        } catch (Throwable e) { failures.onFailure(e); }
    }
    private EdgeMaterialSurface createMaterial(View v,String name,float r){Runnable changed=() -> main.post(() -> updateVisuals(false));return nativeConfig.card?new CardLiquidSurface(v,name,r,nativeConfig,changed):new NativeLiquidSurface(v,name,r,nativeConfig,changed);}
    private int middleInk,bottomInk;
    private void updateVisuals(boolean animate) {
        if (settings==null) return;
        View materialPanel=searchMerged()?searchMergeRegion:panel;
        if(nativePanelOwner!=materialPanel){if(nativePanel!=null){nativePanel.close();nativePanel=null;}if(nativePanelOwner!=null){for(AdaptiveGlassEngine e:panelGlass)e.releaseSurface(nativePanelOwner);nativePanelOwner.setBackground(null);nativePanelOwner.setForeground(null);}nativePanelOwner=materialPanel;}
        if(nativeConfig.enabled&&nativeConfig.panel&&materialPanel!=null&&materialPanel.isAttachedToWindow()&&nativePanel==null)nativePanel=createMaterial(materialPanel,"panel",dp(30));
        if(searchMerged())closeTrayMaterial();
        if(nativeConfig.enabled&&nativeConfig.handle&&nativeConfig.liveHandle&&collapsedHandle!=null&&collapsedHandle.isAttachedToWindow()&&nativeHandle==null)nativeHandle=new NativeLiquidSurface(collapsedHandle,"handle",dp(10),nativeConfig,() -> main.post(() -> updateVisuals(false)));
        if(!searchMerged()&&nativeConfig.enabled&&nativeConfig.panel&&appTray!=null&&appTray.isShown()&&appTray.isAttachedToWindow()&&nativeTray==null)nativeTray=createMaterial(appTray,"search",dp(18));
        boolean nativeCard=nativePanel!=null&&nativePanel.active(),nativeGrip=nativeHandle!=null&&nativeHandle.active();

        if(!nativeConfig.liveHandle){if(handleSampler!=null){handleSampler.stop();handleSampler=null;}handleGlass.setLocalBackdropLight(null);}
        float handleLuma=handleSampler==null?Float.NaN:handleSampler.luminance();
        int handleOpacity=settings.edgeHandleOpacity;
        if (!Float.isNaN(handleLuma)) handleOpacity=Math.round(handleOpacity*(.65f+.35f*Math.min(1f,Math.max(0f,handleLuma)/.5f)));
        AdaptiveGlassEngine.Style handleStyle=handleGlass.resolve(handleOpacity,settings.edgeHandleBlur,settings.edgeHandleTintMode,signalView);
        AdaptiveGlassEngine.Style[] styles=new AdaptiveGlassEngine.Style[3];
        for (int i=0;i<3;i++) styles[i]=panelGlass[i].resolve(settings.edgePanelOpacity,settings.edgePanelBlur,settings.edgePanelTintMode,signalView);
        lastAppearanceAt=android.os.SystemClock.elapsedRealtime();
        boolean right="right".equals(runtimeSide);
        if (collapsedHandle!=null) { if(nativeGrip){if(handleSampler!=null){handleSampler.stop();handleSampler=null;}handleGlass.releaseSurface(collapsedHandle);collapsedHandle.setBackground(null);collapsedHandle.setForeground(null);}else if(nativeConfig.liveHandle)handleGlass.applyEdge(collapsedHandle,handleStyle,dp(10),right);else handleGlass.applyFlatEdge(collapsedHandle,handleStyle,dp(10),right); }
        if(appTray!=null){
            if(searchMerged()&&nativeCard||nativeTray!=null&&nativeTray.active()){panelGlass[1].releaseSurface(appTray);appTray.setBackground(null);appTray.setForeground(null);}
            else panelGlass[1].apply(appTray,styles[1],dp(18),true);
        }
        if (panel!=null) {
            if(nativeCard){
                stopPanelSampling();stopLabelSampling();if(foregroundAnimator!=null){foregroundAnimator.cancel();foregroundAnimator=null;}
                for(AdaptiveGlassEngine engine:panelGlass)engine.releaseSurface(materialPanel);
                if(materialPanel!=null){materialPanel.setBackground(null);materialPanel.setForeground(null);}panel.setBackground(null);panel.setForeground(null);connector.setBackground(null);connector.setForeground(null);
                int ink=settings.edgePanelTextTone>=0?TextTone.color(settings.edgePanelTextTone):0xfff8fafd;
                for(TextView label:adaptiveLabels){
                    if(label==appSearch)appSearch.setHintTextColor(ink);
                    if(label.getCurrentTextColor()!=ink){label.setTextColor(ink);label.setShadowLayer(dp(1),0,dp(1),Color.luminance(ink)>.179f?0x99000000:0x99ffffff);}
                    if(!nativeLabelOriginal.containsKey(label)){
                        nativeLabelOriginal.put(label,label.getBackground());
                        android.graphics.drawable.GradientDrawable backing=new EdgeInkBacking(label,label.getBackground());backing.setCornerRadius(dp(5));nativeLabelBacking.put(label,backing);label.setBackground(backing);((EdgeInkBacking)backing).bind();
                        label.setShadowLayer(dp(1),0,dp(1),Color.luminance(ink)>.179f?0x99000000:0x99ffffff);
                    }
                    int a=nativeConfig.card?0:nativeConfig.preset==0?0:Math.round(170f*(float)Math.sqrt(nativeConfig.contrast));
                    android.graphics.drawable.GradientDrawable backing=nativeLabelBacking.get(label);int color=(a<<24)|(nativeConfig.darkInk?0x00ffffff:0x00131a22);
                    if(backing.getColor()==null||backing.getColor().getDefaultColor()!=color)backing.setColor(color);
                }
                for(ImageView icon:adaptiveIcons){
                    icon.setColorFilter(ink);
                    if(!nativeLabelOriginal.containsKey(icon)){
                        nativeLabelOriginal.put(icon,icon.getBackground());android.graphics.drawable.GradientDrawable backing=new EdgeInkBacking(icon,icon.getBackground());backing.setCornerRadius(dp(6));nativeLabelBacking.put(icon,backing);icon.setBackground(backing);((EdgeInkBacking)backing).bind();
                    }
                    int a=nativeConfig.card?0:nativeConfig.preset==0?0:Math.round(170f*(float)Math.sqrt(nativeConfig.contrast));int color=(a<<24)|(nativeConfig.darkInk?0x00ffffff:0x00131a22);android.graphics.drawable.GradientDrawable backing=nativeLabelBacking.get(icon);if(backing instanceof EdgeInkBacking)((EdgeInkBacking)backing).ink(ink);
                    if(backing.getColor()==null||backing.getColor().getDefaultColor()!=color)backing.setColor(color);
                }
                headerSeparator.setBackgroundColor(0x44ffffff);actionSeparator.setBackgroundColor(0x44ffffff);startAppearanceWatch();return;
            }
            restoreNativeLabelBackings();
            for(TextView label:adaptiveLabels)label.setShadowLayer(0,0,0,0);
            if (editMode) {if(searchMerged()&&searchMergeRegion!=null){searchMergeRegion.setBackground(null);searchMergeRegion.setForeground(null);}panelGlass[1].apply(panel,styles[1],dp(30),true);}
            else panelGlass[1].applyEdge(panel,styles[1],dp(30),right,styles[0].border,styles[2].border);
            // The panel already reaches the screen edge. A second blur surface
            // over it samples/composites twice and creates a mismatched patch.
            connector.setBackground(null); connector.setForeground(null);
            int from=title.getCurrentTextColor(),to=styles[0].foreground;
            if (foregroundAnimator!=null) { foregroundAnimator.cancel(); foregroundAnimator=null; }
            if (animate && settings.edgePanelTextAdaptation&&(from!=to||middleInk!=styles[1].foreground||bottomInk!=styles[2].foreground)) {
                final int fromMiddle=middleInk==0?from:middleInk,fromBottom=bottomInk==0?from:bottomInk;
                final android.animation.ArgbEvaluator evaluator=new android.animation.ArgbEvaluator();
                ValueAnimator colors=ValueAnimator.ofFloat(0,1); colors.setDuration(settings.edgePanelTextDurationMs<0?styles[0].transitionMs:settings.edgePanelTextDurationMs);
                foregroundAnimator=colors;
                colors.addUpdateListener(a -> { if (title!=null) applyForegroundZones((Integer)evaluator.evaluate((Float)a.getAnimatedValue(),from,to),(Integer)evaluator.evaluate((Float)a.getAnimatedValue(),fromMiddle,styles[1].foreground),(Integer)evaluator.evaluate((Float)a.getAnimatedValue(),fromBottom,styles[2].foreground)); });
                colors.start();
            } else applyForegroundZones(to,styles[1].foreground,styles[2].foreground);
            headerSeparator.setBackgroundColor(styles[0].separator); actionSeparator.setBackgroundColor(styles[2].separator);
            placeholder.setAlpha(.74f);
        }
        startAppearanceWatch();
    }
    private void onAppearanceChanged() { if (enabled) updateVisuals(true); }
    private void startSampling(View target) {
        if (target==collapsedHandle) {
            if(!nativeConfig.liveHandle)return;
            if(nativeHandle!=null&&nativeHandle.active())return;
            if (handleSampler!=null&&handleSampler.samples(target)) return;
            if (handleSampler!=null) handleSampler.stop();
            handleSampler=new EdgeBackdropSampler(context,main,samplingExecutor,target,light -> {
                if(handleGlass.setLocalBackdropLight(light)&&enabled)updateVisuals(true);
            }); handleSampler.start(); return;
        }
        if (target==panel) {
            if(nativePanel!=null&&nativePanel.active())return;
            stopPanelSampling();
            float[][] zones={{0f,.26f},{.26f,.76f},{.76f,1f}};
            for (int i=0;i<3;i++) { final int zone=i;
                panelSamplers[i]=new EdgeBackdropSampler(context,main,samplingExecutor,target,zones[i][0],zones[i][1],light -> {
                    if (panelGlass[zone].setLocalBackdropLight(light)&&enabled) updateVisuals(true);
                }); panelSamplers[i].start();
            }
        }
    }
    private void stopSampling(View target) {
        if (target==collapsedHandle&&handleSampler!=null) { handleSampler.stop(); handleSampler=null; }
        if (target==panel) stopPanelSampling();
    }
    private void stopPanelSampling() { for (int i=0;i<panelSamplers.length;i++) if (panelSamplers[i]!=null) { panelSamplers[i].stop(); panelSamplers[i]=null; } }
    void recoverAfterWake() {
        windowGuard.refresh();
        if (!enabled) return;
        try {
            if (modalRoot!=null&&!modalRoot.isAttachedToWindow()) { openProgress=0f; setGestureState(GestureState.CLOSED); removeModal(); }
            if (collapsedHandle!=null&&!collapsedHandle.isAttachedToWindow()) removeCollapsed();
            if (modalRoot==null&&collapsedHandle==null) ensureCollapsed();
            updateGeometryInPlace(); updateVisuals(false); startAppearanceWatch();
            View target=panel!=null?panel:collapsedHandle;
            if (target!=null&&target.isAttachedToWindow()) { stopSampling(target); startSampling(target); }
        } catch (Throwable error) { failures.onFailure(error); }
    }
    private boolean needsAppearanceWatch(){return enabled&&(panel!=null&&(nativePanel==null||!nativePanel.active())||collapsedHandle!=null&&nativeConfig.liveHandle&&(nativeHandle==null||!nativeHandle.active()));}
    private void startAppearanceWatch(){if(!needsAppearanceWatch()){stopAppearanceWatch();return;}if(!appearanceWatching){appearanceWatching=true;lastSignalToken=Integer.MIN_VALUE;main.post(watchAppearance);}}
    private void stopAppearanceWatch(){appearanceWatching=false;main.removeCallbacks(watchAppearance);lastSignalToken=Integer.MIN_VALUE;}
    private void populateLaunchers() {
        if (appGrid==null||settings==null) return;
        stopLabelSampling();
        appGrid.removeAllViews();
        adaptiveLabels.removeIf(label -> label!=title&&label!=placeholder&&label.getTag()==Boolean.TRUE);
        int columns=configureLauncherColumns(); int index=0;
        String raw=editMode?android.text.TextUtils.join(",",draftApps):settings.edgePanelApps.trim(); placeholder.setVisibility(raw.isEmpty()?View.VISIBLE:View.GONE);
        if (raw.isEmpty()) return;
        android.content.pm.PackageManager pm=context.getPackageManager();
        for (String item:raw.split(",")) {
            try {
                String packageName=item.split("\\+")[0]; boolean folder=item.contains("+");
                android.content.Intent launch=pm.getLaunchIntentForPackage(packageName); if (launch==null) continue;
                android.content.pm.ApplicationInfo info=pm.getApplicationInfo(packageName,0);
                LinearLayout content=new LinearLayout(context); content.setOrientation(LinearLayout.VERTICAL); content.setGravity(Gravity.CENTER_HORIZONTAL);
                ImageButton button=new ImageButton(context); button.setImageDrawable(pm.getApplicationIcon(info));
                if (folder) button.setImageDrawable(folderIcon(item));
                button.setContentDescription(pm.getApplicationLabel(info)); button.setBackgroundColor(Color.TRANSPARENT);
                button.setPadding(dp(2),dp(2),dp(2),dp(2)); button.setScaleType(ImageView.ScaleType.FIT_CENTER);
                button.setOnClickListener(v -> {
                    if (editMode) { if (folder) showFolder(item); return; }
                    if (folder) { showFolder(item); return; }
                    try { closeImmediately(); launch.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK); context.startActivity(launch); }
                    catch (Throwable e) { failures.onFailure(e); }
                });
                TextView appName=new TextView(context); appName.setText(folder?folderName(item):pm.getApplicationLabel(info)); appName.setTextSize(10); appName.setGravity(Gravity.CENTER);
                appName.setMaxLines(2); appName.setEllipsize(android.text.TextUtils.TruncateAt.END); appName.setTag(Boolean.TRUE);
                if (title!=null) appName.setTextColor(title.getCurrentTextColor()); adaptiveLabels.add(appName);
                content.addView(button,new LinearLayout.LayoutParams(dp(LAUNCHER_CELL_DP),dp(LAUNCHER_CELL_DP)));
                content.addView(appName,new LinearLayout.LayoutParams(dp(LAUNCHER_CELL_DP),dp(28)));
                FrameLayout cell=new FrameLayout(context); cell.addView(content,new FrameLayout.LayoutParams(-1,-1));
                cell.setTag(item);
                if (!editMode) button.setOnLongClickListener(v -> {
                    enterEditMode(); appGrid.post(() -> { for (int i=0;i<appGrid.getChildCount();i++) {
                        View child=appGrid.getChildAt(i); if (item.equals(child.getTag())) beginIconDrag(item,button.getDrawable());
                    }}); return true;
                });
                if (editMode) {
                    button.setOnLongClickListener(v -> { beginIconDrag(item,button.getDrawable()); return true; });
                    cell.setOnDragListener((v,event) -> {
                        if (event.getAction()==DragEvent.ACTION_DRAG_STARTED) return true;
                        if (event.getAction()==DragEvent.ACTION_DRAG_ENTERED) {
                            if (item.equals(draggingItem)) return true;
                            if (folderHover!=null) main.removeCallbacks(folderHover);
                            folderTarget=null; v.animate().scaleX(1.08f).scaleY(1.08f).setDuration(100).start();
                            folderHover=() -> { resetDragPreview(); folderTarget=item; v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS); v.animate().scaleX(1.18f).scaleY(1.18f).setDuration(100).start(); };
                            main.postDelayed(folderHover,650); return true;
                        }
                        if (event.getAction()==DragEvent.ACTION_DRAG_LOCATION) { if (folderTarget==null) previewReorder(item); return true; }
                        if (event.getAction()==DragEvent.ACTION_DRAG_EXITED||event.getAction()==DragEvent.ACTION_DRAG_ENDED) {
                            if (folderHover!=null) main.removeCallbacks(folderHover); v.animate().scaleX(1f).scaleY(1f).setDuration(100).start();
                            if (event.getAction()==DragEvent.ACTION_DRAG_ENDED) resetDragPreview(); return true;
                        }
                        if (event.getAction()==DragEvent.ACTION_DROP) {
                            if (folderHover!=null) main.removeCallbacks(folderHover);
                            String dragged=event.getClipData().getItemAt(0).getText().toString(); if (dragged.equals(item)) return true;
                            if (java.util.Arrays.asList(item.split("\\+")).contains(dragged)) return true;
                            if (!isSelected(dragged)&&android.text.TextUtils.join(",",draftApps).split("[,+]").length>=12) return true;
                            extractMember(dragged);
                            draftApps.remove(dragged); int target=draftApps.indexOf(item);
                            if (item.equals(folderTarget)) {
                                draftApps.remove(item); String merged=item+"+"+dragged; draftApps.add(Math.max(0,Math.min(target,draftApps.size())),merged);
                                String name=draftFolderNames.optString(item,""); draftFolderNames.remove(item); if (!name.isEmpty()) try { draftFolderNames.put(merged,name); } catch (Exception ignored) {}
                            }
                            else draftApps.add(Math.max(0,Math.min(target,draftApps.size())),dragged);
                            folderTarget=null; resetDragPreview(); populateLaunchers(); return true;
                        } return true;
                    });
                    ImageView remove=new ImageView(context); remove.setImageDrawable(new EdgeCloseDrawable()); remove.setScaleType(ImageView.ScaleType.FIT_CENTER); remove.setContentDescription("Remove "+pm.getApplicationLabel(info));
                    remove.setPadding(dp(5),dp(5),dp(5),dp(5));
                    android.graphics.drawable.GradientDrawable badge=new android.graphics.drawable.GradientDrawable(); badge.setColor(0xCCB3261E); badge.setShape(android.graphics.drawable.GradientDrawable.OVAL); remove.setBackground(badge);
                    remove.setOnClickListener(v -> { draftApps.remove(item); populateLaunchers(); buildCatalog(appSearch==null?"":appSearch.getText().toString()); });
                    FrameLayout.LayoutParams rp=new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.TOP|Gravity.RIGHT); cell.addView(remove,rp);
                }
                GridLayout.LayoutParams p=new GridLayout.LayoutParams(); p.width=dp(LAUNCHER_CELL_DP); p.height=dp(84);
                p.columnSpec=GridLayout.spec(index%columns); p.rowSpec=GridLayout.spec(index/columns); p.setMargins(0,dp(3),0,dp(3));
                appGrid.addView(cell,p);
                appName.post(() -> {
                    if (settings==null||(nativePanel!=null&&nativePanel.active())||!settings.edgePanelTextAdaptation||!appName.isAttachedToWindow()||!isDescendant(appName,appGrid)) return;
                    EdgeBackdropSampler sampler=new EdgeBackdropSampler(context,main,samplingExecutor,appName,light -> {
                        if (settings==null||(nativePanel!=null&&nativePanel.active())||!settings.edgePanelTextAdaptation||!appName.isAttachedToWindow()) return;
                        int target=light?0xFF10161D:0xFFF8FAFD; labelColors.put(appName,target);
                        ValueAnimator old=labelAnimators.remove(appName); if (old!=null) old.cancel();
                        ValueAnimator animator=ValueAnimator.ofArgb(appName.getCurrentTextColor(),target); animator.setDuration(settings.edgePanelTextDurationMs<0?220:settings.edgePanelTextDurationMs);
                        animator.addUpdateListener(a -> appName.setTextColor((Integer)a.getAnimatedValue())); labelAnimators.put(appName,animator); animator.start();
                    }); labelSamplers.put(appName,sampler); sampler.start();
                });
                index++;
            } catch (Throwable ignored) {}
        }
    }
    private int configureLauncherColumns() {
        if (appGrid==null||settings==null) return 1;
        int width=settings.edgePanelWidth;
        if(editMode&&appTray!=null)width=Math.min(width,Math.max(80,Math.round(bounds().width/context.getResources().getDisplayMetrics().density)-164));
        int columns=width<140?1:Math.max(2,2+(width-140)/LAUNCHER_CELL_DP);
        if (appGrid.getColumnCount()!=columns) appGrid.setColumnCount(columns);
        return columns;
    }
    private void populateActions() {
        if (actions==null) return;
        adaptiveLabels.removeIf(v -> isDescendant(v,actions)); adaptiveIcons.removeIf(v -> isDescendant(v,actions)); actions.removeAllViews();
        if (editMode) {
            actions.addView(createAction(android.R.drawable.ic_input_add,"Add",() -> { if (appSearch!=null) { appTray.setVisibility(View.VISIBLE); layoutModal(bounds()); updateVisuals(false); appSearch.requestFocus(); ((android.view.inputmethod.InputMethodManager)context.getSystemService(Context.INPUT_METHOD_SERVICE)).showSoftInput(appSearch,android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT); } }),new LinearLayout.LayoutParams(0,-2,1f));
            actions.addView(createAction(android.R.drawable.ic_menu_close_clear_cancel,"Cancel",() -> exitEditMode(false)),new LinearLayout.LayoutParams(0,-2,1f));
            actions.addView(createAction(android.R.drawable.ic_menu_save,"Save",() -> exitEditMode(true)),new LinearLayout.LayoutParams(0,-2,1f));
        } else {
            actions.addView(createAction(android.R.drawable.ic_menu_camera,"Screenshot",this::takeScreenshot),new LinearLayout.LayoutParams(0,-2,1f));
            actions.addView(createAction(android.R.drawable.ic_menu_preferences,"Settings",this::openSettings),new LinearLayout.LayoutParams(0,-2,1f));
        }
    }
    private void enterEditMode() {
        if (editMode||settings==null||panel==null) return;
        interruptSettling(); setProgress(1f); setGestureState(GestureState.OPEN); removeCollapsed(); setModalTouchable(true);
        editMode=true; draftApps.clear(); for (String value:settings.edgePanelApps.split(",")) if (!value.isEmpty()) draftApps.add(value);
        try { draftFolderNames=new org.json.JSONObject(settings.edgePanelFolderNames); } catch (Exception ignored) { draftFolderNames=new org.json.JSONObject(); }
        title.setText("Edit apps"); appSearch=new EditText(context); appSearch.setSingleLine(true); appSearch.setHint("Search apps"); appSearch.setTextSize(14); appSearch.setTextColor(0xFF10161D); appSearch.setHintTextColor(0xFF5F6368); adaptiveLabels.add(appSearch);
        catalog=new LinearLayout(context); catalog.setOrientation(LinearLayout.VERTICAL);
        appTray=new LinearLayout(context); appTray.setOrientation(LinearLayout.VERTICAL); appTray.setPadding(dp(8),dp(8),dp(8),dp(8));
        android.graphics.drawable.GradientDrawable trayBackground=new android.graphics.drawable.GradientDrawable(); trayBackground.setColor(0xF2F2F5F8); trayBackground.setCornerRadius(dp(18)); appTray.setBackground(trayBackground);
        View grip=createSearchGrip();appTray.addView(grip,new LinearLayout.LayoutParams(-1,dp(28)));
        searchMergeRegion=new EdgeMergeRegion(context,panel,appTray);searchMergeRegion.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);modalRoot.addView(searchMergeRegion,0);
        LinearLayout searchRow=new LinearLayout(context); searchRow.setGravity(Gravity.CENTER_VERTICAL); searchRow.addView(appSearch,new LinearLayout.LayoutParams(0,dp(48),1f));
        ImageButton closeSearch=new ImageButton(context); closeSearch.setImageDrawable(new EdgeCloseDrawable()); closeSearch.setPadding(dp(15),dp(15),dp(15),dp(15)); adaptiveIcons.add(closeSearch); closeSearch.setBackgroundColor(Color.TRANSPARENT); closeSearch.setContentDescription("Close app search"); closeSearch.setOnClickListener(v -> hideAppTray()); searchRow.addView(closeSearch,new LinearLayout.LayoutParams(dp(48),dp(48)));
        appTray.addView(searchRow,new LinearLayout.LayoutParams(-1,-2)); catalogScroll=new ScrollView(context); catalogScroll.addView(catalog); appTray.addView(catalogScroll,new LinearLayout.LayoutParams(-1,0,1f)); modalRoot.addView(appTray);
        appSearch.addTextChangedListener(new android.text.TextWatcher() {
            public void beforeTextChanged(CharSequence s,int start,int count,int after) {} public void onTextChanged(CharSequence s,int start,int before,int count) { buildCatalog(s.toString()); }
            public void afterTextChanged(android.text.Editable e) {}
        });
        populateLaunchers(); populateActions(); buildCatalog(""); layoutModal(bounds()); updateVisuals(false); appTray.post(() -> updateVisuals(false));
    }
    private void exitEditMode(boolean save) {
        if (!editMode) return; if (save) persistApps(android.text.TextUtils.join(",",draftApps));
        if (catalog!=null) adaptiveLabels.removeIf(v -> isDescendant(v,catalog));
        hideKeyboard(); cancelSearchDrag(); closeTrayMaterial(); removeSearchMergeView(); if(appTray!=null){adaptiveLabels.removeIf(v -> isDescendant(v,appTray));adaptiveIcons.removeIf(v -> isDescendant(v,appTray));} editMode=false; if (appTray!=null) modalRoot.removeView(appTray); appTray=null; catalogScroll=null; appSearch=null; catalog=null;
        title.setText("Quick launch"); populateLaunchers(); populateActions(); layoutModal(bounds()); updateVisuals(false);
    }
    private void addDraftApp(String packageName) {
        if (!editMode||draftApps.contains(packageName)) return;
        if (!isSelected(packageName)&&android.text.TextUtils.join(",",draftApps).split("[,+]").length>=12) return;
        extractMember(packageName);
        draftApps.add(packageName); populateLaunchers(); buildCatalog(appSearch==null?"":appSearch.getText().toString());
        scroll.smoothScrollTo(0,0);
    }
    private void buildCatalog(String query) {
        if (!editMode||catalog==null) return; adaptiveLabels.removeIf(v -> isDescendant(v,catalog)); catalog.removeAllViews(); String needle=query.trim().toLowerCase(Locale.ROOT);
        android.content.pm.PackageManager pm=context.getPackageManager(); Intent intent=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        java.util.HashSet<String> seen=new java.util.HashSet<>(); java.util.ArrayList<android.content.pm.ResolveInfo> matches=new java.util.ArrayList<>(pm.queryIntentActivities(intent,0));
        matches.sort((a,b) -> String.CASE_INSENSITIVE_ORDER.compare(a.loadLabel(pm).toString(),b.loadLabel(pm).toString()));
        for (android.content.pm.ResolveInfo info:matches) {
            String pkg=info.activityInfo.packageName,label=info.loadLabel(pm).toString(); if (!seen.add(pkg)||java.util.Arrays.asList(android.text.TextUtils.join(",",draftApps).split("[,+]")).contains(pkg)||(!needle.isEmpty()&&!label.toLowerCase(Locale.ROOT).contains(needle))) continue;
            LinearLayout row=new LinearLayout(context); row.setGravity(Gravity.CENTER_VERTICAL); row.setPadding(0,dp(4),0,dp(4));
            ImageView icon=new ImageView(context); icon.setImageDrawable(info.loadIcon(pm)); TextView text=new TextView(context); text.setText(label); text.setTextSize(13); text.setSingleLine(true); text.setEllipsize(android.text.TextUtils.TruncateAt.END); text.setPadding(dp(8),0,0,0); text.setTextColor(0xFF10161D); adaptiveLabels.add(text);
            row.addView(icon,new LinearLayout.LayoutParams(dp(36),dp(36))); row.addView(text,new LinearLayout.LayoutParams(0,dp(44),1f)); row.setOnClickListener(v -> addDraftApp(pkg));
            row.setOnLongClickListener(v -> { beginIconDrag(pkg,icon.getDrawable()); return true; });
            catalog.addView(row,new LinearLayout.LayoutParams(-1,dp(52)));
        }
        updateVisuals(false);
    }
    private void persistApps(String apps) {
        final String names=draftFolderNames.toString();
        samplingExecutor.execute(() -> { try {
            android.os.Bundle data=new android.os.Bundle(); data.putString("apps",apps); data.putString("names",names);
            context.getContentResolver().call(android.net.Uri.parse("content://com.example.remote_control.customization.health"),"edgeApps",null,data);
        } catch (Throwable error) { main.post(() -> failures.onFailure(error)); } });
    }
    private void hideKeyboard() {
        if (modalRoot!=null) {
            android.view.inputmethod.InputMethodManager input=(android.view.inputmethod.InputMethodManager)context.getSystemService(Context.INPUT_METHOD_SERVICE);
            input.hideSoftInputFromWindow(modalRoot.getWindowToken(),0); modalRoot.clearFocus();
        }
    }
    private void showFolder(String item) {
        if (modalRoot==null) return; closeFolder(); hideAppTray();
        FrameLayout layer=new FrameLayout(context); layer.setBackgroundColor(0x22000000); layer.setOnClickListener(v -> closeFolder());
        LinearLayout card=new LinearLayout(context); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(16),dp(12),dp(16),dp(16)); card.setOnClickListener(v -> {});
        android.graphics.drawable.GradientDrawable background=new android.graphics.drawable.GradientDrawable(); background.setColor(0xF0E2E9EF); background.setCornerRadius(dp(24)); card.setBackground(background);
        LinearLayout header=new LinearLayout(context); EditText name=new EditText(context); name.setSingleLine(true); name.setHint("Edit name"); name.setText(folderName(item)); name.setTextColor(0xFF10161D); name.setHintTextColor(0xFF5F6368); name.setTextSize(16); name.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(40)});
        header.addView(name,new LinearLayout.LayoutParams(0,dp(48),1f)); ImageButton close=new ImageButton(context); close.setImageDrawable(new EdgeCloseDrawable()); close.setColorFilter(0xFF10161D); close.setPadding(dp(12),dp(16),dp(12),dp(16)); close.setBackgroundColor(Color.TRANSPARENT); close.setContentDescription("Close folder"); close.setOnClickListener(v -> closeFolder()); header.addView(close,new LinearLayout.LayoutParams(dp(40),dp(48))); card.addView(header);
        GridLayout grid=new GridLayout(context); grid.setColumnCount(3);
        for (String pkg:item.split("\\+")) try {
            android.content.pm.PackageManager pm=context.getPackageManager(); LinearLayout cell=new LinearLayout(context); cell.setGravity(Gravity.CENTER_HORIZONTAL); cell.setOrientation(LinearLayout.VERTICAL);
            ImageView icon=new ImageView(context); icon.setImageDrawable(pm.getApplicationIcon(pkg)); icon.setContentDescription(pm.getApplicationLabel(pm.getApplicationInfo(pkg,0))); cell.addView(icon,new LinearLayout.LayoutParams(dp(56),dp(56)));
            TextView label=new TextView(context); label.setText(icon.getContentDescription()); label.setGravity(Gravity.CENTER); label.setTextSize(11); label.setTextColor(0xFF10161D); label.setMaxLines(2); cell.addView(label,new LinearLayout.LayoutParams(dp(72),dp(32)));
            cell.setOnClickListener(v -> { if (editMode) return; try { Intent launch=pm.getLaunchIntentForPackage(pkg); if (launch!=null) { closeFolder(); closeImmediately(); context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); } } catch (Throwable error) { failures.onFailure(error); } });
            cell.setOnLongClickListener(v -> { if (!editMode) enterEditMode(); beginIconDrag(pkg,icon.getDrawable()); closeFolder(); return true; });
            GridLayout.LayoutParams params=new GridLayout.LayoutParams(); params.width=dp(80); params.height=dp(96); grid.addView(cell,params);
        } catch (Throwable ignored) {}
        card.addView(grid); name.addTextChangedListener(new android.text.TextWatcher() {
            public void beforeTextChanged(CharSequence s,int start,int count,int after) {} public void afterTextChanged(android.text.Editable e) {}
            public void onTextChanged(CharSequence s,int start,int before,int count) { try {
                if (!editMode) { draftFolderNames=new org.json.JSONObject(settings.edgePanelFolderNames); }
                draftFolderNames.put(item,s.toString()); if (editMode) populateLaunchers(); else persistApps(settings.edgePanelApps);
            } catch (Exception ignored) {} }
        });
        layer.addView(card,new FrameLayout.LayoutParams(dp(280),-2,Gravity.CENTER)); modalRoot.addView(layer,new FrameLayout.LayoutParams(-1,-1)); folderLayer=layer;
    }
    private String folderName(String item) {
        if (editMode) return draftFolderNames.optString(item,"");
        try { return new org.json.JSONObject(settings.edgePanelFolderNames).optString(item,""); } catch (Exception ignored) { return ""; }
    }
    private void closeFolder() { if (folderLayer!=null&&modalRoot!=null) modalRoot.removeView(folderLayer); folderLayer=null; hideKeyboard(); }
    private void closeTrayMaterial(){if(nativeTray!=null){nativeTray.close();nativeTray=null;}if(appTray!=null)panelGlass[1].releaseSurface(appTray);}
    private void hideAppTray() { hideKeyboard(); cancelSearchDrag(); closeTrayMaterial(); if(appTray!=null)appTray.setVisibility(View.GONE);if(searchMergeRegion!=null)searchMergeRegion.setVisibility(View.GONE);updateVisuals(false); }
    private boolean isSelected(String item) { return draftApps.contains(item)||java.util.Arrays.asList(android.text.TextUtils.join(",",draftApps).split("[,+]")).contains(item); }
    private void beginIconDrag(String item,android.graphics.drawable.Drawable drawable) {
        hideKeyboard(); folderTarget=null; draggingItem=item; previewTarget=null; dragCells.clear();
        for (int i=0;i<appGrid.getChildCount();i++) dragCells.add(appGrid.getChildAt(i));
        final android.graphics.drawable.Drawable icon=drawable.getConstantState()==null?drawable:drawable.getConstantState().newDrawable().mutate();
        View.DragShadowBuilder shadow=new View.DragShadowBuilder(modalRoot) {
            @Override public void onProvideShadowMetrics(android.graphics.Point size,android.graphics.Point touch) { size.set(dp(64),dp(64)); touch.set(dp(32),dp(32)); }
            @Override public void onDrawShadow(android.graphics.Canvas canvas) { icon.setAlpha(255); icon.setBounds(0,0,dp(64),dp(64)); icon.draw(canvas); }
        };
        // DRAG_FLAG_OPAQUE prevents WindowManager's default translucent shadow.
        modalRoot.startDragAndDrop(android.content.ClipData.newPlainText("package",item),shadow,item,512);
        hideAppTray();
    }
    private void previewReorder(String target) {
        if (draggingItem==null||draggingItem.equals(target)||target.equals(previewTarget)) return; previewTarget=target;
        java.util.ArrayList<String> order=new java.util.ArrayList<>(); for (View cell:dragCells) if (!draggingItem.equals(cell.getTag())) order.add(String.valueOf(cell.getTag()));
        int destination=order.indexOf(target); if (destination<0) return; order.add(destination,draggingItem);
        for (View cell:dragCells) {
            int index=order.indexOf(String.valueOf(cell.getTag())); if (index<0||index>=dragCells.size()) continue;
            View slot=dragCells.get(index),content=((ViewGroup)cell).getChildAt(0); ((ViewGroup)cell).setClipChildren(false); appGrid.setClipChildren(false);
            content.animate().translationX(slot.getLeft()-cell.getLeft()).translationY(slot.getTop()-cell.getTop()).setDuration(140).start();
        }
    }
    private void resetDragPreview() {
        previewTarget=null;
        for (View cell:dragCells) { View content=((ViewGroup)cell).getChildAt(0); content.animate().translationX(0f).translationY(0f).setDuration(120).start(); }
    }
    private void extractMember(String pkg) {
        if (draftApps.contains(pkg)) return;
        for (int i=0;i<draftApps.size();i++) { String group=draftApps.get(i); java.util.ArrayList<String> members=new java.util.ArrayList<>(java.util.Arrays.asList(group.split("\\+")));
            if (members.size()>1&&members.remove(pkg)) {
                String remaining=android.text.TextUtils.join("+",members); draftApps.set(i,remaining);
                String name=draftFolderNames.optString(group,""); draftFolderNames.remove(group); if (members.size()>1) try { draftFolderNames.put(remaining,name); } catch (Exception ignored) {} return;
            }
        }
    }
    private android.graphics.drawable.Drawable folderIcon(String item) {
        int size=dp(56); android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(size,size,android.graphics.Bitmap.Config.ARGB_8888);
        android.graphics.Canvas canvas=new android.graphics.Canvas(bitmap); android.graphics.Paint paint=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG); paint.setColor(0xB8DDE3EA);
        canvas.drawRoundRect(0,0,size,size,dp(16),dp(16),paint); String[] members=item.split("\\+");
        for (int i=0;i<Math.min(4,members.length);i++) try {
            android.graphics.drawable.Drawable icon=context.getPackageManager().getApplicationIcon(members[i]); int left=dp(6+(i%2)*24),top=dp(6+(i/2)*24);
            icon.setBounds(left,top,left+dp(20),top+dp(20)); icon.draw(canvas);
        } catch (Throwable ignored) {}
        return new android.graphics.drawable.BitmapDrawable(context.getResources(),bitmap);
    }
    private LinearLayout createAction(int iconResource,String label,Runnable action) {
        LinearLayout item=new LinearLayout(context); item.setOrientation(LinearLayout.VERTICAL); item.setGravity(Gravity.CENTER); item.setPadding(0,dp(4),0,0);
        ImageView icon=new ImageView(context); if(iconResource==android.R.drawable.ic_menu_close_clear_cancel)icon.setImageDrawable(new EdgeCloseDrawable());else icon.setImageResource(iconResource); adaptiveIcons.add(icon);
        TextView text=new TextView(context); text.setText(label); text.setTextSize(10); text.setSingleLine(true); text.setGravity(Gravity.CENTER); adaptiveLabels.add(text);
        item.addView(icon,new LinearLayout.LayoutParams(dp(24),dp(24))); item.addView(text,new LinearLayout.LayoutParams(-1,dp(20)));
        item.setOnClickListener(v -> action.run()); return item;
    }
    private void applyForegroundZones(int top,int middle,int bottom) {
        boolean adaptive=settings!=null&&settings.edgePanelTextAdaptation;
        if(!adaptive&&fixedPanelTextColor==0)fixedPanelTextColor=middle;
        int fixed=settings!=null&&settings.edgePanelTextTone>=0?TextTone.color(settings.edgePanelTextTone):fixedPanelTextColor;
        middleInk=adaptive?middle:fixed;bottomInk=adaptive?bottom:fixed;
        for (TextView label:adaptiveLabels) if (!adaptive||!labelColors.containsKey(label)) label.setTextColor(adaptive?(label==title?top:(isDescendant(label,actions)?bottom:middle)):fixed);
        for (ImageView icon:adaptiveIcons) icon.setColorFilter(isDescendant(icon,actions)?bottom:middle);
    }
    private boolean isDescendant(View view,ViewGroup ancestor) {
        if (view==null||ancestor==null) return false; android.view.ViewParent parent=view.getParent();
        while (parent instanceof View) { if (parent==ancestor) return true; parent=parent.getParent(); } return false;
    }
    private void takeScreenshot() {
        closeImmediately(); if (collapsedHandle!=null) collapsedHandle.setVisibility(View.INVISIBLE);
        main.postDelayed(() -> {
            try { requestSystemScreenshot(); } catch (Throwable error) { failures.onFailure(error); }
            main.postDelayed(() -> { if (collapsedHandle!=null) collapsedHandle.setVisibility(View.VISIBLE); },900);
        },180);
    }
    private void requestSystemScreenshot() throws Exception {
        try {
            Class<?> type=Class.forName("com.android.internal.util.ScreenshotHelper");
            Object helper=type.getDeclaredConstructor(Context.class).newInstance(context);
            for (Method method:type.getDeclaredMethods()) {
                Class<?>[] parameters=method.getParameterTypes();
                if (!method.getName().equals("takeScreenshot")||parameters.length==0||parameters[0]!=int.class) continue;
                Object[] args=new Object[parameters.length];
                for (int i=0;i<parameters.length;i++) {
                    Class<?> parameter=parameters[i];
                    if (parameter==int.class) args[i]=i==0?1:0;
                    else if (parameter==boolean.class) args[i]=true;
                    else if (parameter==long.class) args[i]=10_000L;
                    else if (Handler.class.isAssignableFrom(parameter)) args[i]=main;
                    else args[i]=null;
                }
                method.setAccessible(true); method.invoke(helper,args); return;
            }
        } catch (Throwable ignored) {}
        Thread input=new Thread(() -> {
            try { new android.app.Instrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_SYSRQ); }
            catch (Throwable error) { main.post(() -> failures.onFailure(error)); }
        },"NodeCockpitScreenshot"); input.start();
    }
    private void openSettings() {
        try {
            Intent intent=new Intent(Intent.ACTION_MAIN).setClassName("com.example.remote_control","com.example.remote_control.MainActivity");
            intent.addCategory(Intent.CATEGORY_LAUNCHER);
            closeImmediately(); intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP); context.startActivity(intent);
        } catch (Throwable error) { failures.onFailure(error); }
    }
    private void setProgress(float value) {
        if(!enabled){openProgress=0;return;}
        openProgress=clamp(value); if (modalRoot==null && openProgress>0f) ensureModal(false); if (modalRoot==null) return;
        float travel=panelTravel(); float offset=(1f-openProgress)*travel*("right".equals(runtimeSide)?1f:-1f);
        panel.setTranslationX(offset); connector.setTranslationX(offset); panel.setAlpha(1f); connector.setAlpha(openProgress);
        long now=android.os.SystemClock.uptimeMillis();
        if (now-lastMovingSample>=48||openProgress==0f||openProgress==1f) {
            lastMovingSample=now; for (EdgeBackdropSampler sampler:panelSamplers) if (sampler!=null) sampler.refreshBounds();
            for (EdgeBackdropSampler sampler:labelSamplers.values()) sampler.refreshBounds();
        }
    }
    private float panelTravel() { return dp((settings==null?260:settings.edgePanelWidth)+24); }
    private void settle(float openingVelocity) {
        boolean open=Math.abs(openingVelocity)>dp(180)?openingVelocity>0:openProgress>=.5f; animateTo(open?1f:0f,openingVelocity);
    }
    private void animateTo(float target,float velocity) {
        if(!enabled)return;
        if(!EdgeOverlayPolicy.needsModal(modalRoot!=null,target)){openProgress=0;setGestureState(GestureState.CLOSED);ensureCollapsed();return;}
        ensureModal(target>0f); interruptSettling();
        if (target>0f) setGestureState(GestureState.SETTLING_OPEN); else setGestureState(GestureState.SETTLING_CLOSED);
        float distance=Math.abs(target-openProgress); long duration=(long)Math.max(90,Math.min(280,220*distance));
        settleAnimator=ValueAnimator.ofFloat(openProgress,target); settleAnimator.setDuration(duration); settleAnimator.setInterpolator(new DecelerateInterpolator());
        settleAnimator.addUpdateListener(a -> setProgress((Float)a.getAnimatedValue()));
        settleAnimator.addListener(new android.animation.AnimatorListenerAdapter() {
            @Override public void onAnimationEnd(android.animation.Animator a) {
                if (a!=settleAnimator) return;
                settleAnimator=null;
                if (target>=1f) { setProgress(1f); setGestureState(GestureState.OPEN); removeCollapsed(); setModalTouchable(true); updateVisuals(true); }
                else { setProgress(0f); setGestureState(GestureState.CLOSED); removeModal(); ensureCollapsed(); }
            }
        }); settleAnimator.start();
    }
    private void interruptSettling() { if (settleAnimator!=null) { ValueAnimator old=settleAnimator; settleAnimator=null; old.cancel(); } }
    private void setModalTouchable(boolean touchable) {
        if (modalRoot==null || modalParams==null) return;
        int before=modalParams.flags;
        if (touchable) modalParams.flags&=~(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE|WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
        else modalParams.flags|=WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE|WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
        if (before!=modalParams.flags && modalRoot.isAttachedToWindow()) { windows.updateViewLayout(modalRoot,modalParams); if (touchable) modalRoot.requestFocus(); }
    }
    private void registerBack() {
        if (Build.VERSION.SDK_INT<33 || modalRoot==null || backDispatcher!=null) return;
        try {
            backDispatcher=modalRoot.findOnBackInvokedDispatcher(); backCallback=() -> { if (folderLayer!=null) closeFolder(); else if (editMode) exitEditMode(false); else animateTo(0f,0f); };
            if (backDispatcher!=null) backDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,backCallback);
        } catch (Throwable ignored) { backDispatcher=null; backCallback=null; }
    }
    private void unregisterBack() {
        try { if (backDispatcher!=null&&backCallback!=null) backDispatcher.unregisterOnBackInvokedCallback(backCallback); } catch (Throwable ignored) {}
        backDispatcher=null; backCallback=null;
    }
    private void closeImmediately() { interruptSettling(); openProgress=0f; setGestureState(GestureState.CLOSED); removeModal(); if (enabled) ensureCollapsed(); }
    private void removeCollapsed() {
        if(handleLongPress!=null)main.removeCallbacks(handleLongPress);handleLongPress=null;
        if(collapsedHandle!=null)handleGlass.releaseSurface(collapsedHandle);
        if(nativeHandle!=null){nativeHandle.close();nativeHandle=null;}
        stopSampling(collapsedHandle);
        if (collapsedHandle!=null) { try { windows.removeViewImmediate(collapsedHandle); windowRemoves++; } catch (Throwable ignored) {} }
        collapsedHandle=null; collapsedParams=null;
    }
    private void restoreNativeLabelBackings(){for(java.util.Map.Entry<View,android.graphics.drawable.Drawable> e:nativeLabelOriginal.entrySet())e.getKey().setBackground(e.getValue());nativeLabelOriginal.clear();nativeLabelBacking.clear();}
    private void removeModal() {
        if(blankLongPress!=null)main.removeCallbacks(blankLongPress);if(folderHover!=null)main.removeCallbacks(folderHover);blankLongPress=folderHover=null;
        if(panel!=null)for(AdaptiveGlassEngine e:panelGlass)e.releaseSurface(panel);
        cancelSearchDrag();closeTrayMaterial();removeSearchMergeView();nativePanelOwner=null;restoreNativeLabelBackings();
        if(nativePanel!=null){nativePanel.close();nativePanel=null;}
        folderLayer=null; draggingItem=null; dragCells.clear(); previewTarget=null;
        stopLabelSampling();
        if (foregroundAnimator!=null) { foregroundAnimator.cancel(); foregroundAnimator=null; }
        unregisterBack();
        stopSampling(panel);
        if (modalRoot!=null) { try { windows.removeViewImmediate(modalRoot); windowRemoves++; } catch (Throwable ignored) {} }
        modalRoot=null; modalParams=null; panel=null; connector=null; title=null; placeholder=null; scroll=null; appGrid=null; actions=null; bodyContent=null; catalog=null; appSearch=null; appTray=null; catalogScroll=null; editMode=false; draftApps.clear();
        fixedPanelTextColor=0;headerSeparator=null; actionSeparator=null; adaptiveLabels.clear(); adaptiveIcons.clear();
    }
    private void stopLabelSampling() {
        for (EdgeBackdropSampler sampler:labelSamplers.values()) sampler.stop(); labelSamplers.clear(); labelColors.clear();
        for (ValueAnimator animator:labelAnimators.values()) animator.cancel(); labelAnimators.clear();
    }
    private WindowManager.LayoutParams baseParams(int width,int height,boolean focusable) {
        int flags=WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
        if(width<dp(64))flags|=WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL;
        if (!focusable) flags|=WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
        WindowManager.LayoutParams p=new WindowManager.LayoutParams(width,height,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,flags,android.graphics.PixelFormat.TRANSLUCENT);
        p.setTitle("Node Cockpit edge panel"); return p;
    }
    private Bounds bounds() {
        if (Build.VERSION.SDK_INT>=30) {
            WindowMetrics m=windows.getCurrentWindowMetrics(); android.graphics.Rect r=m.getBounds();
            Insets i=m.getWindowInsets().getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
            return new Bounds(r.width(),Math.max(1,r.height()-i.top-i.bottom),i.top,r.height()-i.bottom);
        }
        android.util.DisplayMetrics m=context.getResources().getDisplayMetrics(); return new Bounds(m.widthPixels,m.heightPixels,0,m.heightPixels);
    }
    private void setGestureState(GestureState next) { if (gestureState!=next) { gestureState=next; gestureTransitions++; } }
    String diagnostics() {
        AdaptiveGlassEngine.Style s=settings==null?null:panel==null
            ?handleGlass.resolve(settings.edgeHandleOpacity,settings.edgeHandleBlur,settings.edgeHandleTintMode,signalView)
            :panelGlass[1].resolve(settings.edgePanelOpacity,settings.edgePanelBlur,settings.edgePanelTintMode,signalView);
        int blurCreates=handleGlass.blurCreations(),appearance=handleGlass.appearanceUpdates(); for (AdaptiveGlassEngine engine:panelGlass) { blurCreates+=engine.blurCreations(); appearance+=engine.appearanceUpdates(); }
        return "searchMerged="+searchMerged()+",guard="+windowGuard.diagnostics()+",handleLive="+nativeConfig.liveHandle+",native="+(nativePanel!=null?nativePanel.diagnostics():nativeHandle!=null?nativeHandle.diagnostics():nativeConfig.enabled?"requested":"legacy")+","+String.format(Locale.ROOT,"state=%s,progress=%.3f,creates=%d,removes=%d,rebuilds=%d,geometry=%d,visual=%d,blurCreates=%d,appearance=%d,source=%s,mode=%s,luminance=%.3f,confidence=%.2f,sampler=%s,last=%s,revision=%d",
            gestureState,openProgress,windowCreates,windowRemoves,windowRebuilds,geometryUpdates,visualUpdates,blurCreates,appearance,
            s==null?panelGlass[1].lastSource():s.source,s==null?"unknown":s.mode,s==null?-1:s.luminance,s==null?0:s.confidence,
            panelSamplers[1]!=null?panelSamplers[1].diagnostics():handleSampler==null?"stopped":handleSampler.diagnostics(),lastChange,lastSettingsRevision);
    }
    private static float clamp(float v) { return Math.max(0f,Math.min(1f,v)); }
    private int dp(int v) { return Math.round(v*context.getResources().getDisplayMetrics().density); }
    private static final class Bounds { final int width,height,top,bottom; Bounds(int width,int height,int top,int bottom){this.width=width;this.height=height;this.top=top;this.bottom=bottom;} }

    private final class GestureRoot extends FrameLayout {
        @Override public boolean dispatchTouchEvent(MotionEvent e){if(nativePanel!=null)nativePanel.touch(e);if(nativeTray!=null)nativeTray.touch(e);return super.dispatchTouchEvent(e);}
        float downX,downY,startProgress; boolean horizontal,outsideTap,panelOnRight; int panelLeft,panelRight; VelocityTracker velocity;
        GestureRoot(Context c) { super(c); setOnKeyListener((v,key,e) -> {
            if (key==KeyEvent.KEYCODE_BACK&&e.getAction()==KeyEvent.ACTION_UP) { if (editMode) exitEditMode(false); else animateTo(0f,0f); return true; } return false; }); }
        @Override public boolean onInterceptTouchEvent(MotionEvent e) {
            if(!enabled)return false;
            if (folderLayer!=null) return false;
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    interruptSettling(); downX=e.getX(); downY=e.getY(); startProgress=openProgress; horizontal=false; editLongPress=false;
                    outsideTap=(panelOnRight?e.getX()<panelLeft:e.getX()>panelRight);
                    if (editMode&&appTray!=null&&appTray.getVisibility()==View.VISIBLE) { Rect rect=new Rect(); appTray.getHitRect(rect); if (rect.contains((int)e.getX(),(int)e.getY())) outsideTap=false; }
                    if (!editMode&&!outsideTap) {
                        boolean iconHit=false; for (int i=0;i<appGrid.getChildCount();i++) { Rect rect=new Rect(); appGrid.getChildAt(i).getGlobalVisibleRect(rect); if (rect.contains((int)e.getRawX(),(int)e.getRawY())) iconHit=true; }
                        if (!iconHit) { blankLongPress=() -> { editLongPress=true; enterEditMode(); modalRoot.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS); }; main.postDelayed(blankLongPress,420); }
                    }
                    velocity=VelocityTracker.obtain(); velocity.addMovement(e); return outsideTap;
                case MotionEvent.ACTION_MOVE:
                    if (Math.hypot(e.getX()-downX,e.getY()-downY)>dp(6)&&blankLongPress!=null) main.removeCallbacks(blankLongPress);
                    if (velocity!=null) velocity.addMovement(e);
                    float dx=(e.getX()-downX)*(panelOnRight?1f:-1f),dy=e.getY()-downY;
                    if (!editMode&&!horizontal&&Math.abs(dx)>dp(4)&&Math.abs(dx)>Math.abs(dy)*1.08f) { horizontal=true; setGestureState(GestureState.DRAGGING_CLOSED); return true; }
                    break;
                case MotionEvent.ACTION_UP:
                    if (blankLongPress!=null) main.removeCallbacks(blankLongPress);
                    if (editLongPress) return true;
                    if (editMode&&outsideTap) { hideAppTray(); recycleVelocity(); return true; }
                    if (!horizontal&&outsideTap) { animateTo(0f,0f); return true; }
                    recycleVelocity(); break;
                case MotionEvent.ACTION_CANCEL: if (blankLongPress!=null) main.removeCallbacks(blankLongPress); recycleVelocity(); break;
            }
            return horizontal;
        }
        @Override public boolean onTouchEvent(MotionEvent e) {
            if(!enabled)return false;
            if (editMode) {
                if (e.getActionMasked()==MotionEvent.ACTION_UP) hideAppTray();
                return true;
            }
            if (velocity==null) velocity=VelocityTracker.obtain(); velocity.addMovement(e);
            if (outsideTap&&e.getActionMasked()==MotionEvent.ACTION_UP) { recycleVelocity(); animateTo(0f,0f); return true; }
            if (e.getActionMasked()==MotionEvent.ACTION_MOVE) {
                float dx=(e.getX()-downX)*(panelOnRight?1f:-1f); setGestureState(dx>=0?GestureState.DRAGGING_CLOSED:GestureState.DRAGGING_OPEN);
                setProgress(startProgress-dx/Math.max(1f,panelTravel())); return true;
            }
            if (e.getActionMasked()==MotionEvent.ACTION_UP) {
                velocity.computeCurrentVelocity(1000); float openingVelocity=-velocity.getXVelocity()*(panelOnRight?1f:-1f); recycleVelocity(); settle(openingVelocity); return true;
            }
            if (e.getActionMasked()==MotionEvent.ACTION_CANCEL) { recycleVelocity(); settle(0f); return true; }
            return true;
        }
        private void recycleVelocity() { if (velocity!=null) velocity.recycle(); velocity=null; }
    }
}

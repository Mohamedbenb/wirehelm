package com.nodecockpit.customization;

import android.graphics.*;
import android.os.*;
import android.view.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.Supplier;
import org.json.JSONObject;

/** Existing SF card shader, driven by a native draw-tree anchor and the owning window's frames.
 * Prototype: one axis-aligned round container. All calls except native callbacks are UI-thread only.
 * The opacity supplier must return effective component opacity, not a background paint's color alpha.
 */
@androidx.annotation.RequiresApi(34)
public final class GlassNativeFrameMaterial implements AutoCloseable {
    private static final WeakHashMap<View,Resources> POOL=new WeakHashMap<>();
    private final View owner,window;
    private final Supplier<Float> opacity;
    private final Runnable changed;
    private JSONObject options;
    private final Api api;
    private final RenderNode anchor=new RenderNode("NodeCockpit.Brightness.NativeFrameShader");
    private final GlassNativeFrameState state=new GlassNativeFrameState();
    private Resources resources;
    private SurfaceControl lens;
    private Object listener;
    private SurfaceControl parent;
    private int parentId=-1;
    private Draft draft;
    private GlassBrightnessGeometry.Shape shape;
    private byte[] cachedUniforms;private int uniformWidth,uniformHeight;private float uniformRadius;
    private boolean replace,closed,failed,visible;
    private long sequence,submitted,warmups,commits,positions,lost,late;
    private String error="";
    private float lastAlpha=Float.NaN;
    private GlassNativeFrameState.Submission lastVisual;
    private final ViewTreeObserver.OnPreDrawListener preDraw=()->{startDraft();return true;};
    private final ViewTreeObserver.OnWindowVisibilityChangeListener visibility=this::visibility;
    private final View.OnAttachStateChangeListener attachment=new View.OnAttachStateChangeListener(){
        public void onViewAttachedToWindow(View view){}
        public void onViewDetachedFromWindow(View view){close();}
    };
    private static final class Draft {
        final long generation;GlassNativeFrameState.Appearance value;boolean sealed;
        Draft(long generation){this.generation=generation;}
        synchronized void update(GlassNativeFrameState.Appearance value){if(!sealed)this.value=value;}
        synchronized GlassNativeFrameState.Appearance seal(){sealed=true;return value;}
    }
    public GlassNativeFrameMaterial(View owner,String configuration,Supplier<Float> opacity,Runnable changed)throws Exception{
        if(Looper.myLooper()!=Looper.getMainLooper()||owner==null||opacity==null||changed==null)throw new IllegalArgumentException("UI owner and frame inputs required");
        this.owner=owner;this.window=owner.getRootView();this.opacity=opacity;this.changed=changed;
        JSONObject root=new JSONObject().put("cardMaterial",new JSONObject(configuration));
        if(!CardLiquidParameters.valid(root))throw new IllegalArgumentException("Invalid existing card material");
        options=root.getJSONObject("cardMaterial");api=new Api(owner);
        resources=resources(window);visible=owner.getWindowVisibility()==View.VISIBLE;state.window(visible);
        anchor.setClipToBounds(true);installListener();
        owner.addOnAttachStateChangeListener(attachment);
        owner.getViewTreeObserver().addOnPreDrawListener(preDraw);
        owner.getViewTreeObserver().addOnWindowVisibilityChangeListener(visibility);
    }
    /** Releases a cached transparent buffer on explicit host disable; ordinary owner replacement reuses it. */
    public static void releaseWindowResources(View owner){
        View root=owner.getRootView();Resources r=POOL.remove(root);if(r!=null)r.close();
    }
    public synchronized void configure(String configuration){
        if(closed||failed)return;
        try{JSONObject next=new JSONObject(configuration);if(!CardLiquidParameters.valid(new JSONObject().put("cardMaterial",next)))throw new IllegalArgumentException("Invalid card material");options=next;cachedUniforms=null;updateDraft();owner.post(changed);}catch(Exception e){fail(e);}
    }
    private static Resources resources(View view)throws Exception{
        Resources r=POOL.get(view);
        if(r!=null&&(r.closed||view.getWidth()>r.width||view.getHeight()>r.height)){POOL.remove(view);r.close();r=null;}
        if(r==null){if(POOL.size()>=2)throw new IllegalStateException("Native frame window budget exceeded");r=new Resources(view);POOL.put(view,r);}return r;
    }
    private void installListener()throws Exception{
        if(listener!=null)api.remove.invoke(anchor,listener);
        final long generation=state.generation();
        listener=Proxy.newProxyInstance(api.positionType.getClassLoader(),new Class<?>[]{api.positionType},(proxy,method,args)->{
            String name=method.getName();
            if(name.equals("hashCode"))return System.identityHashCode(proxy);
            if(name.equals("equals"))return proxy==args[0];
            if(name.equals("toString"))return "NativeFrameMaterialPosition";
            try{
                if(name.equals("positionChanged")&&args!=null&&args.length==13){
                    long frame=((Number)args[0]).longValue();
                    GlassNativeFrameState.Pose pose=new GlassNativeFrameState.Pose(frame,i(args,1),i(args,2),i(args,3),i(args,4),i(args,5),i(args,6),i(args,7),i(args,8),i(args,9),i(args,10),(Boolean)args[11],(Boolean)args[12],false);
                    synchronized(this){if(generation!=state.generation())return null;positions++;if(!pose.valid()){fail(new UnsupportedOperationException("Unsupported native container pose"));return null;}state.position(generation,pose);submit(frame);}
                }else if(name.equals("positionLost")&&args!=null){
                    long frame=((Number)args[0]).longValue();
                    synchronized(this){if(generation!=state.generation())return null;lost++;state.position(generation,new GlassNativeFrameState.Pose(frame,0,0,0,0,0,0,0,0,0,0,false,false,true));submit(frame);}
                }else if(name.equals("applyStretch"))fail(new UnsupportedOperationException("Stretch requires native surface stretch integration"));
                else if(name.equals("positionChanged"))fail(new UnsupportedOperationException("Exact clipping callback unavailable"));
            }catch(Exception unavailable){fail(unavailable);}
            return null;
        });
        api.add.invoke(anchor,listener);
    }
    private static int i(Object[] args,int n){return ((Number)args[n]).intValue();}
    /** Called at actual native drawing, before suppressing that primitive. */
    public synchronized boolean record(Canvas canvas,GlassBrightnessGeometry.Shape value){
        if(closed||failed||value==null||!canvas.isHardwareAccelerated())return false;
        try{
            refreshWindow();if(!visible)return false;
            if(Math.abs(value.tl-value.tr)>.01f||Math.abs(value.tl-value.bl)>.01f||Math.abs(value.tl-value.br)>.01f)throw new UnsupportedOperationException("Prototype requires equal container corner radii");
            boolean resized=shape!=null&&((int)Math.ceil(shape.w)!=(int)Math.ceil(value.w)||(int)Math.ceil(shape.h)!=(int)Math.ceil(value.h));
            shape=value;if(resized){state.reset();installListener();draft=null;}
            float effective=opacity.get();
            replace=(resources.proven||state.warm())&&resources.ready()&&parent!=null&&parent.isValid()&&Float.isFinite(effective)&&effective>=0&&effective<=1;
            anchor.setPosition(0,0,(int)Math.ceil(value.w),(int)Math.ceil(value.h));
            // This is a geometry anchor, not a copy of the stock background's paint alpha.
            int save=canvas.save();try{canvas.translate(value.x,value.y);canvas.scale(value.w/(float)Math.ceil(value.w),value.h/(float)Math.ceil(value.h));canvas.drawRenderNode(anchor);}finally{canvas.restoreToCount(save);}
            updateDraft();return replace;
        }catch(Exception unavailable){fail(unavailable);return false;}
    }
    /** Actual native layer-property interception can refresh the current window-frame appearance. */
    public synchronized void appearanceChanged(){if(!closed&&!failed)try{updateDraft();}catch(Exception e){fail(e);}}
    /** A foreign-thread opacity update cannot safely sample Compose UI state. */
    public synchronized void rejectAsynchronousOpacity(){fail(new UnsupportedOperationException("Tracked opacity changed outside UI thread"));}
    private synchronized void startDraft(){
        if(closed||failed)return;
        try{draft=null;refreshWindow();if(visible&&shape!=null)updateDraft();}catch(Exception e){fail(e);}
    }
    private void refreshWindow()throws Exception{
        boolean now=owner.getWindowVisibility()==View.VISIBLE&&owner.isAttachedToWindow();
        if(now!=visible)visibility(now?View.VISIBLE:View.INVISIBLE);
        if(!visible)return;
        if(resources.closed){resources=resources(window);state.reset();installListener();draft=null;destroyLayers();parentId=-1;}
        Object current=api.root.invoke(owner);if(current!=api.rootObject)throw new IllegalStateException("Native root replaced; recreate component");
        SurfaceControl next=(SurfaceControl)api.surface.invoke(current);if(next==null||!next.isValid()){parent=null;replace=false;return;}
        int id=((Number)api.layerId.invoke(next)).intValue();
        if(id!=parentId){state.reset();installListener();draft=null;destroyLayers();parentId=id;}
        parent=next;
    }
    private void updateDraft()throws Exception{
        if(!visible||shape==null||parent==null||!parent.isValid()||!resources.ready())return;
        if(shape.w>resources.width||shape.h>resources.height)throw new IllegalStateException("Native buffer resize required");
        if(lens==null)lens=resources.layer("native-frame-lens");
        float alpha=opacity.get();lastAlpha=alpha;
        int w=(int)Math.ceil(shape.w),h=(int)Math.ceil(shape.h);
        if(cachedUniforms==null||w!=uniformWidth||h!=uniformHeight||shape.tl!=uniformRadius){
            cachedUniforms=NativeQsUniforms.pack(CardLiquidParameters.uniforms(w,h,shape.tl,options,-.577f,-.817f,0,0,0,new float[16]),
                new float[][]{{w/2f,h/2f,w/2f,h/2f,shape.tl,shape.tr,shape.br,shape.bl,0,0,1,0,0,0,w,h}},CardLiquidParameters.blur(options),CardLiquidParameters.mix(options));
            uniformWidth=w;uniformHeight=h;uniformRadius=shape.tl;
        }
        byte[] uniforms=cachedUniforms;
        GlassNativeFrameState.Appearance a=new GlassNativeFrameState.Appearance(++sequence,w,h,shape.tl,alpha,replace,uniforms,Math.round(CardLiquidParameters.blur(options)),CardLiquidParameters.mix(options));
        if(draft==null||draft.sealed){
            Draft next=new Draft(state.generation());draft=next;
            Object callback=Proxy.newProxyInstance(api.frameType.getClassLoader(),new Class<?>[]{api.frameType},(proxy,method,args)->{
                if(method.getName().equals("toString"))return "NativeMaterialFrame";
                if(method.getName().equals("hashCode"))return System.identityHashCode(proxy);
                if(method.getName().equals("equals"))return proxy==args[0];
                if(!method.getName().equals("onFrameDraw"))return null;
                long frame=((Number)args[args.length-1]).longValue();
                synchronized(this){GlassNativeFrameState.Appearance frozen=next.seal();if(frozen!=null&&next.generation==state.generation()){state.appearance(next.generation,frame,frozen);submit(frame);}}
                if(method.getReturnType()==void.class)return null;
                return Proxy.newProxyInstance(api.commitType.getClassLoader(),new Class<?>[]{api.commitType},(p,m,values)->{
                    if(m.getName().equals("onFrameCommit")){synchronized(this){commits++;if(state.commit(next.generation,frame,(Boolean)values[0])){if(state.warm())resources.proven=true;warmups++;owner.post(changed);}}}
                    else if(m.getName().equals("hashCode"))return System.identityHashCode(p);
                    else if(m.getName().equals("equals"))return p==values[0];
                    else if(m.getName().equals("toString"))return "NativeMaterialCommit";
                    return null;
                });
            });
            api.register.invoke(api.rootObject,callback);
        }
        draft.update(a);
    }
    private synchronized void submit(long frame){
        if(closed||failed||!visible||lens==null||parent==null||!parent.isValid()||!resources.ready())return;
        GlassNativeFrameState.Submission s=state.join(frame);if(s==null)return;
        if(resources.proven&&s.sameVisual(lastVisual))return;
        if(!state.submitted(s)){late++;return;}
        try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){
            GlassNativeFrameState.Pose p=s.pose;GlassNativeFrameState.Appearance a=s.appearance;
            boolean show=s.shown();float sx=p.valid()?(p.right-p.left)/(float)a.width:1,sy=p.valid()?(p.bottom-p.top)/(float)a.height:1;
            Rect crop=new Rect(0,0,a.width,a.height);
            if(!p.disableClip&&!crop.intersect(Math.max(0,p.clipLeft),Math.max(0,p.clipTop),Math.min(a.width,p.clipRight),Math.min(a.height,p.clipBottom)))show=false;
            synchronized(resources){
                if(!resources.ready())return;
                t.reparent(lens,parent).setLayer(lens,-1890).setPosition(lens,p.left,p.top).setCrop(lens,crop).setAlpha(lens,a.valid()?a.opacity:0).setVisibility(lens,show);
                api.matrix.invoke(t,lens,sx,0f,0f,sy);
                api.corners.invoke(t,lens,0f);api.destination.invoke(t,lens,new Rect());resources.buffer.append(t,lens,crop);
                api.nativeBlur.invoke(t,lens,0);
                api.post.invoke(t,lens,resources.shader,a.uniforms,1);
                api.merge.invoke(api.rootObject,t,frame);submitted++;lastVisual=s;
            }
        }catch(Exception unavailable){fail(unavailable);}
    }
    private synchronized void visibility(int value){
        if(closed)return;boolean next=value==View.VISIBLE;
        if(next==visible)return;visible=next;replace=false;state.window(next);draft=null;parent=null;parentId=-1;destroyLayers();
        if(next)try{installListener();}catch(Exception e){fail(e);}
    }
    private void destroyLayers(){
        if(lens!=null){try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){t.setVisibility(lens,false).reparent(lens,null).apply();}catch(RuntimeException ignored){}lens.release();}
        lens=null;lastVisual=null;
    }
    private synchronized void fail(Exception value){
        if(failed||closed)return;failed=true;replace=false;error=(value instanceof InvocationTargetException&&value.getCause()!=null?value.getCause():value).toString();destroyLayers();owner.post(changed);
    }
    public synchronized String diagnostics(){return "sf-frame=tx"+submitted+",warm"+warmups+",commit"+commits+",pos"+positions+",lost"+lost+",late"+late+",reject"+state.rejected()+",ready="+state.warm()+",replace="+replace+",visible="+visible+",alpha="+lastAlpha+",parent="+parentId+",err="+error;}
    public synchronized void close(){
        if(closed)return;closed=true;state.close();draft=null;
        SurfaceControl retired=lens;lens=null;lastVisual=null;
        // Compose can replace this draw owner before the next native frame. Retire its
        // old surface with that frame, rather than ahead of the matching foreground.
        if(retired!=null)resources.retire(api,retired,owner.isAttachedToWindow()&&owner.getWindowVisibility()==View.VISIBLE);
        if(listener!=null)try{api.remove.invoke(anchor,listener);}catch(Exception ignored){}
        anchor.discardDisplayList();owner.removeOnAttachStateChangeListener(attachment);
        if(owner.getViewTreeObserver().isAlive()){owner.getViewTreeObserver().removeOnPreDrawListener(preDraw);owner.getViewTreeObserver().removeOnWindowVisibilityChangeListener(visibility);}
    }
    private static final class Resources implements AutoCloseable,View.OnAttachStateChangeListener {
        final View view;final int width,height;final IBinder shader;NativeUniformBuffer buffer;volatile boolean closed,proven;
        final Set<SurfaceControl> retired=Collections.newSetFromMap(new IdentityHashMap<>());
        Resources(View view)throws Exception{
            this.view=view;width=Math.max(view.getWidth(),view.getResources().getDisplayMetrics().widthPixels);height=Math.max(view.getHeight(),view.getResources().getDisplayMetrics().heightPixels);
            if(width>4096||height>4096||(long)width*height>4000000)throw new IllegalStateException("Window buffer budget exceeded");
            if(view.getContext().checkSelfPermission("android.permission.READ_FRAME_BUFFER")!=android.content.pm.PackageManager.PERMISSION_GRANTED)throw new SecurityException("Compositor permission required");
            shader=CardLiquidSurface.acquire(false,true);
            try{buffer=new NativeUniformBuffer(width,height,new Handler(Looper.getMainLooper()),view::invalidate);view.addOnAttachStateChangeListener(this);}catch(Exception e){CardLiquidSurface.release(false,true);throw e;}
        }
        synchronized boolean ready(){return !closed&&buffer!=null&&buffer.ready();}
        SurfaceControl layer(String name)throws Exception{
            Object builder=Class.forName("android.view.SurfaceControl$Builder").getConstructor().newInstance();
            builder.getClass().getMethod("setName",String.class).invoke(builder,"NodeCockpit."+name);
            builder.getClass().getMethod("setOpaque",boolean.class).invoke(builder,false);
            builder.getClass().getMethod("setBufferSize",int.class,int.class).invoke(builder,width,height);
            return (SurfaceControl)builder.getClass().getMethod("build").invoke(builder);
        }
        private static void removeNow(SurfaceControl layer){try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){t.setVisibility(layer,false).reparent(layer,null).apply();}catch(RuntimeException ignored){}finally{layer.release();}}
        synchronized void retire(Api api,SurfaceControl layer,boolean frameBound){
            if(closed||!frameBound||retired.size()>=32){removeNow(layer);return;}
            retired.add(layer);
            try{
                Object callback=Proxy.newProxyInstance(api.frameType.getClassLoader(),new Class<?>[]{api.frameType},(p,m,args)->{
                    if(m.getName().equals("hashCode"))return System.identityHashCode(p);
                    if(m.getName().equals("equals"))return p==args[0];
                    if(m.getName().equals("toString"))return "NativeMaterialRetirement";
                    if(m.getName().equals("onFrameDraw"))synchronized(this){
                        if(retired.remove(layer)){
                            try(SurfaceControl.Transaction t=new SurfaceControl.Transaction()){
                                t.setVisibility(layer,false).reparent(layer,null);api.merge.invoke(api.rootObject,t,((Number)args[args.length-1]).longValue());
                            }catch(Exception unavailable){removeNow(layer);return null;}
                            layer.release();
                        }
                    }
                    return null;
                });
                api.register.invoke(api.rootObject,callback);
            }catch(Exception unavailable){retired.remove(layer);removeNow(layer);}
        }
        public synchronized void close(){if(closed)return;closed=true;view.removeOnAttachStateChangeListener(this);for(SurfaceControl layer:retired)removeNow(layer);retired.clear();if(buffer!=null)buffer.close();buffer=null;CardLiquidSurface.release(false,true);}
        public void onViewAttachedToWindow(View view){}
        public void onViewDetachedFromWindow(View view){POOL.remove(view);close();}
    }
    private static final class Api {
        final Object rootObject;final Class<?> positionType,frameType,commitType;
        final Method root,surface,layerId,add,remove,register,merge,post,nativeBlur,corners,destination,matrix;
        Api(View owner)throws Exception{
            root=View.class.getDeclaredMethod("getViewRootImpl");root.setAccessible(true);rootObject=root.invoke(owner);if(rootObject==null)throw new IllegalStateException("No native root");
            Class<?> type=rootObject.getClass();surface=type.getMethod("getSurfaceControl");layerId=SurfaceControl.class.getMethod("getLayerId");
            positionType=Class.forName("android.graphics.RenderNode$PositionUpdateListener");add=RenderNode.class.getMethod("addPositionUpdateListener",positionType);remove=RenderNode.class.getMethod("removePositionUpdateListener",positionType);
            frameType=Class.forName("android.graphics.HardwareRenderer$FrameDrawingCallback");commitType=Class.forName("android.graphics.HardwareRenderer$FrameCommitCallback");
            if(!frameType.isInterface()||!commitType.isInterface())throw new UnsupportedOperationException("Native frame interfaces unavailable");
            register=type.getMethod("registerRtFrameCallback",frameType);merge=type.getMethod("mergeWithNextTransaction",SurfaceControl.Transaction.class,long.class);
            post=SurfaceControl.Transaction.class.getMethod("setPostProcess",SurfaceControl.class,IBinder.class,byte[].class,int.class);
            matrix=SurfaceControl.Transaction.class.getMethod("setMatrix",SurfaceControl.class,float.class,float.class,float.class,float.class);
            nativeBlur=SurfaceControl.Transaction.class.getMethod("setBackgroundBlurRadius",SurfaceControl.class,int.class);corners=SurfaceControl.Transaction.class.getMethod("setCornerRadius",SurfaceControl.class,float.class);destination=SurfaceControl.Transaction.class.getMethod("setDestinationFrame",SurfaceControl.class,Rect.class);
        }
    }
}

package com.nodecockpit.customization;
import android.app.ActivityManager;
import android.content.*;
import android.os.*;
import java.lang.reflect.*;
import java.util.concurrent.Executor;
/** Event-driven voluntary overlay suppression; never observes input or relaxes obscured-touch checks. */
final class EdgeWindowGuard {
 private final Context context;private final Handler main;private final Executor background;private final Runnable changed;private final EdgeOverlayPolicy policy=new EdgeOverlayPolicy();
 private volatile boolean active;private boolean queued,again,lastBlocked;private int generation;private Object manager,listener;private Method unregister;private String source="pending",error="",lastForegroundPackage="";
 EdgeWindowGuard(Context c,Handler h,Executor executor,Runnable changed){context=c;main=h;background=executor;this.changed=changed;try{Object name=c.getPackageManager().getClass().getMethod("getPermissionControllerPackageName").invoke(c.getPackageManager());if(name instanceof String)policy.permissionPackage((String)name);}catch(Throwable ignored){}}
 boolean blocked(){return active&&policy.blocked();}
 void active(boolean on){if(active==on)return;active=on;generation++;lastForegroundPackage="";policy.reset();lastBlocked=blocked();if(on){subscribe();refresh();}else{main.removeCallbacks(refreshTask);again=false;if(manager!=null&&unregister!=null)try{unregister.invoke(manager,listener);manager=listener=null;unregister=null;}catch(Throwable e){error="Task listener removal unavailable";}}}
 void foreground(String pkg){if(!active||pkg==null||pkg.isEmpty()||pkg.equals(lastForegroundPackage))return;lastForegroundPackage=pkg;generation++;policy.bar(pkg);publish();refresh();}
 void refresh(){if(!active)return;main.removeCallbacks(refreshTask);main.post(refreshTask);}
 private void publish(){boolean now=blocked();if(now!=lastBlocked){lastBlocked=now;changed.run();}}
 private final Runnable refreshTask=this::query;
 private void query(){if(!active)return;final int request=++generation;if(queued){again=true;return;}queued=true;background.execute(()->{ComponentName top=null;try{
  Object service=Class.forName("android.app.ActivityTaskManager").getMethod("getService").invoke(null);Object task=service.getClass().getMethod("getFocusedRootTaskInfo").invoke(service);if(task!=null)top=(ComponentName)task.getClass().getField("topActivity").get(task);
 }catch(Throwable unavailable){try{java.util.List<ActivityManager.RunningTaskInfo> tasks=context.getSystemService(ActivityManager.class).getRunningTasks(1);if(!tasks.isEmpty())top=tasks.get(0).topActivity;}catch(Throwable ignored){}}
 final ComponentName result=top;main.post(()->{queued=false;if(active&&request==generation&&result!=null){policy.task(result.getPackageName(),result.getClassName());publish();}if(again&&active){again=false;refresh();}});});}
 private void subscribe(){if(manager!=null)return;ClassLoader loader=context.getClassLoader();
  for(String name:new String[]{"com.android.wm.shell.shared.TaskStackChangeListeners","com.android.systemui.shared.system.TaskStackChangeListeners"})try{
   Class<?> type=Class.forName(name,false,loader);Object owner=type.getMethod("getInstance").invoke(null);Method register=null;for(Method m:type.getMethods())if(m.getName().equals("registerTaskStackListener")&&m.getParameterCount()==1&&m.getParameterTypes()[0].isInterface()){register=m;break;}if(register==null)continue;
   Class<?> callback=register.getParameterTypes()[0];Object proxy=Proxy.newProxyInstance(loader,new Class<?>[]{callback},(o,m,args)->{String n=m.getName();if(n.equals("equals"))return o==args[0];if(n.equals("hashCode"))return System.identityHashCode(o);if(n.equals("toString"))return "VectorOverlayGuard";
    if(active&&(n.equals("onTaskStackChangedBackground")||n.equals("onTaskStackChanged")||n.equals("onTaskMovedToFront")||n.equals("onTaskFocusChanged")||n.equals("onActivityRestartAttempt")||n.equals("onTaskRemoved")))main.post(this::refresh);
    Class<?> r=m.getReturnType();if(r==boolean.class)return false;if(r==int.class)return 0;if(r==long.class)return 0L;if(r==float.class)return 0f;if(r==double.class)return 0d;return null;});
   Method remove=type.getMethod("unregisterTaskStackListener",callback);register.invoke(owner,proxy);manager=owner;listener=proxy;unregister=remove;source=name;return;
  }catch(Throwable e){error="Task callback unsupported: "+e.getClass().getSimpleName();}
  source="system-bar events / one-shot foreground query";
 }
 String diagnostics(){return (active?policy.reason():"inactive")+",source="+source+(error.isEmpty()?"":",guardError="+error);}
}

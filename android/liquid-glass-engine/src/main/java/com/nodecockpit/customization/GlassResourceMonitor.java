package com.nodecockpit.customization;
import android.content.*;import android.os.*;import java.io.*;import java.util.*;import java.util.concurrent.*;
/** Low-rate process/device telemetry, sampled only while a visible HUD requests it.
 * RSS excludes shared compositor allocations; CPU is percent of one logical core, not whole-device.
 */
@androidx.annotation.RequiresApi(30)
final class GlassResourceMonitor {
 private static final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GlassResourceStats");t.setDaemon(true);return t;});
 private static volatile boolean pending;private static long requested,lastWall,lastCpu;private static volatile String cached="Resources: warming up";
 static String snapshot(Context context){long now=SystemClock.elapsedRealtime();if(!pending&&now-requested>=5000){requested=now;pending=true;Context app=context.getApplicationContext();worker.execute(()->{try{long wall=SystemClock.elapsedRealtime(),cpu=android.os.Process.getElapsedCpuTime();double percent=lastWall>0?100.0*Math.max(0,cpu-lastCpu)/Math.max(1,wall-lastWall):Double.NaN;lastWall=wall;lastCpu=cpu;long rss=0;try(BufferedReader reader=new BufferedReader(new FileReader("/proc/self/status"))){String line;while((line=reader.readLine())!=null)if(line.startsWith("VmRSS:")){rss=Long.parseLong(line.replaceAll("[^0-9]",""));break;}}
 PowerManager power=app.getSystemService(PowerManager.class);int thermal=power==null?-1:power.getCurrentThermalStatus();float headroom=power==null?Float.NaN:power.getThermalHeadroom(0);Intent battery=app.registerReceiver(null,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));int temp=battery==null?Integer.MIN_VALUE:battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE,Integer.MIN_VALUE);boolean plugged=battery!=null&&battery.getIntExtra(BatteryManager.EXTRA_PLUGGED,0)!=0;
 String gpuClock="n/a";try(BufferedReader clock=new BufferedReader(new FileReader("/sys/class/devfreq/34f00000.gpu0/cur_freq"))){gpuClock=String.format(Locale.ROOT,"%.0fMHz",Long.parseLong(clock.readLine().trim())/1000000.0);}catch(Exception unavailableClock){}
 cached=String.format(Locale.ROOT,"Host CPU: %s (1 core) | RSS: %.0fMiB\nGPU clock: %s (not utilization)\nThermal: %d | headroom: %s | battery: %s%s",Double.isNaN(percent)?"warming up":String.format(Locale.ROOT,"%.1f%%",percent),rss/1024.0,gpuClock,thermal,Float.isFinite(headroom)?String.format(Locale.ROOT,"%.2f",headroom):"n/a",temp==Integer.MIN_VALUE?"n/a":String.format(Locale.ROOT,"%.1fC",temp/10.0),plugged?" charging":"");
 }catch(Throwable unavailable){cached="Process/device resources: unavailable";}finally{pending=false;}});}return cached;}
}

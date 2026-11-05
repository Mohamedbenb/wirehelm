package com.nodecockpit.customization;

import java.util.*;

/** Process-shared regional observations. No screenshots, optical-flow or invented colour data. */
final class MaterialEnvironment {
    static final MaterialEnvironment SHARED=new MaterialEnvironment(64);
    static final class Sample {
        final long id,at; final String role,source; final float luminance,raw,target,confidence,changePerSecond; final int mode,left,top,right,bottom; final long observations;
        Sample(long id,long at,String role,String source,float luminance,float raw,float target,float confidence,float change,int mode,int left,int top,int right,int bottom,long observations) {
            this.id=id;this.at=at;this.role=role;this.source=source;this.luminance=luminance;this.raw=raw;this.target=target;this.confidence=confidence;this.changePerSecond=change;this.mode=mode;this.left=left;this.top=top;this.right=right;this.bottom=bottom;this.observations=observations;
        }
    }
    private final Map<Long,BackdropStability> stability=new HashMap<>();
    private final LinkedHashMap<Long,Sample> samples=new LinkedHashMap<>(); private final Map<Long,Long> filterTimes=new HashMap<>(); private final int capacity; private long nextId,rejected;
    MaterialEnvironment(int capacity) { this.capacity=capacity; }
    synchronized long register() { return ++nextId; }
    synchronized Sample observe(long id,String role,float raw,String source,float confidence,long now,int left,int top,int right,int bottom,MaterialTuning tuning) {
        if(!Float.isFinite(raw)||raw<0||raw>1||right<=left||bottom<=top) return null;
        Sample old=samples.get(id);
        if(old==null&&samples.size()>=capacity) { rejected++; return null; }
        long dt=old==null?0:Math.max(0,now-old.at);
        float accepted=BackdropStability.applies(role)?stability.computeIfAbsent(id,ignored -> new BackdropStability()).observe(raw,now,tuning):raw;
        float luma=accepted;
        int response=tuning.luminanceResponse(role);
        if(old!=null&&response>0) { long filterDt=Math.max(0,now-filterTimes.getOrDefault(id,old.at)); luma=old.luminance+(old.target-old.luminance)*GlassTransitionMath.amount(filterDt,response); }
        float dark=tuning.enabled?tuning.get("darkThreshold")/100f:.38f,light=tuning.enabled?tuning.get("lightThreshold")/100f:.62f,h=tuning.enabled?tuning.get("hysteresis")/100f:.08f;
        int mode=luma<dark?-1:luma>light?1:0;
        if(old!=null&&old.mode<0&&luma<Math.min(1,dark+h)) mode=-1;
        if(old!=null&&old.mode>0&&luma>Math.max(0,light-h)) mode=1;
        float change=old==null||dt==0?Float.NaN:Math.abs(raw-old.raw)*1000f/dt;
        Sample sample=new Sample(id,now,role,source,luma,raw,accepted,Math.max(0,Math.min(1,confidence)),change,mode,left,top,right,bottom,old==null?1:old.observations+1);
        samples.put(id,sample);filterTimes.put(id,now);return sample;
    }
    synchronized Sample advance(long id,long now,MaterialTuning tuning) {
        Sample old=samples.get(id); if(old==null||tuning.luminanceResponse(old.role)==0&&!tuning.enabled) return old;
        long dt=Math.max(0,now-filterTimes.getOrDefault(id,old.at));
        int response=tuning.luminanceResponse(old.role);
        BackdropStability filter=stability.get(id);float accepted=filter==null?old.raw:filter.advance(now,tuning);
        float luma=response==0?accepted:old.luminance+(accepted-old.luminance)*GlassTransitionMath.amount(dt,response);
        if(Math.abs(luma-accepted)<.002f) luma=accepted;
        float dark=tuning.enabled?tuning.get("darkThreshold")/100f:.38f,light=tuning.enabled?tuning.get("lightThreshold")/100f:.62f,h=tuning.enabled?tuning.get("hysteresis")/100f:.08f;
        int mode=luma<dark?-1:luma>light?1:0;if(old.mode<0&&luma<dark+h)mode=-1;if(old.mode>0&&luma>light-h)mode=1;
        Sample next=new Sample(id,old.at,old.role,old.source,luma,old.raw,accepted,old.confidence,old.changePerSecond,mode,old.left,old.top,old.right,old.bottom,old.observations);
        samples.put(id,next);filterTimes.put(id,now);return next;
    }
    synchronized boolean needsAdvance(long id){Sample s=samples.get(id);BackdropStability f=stability.get(id);return s!=null&&(Math.abs(s.luminance-s.target)>.002f||f!=null&&f.pending());}
    synchronized float rawLuminance(long id) { Sample s=samples.get(id);return s==null?Float.NaN:s.raw; }
    synchronized void remove(long id) { samples.remove(id);filterTimes.remove(id);stability.remove(id); }
    synchronized List<Map<String,Object>> snapshot(long now,int limit) {
        List<Map<String,Object>> result=new ArrayList<>();
        for(Sample s:samples.values()) {
            if(result.size()>=limit) break;
            Map<String,Object> item=new LinkedHashMap<>(); long age=Math.max(0,now-s.at);
            item.put("id",s.id);item.put("region",s.role);item.put("source",s.source);item.put("luminance",s.luminance);item.put("rawLuminance",s.raw);item.put("stableTarget",s.target);item.put("confidence",age>2000?s.confidence*.5f:s.confidence);item.put("ageMs",age);item.put("observations",s.observations);
            item.put("bounds",Arrays.asList(s.left,s.top,s.right,s.bottom));item.put("mode",s.mode<0?"dark":s.mode>0?"light":"neutral");
            item.put("luminanceChangePerSecond",Float.isFinite(s.changePerSecond)?s.changePerSecond:null);item.put("dominantTint",null);item.put("opticalMotion",null);result.add(item);
        } return result;
    }
    synchronized long rejected() { return rejected; }
}

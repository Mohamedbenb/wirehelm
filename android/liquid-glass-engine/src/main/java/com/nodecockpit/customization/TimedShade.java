package com.nodecockpit.customization;
/** Finite eased-linear transition with gentle10% acceleration/deceleration. Sustained retargets start at displayed shade and bounded velocity. */
final class TimedShade {
    float value,velocity;private float from,to,initialVelocity,time;private int duration=-2;private float span;private boolean seeded;
    void seed(float value,float velocity){this.value=value;this.velocity=velocity;seeded=true;duration=-2;}
    float step(float target,float elapsed,int requested){
        if(!seeded)seed(target,0);
        if(duration!=requested||Math.abs(target-to)>.5f){from=value;to=target;time=0;duration=requested;span=requested;float bound=.5f*Math.abs(to-from)/Math.max(1,duration);initialVelocity=Math.max(-bound,Math.min(bound,velocity));if(Math.abs(to-from)<.5f&&Math.abs(initialVelocity)<.006f){value=to;velocity=0;time=span;return value;}elapsed=Math.min(elapsed,16);}
        time+=Math.max(0,elapsed);
        if(duration==0||time>=span){value=to;velocity=0;return value;}
        float t=time/span,t2=t*t,t3=t2*t,r=.1f,progress,slope;
        if(t<r){progress=t*t/(2*r*(1-r));slope=t/(r*(1-r));}
        else if(t>1-r){float tail=1-t;progress=1-tail*tail/(2*r*(1-r));slope=tail/(r*(1-r));}
        else{progress=(t-r/2)/(1-r);slope=1/(1-r);}
        value=from+(to-from)*progress+(t3-2*t2+t)*span*initialVelocity;
        velocity=(to-from)*slope/span+(3*t2-4*t+1)*initialVelocity;
        if(value<0||value>255){value=Math.max(0,Math.min(255,value));velocity=0;}
        return value;
    }
    void correct(float corrected){value=from=corrected;velocity=initialVelocity=0;span=Math.max(0,span-time);time=0;}
    boolean settled(){return duration>=0&&(duration==0||time>=span);}
}

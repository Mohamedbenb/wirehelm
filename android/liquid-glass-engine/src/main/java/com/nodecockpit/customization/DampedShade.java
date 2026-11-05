package com.nodecockpit.customization;

/** Analytic critically damped motion. Retargeting preserves displayed position and velocity. */
final class DampedShade {
    float value,velocity;boolean seeded;
    void seed(float value){this.value=value;velocity=0;seeded=true;}
    float step(float target,float elapsed,float response){
        if(!seeded)seed(target);float dt=Math.max(0,elapsed),omega=2f/Math.max(8,response),delta=value-target;
        float temporary=(velocity+omega*delta)*dt,decay=(float)Math.exp(-omega*dt);
        value=target+(delta+temporary)*decay;velocity=(velocity-omega*temporary)*decay;
        if(value<0||value>255){value=Math.max(0,Math.min(255,value));velocity=0;}
        return value;
    }
    boolean close(float target,float tolerance){return Math.abs(value-target)<tolerance&&Math.abs(velocity)<.006f;}
}

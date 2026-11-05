package com.nodecockpit.customization;
import java.util.Arrays;
/** Bounded touch-event history, independent of frame cadence and background pixels. */
final class CardRippleTimeline {
 final float[] values=new float[16];private final long[] began=new long[4];private int next;
 CardRippleTimeline(){clear();}
 void emit(float x,float y,long now,boolean release){int k=next*4;values[k]=Float.isFinite(x)?Math.max(0,Math.min(1,x)):.5f;values[k+1]=Float.isFinite(y)?Math.max(0,Math.min(1,y)):.5f;values[k+2]=0;values[k+3]=release?-1:1;began[next]=now;next=(next+1)%4;}
 boolean advance(long now,float lifetime){boolean active=false;for(int i=0;i<4;i++)if(values[i*4+3]!=0){float age=Math.max(0,now-began[i])/1000f;values[i*4+2]=age;if(age>=lifetime){values[i*4+2]=-1;values[i*4+3]=0;}else active=true;}return active;}
 void clear(){Arrays.fill(values,0);for(int i=0;i<4;i++)values[i*4+2]=-1;next=0;}
 static float lifetime(float speed,float damping){float s=Float.isFinite(speed)?Math.max(.25f,Math.min(2.5f,speed)):1f,d=Float.isFinite(damping)?Math.max(.3f,Math.min(3,damping)):1.4f;return Math.min(4.5f,Math.min(1/s+.4f,(float)Math.log(100)/d));}
}

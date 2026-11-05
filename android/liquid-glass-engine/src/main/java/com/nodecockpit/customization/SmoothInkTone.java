package com.nodecockpit.customization;

/** Continuous greyscale projection onto readable bands. No background-opacity changes. */
final class SmoothInkTone {
 private static final double[] LUMA=new double[256];
 static { for(int i=0;i<256;i++){double c=i/255d;LUMA[i]=c<=.04045?c/12.92:Math.pow((c+.055)/1.055,2.4);} }
 private final DampedShade motion=new DampedShade();private final TimedShade timed=new TimedShade();private int duration=-1;
 void duration(int value){if(duration==value)return;duration=value;if(Float.isFinite(shown)){timed.seed(shown,motion.velocity);motion.seed(shown);}}
private boolean emergency;private float rawDangerMs;private int rawDirection;private int repairs;private final int[] safetyEdges=new int[6];
 int repairs(){return repairs;}
 private final int[] bands=new int[8];private int count;private float shown=Float.NaN;private boolean settled,limited;
 void seed(int color){shown=.2126f*((color>>>16)&255)+.7152f*((color>>>8)&255)+.0722f*(color&255);settled=false;motion.seed(shown);timed.seed(shown,0);emergency=false;rawDangerMs=0;rawDirection=0;}
 boolean settled(){return settled;} boolean limited(){return limited;}
 static float context(float local,float surrounding){return Float.isFinite(surrounding)?local*.85f+surrounding*.15f:local;}
 private static int lower(double l){int a=0,b=256;while(a<b){int m=(a+b)>>>1;if(LUMA[m]<l)a=m+1;else b=m;}return a;}
 private static int upper(double l){int a=0,b=256;while(a<b){int m=(a+b)>>>1;if(LUMA[m]<=l)a=m+1;else b=m;}return a-1;}
 private void add(int low,int high){low=Math.max(0,low);high=Math.min(255,high);if(low<=high){bands[count++]=low;bands[count++]=high;}}
 private static double ratio(double a,double b){return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);}
 private static double quality(int tone,double first,double second){return Math.min(ratio(LUMA[tone],first),ratio(LUMA[tone],second));}
 int step(int tint,float local,float surrounding,float raw,int otherTint,boolean constrainOther,float elapsed,MaterialTuning tuning){
  local=Float.isFinite(local)?Math.max(0,Math.min(1,local)):.5f;
  float guard=Float.isFinite(raw)?Math.max(0,Math.min(1,raw)):local;
  double rawFirst=GlassContrast.surfaceLuminance(tint,guard),rawSecond=constrainOther?GlassContrast.surfaceLuminance(otherTint,guard):rawFirst;
  int current=Float.isFinite(shown)?Math.max(0,Math.min(255,Math.round(shown))):0;
  // Raw input bypasses persistence only for severe unreadability. Latch it until
  // the filtered signal catches up; otherwise the stale target fights the correction.
  boolean rawDanger=Float.isFinite(raw)&&Float.isFinite(shown)&&quality(current,rawFirst,rawSecond)<1.6;
  if(rawDanger){int direction=quality(255,rawFirst,rawSecond)>quality(0,rawFirst,rawSecond)?1:-1;if(direction!=rawDirection){rawDirection=direction;rawDangerMs=0;}rawDangerMs+=Math.max(0,Math.min(32,elapsed));}else{rawDangerMs=0;rawDirection=0;}
  boolean confirmedDanger=rawDangerMs>=96;
  if(confirmedDanger)emergency=true;
  if(emergency&&Math.abs(guard-local)<.06f)emergency=false;
  float stable=emergency?guard:local;
  double first=GlassContrast.surfaceLuminance(tint,stable),second=constrainOther?GlassContrast.surfaceLuminance(otherTint,stable):first;
  double minimum=tuning.enabled?tuning.get("minimumContrast")/100d:4.5;
  int dark1=upper((first+.05)/minimum-.05),light1=lower(minimum*(first+.05)-.05);
  count=0;if(!constrainOther){add(0,dark1);add(light1,255);}else{
   int dark2=upper((second+.05)/minimum-.05),light2=lower(minimum*(second+.05)-.05);
   add(0,Math.min(dark1,dark2));add(light2,dark1);add(light1,dark2);add(Math.max(light1,light2),255);
  }
  limited=count==0;
  double environment=GlassContrast.surfaceLuminance(tint,context(local,surrounding));
  float preferred=environment>.18?0:255;
  int old=Float.isFinite(shown)?Math.max(0,Math.min(255,Math.round(shown))):(int)preferred;
  int selected=-1;float distance=Float.MAX_VALUE;
  for(int i=0;i<count;i+=2){if(old>=bands[i]&&old<=bands[i+1]){selected=i;break;}float d=Math.abs(Math.max(bands[i],Math.min(bands[i+1],preferred))-preferred);if(d<distance){distance=d;selected=i;}}
  float target;
  if(limited){
   int a=Math.max(0,Math.min(255,lower(Math.sqrt((first+.05)*(second+.05))-.05))),best=0;
   for(int candidate:new int[]{255,a,Math.max(0,a-1)})if(quality(candidate,first,second)>quality(best,first,second))best=candidate;
   target=best;
  }else{
   float bias=tuning.enabled?tuning.get("textBias")*.25f:0;
   float nearby=Float.isFinite(surrounding)?(surrounding-local)*4.8f:0;
   target=Math.max(bands[selected],Math.min(bands[selected+1],(bands[selected]+bands[selected+1])*.5f+nearby-bias));
  }
  boolean aggressive=tuning.enabled&&tuning.dynamicText;
  float deadband=aggressive?.25f:.5f+(tuning.enabled?tuning.get("contrastHysteresis"):15)/30f;
  boolean readable=quality(old,first,second)>=minimum;
  if(!Float.isFinite(shown)){shown=target;motion.seed(shown);}
  if(duration<0&&readable&&Math.abs(target-shown)<deadband&&Math.abs(motion.velocity)<.006f){settled=true;motion.seed(shown);return gray(Math.round(shown));}
  float base=tuning.enabled?tuning.get("textResponseMs"):90;
  float stability=aggressive?0:(tuning.enabled?tuning.get("textHoldMs"):300)*.2f;
  float response=(base+stability)*(aggressive?.7f:1);
  if(quality(old,first,second)<Math.min(3,minimum*.72))response=Math.min(response,65);
  float next=duration>=0?timed.step(target,elapsed,duration):motion.step(target,elapsed,response);
  // Smooth correction can cross the ideal contrast band briefly. Only a severe
  // loss against the current native observation permits a discontinuous repair.
  if(confirmedDanger&&quality(Math.round(next),rawFirst,rawSecond)<1.6){
   // Correct only as far as needed for readable ink, not straight to the
   // final target. Keep the remaining finite timeline instead of ending it.
   double floor=3;
   safetyEdges[0]=Math.max(0,Math.min(255,upper((rawFirst+.05)/floor-.05)));
   safetyEdges[1]=Math.max(0,Math.min(255,lower(floor*(rawFirst+.05)-.05)));
   safetyEdges[2]=Math.max(0,Math.min(255,upper((rawSecond+.05)/floor-.05)));
   safetyEdges[3]=Math.max(0,Math.min(255,lower(floor*(rawSecond+.05)-.05)));
   safetyEdges[4]=0;safetyEdges[5]=255;
   int safe=quality(0,rawFirst,rawSecond)>=quality(255,rawFirst,rawSecond)?0:255;float nearest=Float.MAX_VALUE;
   for(int candidate:safetyEdges)if(quality(candidate,rawFirst,rawSecond)>=floor-.0001){float distanceToCurrent=Math.abs(candidate-next);if(distanceToCurrent<nearest){nearest=distanceToCurrent;safe=candidate;}}
   next=safe;motion.seed(next);timed.correct(next);repairs++;
  }
  shown=Math.max(0,Math.min(255,next));settled=duration>=0?timed.settled():motion.close(target,Math.max(.6f,deadband));
  if(rawDanger&&!confirmedDanger)settled=false;
  if(settled){shown=target;motion.seed(target);}return gray(Math.round(shown));
 }
 private static int gray(int c){return 0xff000000|(c<<16)|(c<<8)|c;}
}

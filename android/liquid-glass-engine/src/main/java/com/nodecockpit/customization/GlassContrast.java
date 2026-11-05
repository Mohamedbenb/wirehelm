package com.nodecockpit.customization;

/** Contrast of the final translucent surface, independent of Android/SystemUI classes. */
final class GlassContrast {
    static final int DARK=0xff10161d, LIGHT=0xfff8fafd;
    static int foreground(int tint,float backdrop,int previous) { return foreground(tint,backdrop,previous,4.5,1.15,0); }
    static int foreground(int tint,float backdrop,int previous,double minimum,double hysteresis,double bias) {
        double background=surfaceLuminance(tint,backdrop);
        double dark=ratio(luminance(DARK),background), light=ratio(luminance(LIGHT),background);
        double retained=previous==DARK?dark:previous==LIGHT?light:0;
        // Do not oscillate near the crossover, but never retain an unreadable choice.
        if(retained>=minimum&&Math.max(dark,light)<retained*hysteresis) return previous;
                int chosen=dark*(1+bias)>=light?DARK:LIGHT;
        if((chosen==DARK?dark:light)<minimum) chosen=dark>=light?DARK:LIGHT;
        return chosen;
    }
    static double contrast(int ink,int tint,float backdrop) { return ratio(luminance(ink),surfaceLuminance(tint,backdrop)); }
    /** Least extra neutral backing that protects ink even across mixed black/white content. */
    static int protect(int tint,int ink,double minimum) {
        return protect(tint,ink,minimum,0);
    }
    static int protect(int tint,int ink,double minimum,int backing) {
        if(worstContrast(ink,composite(tint,backing))>=minimum) return tint;
        int neutral=luminance(ink)<.5?0xffffffff:0xff000000;
        int low=0,high=255;
        while(low<high) { int mid=(low+high)/2;if(worstContrast(ink,composite(over(tint,neutral,mid),backing))>=minimum) high=mid;else low=mid+1; }
        return over(tint,neutral,low);
    }
    static double worstContrast(int ink,int tint) { return Math.min(contrast(ink,tint,0),contrast(ink,tint,1)); }
    static int composite(int top,int bottom) {
        double a=(top>>>24)/255d,b=(bottom>>>24)/255d,out=a+b*(1-a);if(out==0)return 0;
        int result=(int)Math.round(out*255)<<24;
        for(int shift=16;shift>=0;shift-=8) result|=(int)Math.round((((top>>>shift)&255)*a+((bottom>>>shift)&255)*b*(1-a))/out)<<shift;
        return result;
    }
    private static int over(int tint,int neutral,int amount) {
        double a=(tint>>>24)/255d,p=amount/255d,out=p+a*(1-p);if(out==0)return tint;
        int result=(int)Math.round(out*255)<<24;
        for(int shift=16;shift>=0;shift-=8) result|=(int)Math.round((((neutral>>>shift)&255)*p+((tint>>>shift)&255)*a*(1-p))/out)<<shift;
        return result;
    }
    static double surfaceLuminance(int tint,float backdrop) {
        double gray=Math.max(0,Math.min(1,backdrop));
        double alpha=(tint>>>24)/255d;
        double r=((tint>>16)&255)/255d*alpha+gray*(1-alpha);
        double g=((tint>>8)&255)/255d*alpha+gray*(1-alpha);
        double b=(tint&255)/255d*alpha+gray*(1-alpha);
        return luminance(r,g,b);
    }
    private static double ratio(double a,double b) { return (Math.max(a,b)+.05)/(Math.min(a,b)+.05); }
    private static double luminance(int color) { return luminance(((color>>16)&255)/255d,((color>>8)&255)/255d,(color&255)/255d); }
    private static double luminance(double r,double g,double b) { return .2126*linear(r)+.7152*linear(g)+.0722*linear(b); }
    private static double linear(double value) { return value<=.04045?value/12.92:Math.pow((value+.055)/1.055,2.4); }
}

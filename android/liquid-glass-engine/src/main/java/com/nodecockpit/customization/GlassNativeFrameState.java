package com.nodecockpit.customization;

import java.util.TreeMap;

/** Bounded join of native-frame poses and UI appearances. No window or UI dependencies. */
final class GlassNativeFrameState {
    static final int HISTORY=8;
    static final class Pose {
        final long frame;final int left,top,right,bottom,clipLeft,clipTop,clipRight,clipBottom,width,height;
        final boolean disableClip,swapped,lost;
        Pose(long frame,int left,int top,int right,int bottom,int cl,int ct,int cr,int cb,int width,int height,boolean disableClip,boolean swapped,boolean lost){
            this.frame=frame;this.left=left;this.top=top;this.right=right;this.bottom=bottom;this.clipLeft=cl;this.clipTop=ct;this.clipRight=cr;this.clipBottom=cb;this.width=width;this.height=height;this.disableClip=disableClip;this.swapped=swapped;this.lost=lost;
        }
        boolean valid(){return !lost&&!swapped&&frame>=0&&width>0&&height>0&&width<=4096&&height<=4096&&right>left&&bottom>top
            &&Math.abs((long)left)<32768&&Math.abs((long)top)<32768&&Math.abs((long)right)<32768&&Math.abs((long)bottom)<32768;}
    }
    static final class Appearance {
        final long sequence;final int width,height,blur;final float radius,opacity,blurMix;final boolean replace;final byte[] uniforms;
        Appearance(long sequence,int width,int height,float radius,float opacity,boolean replace,byte[] uniforms){
            this(sequence,width,height,radius,opacity,replace,uniforms,0,0);
        }
        Appearance(long sequence,int width,int height,float radius,float opacity,boolean replace,byte[] uniforms,int blur,float blurMix){
            this.sequence=sequence;this.width=width;this.height=height;this.radius=radius;this.opacity=opacity;this.replace=replace;this.uniforms=uniforms.clone();this.blur=blur;this.blurMix=blurMix;
        }
        boolean valid(){return width>0&&height>0&&width<=4096&&height<=4096&&Float.isFinite(radius)&&radius>=0&&Float.isFinite(opacity)&&opacity>=0&&opacity<=1;}
    }
    static final class Submission {
        final long frame,generation;final Pose pose;final Appearance appearance;
        Submission(long frame,long generation,Pose pose,Appearance appearance){this.frame=frame;this.generation=generation;this.pose=pose;this.appearance=appearance;}
        boolean shown(){return pose.valid()&&appearance.valid()&&appearance.replace&&appearance.opacity>0
            &&pose.width==appearance.width&&pose.height==appearance.height
            &&(pose.disableClip||Math.min(pose.width,pose.clipRight)>Math.max(0,pose.clipLeft)&&Math.min(pose.height,pose.clipBottom)>Math.max(0,pose.clipTop));}
        boolean sameVisual(Submission other){
            if(other==null||generation!=other.generation||shown()!=other.shown())return false;
            Pose b=other.pose;Appearance c=other.appearance;
            return pose.left==b.left&&pose.top==b.top&&pose.right==b.right&&pose.bottom==b.bottom&&pose.clipLeft==b.clipLeft&&pose.clipTop==b.clipTop&&pose.clipRight==b.clipRight&&pose.clipBottom==b.clipBottom&&pose.disableClip==b.disableClip
                &&appearance.width==c.width&&appearance.height==c.height&&appearance.radius==c.radius&&Float.compare(appearance.opacity,c.opacity)==0&&appearance.blur==c.blur&&appearance.blurMix==c.blurMix&&java.util.Arrays.equals(appearance.uniforms,c.uniforms);
        }
    }
    private final TreeMap<Long,Pose> poses=new TreeMap<>();
    private final TreeMap<Long,Appearance> appearances=new TreeMap<>();
    private long generation=1,lastSubmitted=-1,lastAppearance=-1;
    private boolean visible=true,closed,warm;
    private int rejected;
    synchronized long generation(){return generation;}
    synchronized boolean warm(){return visible&&!closed&&warm;}
    synchronized void window(boolean value){if(closed||visible==value)return;visible=value;generation++;clear();}
    synchronized void reset(){if(closed)return;generation++;clear();}
    private void clear(){poses.clear();appearances.clear();lastSubmitted=lastAppearance=-1;warm=false;}
    synchronized void position(long ownerGeneration,Pose pose){
        if(closed||!visible||ownerGeneration!=generation||pose==null||pose.frame<0){rejected++;return;}
        poses.put(pose.frame,pose);trim(poses);
    }
    synchronized void appearance(long ownerGeneration,long frame,Appearance appearance){
        if(closed||!visible||ownerGeneration!=generation||frame<0||appearance==null){rejected++;return;}
        Appearance old=appearances.get(frame);if(old==null||appearance.sequence>=old.sequence)appearances.put(frame,appearance);trim(appearances);
    }
    synchronized Submission join(long frame){
        if(closed||!visible||frame<lastSubmitted)return null;
        java.util.Map.Entry<Long,Appearance> record=appearances.floorEntry(frame);
        Appearance a=record==null?null:record.getValue();java.util.Map.Entry<Long,Pose> p=poses.floorEntry(frame);
        if(a==null||p==null)return null;
        return new Submission(frame,generation,p.getValue(),a);
    }
    synchronized boolean submitted(Submission value){
        if(value==null||closed||!visible||value.generation!=generation||value.frame<lastSubmitted||value.frame==lastSubmitted&&value.appearance.sequence<lastAppearance){rejected++;return false;}
        lastSubmitted=value.frame;lastAppearance=value.appearance.sequence;return true;
    }
    synchronized boolean commit(long ownerGeneration,long frame,boolean produced){
        if(closed||!visible||ownerGeneration!=generation||!produced||frame!=lastSubmitted)return false;
        Submission s=join(frame);boolean next=warm;
        if(s!=null&&!s.appearance.valid())next=false;
        else if(s!=null&&s.pose.valid())next=s.pose.width==s.appearance.width&&s.pose.height==s.appearance.height;
        boolean changed=next!=warm;warm=next;return changed;
    }
    synchronized int rejected(){return rejected;}
    synchronized int retained(){return Math.max(poses.size(),appearances.size());}
    synchronized long latestFrame(){return appearances.isEmpty()?-1:appearances.lastKey();}
    synchronized void close(){closed=true;generation++;clear();}
    private static void trim(TreeMap<?,?> map){while(map.size()>HISTORY)map.pollFirstEntry();}
}

package com.nodecockpit.customization;

/** Allocation-free horizontal collision resolution; all bounds are in root-local pixels. */
final class StatusBarPlacement {
    private StatusBarPlacement() {}
    static int resolve(int preferred,int width,int left,int right,int[] obstacles,int count,int gap) {
        if (width<=0 || right-left<width) return -1;
        gap=Math.max(0,gap); count=Math.min(count,obstacles.length/2);
        int desired=Math.max(left,Math.min(right-width,preferred));
        if (free(desired,width,obstacles,count,gap)) return desired;
        int best=-1; long distance=Long.MAX_VALUE;
        for (int i=-1;i<count;i++) {
            for (int side=0;side<2;side++) {
                int candidate=i<0?(side==0?left:right-width)
                    :(side==0?obstacles[i*2]-gap-width:obstacles[i*2+1]+gap);
                if (candidate<left || candidate+width>right || !free(candidate,width,obstacles,count,gap)) continue;
                long delta=Math.abs((long)candidate-desired);
                if (delta<distance) { best=candidate; distance=delta; }
            }
        }
        return best;
    }
    private static boolean free(int x,int width,int[] obstacles,int count,int gap) {
        for (int i=0;i<count;i++) {
            int start=obstacles[i*2],end=obstacles[i*2+1];
            if (end>start && x<end+gap && x+width>start-gap) return false;
        }
        return true;
    }
}

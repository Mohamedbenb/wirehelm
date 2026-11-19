package com.nodecockpit.customization;

/** Only new, fully published SystemUI screenshots; no historical import or duplicate callbacks. */
final class ScreenshotShelfGate {
    private final long startedAt;
    private final java.util.LinkedHashSet<Long> seen=new java.util.LinkedHashSet<>();
    ScreenshotShelfGate(long startedAt){this.startedAt=startedAt;}
    boolean accept(long id,long taken,String path,String owner,boolean pending,long now){
        if(id<=0||pending||taken<startedAt||taken>now+2000||now-taken>60000||!"com.android.systemui".equals(owner))return false;
        String folder=path==null?"":path.toLowerCase(java.util.Locale.ROOT);
        if(!folder.equals("screenshots/")&&!folder.endsWith("/screenshots/"))return false;
        if(!seen.add(id))return false;
        while(seen.size()>64)seen.remove(seen.iterator().next());
        return true;
    }
    static boolean mayReplaceClipboard(long screenshotAt,long clipboardAt){return clipboardAt<=screenshotAt;}
}

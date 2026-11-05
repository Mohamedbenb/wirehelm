package com.nodecockpit.customization;
import java.util.*;
/** Pure arbitration, independent from notification text and native UI. */
final class CameraRingSelection {
    static CameraRingSettings.App preview(CameraRingSettings settings){
        CameraRingSettings.App best=null;
        for(CameraRingSettings.App app:settings.apps.values())if(best==null||app.priority>best.priority)best=app;
        return best;
    }
    static final class Notice {
        final String key,pkg;final long posted;final boolean ongoing,summary;
        Notice(String k,String p,long time,boolean ongoing,boolean summary){key=k;pkg=p;posted=time;this.ongoing=ongoing;this.summary=summary;}
    }
    static Notice winner(CameraRingSettings settings,Collection<Notice> notices){
        if(!settings.enabled)return null;Notice best=null;int priority=-1;
        for(Notice n:notices){CameraRingSettings.App app=settings.apps.get(n.pkg);if(app==null||n.summary||n.ongoing&&!settings.includeOngoing)continue;
            if(best==null||app.priority>priority||app.priority==priority&&(n.posted>best.posted||n.posted==best.posted&&n.key.compareTo(best.key)<0)){best=n;priority=app.priority;}
        }return best;
    }
}

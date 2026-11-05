package com.nodecockpit.customization;

import java.util.*;

/** Final shade membership owns additions. Interim reconciliation may only remove keys.
 * Thus a retained raw record cannot resurrect a dismissed notification before a new render.
 */
final class CameraRingEligibility {
    private final Map<String,CameraRingSelection.Notice> visible=new LinkedHashMap<>();
    private boolean ready;
    void rendered(Collection<CameraRingSelection.Notice> notices){
        if(notices.size()>2048)throw new IllegalArgumentException("Notification limit");
        visible.clear();for(CameraRingSelection.Notice n:notices)visible.put(n.key,n);ready=true;
    }
    void reconcile(Collection<CameraRingSelection.Notice> stillEligible){
        if(stillEligible.size()>2048)throw new IllegalArgumentException("Notification limit");
        Set<String> keys=new HashSet<>();for(CameraRingSelection.Notice n:stillEligible)keys.add(n.key);
        visible.keySet().retainAll(keys);
    }
    void clear(){visible.clear();ready=false;}
    boolean ready(){return ready;}
    List<CameraRingSelection.Notice> snapshot(){return List.copyOf(visible.values());}
}

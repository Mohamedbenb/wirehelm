package com.nodecockpit.customization;

/** WindowManager registration is owned before View attachment and until removal succeeds. */
final class CameraRingWindow<T> {
    private T current;
    private Runnable removal;
    T get(){return current;}
    void claim(T view,Runnable remove){
        if(current!=null)throw new IllegalStateException("Ring window already owned");
        current=java.util.Objects.requireNonNull(view);
        removal=java.util.Objects.requireNonNull(remove);
    }
    void release(){
        if(current==null)return;
        // A successful addView may still have a pending first traversal. Never
        // use isAttachedToWindow as proof of WindowManager registration.
        try{removal.run();}catch(IllegalArgumentException noRegistration){
            // WindowManager reports this view is already absent.
        }
        // Other failures retain the exact view/remover so cleanup can retry.
        current=null;removal=null;
    }
}

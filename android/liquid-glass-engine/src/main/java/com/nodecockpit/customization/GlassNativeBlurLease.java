package com.nodecockpit.customization;

/** One native draw owner, with no copied screen coordinates or cross-frame readiness. */
final class GlassNativeBlurLease implements AutoCloseable {
    interface Backend {
        void configure(GlassNativeBlurRegion region) throws Exception;
        void visible(boolean visible) throws Exception;
        void release() throws Exception;
    }
    interface Draw { void run() throws Exception; }
    private final Backend backend;
    private boolean closed, visible=true;
    private String failure="";
    private GlassNativeBlurRegion configured;
    GlassNativeBlurLease(Backend backend) { this.backend=backend; }
    boolean draw(GlassNativeBlurRegion region,boolean attached,boolean hardware,Draw draw) {
        if(closed || !visible)return false;
        if(!attached || !hardware){close();failure=attached?"Hardware canvas unavailable":"Native owner detached";return false;}
        try { configure(region);backend.visible(true);draw.run();return true; }
        catch(Exception unavailable) { failure=unavailable.getClass().getSimpleName()+": "+unavailable.getMessage();close();return false; }
    }
    boolean prepare(GlassNativeBlurRegion region){
        if(closed)return false;
        try{configure(region);backend.visible(visible);return true;}
        catch(Exception unavailable){failure=unavailable.getClass().getSimpleName();close();return false;}
    }
    private void configure(GlassNativeBlurRegion region)throws Exception{
        if(!region.same(configured)){backend.configure(region);configured=region;}
    }
    void visible(boolean value) {
        if(closed || visible==value)return;visible=value;
        try {backend.visible(value);}catch(Exception unavailable){failure=unavailable.getClass().getSimpleName();close();}
    }
    String failure(){return failure;}
    boolean closed(){return closed;}
    public void close(){if(closed)return;closed=true;try{backend.visible(false);}catch(Exception ignored){}
        try{backend.release();}catch(Exception ignored){} }
}

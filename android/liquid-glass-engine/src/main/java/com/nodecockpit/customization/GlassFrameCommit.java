package com.nodecockpit.customization;

/** Draw-submission receipt, not a presentation fence. Frames must be immutable, unique objects. */
public final class GlassFrameCommit<T> {
    private T prepared, submitted;
    public void prepare(T frame) { prepared = frame; }
    public boolean submit(T frame) {
        if (frame == null || frame != prepared) return false;
        submitted = frame;
        return true;
    }
    public boolean ready(T frame) { return frame != null && frame == prepared && frame == submitted; }
    public void clear() { prepared = submitted = null; }
}
